## QA — T413 Travel (acceptance FIRST)
Acceptance: `/workspace/roblox/qa/t413-travel-acceptance.md` (2026-10-28 America/Denver). Sources: vision §3 RULE 3 / §4 / audit 24–26, quality-bar DoD, main `a66c562` FerryLogic+GateService+GameConfig, Manager ticket.

**Connor locks:** town/main bridge free; lift bridge TollFee $100 / 180 s; FerryFare **$350** (repo 400 → wire); no paid fast travel V1.

**Must prove:** (1) free town bridge, (2) $100 toll once per window + unpaid push-back, (3) FerryFare 350 in config+UI, (4–6) walkable car ferry ≤40 s + **vehicles allowed** (flip current truck refuse) + fail-closed board/fare, (7) Sparkworks FerryRequired clears only when dock/isle ready, (8) no gondola return, (9) Skyroot switchback + junction signs, (10–11) truck+trailer clearances + overlap lint + bridge/ferry pins, (12) no StoreData/Cap/catalog/Block wood edits, (13) preview/t413 + Art/Builder PASS. MeshId 0 greybox OK.

**Edge:** toll re-pay after window; cargo weld rules; Gloam footbridge foot-only if in PR; harbour berth vs Sparkworks ~(1115,−700).

**Out of scope:** soft bay-stack; T414 remakes; T415 perf; economy retune beyond FerryFare; cloud-island access design (Needs Connor).
