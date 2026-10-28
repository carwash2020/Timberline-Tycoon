--!strict
-- ShopPins (T412): the one live list of shop pins. WorldPlan outlets and
-- WorldLayout floors read this table. WorldPlanDraft.Shops stays the approved
-- picture; tests/T412Shops.spec asserts these numbers match it.
--
-- `x`,`z` is the locked pin (a door, when the building sits back from it).
-- `ox`,`oz` is the model origin MapBuilder places. `y` is set only for the
-- cloud decks; ground shops take HeightAt, and never sit under the sea.

local ShopPins = {}

export type Pin = {
	id: string,
	draftId: string,
	title: string,
	x: number,
	z: number,
	y: number?,
	yaw: number,
	ox: number,
	oz: number,
	sells: boolean,
	ferry: boolean,
	cloud: boolean,
	kiosk: boolean,
	full: boolean,
	preload: boolean,
	hero: string,
	line: string,
}

local function xz(x: number, z: number): { x: number, z: number }
	return { x = x, z = z }
end

-- A point `studs` to the left of segment a -> b, at b. Same rule as the draft.
local function beside(a: { x: number, z: number }, b: { x: number, z: number }, studs: number): { x: number, z: number }
	local dx, dz = b.x - a.x, b.z - a.z
	local len = math.sqrt(dx * dx + dz * dz)
	return xz(b.x + (-dz / len) * studs, b.z + (dx / len) * studs)
end

-- Yaw whose front (-Z) points from (x, z) toward (tx, tz).
local function yawToward(x: number, z: number, tx: number, tz: number): number
	local dx, dz = tx - x, tz - z
	local len = math.sqrt(dx * dx + dz * dz)
	return math.atan2(-dx / len, -dz / len)
end

local SHOULDER = 28
local frostFoot = xz(-178, 691)
local frostPeak = xz(-340, 1000)
local calderaRest = xz(700, 700)
local calderaCone = xz(700, 900)
local coatAt = beside(frostPeak, frostFoot, SHOULDER)
local heatAt = beside(calderaCone, calderaRest, SHOULDER)
local CLOUD_Y = (800 + 880) / 2

local function pin(
	id: string,
	draftId: string,
	title: string,
	x: number,
	z: number,
	yaw: number,
	ox: number,
	oz: number,
	fields: {
		y: number?,
		sells: boolean?,
		ferry: boolean?,
		cloud: boolean?,
		kiosk: boolean?,
		full: boolean?,
		preload: boolean?,
		hero: string,
		line: string,
	}
): Pin
	return {
		id = id,
		draftId = draftId,
		title = title,
		x = x,
		z = z,
		y = fields.y,
		yaw = yaw,
		ox = ox,
		oz = oz,
		sells = fields.sells == true,
		ferry = fields.ferry == true,
		cloud = fields.cloud == true,
		kiosk = fields.kiosk == true,
		full = fields.full == true,
		preload = fields.preload == true,
		hero = fields.hero,
		line = fields.line,
	}
end

local LIST: { Pin } = {
	pin("ToolShed", "ToolShed", "TOOL SHED", -84, 117.7, 0, -84, 117.7, {
		sells = true,
		full = true,
		preload = true,
		hero = "top axe",
		line = "Axes and mill tools.",
	}),
	pin("HearthAndHome", "GeneralStore", "GENERAL STORE", -100, 187.5, 0, -100, 187.5, {
		sells = true,
		full = true,
		preload = true,
		hero = "coat and boots mannequin",
		line = "Food, lamps, and basic gear. Not the gate coat, boots, or lantern.",
	}),
	pin("WeighHouse", "WeighHouse", "WEIGH HOUSE", 53, 111, 0, 53, 111, {
		preload = true,
		hero = "scale",
		line = "Millie buys logs. Not moved.",
	}),
	pin("LandOffice", "LandOffice", "LAND OFFICE", 153.5, 100, 0, 153.5, 109, {
		full = true,
		preload = true,
		hero = "plot map",
		line = "Old Hank sells plots. Look only; not a shop id.",
	}),
	pin("Dealership", "Dealership", "DEALERSHIP", 189.25, 100.3, 0, 189.25, 100.3, {
		sells = true,
		full = true,
		preload = true,
		hero = "truck on the lot",
		line = "Trucks and trailers. The door stays on the east bank.",
	}),
	pin(
		"CoatKiosk",
		"CoatKiosk",
		"COAT KIOSK",
		coatAt.x,
		coatAt.z,
		yawToward(coatAt.x, coatAt.z, frostFoot.x, frostFoot.z),
		coatAt.x,
		coatAt.z,
		{
			sells = true,
			kiosk = true,
			hero = "insulated coat",
			line = "Insulated Coat, at the Frost Road foot.",
		}
	),
	pin(
		"HeatBoots",
		"HeatBoots",
		"HEAT BOOTS",
		heatAt.x,
		heatAt.z,
		yawToward(heatAt.x, heatAt.z, calderaRest.x, calderaRest.z),
		heatAt.x,
		heatAt.z,
		{
			sells = true,
			kiosk = true,
			hero = "heat boots",
			line = "Heat Boots, at the Caldera rest.",
		}
	),
	pin("OddsAndEnds", "OddsAndEnds", "ODDS AND ENDS", -460, -300, 0, -460, -292, {
		sells = true,
		full = true,
		hero = "lantern and charges",
		line = "Blasting charges and the Lantern, at the Pine/Gloam crossroads.",
	}),
	pin("Sparkworks", "Sparkworks", "SPARKWORKS", 1115, -700, 0, 1115, -700, {
		sells = true,
		ferry = true,
		full = true,
		hero = "coil",
		line = "Logic and machines. Shut until the ferry (T413).",
	}),
	pin("SkyForge", "SkyForge", "SKY FORGE", -32, 818, 0, -32, 818, {
		y = CLOUD_Y,
		cloud = true,
		hero = "anvil",
		line = "The forge court. Clouds only. No live sales.",
	}),
	pin("SkyMarket", "SkyMarket", "SKY MARKET", -90, 784, 0, -90, 784, {
		y = CLOUD_Y,
		cloud = true,
		hero = "sky relic",
		line = "Relics. Clouds only. No live sales.",
	}),
	pin("SecretShop", "SecretShop", "SECRET SHOP", -543, -479, 0, -543, -479, {
		full = true,
		hero = "painting easel",
		line = "Nothing yet. Cave stub, sold = false.",
	}),
	pin("BaitShack", "BaitShack", "BAIT SHACK", -720, -660, 0, -720, -660, {
		hero = "waders",
		line = "Waders. Not moved.",
	}),
}

local BY_ID: { [string]: Pin } = {}
local BY_DRAFT: { [string]: Pin } = {}
for _, row in ipairs(LIST) do
	BY_ID[row.id] = row
	BY_DRAFT[row.draftId] = row
end

function ShopPins.All(): { Pin }
	return LIST
end

function ShopPins.Get(id: string): Pin?
	return BY_ID[id]
end

function ShopPins.ByDraft(draftId: string): Pin?
	return BY_DRAFT[draftId]
end

-- Ground pads derived from the pins. Cloud decks are not floors.
function ShopPins.Floors(): { { name: string, x0: number, x1: number, z0: number, z1: number, material: string } }
	local function box(name: string, cx: number, cz: number, hx: number, hz: number)
		return {
			name = name,
			x0 = cx - hx,
			x1 = cx + hx,
			z0 = cz - hz,
			z1 = cz + hz,
			material = "Ground",
		}
	end
	return {
		box("SparkworksFloor", 1115, -700, 24, 24),
		box("CoatKioskFloor", coatAt.x, coatAt.z, 6, 6),
		box("HeatBootsFloor", heatAt.x, heatAt.z, 6, 6),
		box("OddsAndEndsFloor", -460, -292, 12, 10),
		box("SecretShopFloor", -543, -479, 10, 8),
		-- East edge stays 1.5 off the dealership loading pad (x 160).
		box("LandOfficeFloor", 151, 109, 6, 8),
	}
end

return ShopPins
