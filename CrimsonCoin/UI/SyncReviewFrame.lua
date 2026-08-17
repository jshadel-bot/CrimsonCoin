local ADDON, CC = ...

CC.UI = CC.UI or {}
CC.UI.SyncReview = {}
local SyncReview = CC.UI.SyncReview

local ROW_HEIGHT = 20
local ROW_WIDTH = 420
local MAX_ROWS = 200

local frame
local rows = {}
local pending = {}   -- queue of { sender, txs }
local currentSender = nil
local currentTxs = {}

local function createRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(ROW_WIDTH, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

    if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.03)
    end

    row.dateText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.dateText:SetPoint("LEFT", 4, 0)
    row.dateText:SetWidth(95)
    row.dateText:SetJustifyH("LEFT")
    row.dateText:SetTextColor(1, 1, 1)

    row.amountText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.amountText:SetPoint("LEFT", row.dateText, "RIGHT", 4, 0)
    row.amountText:SetWidth(45)
    row.amountText:SetJustifyH("RIGHT")

    row.memberText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.memberText:SetPoint("LEFT", row.amountText, "RIGHT", 10, 0)
    row.memberText:SetWidth(100)
    row.memberText:SetJustifyH("LEFT")
    row.memberText:SetTextColor(1, 1, 1)

    row.reasonText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.reasonText:SetPoint("LEFT", row.memberText, "RIGHT", 6, 0)
    row.reasonText:SetWidth(150)
    row.reasonText:SetJustifyH("LEFT")
    row.reasonText:SetTextColor(0.85, 0.85, 0.85)

    return row
end

local function ensureRow(index)
    if not rows[index] then
        rows[index] = createRow(frame.content, index)
    end
    return rows[index]
end

local function layoutRows()
    local n = math.min(#currentTxs, MAX_ROWS)

    for i = 1, n do
        local row = ensureRow(i)
        local tx = currentTxs[i]

        row.dateText:SetText(CC.Utils.FormatTime(tx.ts))

        if tx.delta == 0 then
            row.amountText:SetText("NOTE")
            row.amountText:SetTextColor(0.4, 0.7, 1)
        elseif tx.delta > 0 then
            row.amountText:SetText("+" .. tostring(tx.delta))
            row.amountText:SetTextColor(0.25, 1, 0.25)
        else
            row.amountText:SetText(tostring(tx.delta))
            row.amountText:SetTextColor(1, 0.3, 0.3)
        end

        row.memberText:SetText(CC.Utils.EscapeText(tx.target or "?"))

        local reasonText = tx.reason
        if not reasonText or reasonText == "" then reasonText = "(no reason given)" end
        row.reasonText:SetText(CC.Utils.EscapeText(reasonText))

        row:Show()
    end

    for i = n + 1, #rows do
        rows[i]:Hide()
    end

    frame.content:SetSize(ROW_WIDTH, math.max(n, 1) * ROW_HEIGHT)
    frame.scroll:UpdateScrollChildRect()
end

local function showNext()
    local job = table.remove(pending, 1)
    if not job then
        frame:Hide()
        return
    end
    currentSender = job.sender
    currentTxs = job.txs
    frame.subtitle:SetText(string.format("|cffff4040%s|r wants to sync %d transaction%s with you",
        currentSender, #currentTxs, #currentTxs == 1 and "" or "s"))
    frame.scroll:SetVerticalScroll(0)
    frame:Show()
    layoutRows()
end

local function build()
    frame = CreateFrame("Frame", "CrimsonCoinSyncReviewFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 440)
    frame:SetPoint("CENTER", 0, 20)
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

    CC.Utils.AddLogo(frame, 28)

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Sync Review")

    frame.subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.subtitle:SetPoint("TOP", 0, -38)
    frame.subtitle:SetWidth(440)

    local colHeader = CreateFrame("Frame", nil, frame)
    colHeader:SetSize(ROW_WIDTH, 16)
    colHeader:SetPoint("TOPLEFT", 24, -66)

    local hDate = colHeader:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hDate:SetPoint("LEFT", 4, 0)
    hDate:SetWidth(95)
    hDate:SetJustifyH("LEFT")
    hDate:SetText("Date")

    local hAmount = colHeader:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hAmount:SetPoint("LEFT", hDate, "RIGHT", 4, 0)
    hAmount:SetWidth(45)
    hAmount:SetJustifyH("RIGHT")
    hAmount:SetText("Amount")

    local hMember = colHeader:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hMember:SetPoint("LEFT", hAmount, "RIGHT", 10, 0)
    hMember:SetWidth(100)
    hMember:SetJustifyH("LEFT")
    hMember:SetText("Member")

    local hReason = colHeader:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hReason:SetPoint("LEFT", hMember, "RIGHT", 6, 0)
    hReason:SetJustifyH("LEFT")
    hReason:SetText("Reason")

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 24, -86)
    scroll:SetPoint("BOTTOMRIGHT", -24, 56)
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

    local acceptBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    acceptBtn:SetSize(120, 24)
    acceptBtn:SetPoint("BOTTOM", -70, 16)
    acceptBtn:SetText("Accept")
    acceptBtn:SetScript("OnClick", function()
        local ok, err = pcall(function()
            local gdb = CC.DB.GetGuildDB()
            local applied = gdb and CC.Sync.MergeIncoming(gdb, currentTxs) or 0
            print(string.format("|cffff4040Crimson Coin:|r Synced %d transaction(s) from %s.", applied, currentSender))
            showNext()
        end)
        if not ok then
            print("|cffff4040Crimson Coin ERROR|r [Sync accept]: " .. tostring(err))
        end
    end)

    local denyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    denyBtn:SetSize(120, 24)
    denyBtn:SetPoint("LEFT", acceptBtn, "RIGHT", 12, 0)
    denyBtn:SetText("Deny")
    denyBtn:SetScript("OnClick", function()
        print(string.format("|cffff4040Crimson Coin:|r Denied sync from %s.", currentSender))
        showNext()
    end)

    tinsert(UISpecialFrames, "CrimsonCoinSyncReviewFrame")
end

function SyncReview.Show(sender, txs)
    if not sender or not txs or #txs == 0 then return end
    local ok, err = pcall(function()
        if not frame then build() end
        table.insert(pending, { sender = sender, txs = txs })
        if not frame:IsShown() then
            showNext()
        end
    end)
    if not ok then
        print("|cffff4040Crimson Coin ERROR|r [SyncReview.Show]: " .. tostring(err))
    end
end
