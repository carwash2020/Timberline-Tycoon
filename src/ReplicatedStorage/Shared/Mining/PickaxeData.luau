--!strict
-- PickaxeData: the pick ladder, plus the Lux Pickaxe. The Lux entry is a
-- stub (passId 0). Nothing here is a store row, and nothing is for sale
-- in Robux until Connor says so.

local PickaxeData = {}

export type Pick = {
	id: string,
	name: string,
	level: number,
	price: number, -- cash; 0 for the free rusty pick and the unpriced Lux stub
	speed: number, -- swing speed multiplier
	free: boolean?,
	needsHeartstone: boolean?,
	passId: number?,
	passKey: string?,
	robux: boolean?,
	forSale: boolean?,
}

local LIST: { Pick } = {
	{ id = "RustyPick", name = "Rusty Pick", level = 1, price = 0, speed = 1.0, free = true },
	{ id = "CopperPick", name = "Copper Pick", level = 2, price = 450, speed = 1.1 },
	{ id = "IronPick", name = "Iron Pick", level = 3, price = 3000, speed = 1.2 },
	{ id = "SteelPick", name = "Steel Pick", level = 4, price = 14000, speed = 1.35 },
	{
		id = "ObsidianPick",
		name = "Obsidian Pick",
		level = 5,
		price = 50000,
		speed = 1.5,
		needsHeartstone = true,
	},
	{
		id = "LuxPickaxe",
		name = "Lux Pickaxe",
		level = 4,
		price = 0,
		speed = 1.45,
		passId = 0,
		passKey = "LuxPickaxe",
		robux = true,
		forSale = false,
	},
}

local BY_ID: { [string]: Pick } = {}
for _, pick in ipairs(LIST) do
	BY_ID[pick.id] = pick
end

PickaxeData.LuxId = "LuxPickaxe"
PickaxeData.LuxPassKey = "LuxPickaxe"
-- Same attribute name ShopService uses for OwnedGear: the server writes it,
-- the hover tag reads it. It is the best owned pick level, not the equipped one.
PickaxeData.LevelAttribute = "PickLevel"

function PickaxeData.All(): { Pick }
	return LIST
end

function PickaxeData.Get(id: string): Pick?
	return BY_ID[id]
end

function PickaxeData.Known(id: string): boolean
	return BY_ID[id] ~= nil
end

-- The free pick of this level (the Lux Pickaxe is a side-grade, not the
-- named requirement on a rock).
function PickaxeData.ForLevel(level: number): Pick?
	local found: Pick? = nil
	for _, pick in ipairs(LIST) do
		if pick.level == level and pick.robux ~= true then
			found = pick
		end
	end
	return found
end

function PickaxeData.NameForLevel(level: number): string
	local pick = PickaxeData.ForLevel(level)
	if pick then
		return pick.name
	end
	return "Rusty Pick"
end

-- Cash picks a prospector sells, rusty first. The Lux Pickaxe is not here.
function PickaxeData.Shop(): { Pick }
	local out: { Pick } = {}
	for _, pick in ipairs(LIST) do
		if pick.robux ~= true then
			table.insert(out, pick)
		end
	end
	return out
end

return PickaxeData
