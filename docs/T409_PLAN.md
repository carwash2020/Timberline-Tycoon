# T409 plan: quality foundation

Goal: CI fails whenever a build makes no physical sense or the core loop breaks. Tools and tests only; the only game edits allowed are small fixes for real hits that the new lints find on main.

## Files

New:
- `tools/blender/meshlint.py`, `assets/meshes/lanes.json` (`{ mesh: [{ name, min, max, kind: lane|door|path }] }`, mesh-local studs). Reuses `glbstats.py` (load, node_matrix, mat_mul, apply). Reads each node's world matrix and triangles, keeps Body and Collision separate, AABB pre-filter then triangle-vs-box SAT (13 axes). Fails when a Body or Collision triangle enters a lane/door/path box, or Collision blocks a box that Body leaves open. Prints `mesh/lane: N tris, first at x,y,z`. About 5 s. Called from the lint step of `scripts/check.sh`. Sawmill entries: slip, carriage, outfeed (lane), front (door); scaled-vs-unscaled decided by asserting the GLB Body size against the design size (the Body is already final studs, so the 1.5 factor is applied to the design numbers; the script asserts and prints which it used). Door box uses the GLB Door node bounds when they differ by more than 0.5.
- `src/ReplicatedStorage/Shared/Lint/Geometry.luau`, `Lanes.luau`, `MustKeep.luau`: pure check logic, each takes a root Instance and returns a list of failures. Lune specs and `tests/cloud/entry.luau` are thin callers.
- `tests/support/WorldBuild.luau`: builds the whole world once headless (sky included) through `tools/loader.luau` the way `MapBuilder.spec` does, caches it for every spec in the process.
- `tests/GeometryLint.spec.luau` (rule 2: CanCollide part inside a door/path/lane box; Transparency 1 + CanCollide without `InvisibleBlocker=true` and a reason; rule 2b: world-wide pair overlap above 0.05 between different top-level pieces; controls), `tests/geometry_allow.json` (every entry needs a reason; the lint fails an entry without one and an entry that no longer hits).
- `tests/MustKeep.spec.luau`, `tests/mustkeep.json` (path, world position, tolerance 0.5): Tool Shed back door, every shop front Door, Dealership entrance, Sawmill door, Intake/Output of Sawmill, ChopSaw, Planer on a default plot, town SellPad (CanCollide off), SellArea, town counters, KeeperSpot, TemperSpot, 4 Socket_*Relic, spawn, ferry and gate prompts. No gondola prompts.
- `tests/PipelineE2E.spec.luau`: server modules, no physics, on the cached build. Steps named in failures with the last state reached.
- `tests/cloud/entry.luau` (Rojo-mapped runner), `tools/cloud/run_task.py`, `tests/RunTask.spec.luau`-style lune spec for arg parsing and the env-missing dry run.
- `docs/RENDER_CHECK.md`.

Changed:
- `src/ReplicatedStorage/Shared/World/Clearance.luau`: add `Clearance.Box(cf, size)` (OBB with a Y range: XZ grid broad phase, Y interval test, 15-axis OBB SAT for depth). The 2D API is unchanged so `Overlap.spec` and `NPCClearance.spec` stay green.
- `scripts/check.sh`: meshlint in the lint step.
- `.github/workflows/checks.yml` (the repo has no ci.yml; the workflow file is `checks.yml`): new job `cloud-test`, `needs: tests`, `concurrency: cloud-test`.

## Approach for the world lint (2b)
Build once, walk every BasePart with CanCollide on, group by top-level piece (child of TimberlineMap or a Model), MeshParts use the Collision node box from meshlint data (falling back to Size). Pairs from different pieces overlapping by more than 0.05 fail, deepest first, one line per hit in the format `[GeometryLint] A (Zone/Piece) x B (Zone/Piece) at (x,y,z), depth d, rule 2b`. Lane hits read `x lane Sawmill.slip`. Welded parts and allowlisted pairs are skipped. Terrain is out of scope.

## Real hits on main
Run the lint on main-as-is first. Every hit is fixed here (small, real fixes), allowlisted with a reason, or listed in the PR body for Builder. The full first hit list goes in the PR body. Nothing is deleted to make room.

## Cloud test
`rojo build default.project.json -o build/test.rbxl`, POST a Saved version to TEST_UNIVERSE_ID/TEST_PLACE_ID only (never the live place), one Luau Execution task per run, poll every 3 s, print logs, 401/403/409 fail with the code. Missing env vars: `cloud-test SKIPPED: missing <names>`, exit 0 and SKIPPED in the run summary, unless repo variable CLOUD_TEST_REQUIRED=1, which fails. The key is never printed.

## Acceptance proofs (each on a throwaway local commit, output pasted in the PR body)
1 restored old Sawmill GLB and lanes: meshlint names the slip. 2 crate in a wall. 3 lamp in a sign. 4 support through a log path and GuardRail +1.2 z (2b and lane). 5 delete Tool Shed back door: MustKeep. 6 remove mill Intake: PipelineE2E at the log-to-Intake step. 7 controls (same-piece welds, allowlist without reason, depth 0.05 pass and 0.06 fail, transparent blocker). 8 main green with the PR. 9 CI time main vs PR head from Actions. 10 test count goes up, nothing skipped. 11 cloud-test: dry run gives SKIPPED; a known overlap makes the runner's failures list non-empty (logic only; the real cloud run needs the secrets and Connor).

## Risks
- Building the full world headless may be slow (MapBuilder.spec is about 66 s). WorldBuild caches it so it is paid once per process; it may land in a heavy shard.
- Lune cannot read `BasePart.Position`; use `CFrame.Position`.
- Many 2b hits may exist on main; large fixes become follow-ups, not part of this PR.
- Studio and the real Roblox cloud cannot run here; nothing is claimed as seen in either.
- Full `check.sh` takes 12+ minutes; development uses targeted specs.
