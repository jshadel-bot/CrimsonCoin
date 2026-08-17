local ADDON, CC = ...

CC.UI = CC.UI or {}
CC.UI.SendCoins = {}
local SendCoins = CC.UI.SendCoins

local ROW_HEIGHT = 20
local ROW_WIDTH = 320

local frame
local rows = {}
local selectedRecipient = nil

local function buildRosterList()
    local myName = UnitName("player")
    local searchText = frame.search and frame.search:GetText():lower() or ""
    local list = {}
    for _, info in ipairs(CC.Perm.GetRosterList()) do
        if info.name ~= myName and (searchText == "" or info.name:lower():find(searchText, 1, true)) then
            table.insert(list, info)
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function createRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetHighlightTexture("Interface/QuestFrame/UI-QuestTitleHighlight", "ADD")

    row.check = row:CreateTexture(nil, "ARTWORK")
    row.check:SetSize(14, 14)
    row.check:SetPoint("LEFT", 4, 0)
    row.check:SetTexture("Interface/Buttons/UI-CheckBox-Check")
    row.check:Hide()

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.name:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
    row.name:SetWidth(ROW_WIDTH - 26)
    row.name:SetJustifyH("LEFT")
    row.name:SetTextColor(1, 1, 1)

    row:SetScript("OnClick", function(self)
        if not self.entryName then return end
        selectedRecipient = self.entryName
        SendCoins.RefreshRoster()
    end)

    return row
end

local function ensureRow(index)
    if not rows[index] then
        rows[index] = createRow(frame.content, index)
    end
    return rows[index]
end

function SendCoins.RefreshRoster()
    if not frame or not frame:IsShown() then return end

    local list = buildRosterList()
    for i, info in ipairs(list) do
        local row = ensureRow(i)
        row.entryName = info.name
        row.name:SetText(CC.Utils.ClassColorize(info.class, info.name))
        row.check:SetShown(info.name == selectedRecipient)
        row:Show()
    end
    for i = #list + 1, #rows do
        rows[i]:Hide()
    end

    frame.content:SetSize(ROW_WIDTH, math.max(#list, 1) * ROW_HEIGHT)
    frame.scroll:UpdateScrollChildRect()

    frame.selectedLabel:SetText(selectedRecipient and ("To: " .. selectedRecipient) or "To: (click a member below)")

    local gdb = CC.DB.GetGuildDB()
    local balance = gdb and CC.DB.GetBalance(gdb, UnitName("player")) or 0
    frame.balanceLabel:SetText(string.format("Your balance: %d Crimson Coin", balance))
end

local function doSend()
    if not selectedRecipient then
        print("|cffff4040Crimson Coin:|r Choose a recipient first.")
        return
    end
    local amount = tonumber(frame.amountBox:GetText())
    if not amount or amount <= 0 then
        print("|cffff4040Crimson Coin:|r Enter a positive amount.")
        return
    end

    local recipient, note = selectedRecipient, frame.noteBox:GetText()

    StaticPopupDialogs["CRIMSONCOIN_SEND_CONFIRM"] = {
        text = string.format("Send %d Crimson Coin to %s?", amount, recipient),
        button1 = "Send",
        button2 = "Cancel",
        OnAccept = function()
            local ok, err = pcall(function()
                local sent, sendErr = CC.Sync.SubmitTransfer(recipient, amount, note)
                if sent then
                    print(string.format("|cffff4040Crimson Coin:|r Sent %d coin(s) to %s.", amount, recipient))
                    frame.amountBox:SetText("")
                    frame.noteBox:SetText("")
                    SendCoins.RefreshRoster()
                else
                    print("|cffff4040Crimson Coin:|r Send failed: " .. tostring(sendErr))
                end
            end)
            if not ok then
                print("|cffff4040Crimson Coin ERROR|r [Send confirm]: " .. tostring(err))
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("CRIMSONCOIN_SEND_CONFIRM")
end

local function build()
    frame = CreateFrame("Frame", "CrimsonCoinSendFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 460)
    frame:SetPoint("CENTER", -150, 0)
    frame:SetFrameStrata("DIALOG")
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
    frame:SetBackdropColor(0.05, 0.02, 0.02, 0.97)
    frame:SetBackdropBorderColor(0.5, 0.05, 0.05, 1)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() frame:Hide() end)

    CC.Utils.AddLogo(frame, 28)

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("|cffff4040Send Crimson Coin|r")

    frame.balanceLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.balanceLabel:SetPoint("TOP", 0, -38)
    frame.balanceLabel:SetTextColor(1, 0.82, 0)

    local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    search:SetSize(160, 20)
    search:SetPoint("TOPLEFT", 24, -64)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function() SendCoins.RefreshRoster() end)
    frame.search = search

    local searchLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchLabel:SetPoint("BOTTOMLEFT", search, "TOPLEFT", 2, 2)
    searchLabel:SetText("Search recipient")

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 24, -92)
    scroll:SetPoint("BOTTOMRIGHT", -24, 172)
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

    frame.selectedLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.selectedLabel:SetPoint("BOTTOMLEFT", 24, 138)

    local amountLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    amountLabel:SetPoint("BOTTOMLEFT", 24, 110)
    amountLabel:SetText("Amount")

    frame.amountBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.amountBox:SetSize(80, 20)
    frame.amountBox:SetPoint("LEFT", amountLabel, "RIGHT", 12, 0)
    frame.amountBox:SetAutoFocus(false)
    frame.amountBox:SetNumeric(true)

    local noteLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    noteLabel:SetPoint("BOTTOMLEFT", 24, 84)
    noteLabel:SetText("Note")

    frame.noteBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.noteBox:SetSize(240, 20)
    frame.noteBox:SetPoint("LEFT", noteLabel, "RIGHT", 12, 0)
    frame.noteBox:SetAutoFocus(false)

    local sendBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sendBtn:SetSize(120, 24)
    sendBtn:SetPoint("BOTTOM", 0, 40)
    sendBtn:SetText("Send")
    sendBtn:SetScript("OnClick", doSend)

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 16)
    hint:SetText("Coins move only if you actually have them -- verified by every officer's client")

    tinsert(UISpecialFrames, "CrimsonCoinSendFrame")
end

function SendCoins.Show()
    local ok, err = pcall(function()
        if not frame then build() end
        CC.Perm.RefreshRoster()
        selectedRecipient = nil
        frame.amountBox:SetText("")
        frame.noteBox:SetText("")
        frame.search:SetText("")
        frame:Show()
        SendCoins.RefreshRoster()
    end)
    if not ok then
        print("|cffff4040Crimson Coin ERROR|r [SendCoins.Show]: " .. tostring(err))
    end
end

function SendCoins.Toggle()
    if not frame then
        SendCoins.Show()
        return
    end
    if frame:IsShown() then
        frame:Hide()
    else
        SendCoins.Show()
    end
end
