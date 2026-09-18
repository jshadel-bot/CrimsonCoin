local ADDON, CC = ...

CC.DB = {}
local DB = CC.DB
local Utils = CC.Utils

local SCHEMA_VERSION = 1

-- Hard cap on any single wallet, enforced at the same place every ledger
-- entry is admitted (DB.ApplyTransaction) so it's checked independently
-- by every client, not just trusted from whoever submitted the award or
-- transfer -- same trust philosophy as the balance/rank checks elsewhere.
DB.MAX_WALLET_BALANCE = 10000

local function defaultGuildData()
    return {
        members = {},      -- [name] = { coins = 0, class = "WARRIOR", rankIndex = n, rankName = "", lastSeen = ts, online = false }
        ledgerIndex = {},  -- [id] = true  (set, for O(1) dedupe)
        ledger = {},        -- ordered array of transactions, append-only
        backups = {},        -- array of { id, time, label, by, snapshot = { members, ledger } }
        settings = {
            -- Guild rank NAMES (lowercased) allowed to add/remove currency,
            -- and to restore backups. Rank names are what officers actually
            -- recognize in-game, and unlike rank index they don't silently
            -- shift if someone reorders the guild's rank list.
            officerRanks = { ["guild master"] = true, ["officer"] = true },
            adminRanks = { ["guild master"] = true },
            -- Character names (lowercased, no realm) that always have admin
            -- access regardless of guild rank. See Permissions.lua for why
            -- a name match is a safe trust anchor.
            superAdmins = { ["grimbot"] = true },
            autoBackupIntervalSeconds = 86400,
            lastAutoBackup = 0,
        },
    }
end

-- CrimsonCoinDB is declared in the .toc as a SavedVariable (account-wide).
function DB.Init()
    if type(CrimsonCoinDB) ~= "table" then
        CrimsonCoinDB = { schemaVersion = SCHEMA_VERSION, guilds = {} }
    end
    if not CrimsonCoinDB.guilds then
        CrimsonCoinDB.guilds = {}
    end
    CrimsonCoinDB.schemaVersion = CrimsonCoinDB.schemaVersion or SCHEMA_VERSION
end

local function ensureGuild(key)
    if not CrimsonCoinDB.guilds[key] then
        CrimsonCoinDB.guilds[key] = defaultGuildData()
    else
        -- backfill any fields added in later versions
        local g = CrimsonCoinDB.guilds[key]
        g.members = g.members or {}
        g.ledgerIndex = g.ledgerIndex or {}
        g.ledger = g.ledger or {}
        g.backups = g.backups or {}
        g.settings = g.settings or defaultGuildData().settings
        -- Migrate from the old numeric rank-index thresholds to rank-name sets.
        if not g.settings.officerRanks then
            g.settings.officerRanks = { ["guild master"] = true, ["officer"] = true }
        end
        if not g.settings.adminRanks then
            g.settings.adminRanks = { ["guild master"] = true }
        end
        if not g.settings.superAdmins then
            g.settings.superAdmins = { ["grimbot"] = true }
        end
        g.settings.officerRankThreshold = nil
        g.settings.adminRankThreshold = nil
    end
    return CrimsonCoinDB.guilds[key]
end

-- Returns the active guild's data table, or nil if the player isn't in a guild.
function DB.GetGuildDB()
    local key = Utils.CurrentGuildKey()
    if not key then return nil, nil end
    return ensureGuild(key), key
end

function DB.EnsureMember(gdb, name)
    if not gdb.members[name] then
        gdb.members[name] = { coins = 0, class = nil, rankIndex = nil, rankName = nil, lastSeen = 0 }
    end
    return gdb.members[name]
end

-- Applying a transaction is idempotent (keyed by tx.id) and commutative --
-- replaying the ledger in any order over any starting point converges to
-- the same balances, which is what makes peer-to-peer sync safe without a
-- central authority.
function DB.ApplyTransaction(gdb, tx)
    if not tx or not tx.id or gdb.ledgerIndex[tx.id] then
        return false -- duplicate or malformed, ignore
    end
    if type(tx.delta) ~= "number" or type(tx.target) ~= "string" or type(tx.actor) ~= "string" then
        return false
    end

    -- The wallet cap only ever blocks NEW admissions that would push a
    -- balance up past it -- it never rejects a debit/note (delta <= 0), so
    -- officers can always correct an over-cap wallet back down, and it
    -- never retroactively rejects anything during a full ledger replay
    -- (DB.RecomputeAllBalances doesn't call this function at all).
    if tx.delta > 0 and DB.GetBalance(gdb, tx.target) + tx.delta > DB.MAX_WALLET_BALANCE then
        return false
    end

    gdb.ledgerIndex[tx.id] = true
    table.insert(gdb.ledger, tx)

    local member = DB.EnsureMember(gdb, tx.target)
    member.coins = (member.coins or 0) + tx.delta

    return true
end

function DB.GetBalance(gdb, name)
    local m = gdb.members[name]
    return m and m.coins or 0
end

-- Applies a member-to-member transfer as a validated debit/credit pair.
-- Unlike an officer award (DB.ApplyTransaction, trusted by rank), a
-- transfer is trusted by arithmetic: no rank check happens here at all --
-- any member can send. What makes it safe is:
--   1. the debit MUST target the same identity as its actor (you can only
--      ever debit your own wallet, never someone else's), and
--   2. the debit is only accepted if THIS CLIENT'S OWN computed balance
--      for that person can currently cover it.
-- Both halves are still deduped by id via ApplyTransaction, so replaying
-- an already-applied pair (e.g. a later SYNCRESP catch-up) is a no-op
-- rather than a second balance check against a moved-on balance.
function DB.ApplyTransferPair(gdb, debitTx, creditTx)
    if not debitTx or not creditTx then return false end

    if gdb.ledgerIndex[debitTx.id] and gdb.ledgerIndex[creditTx.id] then
        return false -- already applied, nothing new happened
    end

    if type(debitTx.delta) ~= "number" or type(creditTx.delta) ~= "number" then return false end
    if type(debitTx.actor) ~= "string" or type(creditTx.actor) ~= "string" then return false end
    if type(debitTx.target) ~= "string" or type(creditTx.target) ~= "string" then return false end
    if debitTx.actor ~= creditTx.actor then return false end       -- one sender authored both halves
    if debitTx.target ~= debitTx.actor then return false end       -- can only debit your own wallet
    if creditTx.target == debitTx.target then return false end     -- no self-transfers
    if debitTx.delta >= 0 or creditTx.delta <= 0 then return false end
    if debitTx.delta ~= -creditTx.delta then return false end      -- must net exactly zero

    if DB.GetBalance(gdb, debitTx.target) + debitTx.delta < 0 then
        return false -- insufficient funds per this client's own ledger view
    end

    -- Checked here too, before either half applies, so a recipient at/near
    -- the cap can't end up with the sender debited and nothing delivered
    -- (ApplyTransaction would reject the credit on its own, but only
    -- *after* the debit had already gone through).
    if DB.GetBalance(gdb, creditTx.target) + creditTx.delta > DB.MAX_WALLET_BALANCE then
        return false -- would push the recipient over the wallet cap
    end

    local a1 = DB.ApplyTransaction(gdb, debitTx)
    local a2 = DB.ApplyTransaction(gdb, creditTx)
    return a1 or a2
end

function DB.RecomputeAllBalances(gdb)
    for _, m in pairs(gdb.members) do
        m.coins = 0
    end
    for _, tx in ipairs(gdb.ledger) do
        local member = DB.EnsureMember(gdb, tx.target)
        member.coins = (member.coins or 0) + tx.delta
    end
end

-- Snapshot / restore --------------------------------------------------

function DB.CreateBackup(gdb, label, by)
    local snapshot = {
        members = CopyTable(gdb.members),
        ledger = CopyTable(gdb.ledger),
        ledgerIndex = CopyTable(gdb.ledgerIndex),
    }
    local backup = {
        id = Utils.NewId(),
        time = Utils.Now(),
        label = label or "Manual backup",
        by = by or UnitName("player"),
        snapshot = snapshot,
    }
    table.insert(gdb.backups, 1, backup) -- newest first

    -- keep the most recent 25 backups to bound SavedVariables growth
    while #gdb.backups > 25 do
        table.remove(gdb.backups)
    end

    return backup
end

function DB.RestoreBackup(gdb, backupId)
    for _, b in ipairs(gdb.backups) do
        if b.id == backupId then
            gdb.members = CopyTable(b.snapshot.members)
            gdb.ledger = CopyTable(b.snapshot.ledger)
            gdb.ledgerIndex = CopyTable(b.snapshot.ledgerIndex)
            DB.RecomputeAllBalances(gdb)
            return true
        end
    end
    return false
end

-- Wipes this client's local copy of the guild's ledger/balances. Purely
-- local: unlike RestoreBackup, nothing is broadcast, so it never touches
-- any other guild member's data. Backups are deliberately left alone --
-- they're the safety net a "clear everything and start over" action
-- would otherwise be most likely to want back; delete them individually
-- with DB.DeleteBackup instead. Settings (rank lists, thresholds) are
-- left alone too, since those are configuration, not history.
function DB.ClearAll(gdb)
    gdb.members = {}
    gdb.ledger = {}
    gdb.ledgerIndex = {}
end

-- Permanently removes one local backup snapshot. Backups are never
-- synced/broadcast, so this only ever affects this client.
function DB.DeleteBackup(gdb, backupId)
    for i, b in ipairs(gdb.backups) do
        if b.id == backupId then
            table.remove(gdb.backups, i)
            return true
        end
    end
    return false
end

-- Fallback for clients where CopyTable might not exist (it's a global
-- Blizzard utility function and has existed for a long time, but guard
-- anyway since this addon must not error on load).
if type(CopyTable) ~= "function" then
    function CopyTable(t)
        if type(t) ~= "table" then return t end
        local copy = {}
        for k, v in pairs(t) do
            copy[k] = type(v) == "table" and CopyTable(v) or v
        end
        return copy
    end
end
