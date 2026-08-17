local ADDON, CC = ...

CC.Sync = {}
local Sync = CC.Sync
local DB = CC.DB
local Perm = CC.Perm
local Comm = CC.Comm

local function refreshUI()
    if CC.UI and CC.UI.Main and CC.UI.Main.Refresh then CC.UI.Main.Refresh() end
    if CC.UI and CC.UI.Officer and CC.UI.Officer.Refresh then CC.UI.Officer.Refresh() end
    if CC.UI and CC.UI.History and CC.UI.History.Refresh then CC.UI.History.Refresh() end
    if CC.UI and CC.UI.SendCoins and CC.UI.SendCoins.RefreshRoster then CC.UI.SendCoins.RefreshRoster() end
end

-- Shared by the auto-merge path (regular members) and the officer
-- review-and-accept path: nothing here is trusted just because it showed
-- up in a payload. Officer-authored entries independently justify
-- themselves by rank, same bar as a live TX. Transfer entries can't be
-- validated one at a time (a lone credit with no matching debit would be
-- free money), so they're grouped by transferId first and only ever
-- applied as a complete, balance-checked pair.
local function mergeLedgerEntries(gdb, txs)
    local applied = 0
    local transfersById = {}
    for _, tx in ipairs(txs or {}) do
        if tx.kind == "transfer" and tx.transferId then
            transfersById[tx.transferId] = transfersById[tx.transferId] or {}
            table.insert(transfersById[tx.transferId], tx)
        elseif Perm.IsOfficer(tx.actor) and DB.ApplyTransaction(gdb, tx) then
            applied = applied + 1
        end
    end

    for _, pair in pairs(transfersById) do
        if #pair == 2 then
            local a, b = pair[1], pair[2]
            local debitTx, creditTx
            if a.delta < 0 and b.delta > 0 then
                debitTx, creditTx = a, b
            elseif b.delta < 0 and a.delta > 0 then
                debitTx, creditTx = b, a
            end
            if debitTx and DB.ApplyTransferPair(gdb, debitTx, creditTx) then
                applied = applied + 1
            end
        end
    end

    return applied
end

-- Exposed so the officer sync-review window can apply what the reviewer
-- accepted, using the exact same validation as everything else.
function Sync.MergeIncoming(gdb, txs)
    local applied = mergeLedgerEntries(gdb, txs)
    if applied > 0 then refreshUI() end
    return applied
end

-- Outbound ----------------------------------------------------------------

-- Applies a transaction locally (caller must already have verified the
-- *local* player is allowed to do this) and broadcasts it to the guild.
function Sync.SubmitTransaction(target, delta, reason)
    local gdb = DB.GetGuildDB()
    if not gdb then return false, "Not in a guild" end
    if not Perm.PlayerIsOfficer() then return false, "Insufficient rank" end

    local tx = {
        id = CC.Utils.NewId(),
        actor = UnitName("player"),
        target = target,
        delta = delta,
        reason = reason or "",
        ts = CC.Utils.Now(),
    }
    DB.ApplyTransaction(gdb, tx)
    Comm.Send({ mt = "TX", tx = tx }, "GUILD")
    refreshUI()
    return true
end

-- Award the same amount to a whole list of names in one batch (boss kill rewards).
function Sync.SubmitBatch(targets, delta, reason)
    local gdb = DB.GetGuildDB()
    if not gdb then return false, "Not in a guild" end
    if not Perm.PlayerIsOfficer() then return false, "Insufficient rank" end

    local txs = {}
    local actor = UnitName("player")
    local ts = CC.Utils.Now()
    for _, name in ipairs(targets) do
        local tx = {
            id = CC.Utils.NewId() .. "-" .. name,
            actor = actor,
            target = name,
            delta = delta,
            reason = reason or "",
            ts = ts,
        }
        DB.ApplyTransaction(gdb, tx)
        table.insert(txs, tx)
    end
    Comm.Send({ mt = "TXBATCH", txs = txs }, "GUILD")
    refreshUI()
    return true
end

-- Sends coins the player actually has to another guild member. Open to
-- every member, not just officers -- see DB.ApplyTransferPair for what
-- actually keeps this safe (you can only debit yourself, and every
-- receiving client independently checks you can cover it from their own
-- ledger, rather than trusting your claim).
function Sync.SubmitTransfer(recipient, amount, note)
    local gdb = DB.GetGuildDB()
    if not gdb then return false, "Not in a guild" end

    local myName = UnitName("player")
    if not recipient or recipient == "" then return false, "Choose a recipient" end
    if recipient == myName then return false, "You can't send coins to yourself" end
    if type(amount) ~= "number" or amount <= 0 then return false, "Enter a positive amount" end

    local balance = DB.GetBalance(gdb, myName)
    if balance < amount then
        return false, string.format("You only have %d coin(s)", balance)
    end

    note = CC.Utils.Trim(note or "")
    local transferId = CC.Utils.NewId()
    local ts = CC.Utils.Now()

    local debitTx = {
        id = transferId .. "-out",
        transferId = transferId,
        kind = "transfer",
        actor = myName,
        target = myName,
        delta = -amount,
        reason = note ~= "" and ("To " .. recipient .. ": " .. note) or ("To " .. recipient),
        ts = ts,
    }
    local creditTx = {
        id = transferId .. "-in",
        transferId = transferId,
        kind = "transfer",
        actor = myName,
        target = recipient,
        delta = amount,
        reason = note ~= "" and ("From " .. myName .. ": " .. note) or ("From " .. myName),
        ts = ts,
    }

    if not DB.ApplyTransferPair(gdb, debitTx, creditTx) then
        return false, "Transfer failed"
    end

    Comm.Send({ mt = "TRANSFER", debitTx = debitTx, creditTx = creditTx }, "GUILD")
    refreshUI()
    return true
end

-- Ask the guild for a copy of the ledger to catch up on anything missed
-- while offline. Peers reply via whisper after a short random delay so we
-- don't get a synchronized flood of replies.
function Sync.RequestSync()
    Comm.Send({ mt = "SYNCREQ" }, "GUILD")
end

-- After DB.RestoreBackup() has been applied locally, push the restored
-- state to the rest of the guild. Receivers independently verify the
-- sender holds admin rank before accepting an overwrite.
function Sync.BroadcastRestore(gdb, label)
    Comm.Send({
        mt = "SNAPSHOT",
        members = gdb.members,
        ledger = gdb.ledger,
        by = UnitName("player"),
        label = label or "",
    }, "GUILD")
end

-- Inbound -------------------------------------------------------------

Comm.RegisterHandler("TX", function(payload, sender)
    local gdb = DB.GetGuildDB()
    if not gdb then return end
    local tx = payload.tx
    if not tx or tx.actor ~= CC.Utils.ShortName(sender) then return end -- actor field must match true sender
    if not Perm.IsOfficer(sender) then return end
    if DB.ApplyTransaction(gdb, tx) then
        refreshUI()
    end
end)

Comm.RegisterHandler("TXBATCH", function(payload, sender)
    local gdb = DB.GetGuildDB()
    if not gdb then return end
    if not Perm.IsOfficer(sender) then return end
    local applied = 0
    local shortSender = CC.Utils.ShortName(sender)
    for _, tx in ipairs(payload.txs or {}) do
        if tx.actor == shortSender and DB.ApplyTransaction(gdb, tx) then
            applied = applied + 1
        end
    end
    if applied > 0 then refreshUI() end
end)

Comm.RegisterHandler("TRANSFER", function(payload, sender)
    local gdb = DB.GetGuildDB()
    if not gdb then return end
    local debitTx, creditTx = payload.debitTx, payload.creditTx
    if not debitTx or not creditTx then return end
    -- No rank check -- transfers aren't rank-gated. The anti-spoof bar
    -- here is narrower but just as firm: the actor claimed on both halves
    -- must be the message's real (unforgeable) sender, and
    -- ApplyTransferPair enforces the debit can only ever target that same
    -- identity, so nobody can move coins out of someone else's wallet.
    local shortSender = CC.Utils.ShortName(sender)
    if debitTx.actor ~= shortSender or creditTx.actor ~= shortSender then return end
    if DB.ApplyTransferPair(gdb, debitTx, creditTx) then
        refreshUI()
    end
end)

Comm.RegisterHandler("SYNCREQ", function(_, sender)
    local gdb = DB.GetGuildDB()
    if not gdb or #gdb.ledger == 0 then return end
    if CC.Utils.ShortName(sender) == UnitName("player") then return end
    -- Only officers/GM/admin serve sync requests, so everyone -- members
    -- and officers alike -- always ends up syncing with a trusted source
    -- rather than a random guildmate's possibly-stale local copy.
    if not Perm.PlayerIsOfficer() then return end
    local delay = 0.5 + math.random() * 2
    C_Timer.After(delay, function()
        Comm.Send({ mt = "SYNCRESP", txs = gdb.ledger }, "WHISPER", sender)
    end)
end)

Comm.RegisterHandler("SYNCRESP", function(payload, sender)
    local gdb = DB.GetGuildDB()
    if not gdb then return end

    -- SYNCRESP relays a peer's whole ledger, most of which we've usually
    -- already got -- only the genuinely new entries are worth anyone's
    -- attention (or an officer's review). Applying is still idempotent
    -- either way, this is purely about not spamming a reviewer with
    -- hundreds of things they've already seen.
    local newTxs = {}
    for _, tx in ipairs(payload.txs or {}) do
        if tx.id and not gdb.ledgerIndex[tx.id] then
            table.insert(newTxs, tx)
        end
    end
    if #newTxs == 0 then return end

    if Perm.PlayerIsOfficer() then
        -- Officers/GM/admin review what's incoming and explicitly accept
        -- or deny it, rather than silently merging into the ledger they're
        -- the trusted source for.
        if CC.UI.SyncReview then
            CC.UI.SyncReview.Show(CC.Utils.ShortName(sender), newTxs)
        else
            Sync.MergeIncoming(gdb, newTxs)
        end
    else
        -- Regular members keep the simple, silent auto-merge -- they're
        -- only ever syncing with an officer in the first place now.
        Sync.MergeIncoming(gdb, newTxs)
    end
end)

Comm.RegisterHandler("SNAPSHOT", function(payload, sender)
    local gdb = DB.GetGuildDB()
    if not gdb then return end
    if not Perm.IsAdmin(sender) then return end

    gdb.members = payload.members or {}
    gdb.ledger = payload.ledger or {}
    gdb.ledgerIndex = {}
    for _, tx in ipairs(gdb.ledger) do
        gdb.ledgerIndex[tx.id] = true
    end
    DB.RecomputeAllBalances(gdb)
    refreshUI()

    print(string.format("|cffff4040Crimson Coin:|r %s restored guild data from a backup (%s). Your ledger has been synced to match.",
        sender, payload.label ~= "" and payload.label or "unlabeled"))
end)
