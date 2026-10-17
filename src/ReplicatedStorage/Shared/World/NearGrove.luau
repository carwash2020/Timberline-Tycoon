--!strict
-- NearGrove (WORLD-SPREAD, T349): oak clumps round the spawn, so the first
-- minute reads as a forest edge. Planned against what already stands near the
-- spawn (the first trees, Murph's three oaks and the town's rings), so no tree
-- anywhere moves: nothing else is planted inside the town's flat zone.
--   * Oak only; clumps of 5, 3 and 5 (odd), each inside CLUMP_RADIUS of its
--     centre, a regrow zone of its own ("neargrove:<n>", cap = its count).
--   * Between 18 and 66 studs from the spawn pad, on TreeFill.TownGround (roads,
--     paths, buildings, the lot, shop doors, plots, props and the townsfolk's
--     walks all keep trees off), TreeFill.Clear, and the 10 stud tree gap.
--   * The walking corridors stay open: 24 studs wide from the pad to the first
--     plot and to the sell stand, and nothing in the middle 40 percent of a
--     phone's frame at the spawn (a cone of +-25 degrees toward the sawmill).
-- Pure and deterministic (fixed rng strings per clump).

local Kit = require(script.Parent.Parent.Art.Kit)
local PlotData = require(script.Parent.Parent.PlotData)
local TerrainGen = require(script.Parent.TerrainGen)
local TreeFill = require(script.Parent.TreeFill)
local TutorialGrove = require(script.Parent.Parent.TutorialGrove)
local WorldLayout = require(script.Parent.WorldLayout)

local NearGrove = {}

NearGrove.Clumps = { 5, 3, 5 } :: { number }
NearGrove.ClumpRadius = 12
NearGrove.SpawnX = 0
NearGrove.SpawnZ = 40
NearGrove.Inner = 18 -- studs from the pad
NearGrove.Outer = 70
NearGrove.Gap = 10 -- TreeFill's tree gap
NearGrove.CorridorHalf = 12 -- a 24 stud walking corridor
NearGrove.ConeDegrees = 25 -- half the middle 40 percent of a phone frame, toward the sawmill
NearGrove.SellStand = { x = 53, z = 111 } -- the sell pad's middle (WorldPlan.SellZone)

export type Spot = {
	woodId: string,
	position: Vector3,
	biome: string,
	zone: {
		id: string,
		cx: number,
		cz: number,
		radius: number,
		cap: number?,
		fixed: boolean?,
	}?,
}

local function hashString(s: string): number
	local h = 7
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 1000003
	end
	return h
end

-- Whether (x, z) keeps the walking corridors and the spawn view open.
function NearGrove.InCorridor(x: number, z: number): boolean
	local p = Vector2.new(x, z)
	local pad = Vector2.new(NearGrove.SpawnX, NearGrove.SpawnZ)
	local firstPlot = PlotData.Slots[1]
	for _, goal in ipairs({ firstPlot, Vector2.new(NearGrove.SellStand.x, NearGrove.SellStand.z) }) do
		if (WorldLayout.SegmentDistance(p, pad, goal)) < NearGrove.CorridorHalf then
			return true
		end
	end
	local off = p - pad
	if off.Magnitude > 1e-6 then
		-- The sawmill is due +Z of the pad.
		local angle = math.deg(math.acos(math.clamp(off.Y / off.Magnitude, -1, 1)))
		if angle <= NearGrove.ConeDegrees then
			return true
		end
	end
	return false
end

-- The clumps, planned against `standing` (positions of the trees already near
-- the spawn). Murph's three oaks count too. A clump is 5 trees where the room
-- allows and 3 where it does not (always odd).
function NearGrove.Plan(standing: { Vector3 }, pause: (() -> ())?): { Spot }
	local taken: { Vector3 } = table.clone(standing)
	for _, spot in ipairs(TutorialGrove.Trees) do
		table.insert(taken, Vector3.new(spot.x, 0, spot.z))
	end
	-- Every legal point of the ring on a 2 stud grid (before the tree gap).
	local legal: { Vector2 } = {}
	local reach = NearGrove.Outer
	for x = NearGrove.SpawnX - reach, NearGrove.SpawnX + reach, 2 do
		for z = NearGrove.SpawnZ - reach, NearGrove.SpawnZ + reach, 2 do
			if pause then
				pause()
			end
			local d = math.sqrt((x - NearGrove.SpawnX) ^ 2 + (z - NearGrove.SpawnZ) ^ 2)
			if
				d >= NearGrove.Inner
				and d <= NearGrove.Outer
				and not NearGrove.InCorridor(x, z)
				and TreeFill.Clear(x, z)
				and TreeFill.TownGround(x, z)
			then
				table.insert(legal, Vector2.new(x, z))
			end
		end
	end

	local out: { Spot } = {}
	local centres: { Vector2 } = {}
	for index, want in ipairs(NearGrove.Clumps) do
		local rng = Kit.rng(hashString("T349 near grove " .. index))
		local best: { Vector3 } = {}
		local bestCentre: Vector2? = nil
		for _ = 1, 200 do
			if #legal == 0 then
				break
			end
			local centre = legal[math.floor(rng:next() * #legal) + 1]
			local apart = true
			for _, c in ipairs(centres) do
				if (centre - c).Magnitude < 24 then
					apart = false
				end
			end
			if apart then
				local mine: { Vector3 } = {}
				local trial: { Vector3 } = table.clone(taken)
				-- Greedy, in a rng-shuffled order, so a clump is not a straight line.
				local order: { Vector2 } = {}
				for _, p in ipairs(legal) do
					if (p - centre).Magnitude <= NearGrove.ClumpRadius then
						table.insert(order, p)
					end
				end
				for i = #order, 2, -1 do
					local j = math.floor(rng:next() * i) + 1
					order[i], order[j] = order[j], order[i]
				end
				for _, p in ipairs(order) do
					if #mine == want then
						break
					end
					if not TreeFill.TakenNearScan(trial, p.X, p.Y, NearGrove.Gap) then
						local v = Vector3.new(p.X, TerrainGen.HeightAt(p.X, p.Y) - 0.3, p.Y)
						table.insert(mine, v)
						table.insert(trial, v)
					end
				end
				if #mine > #best then
					best, bestCentre = mine, centre
				end
				if #mine == want then
					break
				end
			end
		end
		-- Odd clumps only: 5 that found 4 become 3.
		local count = #best
		if count % 2 == 0 then
			count -= 1
		end
		if count >= 3 and bestCentre then
			table.insert(centres, bestCentre)
			local zone = {
				id = "neargrove:" .. tostring(index),
				cx = bestCentre.X,
				cz = bestCentre.Y,
				radius = NearGrove.ClumpRadius + 6,
				cap = count,
			}
			for i = 1, count do
				table.insert(taken, best[i])
				table.insert(out, { woodId = "oak", position = best[i], biome = "wild", zone = zone })
			end
		end
	end
	return out
end

return NearGrove
