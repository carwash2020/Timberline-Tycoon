-- Lanternwood from the mainland ferry dock, and a wall of its planks.
-- Both cameras are night views: NightGlow parts go neon (night.luau),
-- which is the same colour WoodFX swaps in at 19:00–05:00. The preview
-- does not run WoodFX, so it does not add the capped PointLights.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF = roblox.Vector3, roblox.CFrame
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local TreeGen = ctx.shared("TreeGen")
		local WoodData = ctx.shared("WoodData")
		local WorldPlan = ctx.shared("World/WorldPlan")
		local WorldLayout = ctx.shared("World/WorldLayout")
		local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
		local root = roblox.Instance.new("Model")

		local island = WorldLayout.Island
		local dock = WorldLayout.FerryDock
		local x0 = math.min(dock.x, island.x) - 80
		local x1 = math.max(dock.x, island.x) + island.radius + 40
		local z0 = math.min(dock.z, island.z) - island.radius - 40
		local z1 = math.max(dock.z, island.z) + 80

		local def = WoodData.Get("lanternwood")
		local spots = WorldPlan.Lanternwood()
		local tx, ty, tz = 0, 0, 0
		for i, spot in ipairs(spots) do
			local model = TreeArt.FromSkeleton(def, TreeGen.Skeleton(def.id, 20 + i, 1))
			Kit.placeAt(model, CF.new(spot.position))
			model.Parent = root
			tx += spot.position.X
			ty += spot.position.Y
			tz += spot.position.Z
		end
		tx, ty, tz = tx / #spots, ty / #spots, tz / #spots

		local dockY = TerrainGen.HeightAt(dock.x, dock.z)
		local eye = V3.new(dock.x, dockY + 6, dock.z)

		-- A wall of Lanternwood planks, west of the dock so it stays out of
		-- the island view. NightGlow, no light: planks never get one.
		local core, material = TreeArt.Core(def)
		local wallY = dockY + 4
		local wall = CF.new(dock.x - 28, wallY, dock.z) * CF.Angles(0, math.rad(90), 0)
		local boards = Kit.plankWall(root, "PlankWall", wall, 16, 8, 0.4, 8, Kit.rng(3), { core }, material)
		for _, board in ipairs(boards) do
			board:SetAttribute("NightGlow", true)
		end

		local function list(v)
			return { v.X, v.Y, v.Z }
		end
		return {
			root = root,
			fov = 50,
			shadowRadius = 180,
			terrain = Common.terrain(ctx, x0, z0, x1, z1, 10),
			cameras = {
				{
					pos = list(eye),
					target = { tx, ty + 14, tz },
					label = "ferry dock toward Lanternwood at 22:00",
					fov = 46,
					night = true,
				},
				{
					pos = { dock.x - 28, wallY, dock.z + 22 },
					target = { dock.x - 28, wallY, dock.z },
					label = "a wall of Lanternwood planks at 22:00",
					fov = 40,
					night = true,
				},
			},
		}
	end,
}
