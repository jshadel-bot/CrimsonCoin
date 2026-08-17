local ADDON, CC = ...

CC.UI = CC.UI or {}
CC.UI.History = {}
local History = CC.UI.History

local ROW_HEIGHT = 20
local ROW_WIDTH = 400
local MAX_ROWS = 300 -- sanity cap on how much history renders at once

local frame
local rows = {} -- pool of row widgets, grown as needed and reused across shows
local currentName = nil
local currentList = {}

local function buildList(name)
    local gdb = CC.DB.GetGuildDB()
    local list = {}
    if gdb then
        for _, tx in ipairs(gdb.ledger) do
            if tx.target == name then
                table.insert(list, tx)
            end
        end
    end
    table.sort(list, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return list
end

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
    row.dateText:SetWidth(100)
    row.dateText:SetJustifyH("LEFT")
    row.dateText:SetTextColor(1, 1, 1)

    row.amountText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.amountText:SetPoint("LEFT", row.dateText, "RIGHT", 4, 0)
    row.amountText:SetWidth(45)
    row.amountText:SetJustifyH("RIGHT")

    row.reasonText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.reasonText:SetPoint("LEFT", row.amountText, "RIGHT", 10, 0)
    row.reasonText:SetWidth(160)
    row.reasonText:SetJustifyH("LEFT")
    row.reasonText:SetTextColor(1, 1, 1)

    row.byText = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    row.byText:SetPoint("LEFT", row.reasonText, "RIGHT", 6, 0)
    row.byText:SetWidth(80)
    row.byText:SetJustifyH("LEFT")
    row.byText:SetTextColor(0.7, 0.7, 0.7)

    return row
end

local function ensureRow(index)
    if not rows[index] then
        rows[index] = createRow(frame.content, index)
    end
    return rows[index]
end

-- Lays out one row per transaction directly (no virtualized windowing/
-- offset math) -- the scroll frame's native SetVerticalScroll handles
-- showing the right slice, so there's no offset calculation left to get
-- wrong.
local function layoutRows()
    local n = math.min(#currentList, MAX_ROWS)

    for i = 1, n do
        local row = ensureRow(i)
        local tx = currentList[i]

        row.dateText:SetText(CC.Utils.FormatTime(tx.ts))

        -- A zero-delta entry never comes from Add/Remove Coins (both
        -- require a positive amount) -- it can only be an officer note,
        -- so it's a reliable signal to render as one instead of "+0".
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

        local reasonText = tx.reason
        if not reasonText or reasonText == "" then reasonText = "(no reason given)" end
        row.reasonText:SetText(CC.Utils.EscapeText(reasonText))
        if tx.delta == 0 then
            row.reasonText:SetTextColor(0.6, 0.85, 1)
        else
            row.reasonText:SetTextColor(1, 1, 1)
        end

        row.byText:SetText("- " .. CC.Utils.EscapeText(tx.actor or "?"))

        row:Show()
    end

    for i = n + 1, #rows do
        rows[i]:Hide()
    end

    frame.content:SetSize(ROW_WIDTH, math.max(n, 1) * ROW_HEIGHT)
    frame.scroll:UpdateScrollChildRect()

    frame.emptyLabel:SetShown(n == 0)

    local total = 0
    for _, tx in ipairs(currentList) do total = total + (tx.delta or 0) end
    frame.totalLabel:SetText(string.format("Total: %d Crimson Coin  (%d transaction%s)",
        total, #currentList, #currentList == 1 and "" or "s"))
end

local function build()
    frame = CreateFrame("Frame", "CrimsonCoinHistoryFrame", UIParent, "BackdropTemplate")
    frame:SetSize(500, 440)
    frame:SetPoint("CENTER", 0, -30)
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

    frame.title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -14)
    frame.title:SetTextColor(1, 1, 1)

    frame.totalLabel = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.totalLabel:SetPoint("TOP", 0, -38)
    frame.totalLabel:SetTextColor(1, 0.82, 0)

    -- Column headers, aligned with the row layout below
    local colHeader = CreateFrame("Frame", nil, frame)
    colHeader:SetSize(ROW_WIDTH, 16)
    colHeader:SetPoint("TOPLEFT", 24, -58)

    local hDate = colHeader:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hDate:SetPoint("LEFT", 4, 0)
    hDate:SetWidth(100)
    hDate:SetJustifyH("LEFT")
    hDate:SetText("Date")

    local hAmount = colHeader:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hAmount:SetPoint("LEFT", hDate, "RIGHT", 4, 0)
    hAmount:SetWidth(45)
    hAmount:SetJustifyH("RIGHT")
    hAmount:SetText("Amount")

    local hReason = colHeader:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hReason:SetPoint("LEFT", hAmount, "RIGHT", 10, 0)
    hReason:SetWidth(160)
    hReason:SetJustifyH("LEFT")
    hReason:SetText("Reason")

    local hBy = colHeader:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hBy:SetPoint("LEFT", hReason, "RIGHT", 6, 0)
    hBy:SetJustifyH("LEFT")
    hBy:SetText("By")

    -- Plain native ScrollFrame (no XML template). Templates on this
    -- client have proven unreliable in more than one place already
    -- (StaticPopup's .editBox field wasn't where documented), so this
    -- avoids relying on FauxScrollFrameTemplate's internal wiring at all.
    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 24, -78)
    scroll:SetPoint("BOTTOMRIGHT", -24, 40)
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

    frame.emptyLabel = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    frame.emptyLabel:SetPoint("TOPLEFT", 4, 0)
    frame.emptyLabel:SetText("No transactions recorded for this member yet.")
    frame.emptyLabel:Hide()

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("BOTTOM", 0, 18)
    hint:SetText("Scroll with your mouse wheel to see more")

    tinsert(UISpecialFrames, "CrimsonCoinHistoryFrame")
end

function History.Show(name)
    if not name then return end

    local ok, err = pcall(function()
        if not frame then build() end

        currentName = name
        currentList = buildList(name)
        frame.title:SetText(name .. "'s Transactions")

        local gdb = CC.DB.GetGuildDB()
        local ledgerSize = gdb and #gdb.ledger or 0
        print(string.format("|cffff4040Crimson Coin:|r Loaded %d transaction(s) for %s (%d total in the local ledger).",
            #currentList, name, ledgerSize))

        frame.scroll:SetVerticalScroll(0)
        frame:Show()
        layoutRows()
    end)
    if not ok then
        print("|cffff4040Crimson Coin ERROR|r [History.Show]: " .. tostring(err))
    end
end

-- Called by Sync/Backup after the ledger changes, so an open history
-- window doesn't go stale while it's sitting on screen.
function History.Refresh()
    if not frame or not frame:IsShown() or not currentName then return end
    local ok, err = pcall(function()
        currentList = buildList(currentName)
        layoutRows()
    end)
    if not ok then
        print("|cffff4040Crimson Coin ERROR|r [History.Refresh]: " .. tostring(err))
    end
end
