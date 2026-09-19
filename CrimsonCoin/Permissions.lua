local ADDON, CC = ...

CC.Perm = {}
local Perm = CC.Perm

-- Cache of guild-roster rank indices, refreshed by re-reading
-- GetGuildRosterInfo() (on login and on GUILD_ROSTER_UPDATE, plus
-- whenever a UI panel wants current data). This is the trust anchor for
-- the whole sync system:
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
    -- On some clients this alone triggers a "blocked from an action only
    -- available to the Blizzard UI" notice -- that's cosmetic (pcall
    -- can't suppress the popup itself, but it doesn't stop execution
    -- here either) and dismissible. Removing this call entirely was
    -- tried and made things worse: on at least one client build, the
    -- roster never actually gets populated at all without it -- this
    -- request is what makes the client go fetch/refresh guild data in
    -- the first place, not just an optional nudge. So: keep requesting
    -- it, keep it pcall-guarded so a throwing/missing stub can't abort
    -- the refresh, and accept the occasional dismissible popup as the
    -- lesser problem.
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        pcall(C_GuildInfo.GuildRoster)
    else
        pcall(GuildRoster)
    end

    wipe(rosterList)

    local okNum, n = pcall(GetNumGuildMembers)
    if not okNum then
        print("|cffff4040Crimson Coin DIAG|r: GetNumGuildMembers() failed: " .. tostring(n))
        return
    end

    local warnedRosterInfo = false -- only report the first failure; the rest would just repeat it
    for i = 1, n do
        local okInfo, name, rankName, rankIndex, level, class, zone, note, officernote, online, status, classFile =
            pcall(GetGuildRosterInfo, i)
        if not okInfo then
            if not warnedRosterInfo then
                warnedRosterInfo = true
                print(string.format("|cffff4040Crimson Coin DIAG|r: GetGuildRosterInfo(%d) failed: %s", i, tostring(name)))
            end
            name = nil
        end
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
