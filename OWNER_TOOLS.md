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
| `/announce <text>` | a toast for everyone |
| `/admin` | the list, as toasts |

A player is matched by name or a unique start of one. Amounts are whole numbers
from 1 to $2,000,000. Item ids are the game's own (`SteelAxe`, `Lantern`,
`SawmillSturdy`, ...). Vehicles are not giftable yet (they are boxes on a plot).
