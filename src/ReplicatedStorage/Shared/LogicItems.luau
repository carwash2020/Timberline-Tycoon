--!strict
-- LogicItems: the wired pieces of a plot (V2_PLAN.md, wiring). PlotData
-- appends this list to its blueprints. The rules that join them are in
-- WireLogic and the server side is LogicService.
--   * SparkSwitch: flip it, and every lamp or door wired to it follows.
--   * SparkLamp: lit by itself until a switch is wired to it, then lit
--     while any wired switch is on.
-- A door is the ordinary Door piece. It can be wired too (WireLogic).
-- Both are bought once, boxed, at Hearth & Home (unlock), then placed free.
-- Cash only: no gathered material, so no recipe job or biome is needed.
-- Part budget: three boxes for the switch and two for the lamp.

local V2 = Vector2.new
local V3 = Vector3.new

local METAL = "#3C3C41"

return {
	{
		id = "SparkSwitch",
		displayName = "Wall Switch",
		category = "Decor",
		priceCash = 100,
		unlock = true,
		tier = 1,
		footprint = V2(2, 2),
		-- Box 3 is the lever. LogicService tips it when the switch is on.
		boxes = {
			{ size = V3(0.4, 3.2, 0.4), offset = V3(0, 1.6, 0), color = METAL, material = "Metal" },
			{ size = V3(1.2, 1.4, 0.3), offset = V3(0, 3.4, 0), color = "#9AA0A6", material = "Metal" },
			{ size = V3(0.25, 1, 0.25), offset = V3(0, 3.4, 0.25), color = "#C8402F", material = "Metal" },
		},
		note = "Flip it. Use Wire next to a lamp or a door to link them",
	},
	{
		id = "SparkLamp",
		displayName = "Spark Lamp",
		category = "Decor",
		priceCash = 150,
		unlock = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(0.4, 5, 0.4), offset = V3(0, 2.5, 0), color = METAL, material = "Metal" },
			{
				size = V3(1.4, 1.1, 1.4),
				offset = V3(0, 5.5, 0),
				color = "#FFE9A8",
				material = "Neon",
				light = true,
			},
		},
		note = "Lit until you wire a switch to it",
	},
}
