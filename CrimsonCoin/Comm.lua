local ADDON, CC = ...

CC.Comm = {}
local Comm = CC.Comm
local Utils = CC.Utils

Comm.PREFIX = "CrimsonCoin1"
local CHUNK_SIZE = 200

-- payload.mt -> list of handler(payload, senderName)
local handlers = {}

function Comm.RegisterHandler(msgType, fn)
    handlers[msgType] = handlers[msgType] or {}
    table.insert(handlers[msgType], fn)
end

local queue = Utils.NewThrottledQueue(0.2)

local function rawSend(text, channel, target)
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(Comm.PREFIX, text, channel, target)
    else
        SendAddonMessage(Comm.PREFIX, text, channel, target)
    end
end

-- Sends a Lua table as `payload.mt` message type, chunked to respect the
-- addon-message size limit, throttled so we don't trip server rate limits.
function Comm.Send(payload, channel, target)
    channel = channel or "GUILD"
    local serialized = Utils.Serialize(payload)
    local msgId = string.format("%04x", math.random(0, 0xFFFF))
    local total = math.max(1, math.ceil(#serialized / CHUNK_SIZE))

    for i = 1, total do
        local chunkStart = (i - 1) * CHUNK_SIZE + 1
        local chunkData = serialized:sub(chunkStart, chunkStart + CHUNK_SIZE - 1)
        local wire = string.format("%s,%d,%d,%s", msgId, i, total, chunkData)
        queue:Push(function()
            rawSend(wire, channel, target)
        end)
    end
end

-- Reassembly buffers keyed by "sender:msgId"
local buffers = {}
local BUFFER_TTL = 30

local function pruneStaleBuffers()
    local now = GetTime()
    for key, buf in pairs(buffers) do
        if now - buf.startedAt > BUFFER_TTL then
            buffers[key] = nil
        end
    end
end

local function onChunk(sender, wire)
    local msgId, idxStr, totalStr, data = wire:match("^(%x+),(%d+),(%d+),(.*)$")
    if not msgId then return end
    local idx, total = tonumber(idxStr), tonumber(totalStr)

    local key = sender .. ":" .. msgId
    local buf = buffers[key]
    if not buf then
        buf = { parts = {}, total = total, received = 0, startedAt = GetTime() }
        buffers[key] = buf
    end
    if not buf.parts[idx] then
        buf.parts[idx] = data
        buf.received = buf.received + 1
    end

    if buf.received >= buf.total then
        buffers[key] = nil
        local full = table.concat(buf.parts, "", 1, buf.total)
        local payload, err = Utils.Deserialize(full)
        if not payload then
            return -- corrupt/foreign message, silently drop
        end
        local list = payload.mt and handlers[payload.mt]
        if list then
            for _, fn in ipairs(list) do
                local ok, e = pcall(fn, payload, sender)
                if not ok then
                    geterrorhandler()(e)
                end
            end
        end
    end

    if math.random(1, 20) == 1 then
        pruneStaleBuffers()
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent", function(_, event, prefix, message, channel, sender)
    if prefix ~= Comm.PREFIX then return end
    -- Strip realm suffix for a stable key; RefreshRoster() caches both forms.
    onChunk(sender, message)
end)

function Comm.Init()
    -- Temporary diagnostic: pinpointing a "blocked from an action only
    -- available to the Blizzard UI" message on a non-standard client.
    -- pcall can't suppress that dialog if this call is genuinely the
    -- trigger (it's an engine-level notice, not a normal catchable
    -- error), but it WILL let us print the underlying error text -- which
    -- names the exact blocked function -- without the user needing to
    -- change any client settings.
    local ok, err
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        ok, err = pcall(C_ChatInfo.RegisterAddonMessagePrefix, Comm.PREFIX)
        if not ok then
            print("|cffff4040Crimson Coin DIAG|r: C_ChatInfo.RegisterAddonMessagePrefix failed: " .. tostring(err))
        end
    else
        ok, err = pcall(RegisterAddonMessagePrefix, Comm.PREFIX)
        if not ok then
            print("|cffff4040Crimson Coin DIAG|r: RegisterAddonMessagePrefix failed: " .. tostring(err))
        end
    end
end
