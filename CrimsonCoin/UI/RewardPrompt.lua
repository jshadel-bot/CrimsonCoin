local ADDON, CC = ...

CC.UI = CC.UI or {}
CC.UI.Reward = {}
local Reward = CC.UI.Reward

local ROW_HEIGHT = 20
local MAX_ROWS = 12

local frame
local checkRows = {}
local pending = {}     -- queue of { boss, attendees }
local currentAttendees = {}

local function layoutRows()
    local n = #currentAttendees
    FauxScrollFrame_Update(frame.scroll, n, MAX_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(frame.scroll)
    for i = 1, MAX_ROWS do
        local row = checkRows[i]
        local entry = currentAttendees[i + offset]
        if entry then
            row.label:SetText(string.format("%s  |cff888888(%d%%)|r", entry.name, math.floor(entry.attendance * 100)))
            row.check.entry = entry
            row.check:SetChecked(true)
            entry.checked = true
            row:Show()
        else
            row.check.entry = nil
            row:Hide()
        end
    end
end

local function showNext()
    local job = table.remove(pending, 1)
    if not job then
        frame:Hide()
        return
    end
    currentAttendees = job.attendees
    frame.bossLabel:SetText("|cffff4040" .. job.boss .. "|r has been defeated!")
    frame.amountBox:SetText("")
    frame.reasonBox:SetText(job.boss .. " kill")
    frame:Show()
    layoutRows()
end

local function build()
    frame = CreateFrame("Frame", "CrimsonCoinRewardFrame", UIParent, "BackdropTemplate")
    frame:SetSize(380, 440)
    frame:SetPoint("CENTER", 0, 100)
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
    frame:SetBackdropBorderColor(0.8, 0.1, 0.1, 1)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() showNext() end)

    CC.Utils.AddLogo(frame, 28)

    frame.bossLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.bossLabel:SetPoint("TOP", 0, -16)
    frame.bossLabel:SetWidth(340)

    local sub = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sub:SetPoint("TOP", frame.bossLabel, "BOTTOM", 0, -6)
    sub:SetText("Award Crimson Coin to attendees who met the minimum attendance")

    local allBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    allBtn:SetSize(70, 18)
    allBtn:SetPoint("TOPLEFT", 20, -60)
    allBtn:SetText("All")
    allBtn:SetScript("OnClick", function()
        for _, e in ipairs(currentAttendees) do e.checked = true end
        for i = 1, MAX_ROWS do
            if checkRows[i].check.entry then checkRows[i].check:SetChecked(true) end
        end
    end)

    local noneBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    noneBtn:SetSize(70, 18)
    noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 4, 0)
    noneBtn:SetText("None")
    noneBtn:SetScript("OnClick", function()
        for _, e in ipairs(currentAttendees) do e.checked = false end
        for i = 1, MAX_ROWS do
            if checkRows[i].check.entry then checkRows[i].check:SetChecked(false) end
        end
    end)

    local scroll = CreateFrame("ScrollFrame", "CrimsonCoinRewardScroll", frame, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -86)
    scroll:SetPoint("BOTTOMRIGHT", -40, 140)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, layoutRows)
    end)
    frame.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(300, ROW_HEIGHT * MAX_ROWS)
    scroll:SetScrollChild(content)

    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(300, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)

        local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        check:SetPoint("LEFT", 0, 0)
        check:SetScript("OnClick", function(self)
            if self.entry then self.entry.checked = self:GetChecked() end
        end)
        row.check = check

        row.label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        row.label:SetPoint("LEFT", check, "RIGHT", 4, 0)

        checkRows[i] = row
    end

    local amountLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    amountLabel:SetPoint("BOTTOMLEFT", 20, 96)
    amountLabel:SetText("Coins each")

    frame.amountBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.amountBox:SetSize(80, 20)
    frame.amountBox:SetPoint("LEFT", amountLabel, "RIGHT", 8, 0)
    frame.amountBox:SetAutoFocus(false)
    frame.amountBox:SetNumeric(true)

    local reasonLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    reasonLabel:SetPoint("BOTTOMLEFT", 20, 70)
    reasonLabel:SetText("Reason")

    frame.reasonBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    frame.reasonBox:SetSize(240, 20)
    frame.reasonBox:SetPoint("LEFT", reasonLabel, "RIGHT", 8, 0)
    frame.reasonBox:SetAutoFocus(false)

    local awardBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    awardBtn:SetSize(120, 24)
    awardBtn:SetPoint("BOTTOM", -60, 20)
    awardBtn:SetText("Award")
    awardBtn:SetScript("OnClick", function()
        local amount = tonumber(frame.amountBox:GetText())
        if not amount or amount <= 0 then
            print("|cffff4040Crimson Coin:|r Enter a positive coin amount.")
            return
        end
        local reason = frame.reasonBox:GetText()
        local targets = {}
        for _, e in ipairs(currentAttendees) do
            if e.checked then table.insert(targets, e.name) end
        end
        if #targets == 0 then
            print("|cffff4040Crimson Coin:|r No attendees selected.")
            return
        end
        local paidCount, skipped = CC.Sync.SubmitBatch(targets, amount, reason)
        if paidCount > 0 then
            print(string.format("|cffff4040Crimson Coin:|r Awarded %d coin(s) to %d member(s).", amount, paidCount))
        end
        if #skipped > 0 then
            print(string.format("|cffff4040Crimson Coin:|r Skipped %d member(s) at/near the %d coin wallet cap: %s",
                #skipped, CC.DB.MAX_WALLET_BALANCE, table.concat(skipped, ", ")))
        end
        showNext()
    end)

    local skipBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    skipBtn:SetSize(90, 24)
    skipBtn:SetPoint("LEFT", awardBtn, "RIGHT", 8, 0)
    skipBtn:SetText("Skip")
    skipBtn:SetScript("OnClick", showNext)

    tinsert(UISpecialFrames, "CrimsonCoinRewardFrame")
end

function Reward.Show(bossName, attendees)
    if not frame then build() end
    table.insert(pending, { boss = bossName, attendees = attendees })
    if not frame:IsShown() then
        showNext()
    end
end
