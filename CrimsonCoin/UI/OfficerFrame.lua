local ADDON, CC = ...

CC.UI = CC.UI or {}
CC.UI.Officer = {}
local Officer = CC.UI.Officer

local ROW_HEIGHT = 20
local ROW_WIDTH = 300
local MAX_ROWS = 500 -- sanity cap; a guild roster realistically never approaches this

local frame
local rows = {}
local selectedMember = nil
local manageTab, backupTab
local sortMode = "coins" -- "coins" or "name" -- same default as the wallet window
local searchText = ""
local refreshRoster -- forward-declared: createRow's OnClick below needs to call it

local function buildMemberList()
    local gdb = CC.DB.GetGuildDB()
    local list = {}
    for _, info in ipairs(CC.Perm.GetRosterList()) do
        local name = info.name
        if searchText == "" or name:lower():find(searchText, 1, true) then
            local member = gdb and gdb.members[name]
            table.insert(list, { name = name, coins = member and member.coins or 0, class = info.class })
        end
    end

    if sortMode == "coins" then
        table.sort(list, function(a, b)
            if a.coins == b.coins then return a.name < b.name end
            return a.coins > b.coins
        end)
    else
        table.sort(list, function(a, b) return a.name < b.name end)
    end

    return list
end

local function createRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(0.6, 0.1, 0.1, 0.35)
    row.highlight:Hide()

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.name:SetPoint("LEFT", 4, 0)
    row.name:SetWidth(180)
    row.name:SetJustifyH("LEFT")

    row.coins = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.coins:SetPoint("RIGHT", -6, 0)
    row.coins:SetTextColor(1, 0.35, 0.35)

    row:SetScript("OnClick", function(self)
        if self.entryName then
            selectedMember = self.entryName
            refreshRoster()
        end
    end)

    return row
end

local function ensureRow(index)
    if not rows[index] then
        rows[index] = createRow(frame.content, index)
    end
    return rows[index]
end

-- One row per member, laid out directly (no virtualized windowing/offset
-- math) -- the scroll frame's native SetVerticalScroll handles showing the
-- right slice. See MainFrame.lua for why FauxScrollFrameTemplate was
-- dropped in favor of this pattern.
refreshRoster = function()
    if not frame or not frame:IsShown() then return end
    local list = buildMemberList()
    local n = math.min(#list, MAX_ROWS)

    for i = 1, n do
        local row = ensureRow(i)
        local entry = list[i]
        row.name:SetText(CC.Utils.ClassColorize(entry.class, entry.name))
        row.coins:SetText(tostring(entry.coins))
        row.entryName = entry.name
        row:Show()
        if entry.name == selectedMember then
            row.highlight:Show()
        else
            row.highlight:Hide()
        end
    end
    for i = n + 1, #rows do
        rows[i].entryName = nil
        rows[i]:Hide()
    end

    frame.content:SetSize(ROW_WIDTH, math.max(n, 1) * ROW_HEIGHT)
    frame.scroll:UpdateScrollChildRect()

    frame.selectedLabel:SetText(selectedMember and ("Selected: " .. selectedMember) or "Selected: (none)")
end

local function doAdjust(sign)
    if not selectedMember then
        print("|cffff4040Crimson Coin:|r Select a member first.")
        return
    end
    local amount = tonumber(frame.amountBox:GetText())
    if not amount or amount <= 0 then
        print("|cffff4040Crimson Coin:|r Enter a positive amount.")
        return
    end
    local reason = frame.reasonBox:GetText()
    local ok, err = CC.Sync.SubmitTransaction(selectedMember, sign * amount, reason)
    if not ok then
        print("|cffff4040Crimson Coin:|r " .. tostring(err))
    else
        print(string.format("|cffff4040Crimson Coin:|r %s%d coin(s) %s %s.",
            sign > 0 and "+" or "-", amount, sign > 0 and "awarded to" or "removed from", selectedMember))
        frame.amountBox:SetText("")
        frame.reasonBox:SetText("")
    end
end

-- A note is just a zero-delta ledger transaction: it rides the exact same
-- signed/synced/persisted pipeline as a coin award (same permission check,
-- same idempotent replication to other officers), and shows up in the
-- member's transaction history for free since it's the same ledger. The
-- amount box is ignored entirely -- notes never move coins.
local function doAddNote()
    if not selectedMember then
        print("|cffff4040Crimson Coin:|r Select a member first.")
        return
    end
    local note = CC.Utils.Trim(frame.reasonBox:GetText())
    if note == "" then
        print("|cffff4040Crimson Coin:|r Enter a note first.")
        return
    end
    local ok, err = CC.Sync.SubmitTransaction(selectedMember, 0, note)
    if not ok then
        print("|cffff4040Crimson Coin:|r " .. tostring(err))
    else
        print(string.format("|cffff4040Crimson Coin:|r Note added for %s.", selectedMember))
        frame.reasonBox:SetText("")
    end
end

local function buildManageTab(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local scroll = CreateFrame("ScrollFrame", "CrimsonCoinOfficerScroll", p)
    scroll:SetPoint("TOPLEFT", 0, -54) -- below the header/refresh/sync row and the search/sort row
    scroll:SetPoint("BOTTOMRIGHT", 0, 118) -- leaves room for the control section below; see its own comment
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, (frame.content:GetHeight() or 0) - self:GetHeight())
        local newScroll = self:GetVerticalScroll() - delta * (ROW_HEIGHT * 3)
        if newScroll < 0 then newScroll = 0 end
        if newScroll > maxScroll then newScroll = maxScroll end
        self:SetVerticalScroll(newScroll)
    end)
    frame.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(ROW_WIDTH, ROW_HEIGHT)
    scroll:SetScrollChild(content)
    frame.content = content

    local header = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", 0, -2)
    header:SetText("Select a member:")

    -- Pulls the guild's member list itself from the server -- separate
    -- from ledger sync, since one showing up doesn't guarantee the other has.
    local refreshRosterBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    refreshRosterBtn:SetSize(104, 18)
    refreshRosterBtn:SetPoint("TOPRIGHT", 0, 2)
    refreshRosterBtn:SetText("Refresh Roster")
    refreshRosterBtn:SetScript("OnClick", function()
        CC.Perm.RefreshRoster()
        Officer.Refresh()
        print("|cffff4040Crimson Coin:|r Refreshing guild roster...")
    end)

    -- Pulls ledger/transaction history, separate from the roster refresh
    -- above -- same action as the wallet window's "Sync" button.
    local syncBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    syncBtn:SetSize(56, 18)
    syncBtn:SetPoint("RIGHT", refreshRosterBtn, "LEFT", -4, 0)
    syncBtn:SetText("Sync")
    syncBtn:SetScript("OnClick", function()
        CC.Sync.RequestSync()
        print("|cffff4040Crimson Coin:|r Requested a sync from the guild.")
    end)

    -- Search + sort, same behavior as the wallet window's roster list.
    local searchLabel = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 0, -28)
    searchLabel:SetText("Search:")

    local search = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    search:SetSize(100, 18)
    search:SetPoint("LEFT", searchLabel, "RIGHT", 6, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        searchText = self:GetText():lower()
        refreshRoster()
    end)

    local sortLabel = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sortLabel:SetPoint("LEFT", search, "RIGHT", 14, 0)
    sortLabel:SetText("Sort:")

    local sortNameBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    sortNameBtn:SetSize(58, 18)
    sortNameBtn:SetPoint("LEFT", sortLabel, "RIGHT", 4, 0)
    sortNameBtn:SetText("Name")
    sortNameBtn:SetScript("OnClick", function() sortMode = "name"; refreshRoster() end)

    local sortCoinsBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    sortCoinsBtn:SetSize(58, 18)
    sortCoinsBtn:SetPoint("LEFT", sortNameBtn, "RIGHT", 4, 0)
    sortCoinsBtn:SetText("Coins")
    sortCoinsBtn:SetScript("OnClick", function() sortMode = "coins"; refreshRoster() end)

    -- Bottom control section: anchored from the body's own bottom edge
    -- upward (rather than large negative TOPLEFT offsets from the top),
    -- so its total height is always visibly bounded by what's actually
    -- left of the panel instead of silently running off the window.
    local addBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    addBtn:SetSize(90, 22)
    addBtn:SetPoint("BOTTOMLEFT", 0, 8)
    addBtn:SetText("Add Coins")
    addBtn:SetScript("OnClick", function() doAdjust(1) end)

    local removeBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    removeBtn:SetSize(90, 22)
    removeBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    removeBtn:SetText("Remove Coins")
    removeBtn:SetScript("OnClick", function() doAdjust(-1) end)

    local noteBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    noteBtn:SetSize(90, 22)
    noteBtn:SetPoint("LEFT", removeBtn, "RIGHT", 6, 0)
    noteBtn:SetText("Add Note")
    noteBtn:SetScript("OnClick", doAddNote)

    local reasonLabel = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    reasonLabel:SetPoint("BOTTOMLEFT", 0, 38)
    reasonLabel:SetText("Reason / Note")

    local reasonBox = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    reasonBox:SetSize(260, 20)
    reasonBox:SetPoint("BOTTOMLEFT", 100, 38)
    reasonBox:SetAutoFocus(false)
    frame.reasonBox = reasonBox

    local amountLabel = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    amountLabel:SetPoint("BOTTOMLEFT", 0, 64)
    amountLabel:SetText("Amount")

    local amountBox = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    amountBox:SetSize(80, 20)
    amountBox:SetPoint("BOTTOMLEFT", 100, 64)
    amountBox:SetAutoFocus(false)
    amountBox:SetNumeric(true)
    frame.amountBox = amountBox

    frame.selectedLabel = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.selectedLabel:SetPoint("BOTTOMLEFT", 0, 92)

    local historyBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    historyBtn:SetSize(80, 20)
    historyBtn:SetPoint("LEFT", frame.selectedLabel, "RIGHT", 10, 0)
    historyBtn:SetText("History")
    historyBtn:SetScript("OnClick", function()
        if not selectedMember then
            print("|cffff4040Crimson Coin:|r Select a member first.")
        elseif CC.UI.History then
            CC.UI.History.Show(selectedMember)
        else
            print("|cffff4040Crimson Coin ERROR|r History window unavailable (UI/HistoryFrame.lua did not load).")
        end
    end)

    return p
end

-- Backups tab --------------------------------------------------------

local backupRows = {}
local BACKUP_ROWS = 8

local function refreshBackups()
    if not frame or not frame:IsShown() then return end
    local list = CC.Backup.List()
    for i = 1, BACKUP_ROWS do
        local row = backupRows[i]
        local b = list[i]
        if b then
            row.label:SetText(string.format("%s - %s (%s)", CC.Utils.FormatTime(b.time), CC.Utils.EscapeText(b.label), b.by))
            row.backupId = b.id
            row.restoreBtn:SetShown(CC.Perm.PlayerIsAdmin())
            row.deleteBtn:SetShown(CC.Perm.PlayerIsOfficer())
            row:Show()
        else
            row:Hide()
        end
    end
end

local function confirmRestore(backupId, label)
    StaticPopupDialogs["CRIMSONCOIN_RESTORE_CONFIRM"] = {
        text = "Restore guild data from backup:\n" .. label ..
            "\n\nThis overwrites the CURRENT ledger and balances for everyone using Crimson Coin, and pushes the restored data to the guild. This cannot be undone except by restoring another backup.\n\nType RESTORE to confirm.",
        hasEditBox = true,
        button1 = "Restore",
        button2 = "Cancel",
        OnAccept = function(self)
            local ok, err = pcall(function()
                local editBox = CC.Utils.GetPopupEditBox(self)
                local text = CC.Utils.NormalizeConfirmText(editBox and editBox:GetText())
                if text == "RESTORE" then
                    local restored, restoreErr = CC.Backup.Restore(backupId)
                    if restored then
                        print("|cffff4040Crimson Coin:|r Backup restored.")
                    else
                        print("|cffff4040Crimson Coin:|r Restore failed: " .. tostring(restoreErr))
                    end
                else
                    print("|cffff4040Crimson Coin:|r Restore cancelled (confirmation text did not match).")
                end
            end)
            if not ok then
                print("|cffff4040Crimson Coin ERROR|r [Restore confirm]: " .. tostring(err))
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("CRIMSONCOIN_RESTORE_CONFIRM")
end

local function buildBackupTab(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local header = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", 0, -2)
    header:SetText("Backups (most recent first)")

    for i = 1, BACKUP_ROWS do
        local row = CreateFrame("Frame", nil, p)
        row:SetSize(380, 24)
        row:SetPoint("TOPLEFT", 0, -20 - (i - 1) * 26)

        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        row.label:SetPoint("LEFT", 0, 0)
        row.label:SetWidth(190)
        row.label:SetJustifyH("LEFT")

        row.deleteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.deleteBtn:SetSize(64, 20)
        row.deleteBtn:SetPoint("RIGHT", 0, 0)
        row.deleteBtn:SetText("Delete")
        row.deleteBtn:SetScript("OnClick", function()
            CC.Backup.ConfirmDeleteBackup(row.backupId, row.label:GetText())
        end)

        row.restoreBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.restoreBtn:SetSize(72, 20)
        row.restoreBtn:SetPoint("RIGHT", row.deleteBtn, "LEFT", -6, 0)
        row.restoreBtn:SetText("Restore")
        row.restoreBtn:SetScript("OnClick", function()
            confirmRestore(row.backupId, row.label:GetText())
        end)

        backupRows[i] = row
        row:Hide()
    end

    local createBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    createBtn:SetSize(140, 22)
    createBtn:SetPoint("BOTTOMLEFT", 0, 20)
    createBtn:SetText("Create Backup Now")
    createBtn:SetScript("OnClick", function()
        local backup, err = CC.Backup.Create()
        if backup then
            print("|cffff4040Crimson Coin:|r Backup created.")
            refreshBackups()
        else
            print("|cffff4040Crimson Coin:|r " .. tostring(err))
        end
    end)

    local clearCacheBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    clearCacheBtn:SetSize(160, 22)
    clearCacheBtn:SetPoint("BOTTOMLEFT", createBtn, "TOPLEFT", 0, 8)
    clearCacheBtn:SetText("Clear Local Cache")
    clearCacheBtn:SetScript("OnClick", function() CC.Backup.ConfirmClearAll() end)

    return p
end

-- Frame shell ----------------------------------------------------------

local function showTab(which)
    if which == "manage" then
        manageTab:Show()
        backupTab:Hide()
        refreshRoster()
    else
        manageTab:Hide()
        backupTab:Show()
        refreshBackups()
    end
end

local function build()
    frame = CreateFrame("Frame", "CrimsonCoinOfficerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(440, 500)
    frame:SetPoint("CENTER", 200, 0)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0.05, 0.02, 0.02, 0.95)
    frame:SetBackdropBorderColor(0.5, 0.05, 0.05, 1)

    CC.Utils.AddLogo(frame, 28)

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("|cffff4040Crimson Coin - Officer Panel|r")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)

    local helpBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    helpBtn:SetSize(50, 18)
    helpBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -2, -2)
    helpBtn:SetText("Help")
    helpBtn:SetScript("OnClick", function()
        if CC.UI.Help then
            CC.UI.Help.Show()
        else
            print("|cffff4040Crimson Coin ERROR|r Help window unavailable (UI/HelpFrame.lua did not load).")
        end
    end)

    local manageBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    manageBtn:SetSize(90, 22)
    manageBtn:SetPoint("TOPLEFT", 20, -40)
    manageBtn:SetText("Home")
    manageBtn:SetScript("OnClick", function() showTab("manage") end)

    local backupBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    backupBtn:SetSize(90, 22)
    backupBtn:SetPoint("LEFT", manageBtn, "RIGHT", 6, 0)
    backupBtn:SetText("Backups")
    backupBtn:SetScript("OnClick", function() showTab("backup") end)

    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 20, -68)
    body:SetPoint("BOTTOMRIGHT", -20, 20)

    manageTab = buildManageTab(body)
    backupTab = buildBackupTab(body)
    backupTab:Hide()

    frame:SetScript("OnShow", function() showTab("manage") end)

    tinsert(UISpecialFrames, "CrimsonCoinOfficerFrame")
end

function Officer.Refresh()
    if not frame then return end
    local ok, err = pcall(function()
        CC.Perm.RefreshRoster()
        refreshRoster()
        refreshBackups()
    end)
    if not ok then
        print("|cffff4040Crimson Coin ERROR|r [Officer.Refresh]: " .. tostring(err))
    end
end

function Officer.Toggle()
    if not CC.Perm.PlayerIsOfficer() then
        print("|cffff4040Crimson Coin:|r Your guild rank does not have officer access.")
        return
    end
    if not frame then build() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end
