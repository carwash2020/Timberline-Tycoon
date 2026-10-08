# Agent handoff (8 October 2026): read this, then STATUS.md

Written at the end of a long session. It says where the work stands **right now** and what to do next.
STATUS.md has the standing decisions and the history; some of its entries still say "branch ..., not
merged". **Every one of those branches is merged** (see the list below). When this file and STATUS.md
disagree about merge state, this file wins. Fix the stale STATUS.md lines when you next edit it.

## Who and how to work

- Owner: **Connor** (carwash2020). A beginner. Windows PowerShell, one command per line, never chained
  with `&&`, never print secrets. He also has a Mac. He tests in Roblox Studio and on Xbox; you cannot
  run Studio, so every change ships with the exact Studio checks and what good looks like.
- Local copy: `C:\Users\nicho\timberline-tycoon`. Launch commands to give him after a merge:
  `cd $HOME\timberline-tycoon`, `git checkout main`, `git pull`, `rojo build -o build.rbxlx`,
  `start $HOME\timberline-tycoon\build.rbxlx`. Xbox / live: File > Publish to Roblox, Shut Down All
  Servers in Creator Hub, rejoin. (`rojo serve` is the live-sync alternative.)
- Standing instruction: open a PR for each change, subscribe to it, **merge when CI is green** (squash,
  pass `expectedHeadSha`). Commits: `phase-2: <what>`. Never put a model name in commits or PRs.
- Owner tools are for Connor only (Elucidhealer618; Xbox Catman9732). The server never trusts a client
  `IsOwner`. Still needed from him: the two numeric UserIds for `AdminLogic.OwnerUserIds`.
- Verify with `./scripts/check.sh` (about 10 minutes; StyLua, Selene, luau-lsp strict, Lune specs,
  ECONOMY.md and ECONOMY_V1.md current). CI runs the same script, one run per push event plus one per PR.
  After a balance change re-run `lune run tools/economy` and `tools/economy1` and commit the reports.
- Working pattern that worked: one worktree agent per task (`isolation: "worktree"`), branch
  `claude/<topic>`, the agent pushes but does not open the PR, you open the PR, subscribe, wait for CI,
  merge. Agents often cannot re-run the full script after a late fix, so CI is the full check; after any
  merge of main into a branch with real code overlap, run `./scripts/check.sh` before pushing.
- Merge conflicts have almost always been STATUS.md / PHASE2_NOTES.md only (every PR adds a section).
  Resolve by keeping both sides (a small python regex over the conflict markers), then check for markers.
- CodeRabbit comments ("does not receive automatic reviews") are noise. A Rokit/curl 403 on CI before
  any test ran is infrastructure: re-run the failed job once.
- The GitHub MCP connection drops now and then (503). Retry later; do not claim a PR is green or merged
  without reading its check runs. The branch `claude/new-session-7e3s9x` is a scratch branch that the
  stop hook nags about: `git checkout -B claude/new-session-7e3s9x origin/main` then
  `git push -u --force-with-lease origin claude/new-session-7e3s9x` makes it level with main.
- Repo rules that matter most (CLAUDE.md has the rest): the server owns all state, remotes carry
  intents only and every handler validates and uses `RateLimiter`; only EconomyService changes cash;
  only ProfileService touches DataStores; new save fields go in `ProfileSchema` with an idempotent
  `Migrate`; game code is `--!strict`; put rules in pure `Shared/` modules with a spec.

## State of main

`main` is at #116 (`d001a6e`). **No PRs are open and no agents are running.** CI was green on every
merge. **Nothing from #90 onward has been seen in Studio by Connor** except one load test (see below).

Merged this stretch, newest last: #90 store polish; sell station fixes; Sky Bin, sawmill/planer tiers and
conveyors (boxes that open and place once); NPC dialogue box and text-out-of-walls; store bugs; LT2 ground
and raised 1-stud plot platforms; LT2 building kit; window boxes and stepped shelves; Lower/Higher quality
choice; faster loading (97 s to about 9 s); owner hub and paid-item grants; #106 join race fix; #107 plot
picker shows which pad (camera, map card, pillar, claim fade); #108 final pass; #109 held shop boxes hang
steady; #110 uploaded vehicle meshes placed on the part-built hull; #111 NPCs face you while you talk and
keepers/Old Hank use the full dialogue box; #112 drop the axe with B / Q / hotbar long press (no button);
#113 manual saves, Restart save in Settings, Unload base / Load base (LT2 style); #114 **hotfix** for Talk
and Buy dead after #107 to #111; #115 floating NPC bubbles removed; #116 54 more choppable trees in town.

## What is unverified and where the risk is

1. **#114 hotfix is a likely cause, not a proven one.** Four client scripts toggled the global
   `ProximityPromptService.Enabled` by saving and restoring a value; overlapping holders left prompts off
   (Talk, Buy, Open, Pick up). Fixed with `Shared/PromptGate` + `PromptSwitch` (named holds). If Connor
   still cannot talk or buy, ask for Output lines: server `[Talk] pressed Talk on ...`, client
   `[Talk] box open` / `box closed (<reason>)`, `[PromptSwitch] held off a long time`, `[Drag] could not
   start the hold`, any red text. Also look at #109 (`DragController` HoldForce/Upright for ShopBox) and
   #111 (NPCTalkService, DialogueService.Say) if the cause is elsewhere.
2. **Join flow** (#106, #108, #113): MapBuilder loads nobody; `GameServer.enterWorld` waits for gates,
   streams the spawn, loads the character (retry x3), waits for `ClientReady`, then `ProfileLoaded`. A
   Studio log shows first player can play at +9.2 s and the handshake works. The save picker, plot picker
   and Unload/Load base have not been seen. Screen order is `PickerSequence`: quality, save picker, plot.
3. **Saves by hand (#113):** nothing auto-loads; picking a save with a plot opens the plot picker; the
   SAVES panel's top button is UNLOAD BASE (becomes LOAD BASE); Restart save is a two-press row in
   Settings. 120 s unload cooldown (`GameConfig.BaseCooldownSec`, `profile.baseCooldownUntil`). A new
   player with no plot does **not** get a launch picker by Connor's own earlier decision (first plot is
   bought from Old Hank at the Land Office, `GameConfig.PlotPrice` $150). Studio only keeps saves when
   "Enable Studio Access to API Services" is on and the place was published once.
4. **Vehicles (#110):** best-fit placement of uploaded mesh pieces from the part-built hull; mesh facing
   and the Lights fill are Studio-only unknowns. Connor's screenshot also showed a blue block in the bed
   and a dark vehicle with white strips that nobody could explain. Ask for a side-on view and which piece
   (bed, glass, lights, hitch) is off.
5. **"Custom axes not working":** no code bug found in the buy path, the owner-grant path, or the shed
   rack (it falls back to part-built axes if a mesh fails). Likely the mesh asset permissions in Creator
   Hub (STATUS.md open item 3). Need Connor's `[MapBuilder] build check:` and `[MeshKit]` Output lines
   and what exactly failed.
6. **Phone drop-axe:** long press on the hotbar strip (the engine hotbar cannot host a button); unknown
   whether the engine's own slot toggle also fires or whether `TouchLongPress` reaches CoreGui.
7. **Trees (#116):** 54 trees, not "all over"; the phone disc budget went from 1.7x to a new ceiling of
   2.0x (`TownTreeData.PhoneDiscMax`) and needs Connor's OK. None right at the dealership door (keep-outs
   take that wall). Not in BiomeData counts, so the economy model is unchanged.
8. Other untested: owner hub UI (about 1,900 lines), box window performance on phones, Asphalt gravel
   look, platform darkness at night, `ForestFiller` client plan still about 10 s after the player is in.

## Questions waiting on Connor (do not decide these for him)

- 120 s unload cooldown right? Fee for packing? Should UNLOAD BASE also be in the quick / View menu?
  Should loose wood on the plot be saved with the base instead of blocking the unload?
- A one-time toast for Murph's "Press F if you forget the step" for players who never press Talk?
- Phone tree budget 2.0x OK? Push for more trees along roads and farther out?
- Should new players pick a plot at launch again (still $150 or changed)? Owner powers: live weather,
  clear plot, spawn vehicles, reset player save (none added).
- Weigh House rotation; "paint all of this type"; badge IDs; a rollback tag before M1.10.
- Hand-fed wood left more than 4 s on a busy mill is treated as belt-fed (rare wood refused): design call.

## Suggested next steps

1. Get Connor's Studio results on the list above, starting with Talk / Buy (the live regression).
2. Fix whatever the Output lines show; keep each fix minimal and add a spec that reproduces it.
3. When he sends the UserIds, set `AdminLogic.OwnerUserIds` and test the owner hub.
4. Then the cleanups in STATUS.md's open items: `ForestFiller` speed, vehicle leftovers, mesh permissions.
5. Keep STATUS.md current in the same PR as any change that moves it, and fix its stale "not merged" lines.
