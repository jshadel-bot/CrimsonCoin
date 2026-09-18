local ADDON, CC = ...

CC.Backup = {}
local Backup = CC.Backup
local DB = CC.DB
local Perm = CC.Perm

-- Manual backup, any officer can do this (cheap and non-destructive).
function Backup.Create(label)
    local gdb = DB.GetGuildDB()
    if not gdb then return nil, "Not in a guild" end
    if not Perm.PlayerIsOfficer() then return nil, "Insufficient rank" end
    return DB.CreateBackup(gdb, label, UnitName("player"))
end

-- Restore is destructive (overwrites the shared ledger for the whole
-- guild's addon users) so it requires admin rank and is broadcast so
-- everyone converges back to the same state.
function Backup.Restore(backupId)
    local gdb = DB.GetGuildDB()
    if not gdb then return false, "Not in a guild" end
    if not Perm.PlayerIsAdmin() then return false, "Insufficient rank (guild master / top rank only)" end

    -- Always snapshot current state first so a restore is itself undoable.
    DB.CreateBackup(gdb, "Auto-snapshot before restore", UnitName("player"))

    local label
    for _, b in ipairs(gdb.backups) do
        if b.id == backupId then label = b.label end
    end

    local ok = DB.RestoreBackup(gdb, backupId)
    if not ok then return false, "Backup not found" end

    CC.Sync.BroadcastRestore(gdb, label)
    if CC.UI and CC.UI.Officer and CC.UI.Officer.Refresh then CC.UI.Officer.Refresh() end
    if CC.UI and CC.UI.Main and CC.UI.Main.Refresh then CC.UI.Main.Refresh() end
    if CC.UI and CC.UI.History and CC.UI.History.Refresh then CC.UI.History.Refresh() end
    return true
end

function Backup.List()
    local gdb = DB.GetGuildDB()
    return gdb and gdb.backups or {}
end

function Backup.MaybeAutoBackup()
    local gdb = DB.GetGuildDB()
    if not gdb then return end
    local now = CC.Utils.Now()
    local settings = gdb.settings
    if now - (settings.lastAutoBackup or 0) >= settings.autoBackupIntervalSeconds then
        DB.CreateBackup(gdb, "Automatic backup", UnitName("player"))
        settings.lastAutoBackup = now
    end
end

-- Wipes THIS CLIENT's local ledger/balances. Purely local -- nothing is
-- broadcast, so no other guild member's data is touched. Backups are
-- deliberately untouched (delete those individually with
-- Backup.DeleteBackup). Always go through Backup.ConfirmClearAll() rather
-- than calling this directly, so the warning popup can't be skipped.
function Backup.ClearAll()
    local gdb = DB.GetGuildDB()
    if not gdb then return false, "Not in a guild" end
    if not Perm.PlayerIsOfficer() then return false, "Insufficient rank" end

    DB.ClearAll(gdb)

    if CC.UI and CC.UI.Main and CC.UI.Main.Refresh then CC.UI.Main.Refresh() end
    if CC.UI and CC.UI.Officer and CC.UI.Officer.Refresh then CC.UI.Officer.Refresh() end
    if CC.UI and CC.UI.History and CC.UI.History.Refresh then CC.UI.History.Refresh() end
    return true
end

StaticPopupDialogs["CRIMSONCOIN_CLEARCACHE_CONFIRM"] = {
    text = "This permanently erases THIS CHARACTER's local Crimson Coin data:\n\n" ..
        "|cffff4040- Every member's balance\n- The full transaction history|r\n\n" ..
        "Your local backups are NOT touched by this -- delete those separately from the Backups tab if you want them gone too. " ..
        "It also does NOT touch your rank settings, and it does NOT affect any other guild member's data -- this only clears what's stored on this computer.\n\n" ..
        "If another officer online has the addon, /cc sync afterward can rebuild your view from their copy. If you're the only one with the addon installed, this is unrecoverable.\n\n" ..
        "Type CLEAR to confirm.",
    hasEditBox = true,
    button1 = "Clear",
    button2 = "Cancel",
    OnAccept = function(self)
        local ok, err = pcall(function()
            local editBox = CC.Utils.GetPopupEditBox(self)
            local text = CC.Utils.NormalizeConfirmText(editBox and editBox:GetText())
            if text == "CLEAR" then
                local cleared, clearErr = Backup.ClearAll()
                if cleared then
                    print("|cffff4040Crimson Coin:|r Local cache and history cleared. Run /cc sync to re-pull data from the guild if needed.")
                else
                    print("|cffff4040Crimson Coin:|r Could not clear cache: " .. tostring(clearErr))
                end
            else
                print("|cffff4040Crimson Coin:|r Clear cancelled (confirmation text did not match).")
            end
        end)
        if not ok then
            print("|cffff4040Crimson Coin ERROR|r [Clear cache confirm]: " .. tostring(err))
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function Backup.ConfirmClearAll()
    if not Perm.PlayerIsOfficer() then
        print("|cffff4040Crimson Coin:|r Your guild rank does not have officer access.")
        return
    end
    StaticPopup_Show("CRIMSONCOIN_CLEARCACHE_CONFIRM")
end

-- Permanently deletes one local backup. Officer/GM/admin only. Purely
-- local like everything else backup-related -- never broadcast.
function Backup.DeleteBackup(backupId)
    local gdb = DB.GetGuildDB()
    if not gdb then return false, "Not in a guild" end
    if not Perm.PlayerIsOfficer() then return false, "Insufficient rank" end

    local ok = DB.DeleteBackup(gdb, backupId)
    if not ok then return false, "Backup not found" end

    if CC.UI and CC.UI.Officer and CC.UI.Officer.Refresh then CC.UI.Officer.Refresh() end
    return true
end

StaticPopupDialogs["CRIMSONCOIN_DELETEBACKUP_CONFIRM"] = {
    text = "Delete this backup?\n\n%s\n\nThis cannot be undone, but it does not affect any other backup or your live data.",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self)
        local ok, err = pcall(function()
            local backupId = self.data
            local deleted, deleteErr = Backup.DeleteBackup(backupId)
            if deleted then
                print("|cffff4040Crimson Coin:|r Backup deleted.")
            else
                print("|cffff4040Crimson Coin:|r Could not delete backup: " .. tostring(deleteErr))
            end
        end)
        if not ok then
            print("|cffff4040Crimson Coin ERROR|r [Delete backup confirm]: " .. tostring(err))
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function Backup.ConfirmDeleteBackup(backupId, label)
    if not Perm.PlayerIsOfficer() then
        print("|cffff4040Crimson Coin:|r Your guild rank does not have officer access.")
        return
    end
    StaticPopup_Show("CRIMSONCOIN_DELETEBACKUP_CONFIRM", label or "", nil, backupId)
end
