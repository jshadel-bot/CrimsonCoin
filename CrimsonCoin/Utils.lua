local ADDON, CC = ...

CC.Utils = {}
local Utils = CC.Utils

--[[
Safe, dependency-free serializer.

We deliberately do NOT use loadstring/load() to deserialize data that came
over the network (guild chat / addon messages). A modified client could
craft a payload that executes arbitrary Lua in that case. Instead we use a
small length-prefixed (netstring-style) format that a hand-written parser
walks -- there is no code execution path in Deserialize at all.

Wire format:
  nil            -> "z"
  true           -> "t"
  false          -> "f"
  number N       -> "D" .. #tostring(N) .. ":" .. tostring(N)
  string S       -> "S" .. #S .. ":" .. S
  table T        -> "M" .. count .. ":" .. (key,value pairs, each serialized)
]]

function Utils.Serialize(value)
    local t = type(value)
    if t == "nil" then
        return "z"
    elseif t == "boolean" then
        return value and "t" or "f"
    elseif t == "number" then
        local s = tostring(value)
        return "D" .. #s .. ":" .. s
    elseif t == "string" then
        return "S" .. #value .. ":" .. value
    elseif t == "table" then
        local parts = {}
        local n = 0
        for k, v in pairs(value) do
            n = n + 1
            parts[#parts + 1] = Utils.Serialize(k)
            parts[#parts + 1] = Utils.Serialize(v)
        end
        return "M" .. n .. ":" .. table.concat(parts)
    else
        error("CrimsonCoin: cannot serialize value of type " .. t)
    end
end

local function readLen(str, pos)
    local colon = str:find(":", pos, true)
    if not colon then
        error("CrimsonCoin: malformed payload (missing length delimiter)")
    end
    local n = tonumber(str:sub(pos, colon - 1))
    if not n then
        error("CrimsonCoin: malformed payload (bad length)")
    end
    return n, colon + 1
end

local parseValue -- forward declare

local function parseTable(str, pos)
    local n
    n, pos = readLen(str, pos)
    local result = {}
    for _ = 1, n do
        local k, v
        k, pos = parseValue(str, pos)
        v, pos = parseValue(str, pos)
        result[k] = v
    end
    return result, pos
end

parseValue = function(str, pos)
    local tag = str:sub(pos, pos)
    pos = pos + 1
    if tag == "z" then
        return nil, pos
    elseif tag == "t" then
        return true, pos
    elseif tag == "f" then
        return false, pos
    elseif tag == "D" then
        local len
        len, pos = readLen(str, pos)
        local s = str:sub(pos, pos + len - 1)
        return tonumber(s), pos + len
    elseif tag == "S" then
        local len
        len, pos = readLen(str, pos)
        local s = str:sub(pos, pos + len - 1)
        return s, pos + len
    elseif tag == "M" then
        return parseTable(str, pos)
    else
        error("CrimsonCoin: malformed payload (unknown tag '" .. tostring(tag) .. "' at " .. pos .. ")")
    end
end

-- Returns nil, errorMessage on failure instead of throwing, since input
-- comes from the network and must never take down the addon.
function Utils.Deserialize(str)
    if type(str) ~= "string" or str == "" then
        return nil, "empty payload"
    end
    local ok, value = pcall(function()
        local v = parseValue(str, 1)
        return v
    end)
    if not ok then
        return nil, value
    end
    return value
end

-- ID / time helpers -----------------------------------------------------

function Utils.NewId()
    return string.format("%s-%d-%04x", UnitName("player") or "?", time(), math.random(0, 0xFFFF))
end

function Utils.Now()
    return time()
end

function Utils.FormatTime(ts)
    if not ts then return "?" end
    return date("%Y-%m-%d %H:%M", ts)
end

-- Branding ------------------------------------------------------------

Utils.LOGO_TEXTURE = "Interface\\AddOns\\CrimsonCoin\\Textures\\logo.tga"

-- Adds the Crimson Coin crest to a window's top-left corner. Returns the
-- texture object in case a caller wants to anchor other elements to it.
function Utils.AddLogo(parent, size)
    size = size or 28
    local logo = parent:CreateTexture(nil, "ARTWORK")
    logo:SetSize(size, size)
    logo:SetPoint("TOPLEFT", 8, -8)
    logo:SetTexture(Utils.LOGO_TEXTURE)
    return logo
end

-- Class color helper ------------------------------------------------------

function Utils.ClassColorize(classFile, text)
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if color then
        return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, text)
    end
    return text
end

-- Guild key: scopes saved data to a specific guild+realm so switching
-- characters/guilds never mixes ledgers together.
local warnedGetGuildInfo = false -- diagnostic: print at most once per session, this is called very often
function Utils.CurrentGuildKey()
    local ok, guildName = pcall(GetGuildInfo, "player")
    if not ok then
        if not warnedGetGuildInfo then
            warnedGetGuildInfo = true
            print("|cffff4040Crimson Coin DIAG|r: GetGuildInfo(\"player\") failed: " .. tostring(guildName))
        end
        return nil
    end
    if not guildName then
        return nil
    end
    local realm = GetRealmName() or "?"
    return guildName .. " - " .. realm
end

-- CHAT_MSG_ADDON's sender field can carry a "-Realm" suffix on connected
-- realms even when UnitName("player") (used to stamp tx.actor) never does.
function Utils.ShortName(name)
    if not name then return name end
    return name:match("^[^-]+") or name
end

-- WoW's FontString text engine treats a literal "|" as the start of a
-- color/texture escape sequence (|cffRRGGBB, |T...|t, etc). Free-text the
-- user typed (like a transaction reason) can contain one by accident, and
-- an unmatched escape can blank out the rest of that line with no error.
-- Doubling "|" to "||" is WoW's own escape for a literal pipe character.
function Utils.EscapeText(s)
    if not s or s == "" then return s end
    return (s:gsub("|", "||"))
end

function Utils.Trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

-- For "type WORD to confirm" popups: trims whitespace and uppercases, so
-- a trailing space or lowercase typing doesn't silently fail the check.
function Utils.NormalizeConfirmText(s)
    return Utils.Trim(s):upper()
end

-- On this client, StaticPopup dialog frames don't reliably expose their
-- edit box as the `.editBox` field (it's nil even though hasEditBox=true
-- created one) -- but the XML template always creates it as a globally
-- named child, "<dialogName>EditBox", so fall back to that.
function Utils.GetPopupEditBox(dialog)
    if not dialog then return nil end
    if dialog.editBox then return dialog.editBox end
    local name = dialog.GetName and dialog:GetName()
    return name and _G[name .. "EditBox"]
end

function Utils.Round(n)
    return math.floor(n + 0.5)
end

-- Simple message queue used to throttle bursts of addon-message chunks so
-- we don't trip the server's addon-message rate limiting.
function Utils.NewThrottledQueue(intervalSeconds)
    local q = { items = {}, running = false, interval = intervalSeconds or 0.15 }

    function q:Push(fn)
        table.insert(self.items, fn)
        self:Pump()
    end

    function q:Pump()
        if self.running then return end
        if #self.items == 0 then return end
        self.running = true
        local fn = table.remove(self.items, 1)
        local ok, err = pcall(fn)
        if not ok then
            geterrorhandler()(err)
        end
        C_Timer.After(self.interval, function()
            self.running = false
            self:Pump()
        end)
    end

    return q
end
