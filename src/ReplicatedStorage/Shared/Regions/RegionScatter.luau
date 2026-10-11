--!strict
-- RegionScatter: where the small scatter pieces of the Bayou and Red Mesa go
-- (Lane R). Pure and deterministic: a seed per region, the region's disc, off
-- the roads, off the junction's circle, off every footprint of the region's own
-- build, off the trees, a few studs apart. RegionService builds the pieces at
-- these sites; the preview scenes read the same list.

local BayouData = require(script.Parent.BayouData)
local BiomeData = require(script.Parent.Parent.BiomeData)
local Kit = require(script.Parent.Parent.Art.Kit)
local MesaData = require(script.Parent.MesaData)

local RegionScatter = {}

export type Site = { kind: string, x: number, z: number, seed: number, yaw: number }

-- `trees` are the region's tree positions; `roadClear(x, z)` is how far a point
-- is from the nearest road's edge (TerrainGen.RoadClearance).
function RegionScatter.Sites(regionId: string, trees: { Vector3 }, roadClear: (number, number) -> number): { Site }
	local disc, kinds, want, blocked, junction
	if regionId == "bayou" then
		disc = BiomeData.RegionDiscs.bayou
		kinds = BayouData.ScatterKinds
		want = BayouData.Budgets.scatterPieces
		blocked = BayouData.Blocked
		junction = BayouData.Junction
	else
		disc = BiomeData.RegionDiscs.mesa
		kinds = MesaData.ScatterKinds
		want = MesaData.Budgets.scatterPieces
		blocked = MesaData.Blocked
		junction = MesaData.Junction
	end
	local rng = Kit.rng(#regionId * 977 + 13)
	local out: { Site } = {}
	local tries = 0
	while #out < want and tries < want * 80 do
		tries += 1
		local a = rng:range(0, math.pi * 2)
		local r = math.sqrt(rng:next()) * (disc.radius - 10)
		local x, z = disc.x + math.cos(a) * r, disc.z + math.sin(a) * r
		local jd = (x - junction.x) ^ 2 + (z - junction.z) ^ 2
		local ok = roadClear(x, z) >= 8 and jd > (junction.radius + 6) ^ 2 and not blocked(x, z, 4)
		if ok then
			for _, p in ipairs(trees) do
				if (p.X - x) ^ 2 + (p.Z - z) ^ 2 < 5 * 5 then
					ok = false
					break
				end
			end
		end
		if ok then
			for _, s in ipairs(out) do
				if (s.x - x) ^ 2 + (s.z - z) ^ 2 < 6 * 6 then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(out, {
				kind = kinds[(#out % #kinds) + 1],
				x = x,
				z = z,
				seed = rng:int(1, 999999),
				yaw = rng:range(0, math.pi * 2),
			})
		end
	end
	return out
end

return RegionScatter
