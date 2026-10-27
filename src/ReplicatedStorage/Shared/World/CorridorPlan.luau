--!strict
-- CorridorPlan (T409): the draft's roadside stamps, made spawnable.
-- Tree and scatter props stay gateClear studs off the lodge and off each
-- belt edge. Big, mid and small counts stay odd. Wood lots stay an odd
-- handful of parts each, under MaxWoodPartsServer. Nothing here is a
-- choppable tree (that is T410).

local GameConfig = require(script.Parent.Parent.GameConfig)
local WorldPlanDraft = require(script.Parent.WorldPlanDraft)

local CorridorPlan = {}

export type Marker = {
	kind: string,
	x: number,
	z: number,
	road: string,
	offset: number,
	radius: number,
	label: string?,
	wood: string?,
	size: string,
}

local PARTS_PER_LOT = 5

local function sizeOf(kind: string): string
	if kind == "scatter" then
		return "small"
	elseif kind == "medium" or kind == "sign" or kind == "boom" then
		return "mid"
	end
	return "big"
end

local function near(x: number, z: number, px: number, pz: number, r: number): boolean
	local dx, dz = x - px, z - pz
	return dx * dx + dz * dz < r * r
end

local function kept(marker: { kind: string, x: number, z: number }): boolean
	local clear = WorldPlanDraft.Corridor.gateClear
	local lodge = WorldPlanDraft.Lodge
	local treeish = marker.kind == "tree-belt" or marker.kind == "scatter" or marker.kind == "medium"
	if treeish and near(marker.x, marker.z, lodge.x, lodge.z, clear) then
		return false
	end
	if marker.kind == "tree-belt" then
		for _, belt in ipairs(WorldPlanDraft.Belts) do
			if near(marker.x, marker.z, belt.edge.x, belt.edge.z, clear) then
				return false
			end
		end
	end
	return true
end

local function roadByName(name: string): WorldPlanDraft.Road?
	for _, road in ipairs(WorldPlanDraft.Roads) do
		if road.name == name then
			return road
		end
	end
	return nil
end

-- A hairpin can fold a stamp that was offset from one leg onto another leg.
-- Walk it out from the nearest centreline point until it clears the bed.
local function pushOffBed(marker: { x: number, z: number, road: string })
	local road = roadByName(marker.road)
	if not road then
		return
	end
	local need = road.width / 2 + WorldPlanDraft.Corridor.propClearOfBed
	local pts = road.points
	for _ = 1, 8 do
		local best = math.huge
		local px, pz = marker.x, marker.z
		for i = 2, #pts do
			local a, b = pts[i - 1], pts[i]
			local dx, dz = b.x - a.x, b.z - a.z
			local len2 = dx * dx + dz * dz
			local t = 0
			if len2 > 1e-6 then
				t = math.clamp(((marker.x - a.x) * dx + (marker.z - a.z) * dz) / len2, 0, 1)
			end
			local qx = a.x + dx * t
			local qz = a.z + dz * t
			local d = math.sqrt((marker.x - qx) ^ 2 + (marker.z - qz) ^ 2)
			if d < best then
				best = d
				px, pz = qx, qz
			end
		end
		if best >= need - 0.05 then
			return
		end
		local dx, dz = marker.x - px, marker.z - pz
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 0.05 then
			dx, dz, len = 1, 0, 1
		end
		local step = need - best + 0.3
		marker.x += dx / len * step
		marker.z += dz / len * step
	end
end

local function clearsBed(marker: { x: number, z: number, road: string }): boolean
	local road = roadByName(marker.road)
	if not road then
		return true
	end
	local need = road.width / 2 + WorldPlanDraft.Corridor.propClearOfBed - 0.05
	local pts = road.points
	local best = math.huge
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local dx, dz = b.x - a.x, b.z - a.z
		local len2 = dx * dx + dz * dz
		local t = 0
		if len2 > 1e-6 then
			t = math.clamp(((marker.x - a.x) * dx + (marker.z - a.z) * dz) / len2, 0, 1)
		end
		local qx = a.x + dx * t
		local qz = a.z + dz * t
		local d = math.sqrt((marker.x - qx) ^ 2 + (marker.z - qz) ^ 2)
		if d < best then
			best = d
		end
	end
	return best >= need
end

local function collect(): { Marker }
	local out: { Marker } = {}
	for _, marker in ipairs(WorldPlanDraft.Dressing) do
		if kept(marker) then
			local placed = {
				kind = marker.kind,
				x = marker.x,
				z = marker.z,
				road = marker.road,
				offset = marker.offset,
				radius = marker.radius,
				label = marker.label,
				wood = marker.wood,
				size = sizeOf(marker.kind),
			}
			pushOffBed(placed)
			if kept(placed) and clearsBed(placed) then
				table.insert(out, placed)
			end
		end
	end
	-- Drop one non-lot of a class until that class is odd. Wood lots stay
	-- (there are four; each is its own odd pile).
	for _, size in ipairs({ "big", "mid", "small" }) do
		local function count(): number
			local n = 0
			for _, marker in ipairs(out) do
				if marker.size == size then
					n += 1
				end
			end
			return n
		end
		while count() % 2 == 0 and count() > 0 do
			local drop: number? = nil
			for i = #out, 1, -1 do
				if out[i].size == size and out[i].kind ~= "wood-lot" then
					drop = i
					break
				end
			end
			if not drop then
				break
			end
			table.remove(out, drop)
		end
	end
	return out
end

local cached: { Marker }? = nil

function CorridorPlan.Markers(): { Marker }
	local list = cached
	if list then
		return list
	end
	local built = collect()
	cached = built
	return built
end

function CorridorPlan.Counts(): { big: number, mid: number, small: number }
	local big, mid, small = 0, 0, 0
	for _, marker in ipairs(CorridorPlan.Markers()) do
		if marker.size == "big" then
			big += 1
		elseif marker.size == "mid" then
			mid += 1
		else
			small += 1
		end
	end
	return { big = big, mid = mid, small = small }
end

function CorridorPlan.WoodLots(): { number }
	local lots: { number } = {}
	for _, marker in ipairs(CorridorPlan.Markers()) do
		if marker.kind == "wood-lot" then
			table.insert(lots, PARTS_PER_LOT)
		end
	end
	return lots
end

function CorridorPlan.WoodParts(): number
	local n = 0
	for _, parts in ipairs(CorridorPlan.WoodLots()) do
		n += parts
	end
	return n
end

function CorridorPlan.UnderWoodCap(): boolean
	return CorridorPlan.WoodParts() <= GameConfig.MaxWoodPartsServer
end

return CorridorPlan
