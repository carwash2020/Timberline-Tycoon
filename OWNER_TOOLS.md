# Owner tools

Chat commands that only the owner can run. They are server code
(`ServerScriptService/AdminService`, rules in `Shared/AdminLogic`): the server
reads the speaker's UserId off the chat source and checks it on every command.
There is no remote and no button for a client to fake. Anyone else who types
one gets nothing, and the server logs the attempt.

**Who is the owner:** the person whose account owns the experience, plus any
UserIds you paste into `AdminLogic.OwnerUserIds` (needed if a group owns it).
Studio sessions work too. An unpublished place has creator 0, so only Studio
works there.

| Command | What it does |
|---|---|
| `/give <player> <amount>` | add cash (up to the wallet cap) |
| `/take <player> <amount>` | remove cash (never more than they have) |
| `/setcash <player> <amount>` | set their cash |
| `/gift <player> <Axe\|Gear\|Sawmill\|Machine\|Blueprint> <id>` | a free item, any rung, no price. A `Blueprint` is a rolled plan for any building id (`Cabin`, `Shed`, `Wall`): it lands in their hotbar and teaches the building when they use it with the hammer (BUILD_SYSTEM.md). A building they already know is refused (`alreadyOwned`) |
| `/kick <player> [reason]` | remove them from this server |
| `/ban <player> <hours\|perm> [reason]`, `/unban <userId>` | Roblox's ban API, whole experience |
| `/goto <player>`, `/bring <player>` | teleport |
| `/superrun` | toggle your own super run (4x walk speed) |
| `/timespeed <1\|4\|20\|60>` | run the in-game clock faster (this server only) |
| `/settime <6am\|noon\|6pm\|midnight\|7:30pm\|18:30>` | jump to an hour (keeps the speed) |
| `/timereset` | real time again |
| `/announce <text>` | a toast for everyone |
| `/god` | toggle no damage for you (a ForceField on your character) |
| `/heal <player>` | full health |
| `/tospawn` | teleport you to the spawn point |
| `/freeze <player>` | freeze or unfreeze them (never yourself) |
| `/stats <player>` | read-only: cash, plot, tutorial step, axes, blueprints |
| `/resettutorial <player>` | start their tutorial over |
| `/unlockbp <player>` | every building plan in their blueprint book |
| `/shutdown` | kick everyone, you too: this server ends |
| `/delegate <player\|userId> <helper\|moderator\|builder\|tester\|custom> [powers] [session\|1h\|24h\|server] [confirm]` | give someone a role (owner only, see Delegation) |
| `/undelegate <player\|userId>` | take every power back at once (owner only) |
| `/delegates` | who has powers, and for how long (owner only) |
| `/admin` | the list, as toasts |

A player is matched by name or a unique start of one. Amounts are whole numbers
from 1 to $2,000,000. Item ids are the game's own (`SteelAxe`, `Lantern`,
`SawmillSturdy`, ...). Vehicles are not giftable yet (they are boxes on a plot).

## The owner hub (PC, phone and Xbox)

Open it with the **OWNER** side button, or click both thumbsticks (L3 + R3).
Close it with the **X**, **B** or **Esc**. Every tool is also a chat command
(above), so nothing is menu-only.

Layout: a title bar with a **Find a tool** box (type "kick", "teleport",
"restart"...), four tabs, a scrolling body and a status strip at the bottom.
The strip shows who is picked and what just happened, or why the server
refused (green: done, red: refused). Each tool is a big button with a one
line hint under it.

| Tab | What is in it |
|---|---|
| **PLAYERS** | the player list (pick once, kept on every tab), GO TO, BRING, HEAL, FREEZE, STATS (read-only), RESET TUTORIAL, KICK, then BAN with a length (1 hour, 1 day, 1 week, forever) |
| **GIVE** | amount chips ($100 to $1M) or a custom amount (`2500`, `10k`, `1.5m`), GIVE CASH, TAKE CASH, SET CASH, UNLOCK ALL BUILDINGS, then free items: TYPE (All, Recent, Axe, Gear, Sawmill, Machine, Blueprint), a search box, the GIFT button (names the picked item) and the item list. Recent shows what you gifted this session |
| **WORLD** | clock speed (1x, 4x, 20x, 60x), SET HOUR (6 AM, Noon, 6 PM, Midnight), RESET TIME, ANNOUNCE (type it, or fill in a preset) and SHUT DOWN SERVER |
| **SELF** | SUPER RUN, GOD MODE, GO TO SPAWN, and the last eight actions (on screen; the server also logs each one with your UserId in Output) |
| **DELEGATES** (owner only) | role chips (HELPER, MODERATOR, BUILDER, TESTER with a red warning, CUSTOM with tickable powers), how long (session, 1 hour, 24 hours, until the server closes), GRANT, and the current delegates each with REVOKE (see Delegation) |

The player bar at the top of PLAYERS, GIVE and search results is the one
player picker: step with the arrows or tap a name in the list. The pick is by
name, so it survives people leaving. KICK, BAN, TAKE CASH, SET CASH and SHUT
DOWN need a second press within four seconds (the button turns amber and says
SURE?); changing the player or amount starts over.

On a pad: the D-pad or stick walks the order the screen shows (title row, tabs,
then the body top to bottom); the selected button has a thick amber ring; the
list scrolls to keep it in view; **LB / RB** change tab. Everything you tap is
at least 44 px tall.

Not in the hub or in chat (skipped on purpose, see STATUS.md): fly or noclip, mute,
walk speed and jump presets (they would fight SprintLogic), invisibility,
mute, teleport to named places, clearing an inventory item, maxing a plot,
spawning or clearing wood, regrowing trees, weather, seasonal events, test
vehicles, and "reset player save".

**Time tools.** The server keeps three workspace attributes (`TimeAnchorReal`,
`TimeAnchorGame`, `TimeSpeed`) and every clock reader (the sky, shop hours,
night, the corner clock) works from them (`WorldTime.GameNow`). Speeds are
whitelisted (1, 4, 20, 60) and the menu's hours are four named presets; chat
also takes `7:30pm` or `18:30`. Changing the speed carries on from the current
hour, and a set hour keeps the speed. **Nothing is saved**: it lives in server
memory, so a restart (or a new server) is back on real time, and `/timereset`
clears it at once. It is quiet: only the owner gets a toast (everyone sees the
sky move, which is the point). Weather slots and the Gloam grove's countdown
still run on real time.

It is only a way to ask. The hub is built on the owner's client alone (the
server sets `IsOwner` on that player, and that attribute only decides whether
the UI is built), but the real lock is the server: every press fires the
`AdminRun` remote (rate limited), and `AdminService.RunRequest` checks the
sender's UserId against `AdminLogic.IsOwner` before it reads the request, then
`AdminLogic.FromRequest` whitelists it (an action on the list, plain words for
names, amounts 1 to $2,000,000, a speed from the list, an hour from the list,
announcement text up to 120 printable characters), then the command is
checked again. A modified client can fire the remote all it likes: it gets
nothing, no answer, and the attempt is logged. A real owner's request is
answered on the `AdminResult` remote (to that owner only) with whether it
worked and a line of text, which fills the hub's status strip. Kick and ban
never target the owner who sent them (or, outside Studio, any other owner).
`AdminHubLogic` (tabs, tools, confirmation, filters, navigation) is pure
and only decides what the hub shows; it cannot grant anything.

## Delegation: giving other people some powers

Only the owner can grant or revoke anything (`/delegate`, `/undelegate`,
`/delegates`, or the **DELEGATES** tab: pick a player, a role, how long, then
GRANT; REVOKE sits next to each current delegate). A delegate gets a hub that
shows only the tools they were granted, titled **DELEGATE** (or **TESTER**),
with a banner saying their role and the time left.

| Role | Powers |
|---|---|
| **HELPER** | go to and bring players, freeze/unfreeze, stats, announce |
| **MODERATOR** | HELPER plus kick, and bans of **at most 1 hour** |
| **BUILDER** | free items for **themself only**, set the hour, clock speed, reset time, god mode, go to spawn |
| **CUSTOM** | the powers you tick, only from the delegable list: go to, bring, heal, freeze, stats, announce, kick, ban (1 hour), gift (themself), set hour, clock speed, reset time, spawn, god |
| **TESTER** | every owner power except delegation (see the warning below) |

How long: **session** (ends when they leave or the server closes), **1h**,
**24h**, or **server** (until the server closes). All of it lives in server
memory: nothing is saved, so a restart or a new server starts with nobody
delegated. (Saving "until revoked" across servers would have to go through
ProfileService and ProfileSchema; that is a follow-up, not built.) A delegate
who rejoins keeps a 1h, 24h or server grant while the server runs.

**Never delegable** (owner only, enforced in `AdminLogic.GrantAllows`, and
`CleanPowers` refuses them in a CUSTOM list): cash for others (`/give`,
`/take`, `/setcash`), super run, server shutdown, reset tutorial and unlock
buildings (they change another player's save), `/unban`, permanent bans, and
delegation itself. There is no "reset player save" tool at all. Not even
TESTER can grant, revoke or list delegates.

**Safety rules the server enforces on every delegated request**

- The role of whoever sends a request is worked out on the server from
  `AdminLogic.IsOwner` and the server's own delegate table. A role, a power list
  or any other word a client sends is ignored; the `IsOwner` attribute is only
  for showing UI (and is cleared for a delegate).
- A delegate can never aim anything at an owner (no kick, ban, freeze,
  teleport, stats, heal, cash, gift or reset on the owner), and the owner can
  never be made a delegate.
- A delegate is rate limited harder than the owner (at least 0.75 s between
  requests, on top of the remote's own limit), and every number is capped by
  `FromRequest` like the owner's.
- Revoking, expiry and leaving (for a session grant) end it at once: the
  server tells that client, which closes the hub and removes the button, and
  takes back its super run and god mode. A sweep every 15 s ends expired grants
  nobody used.
- Every delegated action is printed to Output with both ids
  (`[Admin] DELEGATE <name> (<id>) role <role> granted by <owner> (<id>): ...`)
  and shown in the owner's SELF tab list (LAST ACTIONS, lines starting with `>`).

### TESTER: full owner power (read this before using it)

> **WARNING. TESTER has full owner power: cash, bans, save resets, shutdown.
> Only give it to someone you trust completely.** It is meant for testing, and
> it is the most dangerous object in the system.

What it can do: everything the owner can do in this hub and in chat, including
the otherwise owner-only tools (give, take and set cash on anyone, permanent
bans, `/unban`, super run, reset tutorial, unlock buildings, free gifts,
`/shutdown`). Guardrails:

1. **Two-step grant.** Selecting TESTER shows a red panel with the warning above;
   GRANT turns amber (SURE? GIVE FULL POWER) and needs a second press. In chat,
   `/delegate <player> tester <1h|24h|session>` only shows the warning; add the
   word `confirm` to grant it. The server enforces the word, so no client can skip it.
2. **It cannot spread.** TESTER cannot grant, revoke or list delegates and cannot
   create another TESTER, and it can never act on the owner (no kick, ban, freeze,
   teleport, cash or reset). It cannot change `AdminLogic.OwnerUserIds` (that is
   source code, not a command). Only the owner ends it.
3. **Short.** Only `session`, `1h` or `24h` (never "until the server closes"),
   never saved, and it ends when the server closes.
4. **Visible.** The TESTER's menu shows a red "TESTER (full power)" banner. Each
   TESTER action is logged with both ids, shown in the owner's audit list, and a
   destructive one (ban, kick, take or set cash, shutdown, unban, reset tutorial)
   also pops a toast on the owner's screen.
5. **Instant revoke**: `/undelegate` or REVOKE closes the TESTER's menu at once.
6. **Extra confirmation**: a TESTER's destructive tools ask for a second press in
   the hub, and the server refuses them without it. Chat has no second step, so a
   TESTER's destructive commands work only from the hub.

## Making sure it is only you

1. Paste your own Roblox UserId into `AdminLogic.OwnerUserIds` (a number
   between the braces). Then you are the owner whoever owns the experience.
   Left empty, the owner is the account that owns it (and nobody if a group does).
2. Studio sessions count as owner (they are never live servers).
3. A spec fails if any server file ever trusts the `IsOwner` attribute for a
   decision, and if anything but the owner tools sets the free-gift flag.
