local ADDON, CC = ...

CC.UI = CC.UI or {}
CC.UI.Main = {}
local Main = CC.UI.Main

local ROW_HEIGHT = 20
local VISIBLE_ROWS = 14

local frame
local rows = {}
local sortMode = "coins" -- "coins" or "name"
local searchText = ""

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
    row:SetSize(360, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")

    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.03)
    end

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetWidth(230)
    row.name:SetJustifyH("LEFT")

    row.coins = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.coins:SetPoint("RIGHT", -10, 0)
    row.coins:SetTextColor(1, 0.35, 0.35)

    row:SetScript("OnClick", function(self)
        if not self.entryName then return end
        if CC.UI.History then
            CC.UI.History.Show(self.entryName)
        else
            print("|cffff4040Crimson Coin ERROR|r History window unavailable (UI/HistoryFrame.lua did not load).")
        end
    end)

    return row
end

local function refreshRows()
    if not frame or not frame:IsShown() then return end
    local list = buildMemberList()

    FauxScrollFrame_Update(frame.scroll, #list, VISIBLE_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(frame.scroll)

    for i = 1, VISIBLE_ROWS do
        local row = rows[i]
        local dataIndex = i + offset
        local entry = list[dataIndex]
        if entry then
            row.name:SetText(CC.Utils.ClassColorize(entry.class, entry.name))
            row.coins:SetText(entry.coins .. "  |cffffd100cc|r")
            row.entryName = entry.name
            row:Show()
        else
            row.entryName = nil
            row:Hide()
        end
    end
end

local function updatePlayerWallet()
    local gdb = CC.DB.GetGuildDB()
    local myName = UnitName("player")
    local coins = gdb and CC.DB.GetBalance(gdb, myName) or 0
    frame.walletValue:SetText(coins .. "  |cffffd100Crimson Coin|r")
end

local function build()
    frame = CreateFrame("Frame", "CrimsonCoinMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 480)
    frame:SetPoint("CENTER")
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
    title:SetText("|cffff4040Crimson Coin - DKP Ledger|r")

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

    -- Wallet summary
    local walletLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    walletLabel:SetPoint("TOP", 0, -42)
    walletLabel:SetText("Your Balance")

    frame.walletValue = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    frame.walletValue:SetPoint("TOP", 0, -60)

    local historyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    historyBtn:SetSize(90, 18)
    historyBtn:SetPoint("TOP", frame.walletValue, "BOTTOM", -49, -6)
    historyBtn:SetText("History")
    historyBtn:SetScript("OnClick", function()
        if CC.UI.History then
            CC.UI.History.Show(UnitName("player"))
        else
            print("|cffff4040Crimson Coin ERROR|r History window unavailable (UI/HistoryFrame.lua did not load).")
        end
    end)

    local sendBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sendBtn:SetSize(90, 18)
    sendBtn:SetPoint("LEFT", historyBtn, "RIGHT", 8, 0)
    sendBtn:SetText("Send Coins")
    sendBtn:SetScript("OnClick", function()
        if CC.UI.SendCoins then
            CC.UI.SendCoins.Show()
        else
            print("|cffff4040Crimson Coin ERROR|r Send window unavailable (UI/SendCoinsFrame.lua did not load).")
        end
    end)

    -- Search box
    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(160, 20)
    search:SetPoint("TOPLEFT", 24, -122)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(self)
        searchText = self:GetText():lower()
        refreshRows()
    end)
    frame.search = search

    local searchLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchLabel:SetPoint("BOTTOMLEFT", search, "TOPLEFT", 2, 2)
    searchLabel:SetText("Search")

    -- Sort buttons
    local sortName = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sortName:SetSize(70, 20)
    sortName:SetPoint("TOPRIGHT", -100, -122)
    sortName:SetText("Name")
    sortName:SetScript("OnClick", function() sortMode = "name"; refreshRows() end)

    local sortCoins = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sortCoins:SetSize(70, 20)
    sortCoins:SetPoint("LEFT", sortName, "RIGHT", 4, 0)
    sortCoins:SetText("Coins")
    sortCoins:SetScript("OnClick", function() sortMode = "coins"; refreshRows() end)

    -- Roster header
    local header = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", 26, -150)
    header:SetText("Guild Roster  |cff888888(click a member for their history)|r")

    -- Scroll list
    local scroll = CreateFrame("ScrollFrame", "CrimsonCoinMainScroll", frame, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 24, -168)
    scroll:SetPoint("BOTTOMRIGHT", -44, 44)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, refreshRows)
    end)
    frame.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(360, ROW_HEIGHT * VISIBLE_ROWS)
    scroll:SetScrollChild(content)

    for i = 1, VISIBLE_ROWS do
        rows[i] = createRow(content, i)
    end

    -- Footer buttons
    local syncBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    syncBtn:SetSize(60, 22)
    syncBtn:SetPoint("BOTTOMLEFT", 20, 12)
    syncBtn:SetText("Sync")
    syncBtn:SetScript("OnClick", function()
        CC.Sync.RequestSync()
        print("|cffff4040Crimson Coin:|r Requested a sync from the guild.")
    end)

    -- "Sync" pulls transaction history from other addon users; this pulls
    -- the guild's member list itself from the server -- different data,
    -- separate button, since one showing up doesn't guarantee the other has.
    local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(112, 22)
    refreshBtn:SetPoint("LEFT", syncBtn, "RIGHT", 6, 0)
    refreshBtn:SetText("Refresh Roster")
    refreshBtn:SetScript("OnClick", function()
        CC.Perm.RefreshRoster()
        Main.Refresh()
        print("|cffff4040Crimson Coin:|r Refreshing guild roster...")
    end)

    local officerBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    officerBtn:SetSize(110, 22)
    officerBtn:SetPoint("BOTTOMRIGHT", -20, 12)
    officerBtn:SetText("Officer Panel")
    officerBtn:SetScript("OnClick", function() CC.UI.Officer.Toggle() end)
    frame.officerBtn = officerBtn

    frame:SetScript("OnShow", function()
        Main.Refresh()
    end)

    tinsert(UISpecialFrames, "CrimsonCoinMainFrame") -- allows Escape to close it
end

function Main.Refresh()
    if not frame then return end
    local ok, err = pcall(function()
        CC.Perm.RefreshRoster()
        updatePlayerWallet()
        refreshRows()
        if frame.officerBtn then
            frame.officerBtn:SetShown(CC.Perm.PlayerIsOfficer())
        end
    end)
    if not ok then
        print("|cffff4040Crimson Coin ERROR|r [Main.Refresh]: " .. tostring(err))
    end
end

function Main.Toggle()
    if not frame then build() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function Main.Show()
    if not frame then build() end
    frame:Show()
end
