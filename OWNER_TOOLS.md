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
| `/gift <player> <Axe\|Gear\|Sawmill\|Machine\|Blueprint> <id>` | a free item, any rung, no price |
| `/kick <player> [reason]` | remove them from this server |
| `/ban <player> <hours\|perm> [reason]`, `/unban <userId>` | Roblox's ban API, whole experience |
| `/goto <player>`, `/bring <player>` | teleport |
| `/superrun` | toggle your own super run (4x walk speed) |
| `/timespeed <1\|4\|20\|60>` | run the in-game clock faster (this server only) |
| `/settime <6am\|noon\|6pm\|midnight\|7:30pm\|18:30>` | jump to an hour (keeps the speed) |
| `/timereset` | real time again |
| `/announce <text>` | a toast for everyone |
| `/admin` | the list, as toasts |

A player is matched by name or a unique start of one. Amounts are whole numbers
from 1 to $2,000,000. Item ids are the game's own (`SteelAxe`, `Lantern`,
`SawmillSturdy`, ...). Vehicles are not giftable yet (they are boxes on a plot).

## The menu (controller)

A pad can't type commands, so the owner also gets a menu: the **OWNER** side
button, or click both thumbsticks (L3 + R3). D-pad moves, A presses, B closes.
Pick a player and an amount, then Give, Take, Set cash, Go to, Bring or Kick
(press twice to confirm); pick an item type and an item and Gift it free;
toggle Super run; set Time speed (1x, 4x, 20x, 60x) and Set hour (6 AM, Noon,
6 PM, Midnight) or Reset time. The panel scrolls, so a phone can reach it all.
(Bans and announcements stay chat-only.)

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

It is only a way to ask. The menu shows up for the owner's client alone
(the server sets `IsOwner` on that player), but the real lock is the server:
every press fires the `AdminRun` remote, and `AdminService.RunRequest` checks
the sender's UserId against `AdminLogic.IsOwner` before it reads the request,
then the command is checked again. A modified client can fire the remote all
it likes: it gets nothing, and the attempt is logged.

## Making sure it is only you

1. Paste your own Roblox UserId into `AdminLogic.OwnerUserIds` (a number
   between the braces). Then you are the owner whoever owns the experience.
   Left empty, the owner is the account that owns it (and nobody if a group does).
2. Studio sessions count as owner (they are never live servers).
3. A spec fails if any server file ever trusts the `IsOwner` attribute for a
   decision, and if anything but the owner tools sets the free-gift flag.
