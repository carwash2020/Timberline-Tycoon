--!strict
-- BadgeData: the badges a player can earn (the StoreData pattern).
--
-- Paste ids in Ids only. 0 means "not awarded": AwardBadge is never called
-- for that badge, and nothing errors. Never invent an id.
--   Creator Hub → your experience → Engagement → Badges → Create → ID
--
-- Lanternwood is the night-glow wood, its own id ("lanternwood"). It is
-- not lumenwood. Ferry Island is not built yet: its id stays 0. The Secret
-- Cave is built (the Petrified Reach disc); its id stays 0 until pasted. The North Strip trigger is built; its id stays 0 until the
-- dashboard has one, and AreasAt still records the visit.
--
-- Lane X (V1 extras) added eight: the Bayou and Red Mesa (WorldLayout's
-- reserved discs, so they work before Lane R fills them), Bog Cypress and
-- Ironwood logs, the three build badges (a kit piece fully filled; 40 of
-- them; a sandstone one) and a million earned. Creator Hub allows five new
-- badges a day for free, so the first five of the eight (AreaBayou to
-- FirstBuild) are the ones to create first.

local RegionLogic = require(script.Parent.RegionLogic)
local WorldLayout = require(script.Parent.World.WorldLayout)

local BadgeData = {}

export type Group = "milestone" | "area" | "wood"

export type BadgeDef = {
	key: string,
	name: string,
	detail: string,
	group: Group,
	woodId: string?,
	visit: string?, -- areasVisited key, set when this area badge is earned
}

export type Row = {
	key: string,
	name: string,
	detail: string,
	group: Group,
	unlocked: boolean,
	status: string,
}

-- What MilestoneService.Event passes. Fields are optional; unknown kinds
-- award nothing.
export type Hook = {
	name: string?,
	woodId: string?,
	id: string?,
	count: number?, -- "build": filled kit pieces on the plot, this one included. "earned": lifetime earnings.
}

-- The only place a Creator Hub badge id is written. Fill these in when the
-- badge exists; leave 0 until then. 0 = do not call AwardBadge.
BadgeData.Ids = {
	FirstSale = 0, -- PASTE: Engagement → Badges → First Sale → ID
	FirstTruck = 0, -- PASTE: Engagement → Badges → First Truck → ID
	FirstPlank = 0, -- PASTE: Engagement → Badges → First Plank → ID
	AreaStarter = 0, -- PASTE: Engagement → Badges → Starter Forest → ID
	AreaHills = 0, -- PASTE: Engagement → Badges → The Hills → ID
	AreaSnow = 0, -- PASTE: Engagement → Badges → Snowfields → ID
	AreaVolcano = 0, -- PASTE: Engagement → Badges → The Volcano → ID
	AreaGrove = 0, -- PASTE: Engagement → Badges → Gloam Hollow → ID
	AreaSky = 0, -- PASTE: Engagement → Badges → Aether Isles → ID
	-- Leave these at 0 until the dashboard has the badge. Awarding skips 0.
	AreaFerry = 0, -- PASTE: Engagement → Badges → Ferry Island → ID
	AreaCave = 0, -- PASTE: Engagement → Badges → Secret Cave → ID
	AreaToll = 0, -- PASTE: Engagement → Badges → North Strip → ID
	WoodFrostwood = 0, -- PASTE: Engagement → Badges → Frostwood → ID
	WoodEmberwood = 0, -- PASTE: Engagement → Badges → Emberwood → ID
	WoodGloamwood = 0, -- PASTE: Engagement → Badges → Gloamwood → ID
	WoodLumenwood = 0, -- PASTE: Engagement → Badges → Lumenwood → ID
	WoodLanternwood = 0, -- PASTE: Engagement → Badges → Lanternwood → ID
	-- Lane X. Create these in this order (five free a day).
	AreaBayou = 0, -- PASTE: Engagement → Badges → The Bayou → ID
	AreaMesa = 0, -- PASTE: Engagement → Badges → Red Mesa → ID
	WoodCypress = 0, -- PASTE: Engagement → Badges → Bog Cypress → ID
	WoodIronwood = 0, -- PASTE: Engagement → Badges → Ironwood → ID
	FirstBuild = 0, -- PASTE: Engagement → Badges → First Build → ID
	Homestead = 0, -- PASTE: Engagement → Badges → Homestead → ID
	Stonemason = 0, -- PASTE: Engagement → Badges → Stonemason → ID
	Millionaire = 0, -- PASTE: Engagement → Badges → Millionaire → ID
} :: { [string]: number }

-- Thresholds (PROPOSALS, Connor decides): filled kit pieces for Homestead,
-- and lifetime earnings (profile.totalEarned) for Millionaire.
BadgeData.HomesteadPieces = 40
BadgeData.MillionaireEarned = 1000000
-- A kit piece whose blueprint id starts with this is sandstone (Stonemason).
BadgeData.SandstonePrefix = "Sand"

-- Places that are not in the world yet. AreasAt skips every key here, so
-- standing there earns nothing. Their ids stay 0.
-- A key leaves NotBuilt when its trigger is built. The North Strip box
-- (x -400..400, z 1586..1900, not the booth or the bridge deck), the Ferry
-- Island disc (reached by Cap'n Moss's ferry, FerryService) and the Secret
-- Cave (standing in the Petrified Reach disc, RegionLogic.ReachCenter,
-- radius 46, which holds the cave room) are all built.
BadgeData.NotBuilt = {}

-- A phone tap target (InputKit.MinTouchPx). BadgeUI rows and the open
-- button are at least this tall.
BadgeData.MinTapPx = 44

-- Menu binds. Not ButtonX and not keyboard E (those are world prompts).
-- Close on a gamepad is ButtonB, which HUD.Popup already binds. A gamepad
-- has no bind of its own for Badges any more: the View button opens the
-- quick menu (QuickMenuLogic.OpenGamepad) and Badges is one of its tiles.
BadgeData.OpenKeyboard = Enum.KeyCode.B
BadgeData.CloseKeyboard = Enum.KeyCode.Escape

local ALL: { BadgeDef } = {
	{
		key = "FirstSale",
		name = "First Sale",
		detail = "Sell wood for the first time.",
		group = "milestone",
	},
	{
		key = "FirstTruck",
		name = "First Truck",
		detail = "Buy your first truck.",
		group = "milestone",
	},
	{
		key = "FirstPlank",
		name = "First Plank",
		detail = "Mill a log into a plank.",
		group = "milestone",
	},
	{
		key = "AreaStarter",
		name = "Starter Forest",
		detail = "Walk into the Starter Forest.",
		group = "area",
		visit = "starter",
	},
	{
		key = "AreaHills",
		name = "The Hills",
		detail = "Walk into the Hills.",
		group = "area",
		visit = "hills",
	},
	{
		key = "AreaSnow",
		name = "Snowfields",
		detail = "Walk into the Snowfields.",
		group = "area",
		visit = "snow",
	},
	{
		key = "AreaVolcano",
		name = "The Volcano",
		detail = "Walk into the Volcano.",
		group = "area",
		visit = "volcano",
	},
	{
		key = "AreaGrove",
		name = "Gloam Hollow",
		detail = "Walk into Gloam Hollow.",
		group = "area",
		visit = "grove",
	},
	{
		key = "AreaSky",
		name = "Aether Isles",
		detail = "Reach the Aether Isles.",
		group = "area",
		visit = "sky",
	},
	{
		key = "AreaFerry",
		name = "Ferry Island",
		detail = "Step onto Ferry Island.",
		group = "area",
		visit = "ferry",
	},
	{
		key = "AreaCave",
		name = "Secret Cave",
		detail = "Find the secret cave, past Gloam Hollow.",
		group = "area",
		visit = "cave",
	},
	{
		key = "AreaToll",
		name = "North Strip",
		detail = "Cross Old Tolly's bridge into the North Strip.",
		group = "area",
		visit = "toll",
	},
	{
		key = "WoodFrostwood",
		name = "Frostwood",
		detail = "Cut or sell frostwood.",
		group = "wood",
		woodId = "frostwood",
	},
	{
		key = "WoodEmberwood",
		name = "Emberwood",
		detail = "Cut or sell emberwood.",
		group = "wood",
		woodId = "emberwood",
	},
	{
		key = "WoodGloamwood",
		name = "Gloamwood",
		detail = "Cut or sell gloamwood.",
		group = "wood",
		woodId = "phantomwood",
	},
	{
		key = "WoodLumenwood",
		name = "Lumenwood",
		detail = "Cut or sell lumenwood.",
		group = "wood",
		woodId = "lumenwood",
	},
	{
		key = "WoodLanternwood",
		name = "Lanternwood",
		detail = "Cut or sell Lanternwood. It grows on Ferry Island after dark.",
		group = "wood",
		woodId = "lanternwood",
	},
	{
		key = "AreaBayou",
		name = "The Bayou",
		detail = "Wade into the Bayou.",
		group = "area",
		visit = "bayou",
	},
	{
		key = "AreaMesa",
		name = "Red Mesa",
		detail = "Climb onto Red Mesa.",
		group = "area",
		visit = "redmesa",
	},
	{
		key = "WoodCypress",
		name = "Bog Cypress",
		detail = "Cut or sell Bog Cypress.",
		group = "wood",
		woodId = "bogcypress",
	},
	{
		key = "WoodIronwood",
		name = "Ironwood",
		detail = "Cut or sell Ironwood.",
		group = "wood",
		woodId = "ironwood",
	},
	{
		key = "FirstBuild",
		name = "First Build",
		detail = "Finish your first kit piece on your plot.",
		group = "milestone",
	},
	{
		key = "Homestead",
		name = "Homestead",
		detail = "Finish 40 kit pieces on your plot.",
		group = "milestone",
	},
	{
		key = "Stonemason",
		name = "Stonemason",
		detail = "Finish a sandstone piece.",
		group = "milestone",
	},
	{
		key = "Millionaire",
		name = "Millionaire",
		detail = "Earn $1,000,000 in total.",
		group = "milestone",
	},
}

local BY_KEY: { [string]: BadgeDef } = {}
for _, def in ipairs(ALL) do
	BY_KEY[def.key] = def
end

-- MilestoneService.Mark names that earn a badge. Other mark names do not.
local MARK_BADGE: { [string]: string } = {
	["First sale"] = "FirstSale",
	["Bought a truck"] = "FirstTruck",
}

-- RegionLogic base id (and a few names that aren't discs) -> badge key.
local REGION_BADGE: { [string]: string } = {
	starter = "AreaStarter",
	hills = "AreaHills",
	snow = "AreaSnow",
	volcano = "AreaVolcano",
	grove = "AreaGrove",
	sky = "AreaSky",
	ferry = "AreaFerry",
	island = "AreaFerry",
	bayou = "AreaBayou",
	mesa = "AreaMesa",
	redmesa = "AreaMesa",
	cave = "AreaCave",
	toll = "AreaToll",
}

function BadgeData.All(): { BadgeDef }
	return ALL
end

function BadgeData.Get(key: string): BadgeDef?
	return BY_KEY[key]
end

-- The Creator Hub id for `key`, or 0 when it was never pasted.
function BadgeData.RobloxId(key: string): number
	local id = BadgeData.Ids[key]
	if type(id) ~= "number" then
		return 0
	end
	return id
end

-- True when `id` is a real badge id. 0 (and anything that isn't a positive
-- whole id) is not awarded: skip AwardBadge, don't error.
function BadgeData.IsLive(id: number): boolean
	return type(id) == "number" and id > 0 and id == math.floor(id) and id < 1e15
end

function BadgeData.ForMark(name: string): string?
	return MARK_BADGE[name]
end

function BadgeData.ForWood(woodId: string): { string }
	local keys: { string } = {}
	for _, def in ipairs(ALL) do
		if def.woodId == woodId then
			table.insert(keys, def.key)
		end
	end
	return keys
end

-- Build badges for a kit piece that just filled: `id` is its blueprint id,
-- `count` the filled kit pieces on the plot, that one included.
function BadgeData.BuildKeys(id: unknown, count: unknown): { string }
	local keys: { string } = {}
	if type(count) == "number" and count >= 1 then
		table.insert(keys, "FirstBuild")
		if count >= BadgeData.HomesteadPieces then
			table.insert(keys, "Homestead")
		end
	end
	local prefix = BadgeData.SandstonePrefix
	if type(id) == "string" and string.sub(id, 1, #prefix) == prefix then
		table.insert(keys, "Stonemason")
	end
	return keys
end

-- Badge keys for a MilestoneService.Event. Unknown kinds award nothing.
function BadgeData.KeysFor(kind: string, data: Hook?): { string }
	if kind == "mark" then
		local name = if data then data.name else nil
		local key = if type(name) == "string" then MARK_BADGE[name] else nil
		return if key then { key } else {}
	elseif kind == "sale" then
		return { "FirstSale" }
	elseif kind == "truck" then
		return { "FirstTruck" }
	elseif kind == "plank" then
		return { "FirstPlank" }
	elseif kind == "wood" then
		local woodId = if data then data.woodId else nil
		return if type(woodId) == "string" then BadgeData.ForWood(woodId) else {}
	elseif kind == "build" then
		return BadgeData.BuildKeys(if data then data.id else nil, if data then data.count else nil)
	elseif kind == "earned" then
		local total = if data then data.count else nil
		return if type(total) == "number" and total >= BadgeData.MillionaireEarned then { "Millionaire" } else {}
	elseif kind == "area" then
		local id = if data then data.id else nil
		if type(id) ~= "string" then
			return {}
		end
		local direct = BY_KEY[id]
		if direct and direct.group == "area" then
			return { id }
		end
		local key = REGION_BADGE[id]
		return if key then { key } else {}
	end
	return {}
end

local function inside(x: number, z: number, cx: number, cz: number, radius: number): boolean
	local dx, dz = x - cx, z - cz
	return dx * dx + dz * dz <= radius * radius
end

-- Area badges for a world position (x, y, z). Region discs come from
-- RegionLogic. Ferry Island is the offshore island. The secret cave is the
-- reach past Gloam Hollow, not the cave on the Volcano. Keys in NotBuilt
-- are skipped until W2 or W3 removes them.
function BadgeData.AreasAt(x: number, y: number, z: number): { string }
	local keys: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(key: string?)
		if key and not seen[key] and table.find(BadgeData.NotBuilt, key) == nil then
			seen[key] = true
			table.insert(keys, key)
		end
	end
	local here = RegionLogic.At(x, z, y)
	if here then
		add(REGION_BADGE[here.base])
	end
	local island = WorldLayout.Island
	if inside(x, z, island.x, island.z, island.radius) then
		add("AreaFerry")
	end
	-- The Bayou and Red Mesa discs are WorldLayout's reserved regions: they
	-- count before Lane R's own region ids exist (REGION_BADGE has those too).
	local bayou, mesa = WorldLayout.Bayou, WorldLayout.RedMesa
	if inside(x, z, bayou.x, bayou.z, bayou.radius) then
		add("AreaBayou")
	end
	if inside(x, z, mesa.x, mesa.z, mesa.radius) then
		add("AreaMesa")
	end
	local rx, rz, rr = RegionLogic.ReachCenter()
	if inside(x, z, rx, rz, rr) then
		add("AreaCave")
	end
	if WorldLayout.InTollBadge(x, z) then
		add("AreaToll")
	end
	return keys
end

-- "FirstSale,AreaSnow" for the badges already earned. Unknown keys drop out.
function BadgeData.Encode(awarded: { [string]: boolean }?): string
	local ids: { string } = {}
	if type(awarded) == "table" then
		for key, on in pairs(awarded) do
			if on == true and BY_KEY[key] ~= nil then
				table.insert(ids, key)
			end
		end
	end
	table.sort(ids)
	return table.concat(ids, ",")
end

function BadgeData.Decode(payload: unknown): { [string]: boolean }
	local set: { [string]: boolean } = {}
	if type(payload) ~= "string" then
		return set
	end
	for key in string.gmatch(payload, "[%w]+") do
		if BY_KEY[key] ~= nil then
			set[key] = true
		end
	end
	return set
end

-- Every badge, locked or earned, in list order. Read-only: status is a label.
function BadgeData.Rows(awarded: { [string]: boolean }?): { Row }
	local have = if type(awarded) == "table" then awarded else {}
	local rows: { Row } = {}
	for _, def in ipairs(ALL) do
		local on = have[def.key] == true
		table.insert(rows, {
			key = def.key,
			name = def.name,
			detail = def.detail,
			group = def.group,
			unlocked = on,
			status = if on then "Earned" else "Locked",
		})
	end
	return rows
end

function BadgeData.Count(awarded: { [string]: boolean }?): (number, number)
	local n = 0
	local rows = BadgeData.Rows(awarded)
	for _, row in ipairs(rows) do
		if row.unlocked then
			n += 1
		end
	end
	return n, #rows
end

return BadgeData
