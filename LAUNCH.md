# Publishing Timberline Tycoon

This is the path from the repo to a public Roblox game. Studio steps are
yours: this machine can't press Play. Do them in order. The long history of
what each build changed is [PHASE2_NOTES.md](PHASE2_NOTES.md); the checks
below are the ones that matter before anyone else joins.

## 1. Build the place and connect

In Terminal, in the game folder:

```sh
git checkout main
git pull
rojo build -o build.rbxlx
```

Open `build.rbxlx` in Studio (double-click it, or File → Open from File).
Then:

```sh
rojo serve
```

In Studio: **Plugins → Rojo → Connect**.

`rojo serve` updates scripts. It does **not** update place settings
(streaming, lighting, grass, wind). Those arrive only when you open a fresh
`build.rbxlx` and publish that file. Max Players does not arrive with the
file: Roblox stores it in Game Settings (step 2). If you Connect Rojo to an
older place, the scripts are new and the settings may still be the old ones.
Play will warn. See step 2.

## 2. Settings you set by hand

Play once with **View → Output** open. You want a line that says
`[PlaceCheck] OK`. Any yellow `[PlaceCheck]` line names the setting and how
to fix it. Put it back, Stop, and Play again until you see OK.

Set these before you call it published. Code cannot set the ones marked
"Studio":

| Where | Set this | Why |
|---|---|---|
| The built place, Workspace | StreamingEnabled **on**, StreamingTargetRadius **640**, StreamingMinRadius **128**, StreamingIntegrityMode **PauseOutsideLoadedArea**, ModelStreamingBehavior **Improved**, StreamOutBehavior **Opportunistic** | A fresh `build.rbxlx` already has these. 640 (it was 1024) is so a phone doesn't keep most of the map in memory. See "Phones" below. |
| Workspace → Terrain | Decoration **on** | Grass. A fresh `build.rbxlx` already has this. Scripts often can't read it; check the Properties panel. |
| Lighting | LightingStyle **Realistic**, PrioritizeLightingQuality **off** | A fresh `build.rbxlx` has both. Studio resets a Rojo place's style to Soft unless the file also carries Studio's internal lighting attributes (they are in the project, on Lighting). Off keeps town-at-night playable on a phone. |
| Home → Game Settings → Places | **Max Players = 12** | Not part of the place file. Roblox keeps this in Game Settings, and a script cannot write `Players.MaxPlayers`. A fresh `build.rbxlx` does contain an old internal field (`MaxPlayersInternal` = 12); Studio Play ignores it and reports **60** until you set this. There are 12 plots. More players than plots get a full-district message. PlaceCheck keeps warning until you set it. |
| Home → Game Settings → Security | **Enable Studio Access to API Services** on | Studio playtests can save. A place that was never published has no DataStores: publish once (step 5) before expecting this to work. |
| Home → Game Settings → Security | **Allow HTTP Requests** off | The game doesn't call websites. Leave it off. |
| Workspace attributes | Clear the debug ones (below) | Live servers ignore them. Clear them anyway so the next publish is clean. |

Debug attributes, in the **edit mode** command bar (not during Play), then
save or publish:

```lua
for _, name in ipairs({ "CoreLoop", "ClockOverride", "WeatherOverride", "WeatherOverrideIntensity", "RainbowTest" }) do
	workspace:SetAttribute(name, nil)
end
for name, _ in workspace:GetAttributes() do
	if string.sub(name, 1, 5) == "Tune_" then
		workspace:SetAttribute(name, nil)
	end
end
```

What already differs between Studio and a live server, on purpose:

- Studio saves go to DataStore `PlayerProfiles_Studio`. The published game
  uses `PlayerProfiles`. A Studio save never overwrites a real player, and
  your Studio progress is **not** what you'll see when you join the live
  game. The first live join is a new save ($20 and a Rusty Axe).
- `/spawnwood` and `/giveaxe` work only in Studio. Players on the live game
  don't have them.
- `ClockOverride`, `WeatherOverride`, `WeatherOverrideIntensity`, and
  `RainbowTest` work only in Studio. A live server plays the real clock and
  the real weather.
- The workspace attribute `CoreLoop` and any `Tune_*` attribute override
  balance only in Studio. The live game uses `GameConfig` (`CoreLoop` is 2,
  the current loop).

## 3. Playtest before you publish

Output open. No red errors. These are the checks from
[PHASE2_NOTES.md](PHASE2_NOTES.md) that gate a launch (day 3, the v2 loop,
and the smoke test). Skip the rest until something looks wrong.

| # | Do this | Good looks like |
|---|---|---|
| 1 | Press Play | Roblox's loader, then a **Timberline Tycoon** card, then the spawn. Output: `[PlaceCheck] OK`, `[CoreLoop] 2`, `[Client] Timberline Tycoon client started.` No red, no `failed to load` |
| 2 | Wait on the spawn | Murph's tutorial appears. (A save that already finished the old tutorial gets a short "WHAT'S NEW" version.) |
| 3 | Tutorial: fell an oak, put the axe away, drag the wood onto the Rustbucket, drive to the mill, sell | A notch grows, the tree falls, the wood stays on the bed, the pad says it sold. Spawn to first sale under 4 minutes |
| 4 | Stop, then Play again with wood on the bed | Cash, axe, and the load are still there. If they reset, Studio API access is off or the place was never published |
| 5 | **Test → Clients and Servers**, 2 players | The other player can't take your wood ("That's on your truck" / "That's Player1's wood"). Their truck moves smoothly on your screen |
| 6 | Drive out of the lot and back onto the sell pad | You fit in the cab, you can turn, you hop out beside the door, nothing on the bed falls off on a straight road |
| 7 | **Test → Device Emulator**, iPhone SE and iPhone 14 Pro, landscape | `[Quality] low` in Output. Buttons don't cover the cash. In town, the Starter Forest, and on the Snow Road, about 30 fps or better (View → Stats; a frame under 33 ms). Drive the Rustbucket at full speed toward the Snowfields: no long pause spinner |
| 8 | Look north from the spawn, desktop and the phone emulator | The mountain backdrop is still there. Trees don't pop in on top of empty void at the forest edge. If the horizon is gone or a truck pauses the whole way, tell Claude before changing the stream radius |
| 9 | Look at the screen corner | No **STORE** button yet. That's correct until step 4 |

On the live game the same server lines are in the in-game console: **F9**
(or `/console`) → **Server**.

## 4. Robux (when you want the Store)

Ids start at 0. While they are 0 the STORE button is hidden, those rows
aren't listed, and the server will not prompt or grant a purchase. Nothing
errors.

Prices are set in Creator Hub, not in the code. The game asks Roblox what
each item costs.

1. Publish the place once (step 5) if you haven't. Passes belong to the
   experience.
2. [create.roblox.com](https://create.roblox.com) → **Creations** →
   Timberline Tycoon → **Monetization → Passes** → Create a Pass named
   **2x Cash**. Give it an icon, put it on sale, copy the **ID** (a number).
3. **Monetization → Developer Products** → Create four products:
   **$1,000**, **$10,000**, **2x Wood (48 hours)**, **Instant Delivery**.
   Set each price. Copy each ID.
4. Paste the numbers into `src/ReplicatedStorage/Shared/StoreData.luau`,
   in the `CreatorIds` table at the top. That table is the only place an
   id is written. Leave a line at 0 to keep that one item hidden.

```lua
StoreData.CreatorIds = {
	Passes = {
		DoubleCash = 0, -- paste the 2x Cash pass id
	},
	Products = {
		Cash1k = 0,
		Cash10k = 0,
		DoubleWood = 0,
		InstantDelivery = 0,
	},
}
```

5. `rojo serve` is already connected, so Play again. The STORE button
   shows once at least one id is filled in. Studio purchases are free test
   purchases.

| Check | Good looks like |
|---|---|
| Buy $1,000 | Roblox's prompt, then +$1,000 and a thank-you |
| Wallet near the $2,000,000 cap | The $10,000 pack says "Wallet full" and never prompts |
| Buy 2x Wood | Trees drop double; the Store shows hours left |
| Buy Instant Delivery with logs in the truck | "Sell here" sells the bed from anywhere, once |
| Buy 2x Cash, then rejoin | Sales pay double; the Store says Owned; still owned after rejoin |
| Leave during a purchase and rejoin | Granted once, not twice |

What they do: 2x Cash doubles sale money forever. The cash packs add cash
only if it fits under the $2,000,000 cap. 2x Wood doubles logs from trees
for 48 hours (buying again extends it). Instant Delivery sells the current
truck load from anywhere, once.

## 5. Publish, then go public

1. Stop Play. **File → Publish to Roblox**. Pick this experience. If Studio
   asks to overwrite, overwrite the same place you test (don't make a
   second place by accident).
2. On create.roblox.com open the experience and use **Restart servers for
   updates** (Migrate to Latest Update) so old servers don't keep running
   the previous build.
3. Join the **published** game from the Roblox app (not Studio) and run
   checklist rows 1–4 again. This is the only way to see a real phone and
   a real DataStore save.
4. While it's still **Private**, fill in the listing:
   - **Icon** and at least one **thumbnail**
   - **Name** and **description** (chop, haul, sell, grow the yard)
   - **Maturity questionnaire** (Creator Hub asks before a public launch)
   - **Devices**: phone, tablet, and computer. Add console only if you've
     tried a gamepad
5. When the private play was clean, set the experience from **Private** to
   **Public**.

## 6. Later updates

```sh
git pull
rojo build -o build.rbxlx
```

Open `build.rbxlx`, Play the checklist that your change touches, Stop,
**File → Publish to Roblox**, then **Restart servers for updates**.

To roll the core loop back: set `CoreLoop = 1` in
`src/ReplicatedStorage/Shared/GameConfig.luau`, rebuild, and republish.
Saves that already moved to the new loop still load.

## Phones (why the stream radius changed)

Roblox uses one `StreamingTargetRadius` for every device. 1024 studs kept
most of the map loaded on a phone. It's now **640**, and the minimum that
must be loaded before you can walk into it is **128**.

The client forest follows that. Detailed filler trees still reach 480 studs
on a computer and 340 on a phone. The cheap stand-in trees stop at 600
(computer) and 520 (phone), inside the streamed ground, so they don't
float on void. The mountain ring is a separate persistent backdrop, so the
horizon from town should still be there.

Tradeoff: things between 640 and 1024 studs away (far forest, distant
terrain) appear as you drive toward them instead of already being loaded.
A fast drive can also hitch if a phone can't keep 128 studs ahead of the
truck. Step 3 rows 7 and 8 are the check. If the truck pauses or the forest
edge pops hard, say so; don't bump the radius back to 1024 without looking
at phone memory.

A phone on Automatic graphics already uses the smaller effects budget
(less decoration, no sun rays, fewer leaves). A phone whose graphics were
set to level 5 or higher still gets the fuller effects. The stream radius
is what got tighter for everyone, because that setting can't be per device.
