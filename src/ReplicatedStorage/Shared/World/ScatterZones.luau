--!strict
-- ScatterZones: where ambient life may stand. Lane G reads Zones and
-- Blocked. Kind "cave" is the ground over the mine. Blocked is true on
-- roads, pads, water, the spawn lane, tunnel floors and cave paths.

local WorldLayout = require(script.Parent.WorldLayout)
local UndergroundData = require(script.Parent.UndergroundData)

local ScatterZones = {}

export type Kind = "meadow" | "forest" | "shore" | "snow" | "volcano" | "gloam" | "isle" | "town" | "cave"

export type Zone = {
	id: string,
	kind: Kind,
	center: Vector2,
	radius: number,
	density: number,
}

ScatterZones.Zones = {
	{ id = "town", kind = "town", center = Vector2.new(0, 90), radius = 180, density = 0.35 },
	{ id = "starter", kind = "forest", center = Vector2.new(0, -180), radius = 100, density = 0.8 },
	{ id = "hills", kind = "forest", center = Vector2.new(-500, 110), radius = 150, density = 0.7 },
	{ id = "meadow-east", kind = "meadow", center = Vector2.new(300, -40), radius = 80, density = 0.4 },
	{ id = "snow", kind = "snow", center = Vector2.new(0, 720), radius = 115, density = 0.45 },
	{ id = "volcano", kind = "volcano", center = Vector2.new(450, 500), radius = 125, density = 0.4 },
	{ id = "gloam", kind = "gloam", center = Vector2.new(10, -720), radius = 80, density = 0.35 },
	{ id = "shore", kind = "shore", center = Vector2.new(820, 40), radius = 120, density = 0.3 },
	{ id = "isle", kind = "isle", center = Vector2.new(680, 280), radius = 100, density = 0.25 },
	{ id = "cave", kind = "cave", center = Vector2.new(150, -200), radius = 80, density = 0.15 },
} :: { Zone }

local ROADS: { WorldLayout.FastLine } = {}
local ROAD_HALF: { number } = {}
for _, road in ipairs(WorldLayout.Roads) do
	table.insert(ROADS, WorldLayout.FastLine(road.points))
	table.insert(ROAD_HALF, road.width / 2 + 4)
end
local TUNNEL = WorldLayout.FastLine(WorldLayout.TunnelPoints)

function ScatterZones.Blocked(x: number, z: number): boolean
	if WorldLayout.OnPlotPad(x, z) or WorldLayout.InReservedRegion(x, z) then
		return true
	end
	for i, line in ipairs(ROADS) do
		if WorldLayout.FastDistance(line, x, z, ROAD_HALF[i] + 2) <= ROAD_HALF[i] then
			return true
		end
	end
	local lake = WorldLayout.Lake
	local pond = WorldLayout.Pond
	local function inDisc(cx: number, cz: number, r: number): boolean
		return (x - cx) ^ 2 + (z - cz) ^ 2 <= r * r
	end
	if inDisc(lake.x, lake.z, lake.radius) or inDisc(pond.x, pond.z, pond.radius) then
		return true
	end
	for _, pool in ipairs(WorldLayout.Pools) do
		if inDisc(pool.x, pool.z, pool.radius) then
			return true
		end
	end
	if math.abs(x) < 8 and z > 20 and z < 90 then
		return true -- the spawn lane
	end
	if WorldLayout.FastDistance(TUNNEL, x, z, 16) < WorldLayout.TunnelWidth / 2 then
		return true
	end
	for _, cave in ipairs(UndergroundData.Caves) do
		if math.abs(x - cave.x) < 8 and math.abs(z - cave.z) < cave.sz / 2 then
			return true
		end
	end
	return false
end

return ScatterZones
