local ADDON, CC = ...

CC.UI = CC.UI or {}
CC.UI.Help = {}
local Help = CC.UI.Help

local BODY_WIDTH = 372

local frame

local function build()
    frame = CreateFrame("Frame", "CrimsonCoinHelpFrame", UIParent, "BackdropTemplate")
    frame:SetSize(440, 460)
    frame:SetPoint("CENTER")
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
    title:SetText("|cffff4040Crimson Coin - Help|r")

    local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("TOP", title, "BOTTOM", 0, -4)
    version:SetText("Version " .. CC.VERSION)

    local cmdHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cmdHeader:SetPoint("TOPLEFT", 24, -58)
    cmdHeader:SetText("Slash Commands")
    cmdHeader:SetTextColor(1, 0.82, 0)

    -- Scrollable command list. Only this part scrolls -- the contact
    -- section below is fixed, outside the scroll frame entirely.
    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", 24, -78)
    scroll:SetPoint("BOTTOMRIGHT", -24, 114)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, (frame.content:GetHeight() or 0) - self:GetHeight())
        local newScroll = self:GetVerticalScroll() - delta * 30
        if newScroll < 0 then newScroll = 0 end
        if newScroll > maxScroll then newScroll = maxScroll end
        self:SetVerticalScroll(newScroll)
    end)
    frame.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(BODY_WIDTH, 10)
    scroll:SetScrollChild(content)
    frame.content = content

    local lines = {}
    for _, entry in ipairs(CC.HELP_COMMANDS) do
        table.insert(lines, string.format("|cffffd100%s|r\n%s", entry.cmd, entry.desc))
    end

    local body = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    body:SetPoint("TOPLEFT", 0, 0)
    body:SetWidth(BODY_WIDTH)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(4)
    body:SetTextColor(1, 1, 1)
    body:SetText(table.concat(lines, "\n\n"))

    -- Size the scroll child to the text's actual rendered height (wrapped
    -- long lines included) so the scroll range matches the real content.
    content:SetHeight(body:GetStringHeight() + 10)
    scroll:UpdateScrollChildRect()

    local scrollHint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    scrollHint:SetPoint("TOP", cmdHeader, "TOP", 60, 0)
    scrollHint:SetText("(scroll for more)")

    -- Fixed footer, not part of the scroll frame.
    local contactHeader = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    contactHeader:SetPoint("BOTTOMLEFT", 24, 88)
    contactHeader:SetText("Questions or Bugs?")
    contactHeader:SetTextColor(1, 0.82, 0)

    local contactDesc = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    contactDesc:SetPoint("TOPLEFT", contactHeader, "BOTTOMLEFT", 0, -4)
    contactDesc:SetText("Click the box below to select the address, then Ctrl+C to copy it.")

    local emailBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    emailBox:SetSize(240, 20)
    emailBox:SetPoint("TOPLEFT", contactDesc, "BOTTOMLEFT", 4, -8)
    emailBox:SetAutoFocus(false)
    emailBox:SetText(CC.CONTACT_EMAIL)
    emailBox:SetCursorPosition(0)
    emailBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    emailBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    emailBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    tinsert(UISpecialFrames, "CrimsonCoinHelpFrame")
end

function Help.Show()
    local ok, err = pcall(function()
        if not frame then build() end
        frame.scroll:SetVerticalScroll(0)
        frame:Show()
    end)
    if not ok then
        print("|cffff4040Crimson Coin ERROR|r [Help.Show]: " .. tostring(err))
    end
end

function Help.Toggle()
    if not frame then
        Help.Show()
        return
    end
    if frame:IsShown() then
        frame:Hide()
    else
        Help.Show()
    end
end
