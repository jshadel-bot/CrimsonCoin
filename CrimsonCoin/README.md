# Crimson Coin

A guild-run currency & DKP tracker for WoW Classic Era (interface 11509 /
v1.15.9), themed as the Scarlet Crusade's own coinage. Every guild member
with the addon installed sees their own wallet and everyone else's; guild
masters and raid leaders (by guild rank) can adjust balances, and the addon
can prompt them to reward attendees automatically when a tracked raid/dungeon
boss dies.

Crimson Coin and "DKP" are treated as the same thing here: one currency, one
wallet per member. If you actually want two separate pools (say, a DKP score
*and* a spendable coin), that's a straightforward follow-up — the ledger/tx
system already generalizes to multiple currencies, it would just need a
`currency` field threaded through.

## Install

Copy the `CrimsonCoin` folder into:

```
World of Warcraft/_classic_era_/Interface/AddOns/CrimsonCoin
```

so that `CrimsonCoin.toc` sits directly inside `AddOns/CrimsonCoin`. Every
guild member who wants a wallet, and every officer who wants to manage
coins, needs this installed — there is no server component; it's pure
peer-to-peer over guild chat.

## Using it

- `/cc` — open your wallet and the guild roster's balances.
- `/cc officer` — open the officer panel (only visible/usable at or above
  the configured officer rank).
- Minimap button — left-click opens the wallet, right-click opens the
  officer panel (if you have access).
- **"Help"** button (top of both the wallet and officer windows) — lists
  every `/cc` subcommand with a description, plus a contact box
  (jgshadel@gmail.com) you can click and Ctrl+C to copy for bug reports
  or questions. The command list is generated from the same data `/cc`
  itself prints, so it can't drift out of date.
- **"Refresh Roster"** button (wallet footer, and top of the officer
  panel's Manage tab) — forces WoW to re-fetch the guild's member list
  from the server. This is *not* the same as "Sync": Sync pulls
  transaction history from other addon users, while Refresh Roster pulls
  the member list itself from Blizzard's servers. If members are missing
  or `/cc whoami` says it can't find you in the roster yet, try this
  first — it's the fix for both.

### Sending coins

"Send Coins" (next to "History" on your own balance) lets **any** member —
not just officers — send coins they actually have to another guild member,
including their own alts (an alt is just another name in the same guild's
roster, so it needs no special handling: pick it like anyone else). Pick a
recipient from the list, enter an amount, optionally add a note, confirm.

This is deliberately a different capability from what officers have.
Officers can *create* coins (award/remove, out of nowhere, by rank).
Members can only *move* coins they already hold — the addon won't let you
send more than your current balance, and critically, that's not just a
client-side courtesy: every other officer's client independently verifies
from its own copy of the ledger that you actually had the funds before
accepting the transfer, the same way it already verifies rank for officer
awards. Under the hood a transfer is a linked debit/credit pair (you lose
exactly what the recipient gains), and it shows up in both your and their
transaction history like anything else.

### Transaction history

Click any member's row in the wallet's Guild Roster list (or the
"History" button next to your own balance) to see every transaction that
makes up their current total — date, amount, reason, and who awarded or
removed it. This reads directly from the shared ledger, so it's the same
history everyone running the addon sees, not just what happened locally.
The officer panel's Manage tab has the same "History" button for whoever
is currently selected.

### Officer panel

- **Manage** tab: click a member, enter an amount and reason, Add/Remove
  coins. This broadcasts the change to every other online guild member
  running the addon. The "History" button next to the selected member
  shows their full transaction list.
  "Add Note" writes whatever's in the Reason/Note box as a note on the
  selected member instead — it ignores the Amount box entirely. A note is
  just a zero-coin ledger entry, so it rides the same sync/persistence as
  a coin award and shows up in that member's transaction history
  (labeled "NOTE" instead of an amount) for everyone running the addon,
  not just you.
- **Backups** tab: create a manual backup any time; restoring one (top
  rank only) snapshots the *current* state first (so a bad restore is
  itself undoable), then pushes the restored ledger to the guild. Each
  backup row also has a **Delete** button (officer/GM/admin) that
  permanently removes just that one backup, after a confirmation — purely
  local, like everything else backup-related.
  "Clear Local Cache" (also `/cc clearcache`) wipes *this character's*
  local balances and transaction history after a typed confirmation.
  **Your backups are not touched by this** — they're your safety net, so
  clearing everything else on purpose shouldn't take them with it; delete
  individual backups separately if you actually want those gone too. It's
  all purely local either way — nothing is broadcast, so no other guild
  member's data is touched. If another officer online has the addon,
  `/cc sync` afterward rebuilds your view from their copy; if you're the
  only install, the cleared data (not the backups) is unrecoverable. Rank
  settings and locally-learned boss ids (`/cc addboss`) are left alone
  since those are configuration, not history.

### Boss kills

The addon watches the combat log for known raid/dungeon boss NPC IDs. While
your group is fighting one, it samples your raid/party roster every 15
seconds. On a kill, anyone in officer or GM chat who is an officer gets a
popup listing everyone who met the attendance threshold (50% of samples by
default), with per-person checkboxes, a coins-per-person field, and an
Award button that pays everyone checked in one batch.

The built-in boss list is best-effort (Blizzard doesn't expose a "this is a
raid boss" flag, so it's a curated NPC ID table) — some IDs may be wrong or
missing. To fix that:

1. `/cc bosslog` — toggles printing the NPC id of anything that dies near
   you, so you can confirm the real id in-game.
2. `/cc addboss <npcId> <name>` — teaches your own client that id. This is
   stored locally (not synced to other officers), so if several officers
   need it, each one runs the command once.

## Permissions model

There's no central server, so trust is anchored in something every client
can verify independently: **your own copy of the guild roster**. Guild
rank *names* (e.g. "Officer", "Guild Master") are read from
`GetGuildRosterInfo()`, refreshed on login and on `GUILD_ROSTER_UPDATE`,
and checked case-insensitively against a whitelist per permission level.

- **Officer ranks** (default: `Guild Master`, `Officer`) — can add/remove
  coins and award bosses. Manage with `/cc officerrank list|add
  <name>|remove <name>` (admin only).
- **Admin ranks** — can restore or delete a backup and manage the rank
  lists, since restoring overwrites everyone's ledger. Anyone whose guild
  rank is literally named `Officer` or `Guild Master` automatically gets
  admin too, no configuration needed — those are the two rank names
  guilds almost always already have. `/cc adminrank list|add
  <name>|remove <name>` (admin only) is there for guilds using different
  rank names for their trusted tier.
- The true Guild Master (guild rank index 0 — unforgeable, exactly one per
  guild, regardless of what it's renamed to) always has officer *and*
  admin access, even if the configured rank name lists don't happen to
  match. This exists so renaming the GM rank can never lock everyone out
  of `/cc adminrank add` at once.
- `/cc whoami` shows your detected rank name/index and whether you
  currently have officer/admin access, for debugging permission issues.
- **Super-admins** (default: `Grimbot`) — specific character names that
  always have full officer *and* admin access, regardless of guild rank.
  Like the rank-index-0 GM check above, this is safe because character
  names are unique per (connected-)realm and enforced by Blizzard's
  servers — a modified client can't make itself *be* Grimbot in guild
  chat, only the real character can. Manage with `/cc superadmin
  list|add <name>|remove <name>` (admin only).

When your client receives a "someone added coins" message, it checks the
*sender's* rank in *your own* roster snapshot before applying it — a
modified client can lie about anything except the guild rank the real
server told you it has. This is also why balances are never sent as raw
numbers over the wire: every change is an individual signed transaction
(`{id, actor, target, delta, reason, ts}`) that gets replayed into each
client's ledger. Replaying the same set of transactions in any order,
any number of times, always produces the same balances — so two clients
that have seen different subsets of history just need to trade the
transactions they're missing (which is what `/cc sync` and the automatic
post-login sync do) to converge, with no risk of double-applying anything.

### Who you sync with

Only officers/GM/admin ever answer a sync request — a regular member's
`/cc sync` (or the automatic post-login one) always ends up pulling from
a trusted source, never from some other member's possibly-stale local
copy, because non-officers simply don't reply to `SYNCREQ` at all anymore.

Officers/GM/admin get one extra step members don't: when *their* sync
comes back, it doesn't merge automatically. A **Sync Review** window pops
up showing who it's from and a row-by-row list of exactly which new
transactions are about to be merged (already-known ones are filtered out
first, so this is only ever the genuinely new stuff) — nothing is applied
until you click **Accept**, or discarded until you click **Deny**. Regular
members keep the old silent auto-merge, since they're only ever syncing
with an already-trusted officer in the first place.

## Known limitations

- **Boss ID list is best-effort.** See "Boss kills" above.
- **Full-ledger sync on login.** New/returning clients currently ask the
  guild for the *entire* transaction history, not a delta. For a season's
  worth of a few hundred members this is fine; for a very large, very long
  running guild it's the first thing worth optimizing (e.g. sync-since-
  timestamp, or a periodic ledger compaction into "balance as of date X").
- **Addon message size.** Classic's addon-message channel is small, so
  large payloads (a full backup restore, a big sync response) get split
  into many chunks and trickle out over a couple of seconds rather than
  arriving instantly. This is intentional — it avoids tripping the
  server's spam/rate limiting.
- **Everything is per-guild, per-account.** Saved data is scoped by
  guild name + realm, so playing an alt in a different guild (or the same
  guild on a different realm) never mixes ledgers.
