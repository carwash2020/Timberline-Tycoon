--!strict
-- RegionLogic: the world's named regions, the way Oaklands splits a map
-- (a place you can name, with its own shape, palette and species) without
-- moving Timberline's biomes or the trees saves already point at.
--
-- Biome discs, haul distances and wood prices stay in BiomeData and
-- WoodData. This adds:
--   * a name, a terrain shape and a palette for each place, including the
--     beach, the river banks and two hidden pockets;
--   * single-species stands (StandKind) with a thin band of neighbor
--     species at the borders (limited bleed);
--   * meadows you can walk into, trails, and the points of interest;
--   * which choppable trees should stay in the world around the players
--     (KeepTree). Far ones are parked by RegionWake.
-- Pure. WorldPlan, the filler and BiomeService read it.

local BiomeData = require(script.Parent.BiomeData)
local WorldLayout = require(script.Parent.World.WorldLayout)

local RegionLogic = {}

export type Shape = "plains" | "hills" | "plateau" | "cone" | "hollow" | "beach" | "banks" | "sky"

export type RegionDef = {
	id: string,
	displayName: string,
	-- The toast under the name: shape, palette and what grows there.
	blurb: string,
	shape: Shape,
	palette: string,
	biomeId: string?,
	species: { string }, -- filler kinds that form this place's stands
	bleed: { string }, -- neighbor kinds allowed in the border band
	hidden: boolean?,
	exclusive: string?, -- a wood that grows in this place and nowhere else
}

-- Where a player is, for toasts and for waking a region.
export type Here = {
	id: string, -- attribute value; a meadow appends "/meadow id"
	base: string,
	displayName: string,
	blurb: string,
	shape: Shape,
	palette: string,
	biomeId: string?,
	hidden: boolean,
}

export type Person = { x: number, z: number, y: number }

export type Anchor = {
	id: string,
	name: string,
	kind: string, -- LookoutTower | RuinedCabin | Cave | Crystal | Sign
	region: string,
	x: number,
	z: number,
	search: number,
	secret: string?,
	text: string?,
}

export type Trail = { name: string, ax: number, az: number, bx: number, bz: number }

-- A player keeps every choppable tree inside this radius, plus the whole
-- region they are standing in and any region whose edge they are this
-- close to. Farther trees leave the workspace (RegionWake) so a phone
-- never replicates a region it has not reached. Streaming still caps what
-- is left at StreamingTargetRadius.
RegionLogic.WakeRadius = 300
RegionLogic.WakeMargin = 110
-- The isles stay asleep until someone is up in them.
RegionLogic.SkyWakeY = 480

-- Stands are this wide. One cell is one species; neighbors differ, so a
-- few cells of the same roll read as a grove.
RegionLogic.StandStuds = 84
-- Inside this of a region's edge (and a short way outside it), a stand
-- may grow the neighbor's species instead.
RegionLogic.BleedStuds = 48
RegionLogic.BleedChance = 0.16
-- Past this far outside every region, the old scattered mix stands.
RegionLogic.StandReach = 300

local function areaOf(id: string): BiomeData.BiomeDef?
	return BiomeData.Get(id)
end

local function disc(id: string): (number, number, number)
	local def = areaOf(id)
	local area = if def then def.area else nil
	if area then
		return area.x, area.z, area.radius
	end
	return 1e6, 1e6, 1
end

-- The Petrified Reach: a pocket on the far side of the Gloam Hollow's
-- ridge, away from the gap that faces town. No road. Phantomwood, the
-- same night-only wood as the hollow (WoodData still prices it).
local function reachDisc(): (number, number, number)
	local gx, gz = disc("grove")
	local mill = WorldLayout.Sawmill
	local dx, dz = mill.X - gx, mill.Z - gz
	local len = math.sqrt(dx * dx + dz * dz)
	local dist = WorldLayout.GroveRidge.outer + 78
	if len < 1 then
		return gx, gz - dist, 46
	end
	return gx - dx / len * dist, gz - dz / len * dist, 46
end

local function buildRegions(): { RegionDef }
	local regions: { RegionDef } = {
		{
			id = "starter",
			displayName = "Starter Forest",
			blurb = "flat green plains · oak and birch stands",
			shape = "plains",
			palette = "bright grass",
			biomeId = "starter",
			species = { "broad", "birch" },
			bleed = { "conifer" },
		},
		{
			id = "hills",
			displayName = "The Hills",
			blurb = "rolling hills · pine and maple stands",
			shape = "hills",
			palette = "deep leafy green",
			biomeId = "hills",
			species = { "conifer", "maple" },
			bleed = { "broad", "birch" },
		},
		{
			id = "snow",
			displayName = "Snowfields",
			blurb = "a cold plateau · frostwood, pine along the climb",
			shape = "plateau",
			palette = "snow and ice",
			biomeId = "snow",
			species = { "snowpine", "conifer" },
			bleed = { "birch" },
			exclusive = "frostwood",
		},
		{
			id = "volcano",
			displayName = "The Volcano",
			blurb = "a basalt cone · emberwood on the shelf",
			shape = "cone",
			palette = "basalt and lava",
			biomeId = "volcano",
			species = { "dead", "conifer" },
			bleed = { "snowpine" },
			exclusive = "emberwood",
		},
		{
			id = "grove",
			displayName = "Gloam Hollow",
			blurb = "a hidden hollow · gloamwood, and only at night",
			shape = "hollow",
			palette = "violet mud",
			biomeId = "grove",
			species = { "dead", "conifer" },
			bleed = { "broad" },
			hidden = true,
			exclusive = "phantomwood",
		},
		{
			id = "reach",
			displayName = "The Petrified Reach",
			blurb = "a lost stand of gloamwood, past the ridge",
			shape = "hollow",
			palette = "pale dead wood",
			biomeId = "grove",
			species = { "dead" },
			bleed = { "conifer" },
			hidden = true,
			exclusive = "phantomwood",
		},
		{
			id = "strand",
			displayName = "The Strand",
			blurb = "a pale beach · palms offshore, once you have a boat",
			shape = "beach",
			palette = "sand",
			species = { "broad" },
			bleed = { "birch" },
		},
		{
			id = "banks",
			displayName = "Mirrorwater",
			blurb = "river banks · reeds, no trees in the water",
			shape = "banks",
			palette = "dark water and grass",
			species = { "birch", "broad" },
			bleed = { "conifer" },
		},
		{
			id = "sky",
			displayName = "Aether Isles",
			blurb = "the isles above the Skyroot · lumenwood",
			shape = "sky",
			palette = "cloud and gold",
			biomeId = "sky",
			species = { "broad", "birch" },
			bleed = {},
			exclusive = "lumenwood",
		},
	}
	return regions
end

local REGIONS = buildRegions()
local BY_ID: { [string]: RegionDef } = {}
for _, region in ipairs(REGIONS) do
	BY_ID[region.id] = region
end

-- Centres for the discs BiomeData owns, plus the reach, the sky's floor
-- and the places that aren't discs.
local function centerOf(id: string): (number, number, number, number?)
	if id == "reach" then
		local x, z, r = reachDisc()
		return x, z, r, nil
	end
	local def = areaOf(id)
	local area = if def then def.area else nil
	if area then
		return area.x, area.z, area.radius, area.y
	end
	return 0, 0, 0, nil
end

export type Meadow = { id: string, name: string, blurb: string, region: string, x: number, z: number, radius: number }

local function meadows(): { Meadow }
	local sx, sz = disc("starter")
	local hx, hz = disc("hills")
	return {
		{
			id = "first-clearing",
			name = "The First Clearing",
			blurb = "an oak meadow in the Starter Forest",
			region = "starter",
			x = sx + 8,
			z = sz - 36,
			radius = 26,
		},
		{
			id = "maple-glade",
			name = "The Maple Glade",
			blurb = "a bright stand of maple in the Hills",
			region = "hills",
			x = hx + 36,
			z = hz + 24,
			radius = 34,
		},
	}
end

local MEADOWS = meadows()

function RegionLogic.All(): { RegionDef }
	return REGIONS
end

function RegionLogic.Get(id: string?): RegionDef?
	if not id or id == "" then
		return nil
	end
	local base = string.match(id, "^([^/]+)") or id
	return BY_ID[base]
end

-- "starter/first-clearing" -> "starter". A bare id is itself.
function RegionLogic.Base(id: string?): string
	if not id or id == "" then
		return ""
	end
	return string.match(id, "^([^/]+)") or id
end

local function hash01(ix: number, iz: number): number
	local n = bit32.bxor(bit32.bxor(ix * 374761393, iz * 668265263), 0x9E3779B9)
	n = bit32.bxor(n, bit32.rshift(n, 13))
	n = bit32.bxor(n, bit32.lshift(n, 8))
	-- bit32 results are 0 .. 2^32-1. Fold into 0 .. 1.
	return (n % 1000003) / 1000003
end

local function dist(x: number, z: number, cx: number, cz: number): number
	local dx, dz = x - cx, z - cz
	return math.sqrt(dx * dx + dz * dz)
end

-- Signed distance to a disc's edge: negative inside.
local function edgeDistance(x: number, z: number, id: string): number?
	if id == "strand" or id == "banks" then
		return nil
	end
	local cx, cz, r = centerOf(id)
	if r <= 0 then
		return nil
	end
	return dist(x, z, cx, cz) - r
end

local function inSky(x: number, z: number, y: number?): boolean
	local cx, cz, r, floorY = centerOf("sky")
	if floorY == nil or (y or 0) < floorY - 40 then
		return false
	end
	return dist(x, z, cx, cz) <= r + 20
end

local function inStrand(x: number, z: number): boolean
	local coast = WorldLayout.Coast
	if z > coast.northZ then
		return false
	end
	local inland = coast.shoreX - coast.beachWidth - 36
	return x >= inland and x <= coast.shoreX + 30
end

local function inBanks(x: number, z: number): boolean
	local river = WorldLayout.River
	local d = WorldLayout.PolylineDistance(Vector2.new(x, z), river.points)
	local band = river.width / 2 + 22
	if d < river.width / 2 - 2 then
		return false -- in the water itself: not a place you stand
	end
	return d <= band
end

local DISC_IDS = { "reach", "grove", "starter", "hills", "snow", "volcano" }

local function discAt(x: number, z: number, y: number?): RegionDef?
	if inSky(x, z, y) then
		return BY_ID.sky
	end
	-- The reach is tested before the hollow so its pocket wins on the
	-- ridge's far side (the discs don't overlap; the order is the rule).
	for _, id in ipairs(DISC_IDS) do
		local cx, cz, r = centerOf(id)
		if dist(x, z, cx, cz) <= r then
			return BY_ID[id]
		end
	end
	return nil
end

local function meadowAt(x: number, z: number, regionId: string): Meadow?
	for _, meadow in ipairs(MEADOWS) do
		if meadow.region == regionId and dist(x, z, meadow.x, meadow.z) <= meadow.radius then
			return meadow
		end
	end
	return nil
end

local function hereFrom(region: RegionDef, meadow: Meadow?): Here
	if meadow then
		return {
			id = region.id .. "/" .. meadow.id,
			base = region.id,
			displayName = meadow.name,
			blurb = meadow.blurb,
			shape = region.shape,
			palette = region.palette,
			biomeId = region.biomeId,
			hidden = region.hidden == true,
		}
	end
	return {
		id = region.id,
		base = region.id,
		displayName = region.displayName,
		blurb = region.blurb,
		shape = region.shape,
		palette = region.palette,
		biomeId = region.biomeId,
		hidden = region.hidden == true,
	}
end

-- The named place at (x, z), or nil out in the open country between them.
-- `y` matters for the isles: the ground under them is not the sky.
function RegionLogic.At(x: number, z: number, y: number?): Here?
	local region = discAt(x, z, y)
	if not region and inStrand(x, z) then
		region = BY_ID.strand
	end
	if not region and inBanks(x, z) then
		region = BY_ID.banks
	end
	if not region then
		return nil
	end
	return hereFrom(region, meadowAt(x, z, region.id))
end

-- The toast when you enter `id` (the attribute RegionLogic.At().id).
function RegionLogic.Toast(id: string?): string?
	if not id or id == "" then
		return nil
	end
	local region = RegionLogic.Get(id)
	if not region then
		return nil
	end
	local meadowId = string.match(id, "/(.+)$")
	if meadowId then
		for _, meadow in ipairs(MEADOWS) do
			if meadow.id == meadowId then
				return meadow.name .. " — " .. meadow.blurb
			end
		end
	end
	return region.displayName .. " — " .. region.blurb
end

local function cellSpecies(region: RegionDef, x: number, z: number): string
	local list = region.species
	local studs = RegionLogic.StandStuds
	local ix = math.floor(x / studs)
	local iz = math.floor(z / studs)
	local i = math.floor(hash01(ix, iz) * #list) + 1
	return list[math.clamp(i, 1, #list)]
end

-- The filler kind that grows at (x, z): one species per stand, with a
-- neighbor's species now and then inside the border band. nil far from
-- every region (the caller keeps its old mix).
function RegionLogic.StandKind(x: number, z: number): string?
	local best: RegionDef? = nil
	local bestD = math.huge
	local second: RegionDef? = nil
	local secondD = math.huge
	for _, id in ipairs(DISC_IDS) do
		local d = edgeDistance(x, z, id)
		if d then
			local region = BY_ID[id]
			if d < bestD then
				second, secondD = best, bestD
				best, bestD = region, d
			elseif d < secondD then
				second, secondD = region, d
			end
		end
	end
	if not best or bestD > RegionLogic.StandReach then
		return nil
	end
	local species = cellSpecies(best, x, z)
	local border = bestD > -RegionLogic.BleedStuds
	if border and second and secondD < RegionLogic.BleedStuds + 80 and #best.bleed > 0 then
		local ix = math.floor(x / RegionLogic.StandStuds)
		local iz = math.floor(z / RegionLogic.StandStuds)
		if hash01(ix + 17, iz - 11) < RegionLogic.BleedChance then
			local list = best.bleed
			local i = math.floor(hash01(ix - 3, iz + 5) * #list) + 1
			species = list[math.clamp(i, 1, #list)]
		end
	end
	return species
end

-- True when `kind` is one this region grows on purpose (its stands or the
-- thin bleed). Used by tests; the filler asks StandKind.
function RegionLogic.Allows(regionId: string, kind: string): boolean
	local region = BY_ID[regionId]
	if not region then
		return false
	end
	return table.find(region.species, kind) ~= nil or table.find(region.bleed, kind) ~= nil
end

function RegionLogic.Meadows(): { Meadow }
	return MEADOWS
end

-- Where to look for a point of interest. WorldPlan nudges each one onto
-- dry, open ground; these are the centres of that search.
function RegionLogic.Anchors(): { Anchor }
	local sx, sz = disc("starter")
	local hx, hz = disc("hills")
	local vx, vz = disc("volcano")
	local rx, rz = reachDisc()
	local river = WorldLayout.River.points[1]
	return {
		{
			id = "lookout",
			name = "South Lookout",
			kind = "LookoutTower",
			region = "starter",
			-- Just south of the starter disc, in the gap before the forest ring.
			x = sx + 18,
			z = sz - 108,
			search = 36,
			secret = "The railing hides a tin of nails. Murph's, if the rust is his.",
			text = "SOUTH LOOKOUT",
		},
		{
			id = "cabin",
			name = "Old Ranger Cabin",
			kind = "RuinedCabin",
			region = "hills",
			-- North of the Hills' centre, off the haul road.
			x = hx,
			z = hz + 150,
			search = 48,
			secret = "A board inside the chimney is carved: 'the ridge hides a second grove'.",
			text = "RANGER CABIN",
		},
		{
			id = "cave",
			name = "Cinder Cave",
			kind = "Cave",
			region = "volcano",
			x = vx - 90,
			z = vz - 70,
			search = 50,
			secret = "The back of the cave holds one warm crystal. It isn't for sale.",
			text = "CINDER CAVE",
		},
		{
			id = "cache",
			name = "The Pale Cache",
			kind = "Crystal",
			region = "reach",
			x = rx,
			z = rz,
			search = 24,
			secret = "Crystals ring a stump that was a tree before the ridge rose.",
			text = "PALE CACHE",
		},
		{
			id = "falls",
			name = "Skyroot Falls",
			kind = "Sign",
			region = "sky",
			x = river.X + 18,
			z = river.Y - 16,
			search = 30,
			text = "SKYROOT FALLS",
		},
	}
end

function RegionLogic.ReachCenter(): (number, number, number)
	return reachDisc()
end

-- Footpaths. WorldPlan drops any step that lands on a road, the town, the
-- plots or the water; what remains is a trail of worn slabs.
function RegionLogic.Trails(): { Trail }
	local sx, sz = disc("starter")
	local pond = WorldLayout.Pond
	local rx, rz = reachDisc()
	local gx, gz = disc("grove")
	local hx, hz = disc("hills")
	return {
		{
			name = "PondPath",
			ax = sx + 70,
			az = sz - 20,
			bx = pond.x - 8,
			bz = pond.z + 10,
		},
		{
			name = "RidgePath",
			ax = gx - 40,
			az = gz - 20,
			bx = rx,
			bz = rz + 20,
		},
		{
			name = "GladePath",
			ax = hx + 80,
			az = hz - 20,
			bx = hx + 36,
			bz = hz + 24,
		},
	}
end

-- A player at `people` should have the choppable tree at (x, z) in the
-- world. `region` is the tree's Region attribute (a biome id, "wild",
-- "reach" or "sky"). No people: keep it (an empty server, a test).
function RegionLogic.KeepTree(region: string?, x: number, z: number, y: number, people: { Person }): boolean
	if #people == 0 then
		return true
	end
	local base = RegionLogic.Base(region)
	if base == "sky" or y > RegionLogic.SkyWakeY - 40 then
		for _, person in ipairs(people) do
			if person.y >= RegionLogic.SkyWakeY then
				return true
			end
		end
		return false
	end
	local radius = RegionLogic.WakeRadius
	local margin = RegionLogic.WakeMargin
	for _, person in ipairs(people) do
		local dx, dz = x - person.x, z - person.z
		if dx * dx + dz * dz <= radius * radius then
			return true
		end
		local here = RegionLogic.At(person.x, person.z, person.y)
		if here and here.base == base and base ~= "" and base ~= "wild" then
			return true
		end
		if base ~= "" and base ~= "wild" and base ~= "strand" and base ~= "banks" then
			local d = edgeDistance(x, z, base)
			-- The tree's own region: wake the whole disc once someone is
			-- near its edge, so the forest is there before the road enters.
			if d then
				local cx, cz, r = centerOf(base)
				local outside = dist(person.x, person.z, cx, cz) - r
				if outside < margin then
					return true
				end
			end
		end
	end
	return false
end

return RegionLogic
