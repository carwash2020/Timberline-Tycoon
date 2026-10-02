--!nocheck
-- The forest's band layout (phase 10, FOR-01: WorldLayout.Forest and
-- WorldLayout.ForestCover) as a map over the real land: the hub's open
-- lawn (pale green), the forest ring's canopy (dark green) with its
-- clearings (mid green), the wild landscapes beyond (straw) with their
-- copses (olive), the biomes in their own ground colours, roads brown,
-- water blue. No parts: the colours are the terrain's.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
		local WorldLayout = ctx.load("ReplicatedStorage/Shared/World/WorldLayout")
		local BiomeData = ctx.shared("BiomeData")
		local colors = {
			Hub = "B9DB8A",
			Canopy = "2E6631",
			Edge = "4E8A3E",
			Clearing = "8DBE62",
			Wild = "D8D49A",
			Copse = "6F8F3A",
			Road = "8A6444",
		}
		for name, c in pairs(TerrainGen.MaterialColors) do
			colors[name] = c:ToHex()
		end
		return {
			root = roblox.Instance.new("Model"),
			terrain = {
				x0 = -1500,
				z0 = -1500,
				x1 = 1500,
				z1 = 1500,
				step = 10,
				colors = colors,
				waterColor = "#3f9ac2",
				sample = function(x, z)
					local h, material, water = TerrainGen.Sample(x, z)
					if water or TerrainGen.RoadClearance(x, z) < 0 or WorldLayout.FlatWeight(x, z) > 0.9 then
						return h, if TerrainGen.RoadClearance(x, z) < 0 then "Road" else material, water
					end
					local c, ring = WorldLayout.ForestCover(x, z)
					local biome = BiomeData.At(x, z)
					if biome and c == 0 then
						return h, material, water
					end
					if h > 70 then
						return h, material, water
					end
					local band
					if c > 0.5 then
						band = if ring > 0.5 then (if c < 0.7 then "Edge" else "Canopy") else "Copse"
					elseif ring > 0.5 then
						band = "Clearing"
					elseif WorldLayout.HubDistance(x, z) <= 0 then
						band = "Hub"
					else
						band = "Wild"
					end
					return h, band, water
				end,
			},
			shadowRadius = 1600,
			lighting = { fogNear = 4000, fogFar = 9000 },
			fov = 50,
			cameras = {
				{ pos = { 0, 3800, 1 }, target = { 0, 0, 0 }, label = "the bands, top down" },
				{ pos = { 0, 1500, -900 }, target = { 0, 0, 200 }, label = "the hub and the ring from the south" },
			},
		}
	end,
}
