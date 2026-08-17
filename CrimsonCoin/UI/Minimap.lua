local ADDON, CC = ...

-- Small draggable minimap button that opens the wallet UI (left click)
-- or the officer panel (right click, if the player has access).

local function build()
    local button = CreateFrame("Button", "CrimsonCoinMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface/Icons/INV_Misc_Coin_02")
    icon:SetPoint("CENTER", 0, 1)
    button.icon = icon

    local function updatePosition()
        local angle = math.rad(CrimsonCoinDB.minimapAngle or 215)
        local radius = 80
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local angle = math.deg(math.atan2(py - my, px - mx))
            CrimsonCoinDB.minimapAngle = angle
            updatePosition()
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            -- Officer.Toggle() does its own permission check and prints a
            -- clear reason on failure, instead of silently doing nothing
            -- (or falling back to something that looks like a left-click).
            CC.UI.Officer.Toggle()
        else
            CC.UI.Main.Toggle()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Crimson Coin")
        GameTooltip:AddLine("Left-click: open wallet", 1, 1, 1)
        GameTooltip:AddLine("Right-click: officer panel", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    updatePosition()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if CrimsonCoinDB.minimapAngle == nil then
        CrimsonCoinDB.minimapAngle = 215
    end
    build()
end)
