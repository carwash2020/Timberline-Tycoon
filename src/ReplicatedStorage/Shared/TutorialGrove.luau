--!strict
-- TutorialGrove: the first-sale grove. A few small oaks stand just west of
-- the spawn, so the first chop is a short walk. The first sale is at the
-- sawmill's sell pad like every later one (Murph's buy cart is gone). The
-- spots stay off the roads, the spawn walk, the street and the lot
-- (tests/StoreBoard.spec, TreeFill.spec).

local TutorialGrove = {}

export type Spot = { x: number, z: number }

-- West of the spawn walk (x -6), south of the street (z 62) and of Bram's
-- walk (his south mark is -17, 50), north of the road mouths (z 36), and
-- clear of Murph's camp at (-28, 45).
TutorialGrove.Trees = {
	{ x = -22, z = 44 },
	{ x = -21, z = 40 },
	{ x = -19, z = 46 },
} :: { Spot }

return TutorialGrove
