local ADDON, CC = ...

CC.Perm = {}
local Perm = CC.Perm

-- Cache of guild-roster rank indices, refreshed from GuildRoster() /
-- GUILD_ROSTER_UPDATE. This is the trust anchor for the whole sync system:
-- every client independently verifies a sender's *actual* guild rank from
-- its own roster snapshot before accepting a mutating message from them.
-- A modified client can claim anything it wants about itself, but it
-- cannot change what the honest client's own GetGuildRosterInfo() reports.
local rosterCache = {} -- [name] = { name = shortName, rankIndex = n, rankName = "", class = "", online = bool }
local rosterList = {}  -- ordered array of the same info tables, one per member (no short/full-name duplicates)

function Perm.RefreshRoster()
    if not IsInGuild() then
        wipe(rosterCache)
        wipe(rosterList)
        return
    end
    -- The global GuildRoster() has been deprecated/no-op on some client
    -- builds; C_GuildInfo.GuildRoster() is the modern namespaced
    -- replacement that actually requests a fresh sync from the server on
    -- current clients. Try that first, fall back to the old global, and
    -- pcall either way so a missing/throwing stub never aborts the
    -- refresh (which would otherwise silently kill the caller).
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        pcall(C_GuildInfo.GuildRoster)
    else
        pcall(GuildRoster)
    end
    wipe(rosterList)
    local n = GetNumGuildMembers()
    for i = 1, n do
        local name, rankName, rankIndex, level, class, zone, note, officernote, online, status, classFile = GetGuildRosterInfo(i)
        if name then
            local shortName = CC.Utils.ShortName(name)
            local info = {
                name = shortName,
                rankIndex = rankIndex,
                rankName = rankName,
                class = classFile,
                online = online,
            }
            rosterCache[shortName] = info
            -- Also key by full "Name-Realm" so cross-realm-formatted senders resolve too.
            rosterCache[name] = info
            table.insert(rosterList, info)
        end
    end
end

function Perm.GetRosterInfo(name)
    if not name then return nil end
    local short = CC.Utils.ShortName(name)
    return rosterCache[name] or rosterCache[short]
end

-- Every current guild member (from the live roster, not just people who
-- happen to already have a ledger entry), for populating roster UIs.
function Perm.GetRosterList()
    return rosterList
end

local function guildSettings()
    local gdb = CC.DB.GetGuildDB()
    return gdb and gdb.settings or nil
end

-- Character names are unique per (connected-)realm and enforced by
-- Blizzard's servers, so -- like guild rank index 0 -- a name match is a
-- trust anchor a modified client can't forge: only the real "Grimbot"
-- can ever be the sender of a GUILD-channel message claiming to be Grimbot.
function Perm.IsSuperAdmin(name)
    local settings = guildSettings()
    local short = CC.Utils.ShortName(name)
    if not settings or not settings.superAdmins or not short then return false end
    return settings.superAdmins[short:lower()] == true
end

-- Can this (possibly remote) player broadcast add/remove coin transactions?
function Perm.IsOfficer(name)
    if Perm.IsSuperAdmin(name) then return true end
    local info = Perm.GetRosterInfo(name)
    if not info then return false end
    if info.rankIndex == 0 then return true end -- true Guild Master, whatever it's named, always has access
    local settings = guildSettings()
    if not settings or not info.rankName then return false end
    return settings.officerRanks[info.rankName:lower()] == true
end

-- Can this (possibly remote) player push/restore full snapshots (backups),
-- delete backups, and manage rank/superadmin lists?
function Perm.IsAdmin(name)
    if Perm.IsSuperAdmin(name) then return true end
    local info = Perm.GetRosterInfo(name)
    if not info then return false end
    if info.rankIndex == 0 then return true end -- true Guild Master, whatever it's named, always has access
    if not info.rankName then return false end
    local rankLower = info.rankName:lower()
    -- Anyone whose rank is literally named "Officer" or "Guild Master"
    -- automatically gets admin too -- no separate adminRanks entry needed
    -- for the two rank names guilds almost always already use.
    if rankLower == "officer" or rankLower == "guild master" then
        return true
    end
    local settings = guildSettings()
    if not settings then return false end
    return settings.adminRanks[rankLower] == true
end

function Perm.PlayerIsOfficer()
    return Perm.IsOfficer(UnitName("player"))
end

function Perm.PlayerIsAdmin()
    return Perm.IsAdmin(UnitName("player"))
end
