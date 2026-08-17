local ADDON, CC = ...

CC.VERSION = "1.0.0"
CC.UI = CC.UI or {}

local Core = {}
CC.Core = Core

local function guildOnlyPrint(msg)
    print("|cffff4040Crimson Coin:|r " .. msg)
end

local function formatRankSet(set)
    local names = {}
    for name in pairs(set or {}) do table.insert(names, name) end
    table.sort(names)
    return next(names) and table.concat(names, ", ") or "(none)"
end

-- Event wiring ------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")

local hasEnteredWorld = false

local function onEvent(event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        CC.DB.Init()
        CC.Boss.InitCustomDB()
        CC.Comm.Init()

    elseif event == "PLAYER_ENTERING_WORLD" then
        if hasEnteredWorld then return end
        hasEnteredWorld = true

        if not IsInGuild() then
            return
        end

        CC.Perm.RefreshRoster()

        C_Timer.After(2, function()
            CC.Perm.RefreshRoster()
            CC.Backup.MaybeAutoBackup()
            CC.Sync.RequestSync()
        end)

    elseif event == "GUILD_ROSTER_UPDATE" then
        CC.Perm.RefreshRoster()
        if CC.UI.Main and CC.UI.Main.Refresh then CC.UI.Main.Refresh() end
        if CC.UI.Officer and CC.UI.Officer.Refresh then CC.UI.Officer.Refresh() end
    end
end

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    -- An uncaught error here (e.g. during ADDON_LOADED) silently aborts
    -- whatever ran after it in the same handler, with zero visible
    -- indication anything went wrong. Surface it instead of guessing later.
    local ok, err = pcall(onEvent, event, arg1)
    if not ok then
        print("|cffff4040Crimson Coin ERROR|r [" .. event .. "]: " .. tostring(err))
    end
end)

-- Slash commands ------------------------------------------------------

-- Single source of truth for every /cc subcommand, so the chat help text
-- and the in-UI Help window can never drift apart from each other.
CC.HELP_COMMANDS = {
    { cmd = "/cc", desc = "open your wallet" },
    { cmd = "/cc officer", desc = "open the officer management panel (requires rank)" },
    { cmd = "/cc sync", desc = "request a ledger sync from the guild" },
    { cmd = "/cc backup [label]", desc = "create a manual backup (officer)" },
    { cmd = "/cc clearcache", desc = "wipe this character's local ledger/balances (not backups) (officer, asks to confirm)" },
    { cmd = "/cc officerrank list|add <name>|remove <name>", desc = "guild rank names allowed officer access (admin)" },
    { cmd = "/cc adminrank list|add <name>|remove <name>", desc = "guild rank names allowed to restore backups (admin)" },
    { cmd = "/cc superadmin list|add <name>|remove <name>", desc = "character names always treated as admin (admin)" },
    { cmd = "/cc bosslog", desc = "toggle printing NPC ids of things that die, to help identify boss ids" },
    { cmd = "/cc addboss <npcId> <name>", desc = "teach the addon a boss NPC id" },
    { cmd = "/cc whoami", desc = "show your detected guild rank and officer/admin status" },
}

CC.CONTACT_EMAIL = "jgshadel@gmail.com"

local function printHelp()
    guildOnlyPrint(CC.VERSION .. " commands:")
    for _, entry in ipairs(CC.HELP_COMMANDS) do
        print("  " .. entry.cmd .. " - " .. entry.desc)
    end
    print("  Questions or bugs: " .. CC.CONTACT_EMAIL)
end

local function handleSlashCommand(msg)
    msg = CC.Utils.Trim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if not IsInGuild() then
        guildOnlyPrint("You must be in a guild to use this addon.")
        return
    end

    if cmd == "" then
        CC.UI.Main.Toggle()

    elseif cmd == "officer" or cmd == "o" then
        if not CC.Perm.PlayerIsOfficer() then
            guildOnlyPrint("Your guild rank does not have officer access.")
            return
        end
        CC.UI.Officer.Toggle()

    elseif cmd == "sync" then
        CC.Sync.RequestSync()
        guildOnlyPrint("Requested a sync from the guild.")

    elseif cmd == "backup" then
        local backup, err = CC.Backup.Create(rest ~= "" and rest or nil)
        if backup then
            guildOnlyPrint("Backup created: " .. backup.label)
        else
            guildOnlyPrint("Could not create backup: " .. tostring(err))
        end

    elseif cmd == "clearcache" then
        CC.Backup.ConfirmClearAll()

    elseif cmd == "officerrank" or cmd == "adminrank" or cmd == "superadmin" then
        local settingsKey = ({ officerrank = "officerRanks", adminrank = "adminRanks", superadmin = "superAdmins" })[cmd]
        local label = ({ officerrank = "Officer ranks", adminrank = "Admin (restore) ranks", superadmin = "Super-admins (by character name)" })[cmd]
        local sub, entryName = rest:match("^(%S*)%s*(.-)$")
        sub = (sub or ""):lower()
        local gdb = CC.DB.GetGuildDB()

        if sub == "" or sub == "list" then
            if gdb then
                guildOnlyPrint(label .. ": " .. formatRankSet(gdb.settings[settingsKey]))
            end
        elseif sub == "add" or sub == "remove" then
            if not CC.Perm.PlayerIsAdmin() then
                guildOnlyPrint("Only a guild rank with admin access can change this.")
                return
            end
            if entryName == "" or not gdb then
                guildOnlyPrint("Usage: /cc " .. cmd .. " add|remove <name>")
                return
            end
            if cmd == "superadmin" then
                entryName = CC.Utils.ShortName(entryName) -- character names never include a realm suffix internally
            end
            if sub == "add" then
                gdb.settings[settingsKey][entryName:lower()] = true
                guildOnlyPrint("Added to " .. label:lower() .. ": " .. entryName)
            else
                gdb.settings[settingsKey][entryName:lower()] = nil
                guildOnlyPrint("Removed from " .. label:lower() .. ": " .. entryName)
            end
        else
            guildOnlyPrint("Usage: /cc " .. cmd .. " list|add <name>|remove <name>")
        end

    elseif cmd == "bosslog" then
        CC.Boss.debugMode = not CC.Boss.debugMode
        guildOnlyPrint("Boss NPC id logging " .. (CC.Boss.debugMode and "enabled" or "disabled") .. ".")

    elseif cmd == "whoami" then
        CC.Perm.RefreshRoster()
        local myName = UnitName("player")
        local info = CC.Perm.GetRosterInfo(myName)
        local gdb = CC.DB.GetGuildDB()
        if not info then
            guildOnlyPrint("Could not find you in the cached guild roster yet. Wait a moment for GUILD_ROSTER_UPDATE and try again.")
            return
        end
        guildOnlyPrint(string.format("%s - rank \"%s\" (index %d)", myName, info.rankName or "?", info.rankIndex or -1))
        if gdb then
            if CC.Perm.IsSuperAdmin(myName) then
                print("  super-admin: YES (name-based override, bypasses rank checks)")
            end
            print(string.format("  officer access: %s (allowed ranks: %s)",
                CC.Perm.PlayerIsOfficer() and "YES" or "no", formatRankSet(gdb.settings.officerRanks)))
            print(string.format("  admin access: %s (allowed ranks: %s)",
                CC.Perm.PlayerIsAdmin() and "YES" or "no", formatRankSet(gdb.settings.adminRanks)))
        end

    elseif cmd == "addboss" then
        local id, name = rest:match("^(%d+)%s+(.+)$")
        if id and name then
            CC.Boss.AddCustomBoss(id, name)
            guildOnlyPrint(string.format("Added boss %s (id %s).", name, id))
        else
            guildOnlyPrint("Usage: /cc addboss <npcId> <name>")
        end

    else
        printHelp()
    end
end

SLASH_CRIMSONCOIN1 = "/cc"
SLASH_CRIMSONCOIN2 = "/crimsoncoin"
SlashCmdList["CRIMSONCOIN"] = function(msg)
    -- WoW hides Lua errors from slash-command handlers by default (no
    -- popup unless "Display Lua Errors" / scriptErrors is on), so an
    -- uncaught error here looks exactly like the command doing nothing.
    -- pcall so a bug always prints something visible instead of silence.
    local ok, err = pcall(handleSlashCommand, msg)
    if not ok then
        print("|cffff4040Crimson Coin:|r Command error: " .. tostring(err))
    end
end
