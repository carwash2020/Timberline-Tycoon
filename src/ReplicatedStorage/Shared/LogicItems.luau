--!strict
-- LogicItems: the wired pieces of a plot (V2_PLAN.md §10). PlotData appends
-- this list to its blueprints. WireLogic joins them; LogicService runs them.
--
-- Bought once, boxed, then placed free. The two originals (Wall Switch,
-- Spark Lamp) stay Hearth & Home unlocks until Sparkworks is stocked from
-- SparkworksStock. Every new piece is gated so it is not a free starter
-- plan. Cash only: no gathered material.
--
-- Hex values are BuildingArt palette names (comments). Part budget: at most
-- five boxes, and at most one light.

local V2 = Vector2.new
local V3 = Vector3.new

-- Palette (BuildingArt): IRON, STEEL, STEEL_DARK, BRASS, GLOW, EMBER,
-- TIMBER, ANVIL, BRICK, PAPER. The Wall Switch and Spark Lamp keep the
-- colours they already shipped with.

local IRON = "#3B3634"
local STEEL = "#C9CED3"
local BRASS = "#C9A24A"
local GLOW = "#FFC872"
local EMBER = "#FF7A2E"
local TIMBER = "#5B3920"
local ANVIL = "#3C3F48"
local BRICK = "#A8553D"
local PAPER = "#F4ECD8"

local METAL = "#3C3C41" -- the shipped switch post

type Box = {
	size: Vector3,
	offset: Vector3,
	color: string,
	material: string,
	light: boolean?,
	leaf: boolean?,
}

type Item = {
	id: string,
	displayName: string,
	category: string,
	priceCash: number,
	tier: number,
	footprint: Vector2,
	boxes: { Box },
	note: string?,
	unlock: boolean?,
	gated: boolean?,
}

local items: { Item } = {
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
		note = "Flip it. Wire it to a lamp, a door or a gate",
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
		note = "Lit until you wire it, then it follows the wire",
	},
	{
		id = "Button",
		displayName = "Button",
		category = "Decor",
		priceCash = 320,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.4, 0.3, 1.4), offset = V3(0, 0.15, 0), color = STEEL, material = "Metal" },
			{ size = V3(0.4, 0.6, 0.4), offset = V3(0, 0.6, 0), color = IRON, material = "Metal" },
			{ size = V3(1, 0.35, 1), offset = V3(0, 1.05, 0), color = EMBER, material = "Metal" },
		},
		note = "On for one second when you press it",
	},
	{
		id = "Lever",
		displayName = "Lever",
		category = "Decor",
		priceCash = 520,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		-- Box 3 is the handle. LogicService tips it when the lever is on.
		boxes = {
			{ size = V3(0.4, 2.2, 0.4), offset = V3(0, 1.1, 0), color = IRON, material = "Metal" },
			{ size = V3(1.2, 1.2, 0.3), offset = V3(0, 2.4, 0), color = STEEL, material = "Metal" },
			{ size = V3(0.25, 0.9, 0.25), offset = V3(0, 2.4, 0.25), color = BRASS, material = "Metal" },
		},
		note = "Stays on or off until you flip it again",
	},
	{
		id = "PressurePlate",
		displayName = "Pressure Plate",
		category = "Decor",
		priceCash = 640,
		gated = true,
		tier = 1,
		footprint = V2(4, 4),
		boxes = {
			{ size = V3(3.6, 0.25, 3.6), offset = V3(0, 0.125, 0), color = ANVIL, material = "Metal" },
			{ size = V3(3.2, 0.2, 3.2), offset = V3(0, 0.35, 0), color = STEEL, material = "Metal" },
			{
				size = V3(0.4, 0.3, 0.4),
				offset = V3(0, 0.55, 0),
				color = GLOW,
				material = "Neon",
				light = true,
			},
		},
		note = "On while a player or a piece of wood rests on it",
	},
	{
		id = "GateAnd",
		displayName = "AND Gate",
		category = "Decor",
		priceCash = 260,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.4, 1, 1.4), offset = V3(0, 0.5, 0), color = IRON, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(-0.45, 1.15, 0.4), color = STEEL, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(0.45, 1.15, 0.4), color = STEEL, material = "Metal" },
			{
				size = V3(0.35, 0.35, 0.35),
				offset = V3(0, 1.2, -0.45),
				color = GLOW,
				material = "Neon",
				light = true,
			},
		},
		note = "On only when both inputs are on",
	},
	{
		id = "GateOr",
		displayName = "OR Gate",
		category = "Decor",
		priceCash = 260,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.4, 1, 1.4), offset = V3(0, 0.5, 0), color = IRON, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(-0.45, 1.15, 0.4), color = BRASS, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(0.45, 1.15, 0.4), color = BRASS, material = "Metal" },
			{
				size = V3(0.35, 0.35, 0.35),
				offset = V3(0, 1.2, -0.45),
				color = GLOW,
				material = "Neon",
				light = true,
			},
		},
		note = "On when either input is on",
	},
	{
		id = "GateXor",
		displayName = "XOR Gate",
		category = "Decor",
		priceCash = 260,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.4, 1, 1.4), offset = V3(0, 0.5, 0), color = IRON, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(-0.45, 1.15, 0.4), color = BRICK, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(0.45, 1.15, 0.4), color = BRICK, material = "Metal" },
			{
				size = V3(0.35, 0.35, 0.35),
				offset = V3(0, 1.2, -0.45),
				color = GLOW,
				material = "Neon",
				light = true,
			},
		},
		note = "On when the inputs disagree",
	},
	{
		id = "GateNot",
		displayName = "NOT Gate",
		category = "Decor",
		priceCash = 200,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.4, 1, 1.4), offset = V3(0, 0.5, 0), color = IRON, material = "Metal" },
			{ size = V3(0.3, 0.3, 0.3), offset = V3(0, 1.15, 0.4), color = STEEL, material = "Metal" },
			{
				size = V3(0.35, 0.35, 0.35),
				offset = V3(0, 1.2, -0.45),
				color = GLOW,
				material = "Neon",
				light = true,
			},
		},
		note = "On when its input is off",
	},
	{
		id = "Delay",
		displayName = "Delay",
		category = "Decor",
		priceCash = 520,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.5, 1.1, 1.2), offset = V3(0, 0.55, 0), color = TIMBER, material = "Wood" },
			{ size = V3(0.9, 0.7, 0.2), offset = V3(0, 0.9, -0.55), color = PAPER, material = "SmoothPlastic" },
			{
				size = V3(0.35, 0.35, 0.35),
				offset = V3(0.55, 1.25, 0),
				color = GLOW,
				material = "Neon",
				light = true,
			},
		},
		note = "Passes a signal through after the time you set",
	},
	{
		id = "Sustain",
		displayName = "Sustain",
		category = "Decor",
		priceCash = 520,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.5, 1.1, 1.2), offset = V3(0, 0.55, 0), color = TIMBER, material = "Wood" },
			{ size = V3(0.9, 0.7, 0.2), offset = V3(0, 0.9, -0.55), color = BRASS, material = "Metal" },
			{
				size = V3(0.35, 0.35, 0.35),
				offset = V3(0.55, 1.25, 0),
				color = GLOW,
				material = "Neon",
				light = true,
			},
		},
		note = "Stays on for the time you set after the signal drops",
	},
	{
		id = "Clock",
		displayName = "Clock",
		category = "Decor",
		priceCash = 902,
		gated = true,
		tier = 1,
		footprint = V2(2, 2),
		boxes = {
			{ size = V3(1.4, 1.4, 0.4), offset = V3(0, 0.9, 0), color = ANVIL, material = "Metal" },
			{ size = V3(0.9, 0.9, 0.15), offset = V3(0, 0.9, -0.25), color = PAPER, material = "SmoothPlastic" },
			{
				size = V3(0.35, 0.35, 0.3),
				offset = V3(0, 1.7, 0),
				color = GLOW,
				material = "Neon",
				light = true,
			},
		},
		note = "Blinks on and off over the period you set",
	},
	{
		id = "GlowWire",
		displayName = "Glow Wire",
		category = "Decor",
		priceCash = 720,
		gated = true,
		tier = 1,
		footprint = V2(4, 2),
		boxes = {
			{
				size = V3(3.4, 0.28, 0.28),
				offset = V3(0, 0.55, 0),
				color = GLOW,
				material = "Neon",
				light = true,
			},
			{ size = V3(0.3, 0.5, 0.3), offset = V3(-1.7, 0.25, 0), color = IRON, material = "Metal" },
			{ size = V3(0.3, 0.5, 0.3), offset = V3(1.7, 0.25, 0), color = IRON, material = "Metal" },
		},
		note = "A wire that lights while its input is on",
	},
	{
		id = "Hatch",
		displayName = "Hatch",
		category = "Decor",
		priceCash = 830,
		gated = true,
		tier = 1,
		footprint = V2(4, 4),
		boxes = {
			{ size = V3(3.8, 0.2, 3.8), offset = V3(0, 0.1, 0), color = TIMBER, material = "Wood" },
			{
				size = V3(3.2, 0.16, 3.2),
				offset = V3(0, 0.28, 0),
				color = BRASS,
				material = "Metal",
				leaf = true,
			},
			{ size = V3(3.4, 0.2, 0.25), offset = V3(0, 0.4, 1.5), color = IRON, material = "Metal" },
		},
		note = "A floor door that opens while it is on",
	},
}

return items
