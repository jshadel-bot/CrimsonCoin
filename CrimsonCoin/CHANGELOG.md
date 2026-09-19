# Changelog

All notable changes to Crimson Coin are documented here. Format loosely
follows [Keep a Changelog](https://keepachangelog.com/).

## [1.0.0] — Initial Release

First public release. Everything below shipped together as v1.0.0; there
is no prior published version to diff against, so this entry summarizes
the full feature set rather than an incremental delta.

### Wallets & Currency

- Added a guild-wide Crimson Coin wallet system: every member with the
  addon installed sees their own balance and the whole guild roster's
  balances, searchable and sortable by name or coin count.
- Added a **10,000 coin hard cap** per wallet. Enforced at the lowest
  shared layer so it applies uniformly to officer awards and
  member-to-member transfers alike, and is checked independently by
  every receiving client (not just trusted from whoever sent the
  transaction) — a modified client can't grant itself an exception.
  Debits and notes are never blocked, so an officer can always correct
  an over-cap wallet back down.

### Officer Tools

- Added an **Officer Panel** with a Home tab (select a member, then
  Add/Remove Coins with a reason, or Add Note) and a Backups tab.
- Added guild-rank-based officer permissions: access is driven by
  configurable rank *names* (default `Officer`, `Guild Master`) rather
  than a numeric rank index, so it survives a guild reordering its rank
  list. Managed via `/cc officerrank list|add|remove`.
- Added officer **notes**: a note attached to a member is stored as a
  zero-coin ledger entry, so it's signed, synced, and shows up in that
  member's transaction history (labeled "NOTE") exactly like a coin
  award — no separate storage or sync path needed.
- Added **Search** and **Sort (Name/Coins)** to the officer panel's
  roster list, matching the wallet window's roster controls.
- Added a **Sync** button to the officer panel (previously only on the
  wallet window) and renamed the "Manage" tab to "Home".

### Member-to-Member Transfers

- Added **Send Coins**: any member (not just officers) can send coins
  they actually hold to another guild member, including their own alts.
  Deliberately a different capability from officer awards — officers can
  *create* coins by rank, members can only *move* coins they already
  have. Enforced as a linked debit/credit pair verified independently by
  every receiving client from its own ledger, not trusted from the
  sender's claim.

### Transaction History

- Added a scrollable **History** window per member — date, amount,
  reason, and who awarded/removed/transferred it — reachable by clicking
  any roster row or the "History" button next to a balance. Reads
  directly from the shared ledger, so it's the same history for
  everyone, not a local log.

### Backups & Recovery

- Added manual guild-ledger **backups** (officer) and **restore**
  (admin only), with the current state auto-snapshotted before every
  restore so even a bad restore is itself undoable. Restoring pushes the
  restored ledger to the rest of the guild.
- Added per-backup **Delete** (officer/GM/admin), with confirmation.
- Added **`/cc clearcache`** / "Clear Local Cache": wipes *this
  character's* local balances and transaction history after a typed
  confirmation. Deliberately leaves backups, rank settings, and other
  guild members' data untouched.

### Sync & Trust Model

- Added a peer-to-peer sync protocol over guild chat: every balance
  change is an individually signed transaction that gets replayed into
  each client's ledger, so two clients that have seen different subsets
  of history just trade what they're missing to converge — no central
  server, no risk of double-applying anything.
- Restricted **sync sources to officers/GM/admin only** — `/cc sync`
  always ends up pulling from a verified trusted source, never a random
  guildmate's possibly-stale local copy.
- Added a **Sync Review** window for officers/GM/admin: incoming syncs
  no longer merge automatically for this tier — a window lists exactly
  which *new* transactions are about to be applied, with explicit
  Accept/Deny. Regular members keep the simpler silent auto-merge, since
  they only ever sync with an already-trusted officer.

### Permissions

- Added a rank-name-based permission model (officer / admin tiers),
  each independently configurable (`/cc officerrank`, `/cc adminrank`).
- Added automatic admin access for anyone whose guild rank is literally
  named `Officer` or `Guild Master` (case-insensitive), no configuration
  required.
- Added an unforgeable safety net: the true Guild Master (guild rank
  index 0, exactly one per guild, regardless of what it's renamed to)
  always has officer and admin access, so renaming the GM rank can never
  lock everyone out of configuring the rest.
- Added **super-admins**: specific character names (default `Grimbot`)
  with permanent officer + admin access regardless of guild rank —
  restricted the same way as the trust model verifies rank, since
  character names are unique and unforgeable per realm.
- Added `/cc whoami` to show your detected rank and current
  officer/admin status, for diagnosing permission issues.

### UI & Branding

- Added a minimap button (left-click for wallet, right-click for
  officer panel).
- Added a branded crest logo to the top-left corner of every window and
  updated window titles to "Crimson Coin - DKP Ledger" (wallet) /
  "Crimson Coin - Officer Panel" (officer panel).
- Added a **Help** window (and button, on both panels) listing every
  `/cc` command with a description, plus a click-to-copy contact field
  — generated from the same data `/cc`'s chat output uses, so the two
  can never drift out of sync.

### Fixed

- Fixed the guild roster not showing all members in the wallet/officer
  windows — it was being built from the ledger's own member records
  (which only existed for people who'd already received a transaction)
  instead of the live guild roster.
- Fixed backup restore and "Clear Cache" confirmation dialogs silently
  doing nothing when confirmed — the client's `StaticPopup` dialogs
  don't reliably expose their edit box via the documented `.editBox`
  field; added a fallback lookup by the dialog's actual global name.
- Fixed a transaction-submission bug where a rejected transaction (e.g.
  over the wallet cap) was still reported as successful and still
  broadcast to the guild, because the local apply's return value was
  never checked.
- Fixed the minimap button's right-click silently falling back to
  opening the wallet (indistinguishable from a left-click) when the
  officer-panel permission check failed, instead of showing a clear
  reason.
- Fixed guild member names not appearing in the wallet ("DKP Ledger")
  and Officer Panel roster lists on some clients — even though the same
  roster displayed correctly in Send Coins — caused by
  `FauxScrollFrameTemplate`'s offset bookkeeping being unreliable on
  those clients. Both windows' roster lists were rebuilt on a plain
  native `ScrollFrame` with manual mouse-wheel handling, the same fix
  already proven out on the History, Send Coins, and Sync Review
  windows.
- Restored the `GuildRoster()` / `C_GuildInfo.GuildRoster()` roster
  request after finding that removing it (an earlier attempt to stop
  the "blocked from an action only available to the Blizzard UI"
  notice) didn't actually stop the notice, but did stop the roster from
  populating at all on some clients. The dismissible notice is
  accepted as a lesser, cosmetic problem.
- Fixed a Lua error ("attempt to call a nil value") when clicking a
  member row in the Officer Panel, introduced by the roster-list
  rewrite above — a local function was referenced before its
  declaration in the file, so it resolved to a nil global instead of
  itself at the time the row's click handler was compiled.
- Hardened error handling throughout: slash commands, event handlers,
  and window refresh paths now catch and print errors instead of
  failing silently, since WoW hides Lua errors from these paths by
  default.

### Removed

- Removed the boss-kill detection feature (combat-log-based boss
  tracking, attendance sampling, and the associated reward-award prompt)
  and all related settings/commands, as it went unused.

### Known Limitations

- New/returning clients sync the guild's **entire** transaction history
  rather than just what changed — fine at guild scale, the first thing
  worth optimizing for very large, long-running guilds.
- Large sync/restore payloads are chunked and trickle out over a couple
  of seconds rather than arriving instantly, to avoid tripping the
  server's addon-message rate limiting.
- Data is scoped per guild + realm; an alt in a different guild never
  shares a ledger with your main.
