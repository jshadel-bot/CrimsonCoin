local ADDON, CC = ...

CC.Boss = {}
local Boss = CC.Boss
local Utils = CC.Utils

--[[
Known raid/dungeon boss NPC IDs for Classic Era content, keyed by NPC id
(the number embedded in a unit GUID). This list is best-effort and may
have gaps or the odd wrong id -- Blizzard doesn't expose a "this is a
raid boss" flag anywhere the addon API can see, so detection is inherently
a curated list. Use `/cc bosslog` (officer-only) to print the NPC id of
anything that dies near you in combat, then `/cc addboss <id> <name>` to
teach the addon about a boss that's missing or misidentified. Additions
are stored locally per-install (CrimsonCoinBossDB), not synced.
]]
Boss.KnownBosses = {
    -- Molten Core
    [12118] = "Lucifron",
    [11982] = "Magmadar",
    [12259] = "Gehennas",
    [12057] = "Garr",
    [12056] = "Baron Geddon",
    [12264] = "Shazzrah",
    [12098] = "Sulfuron Harbinger",
    [11988] = "Golemagg the Incinerator",
    [12018] = "Majordomo Executus",
    [11502] = "Ragnaros",
    -- Onyxia's Lair
    [10184] = "Onyxia",
    -- Blackwing Lair
    [12435] = "Razorgore the Untamed",
    [13020] = "Vaelastrasz the Corrupt",
    [12017] = "Broodlord Lashlayer",
    [11983] = "Firemaw",
    [14601] = "Ebonroc",
    [11981] = "Flamegor",
    [14020] = "Chromaggus",
    [11583] = "Nefarian",
    -- Zul'Gurub
    [14517] = "High Priestess Jeklik",
    [14507] = "High Priest Venoxis",
    [14510] = "High Priestess Mar'li",
    [11382] = "Bloodlord Mandokir",
    [14515] = "High Priestess Arlokk",
    [14834] = "Hakkar",
    [11380] = "Jin'do the Hexxer",
    -- Ahn'Qiraj Ruins (AQ20) & Temple (AQ40) -- verify/extend via /cc addboss
    [15348] = "Kurinnaxx",
    [15341] = "General Rajaxx",
    [15340] = "Moam",
    [15370] = "Buru the Gorger",
    [15369] = "Ayamiss the Hunter",
    [15339] = "Ossirian the Unscarred",
    [15263] = "The Prophet Skeram",
    [15544] = "Battleguard Sartura",
    [15516] = "Fankriss the Unyielding",
    [15510] = "Viscidus",
    [15299] = "Princess Huhuran",
    [15517] = "Vem",
    [15276] = "Fankriss",
    [15275] = "C'Thun",
    -- Naxxramas
    [15956] = "Anub'Rekhan",
    [15953] = "Grand Widow Faerlina",
    [15952] = "Maexxna",
    [16011] = "Noth the Plaguebringer",
    [15954] = "Heigan the Unclean",
    [16061] = "Loatheb",
    [16060] = "Instructor Razuvious",
    [16064] = "Gothik the Harvester",
    [16063] = "The Four Horsemen",
    [15989] = "Patchwerk",
    [16065] = "Grobbulus",
    [15931] = "Gluth",
    [15928] = "Thaddius",
    [15978] = "Sapphiron",
    [15990] = "Kel'Thuzad",
}

-- Locally-added custom bosses (SavedVariables, account-wide).
local customBosses = {}

local function isKnownBossId(npcId)
    return Boss.KnownBosses[npcId] or customBosses[npcId]
end

function Boss.InitCustomDB()
    if type(CrimsonCoinBossDB) ~= "table" then
        CrimsonCoinBossDB = {}
    end
    customBosses = CrimsonCoinBossDB
end

function Boss.AddCustomBoss(npcId, name)
    npcId = tonumber(npcId)
    if not npcId then return false end
    customBosses[npcId] = name
    return true
end

Boss.debugMode = false

local function getNpcIdFromGuid(guid)
    if not guid then return nil end
    -- Creature GUID layout: Creature-0-<server>-<instance>-<zone>-<npcId>-<spawnUID>
    local kind, npcId = guid:match("^(%a+)-%d+-%d+-%d+-%d+-(%d+)-")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(npcId)
end

-- Active pull tracking -----------------------------------------------

local activePulls = {} -- [guid] = { npcId, name, samples = {[player]=count}, sampleCount, lastActivity }
local sampleTicker = nil
local PULL_TIMEOUT = 25 -- seconds of no damage before we consider it a wipe/reset
local SAMPLE_INTERVAL = 15

local function currentRosterNames()
    local names = {}
    if IsInRaid() then
        -- raidN units include the player.
        for i = 1, GetNumGroupMembers() do
            local name = UnitName("raid" .. i)
            if name then table.insert(names, name) end
        end
    elseif IsInGroup() then
        -- partyN units exclude the player; add them separately.
        table.insert(names, UnitName("player"))
        for i = 1, GetNumGroupMembers() - 1 do
            local name = UnitName("party" .. i)
            if name then table.insert(names, name) end
        end
    else
        table.insert(names, UnitName("player"))
    end
    return names
end

local function ensurePull(guid, npcId)
    if not activePulls[guid] then
        activePulls[guid] = {
            npcId = npcId,
            name = isKnownBossId(npcId),
            samples = {},
            sampleCount = 0,
            lastActivity = GetTime(),
        }
    end
    activePulls[guid].lastActivity = GetTime()
    return activePulls[guid]
end

local function sampleAttendance()
    local now = GetTime()
    local any = false
    for guid, pull in pairs(activePulls) do
        if now - pull.lastActivity > PULL_TIMEOUT then
            activePulls[guid] = nil
        else
            any = true
            pull.sampleCount = pull.sampleCount + 1
            for _, name in ipairs(currentRosterNames()) do
                pull.samples[name] = (pull.samples[name] or 0) + 1
            end
        end
    end
    if not any and sampleTicker then
        sampleTicker:Cancel()
        sampleTicker = nil
    end
end

local function ensureTicker()
    if not sampleTicker then
        sampleTicker = C_Timer.NewTicker(SAMPLE_INTERVAL, sampleAttendance)
        sampleAttendance() -- take an immediate first sample
    end
end

local function onBossDied(guid, npcId, name)
    local pull = activePulls[guid]
    activePulls[guid] = nil

    local attendees = {}
    if pull and pull.sampleCount > 0 then
        local gdb = CC.DB.GetGuildDB()
        local minAttendance = gdb and gdb.settings.minAttendance or 0.5
        for playerName, count in pairs(pull.samples) do
            if count / pull.sampleCount >= minAttendance then
                table.insert(attendees, { name = playerName, attendance = count / pull.sampleCount })
            end
        end
    else
        -- No samples captured (very fast kill) -- fall back to current roster.
        for _, playerName in ipairs(currentRosterNames()) do
            table.insert(attendees, { name = playerName, attendance = 1.0 })
        end
    end

    table.sort(attendees, function(a, b) return a.attendance > b.attendance end)

    local gdb = CC.DB.GetGuildDB()
    if gdb then
        table.insert(gdb.bossKillLog, 1, {
            id = Utils.NewId(),
            boss = name,
            time = Utils.Now(),
            zone = GetRealZoneText(),
            awarded = false,
        })
        while #gdb.bossKillLog > 100 do table.remove(gdb.bossKillLog) end
    end

    if CC.Perm.PlayerIsOfficer() and CC.UI.Reward then
        CC.UI.Reward.Show(name, attendees)
    end

    print(string.format("|cffff4040Crimson Coin:|r %s has fallen! (%d attendee%s tracked)",
        name, #attendees, #attendees == 1 and "" or "s"))
end

-- Event handling --------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:SetScript("OnEvent", function()
    local _, subevent, _, sourceGUID, _sourceName, _sf, _sr, destGUID, destName = CombatLogGetCurrentEventInfo()

    if Boss.debugMode and subevent == "UNIT_DIED" then
        local npcId = getNpcIdFromGuid(destGUID)
        if npcId then
            print(string.format("|cffff4040CrimsonCoin bosslog:|r %s died, npcId=%d%s",
                destName or "?", npcId, isKnownBossId(npcId) and " (known boss)" or ""))
        end
    end

    if subevent == "UNIT_DIED" then
        local npcId = getNpcIdFromGuid(destGUID)
        if npcId and isKnownBossId(npcId) then
            onBossDied(destGUID, npcId, isKnownBossId(npcId))
        end
        return
    end

    -- Any damage event touching a known boss keeps/opens its pull window.
    local involvedGuid, involvedNpcId
    for _, guid in ipairs({ sourceGUID, destGUID }) do
        local npcId = getNpcIdFromGuid(guid)
        if npcId and isKnownBossId(npcId) then
            involvedGuid, involvedNpcId = guid, npcId
            break
        end
    end
    if involvedGuid then
        ensurePull(involvedGuid, involvedNpcId)
        ensureTicker()
    end
end)
