-- T411: the town sawmill and the Weigh House as one lumber yard.
-- Cameras match the brief's preview/t411 shots. Lane boxes are drawn only
-- when T411_LANES=1 (the top-down shot), so the other shots stay clear.
--
-- TownMeshes stays off in this scene. The uploaded Sawmill mesh is still the
-- previous building (TownModels sizes and ids are unchanged until Connor
-- re-uploads). Dressing it here would hide the remade part yard. The part
-- build is the fallback, and it is what these shots show.
local process = require("@lune/process")
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		ctx.art("TownMeshes").Enabled = false
		local BuildingArt = ctx.art("BuildingArt")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local LaneData = ctx.load("ReplicatedStorage/Shared/Lint/LaneData")
		local root = roblox.Instance.new("Model")

		Common.ground(ctx, root, 220, C3.fromRGB(122, 158, 86), V3.new(20, -0.5, 8))
		-- A dirt apron in front of the yard, the colour of the approach road.
		Kit.part(
			root,
			"Approach",
			V3.new(160, 0.2, 70),
			CF.new(24, 0.05, -28),
			C3.fromRGB(168, 140, 96),
			Enum.Material.Ground
		)

		local mill = BuildingArt.Sawmill()
		mill.Parent = root
		-- The town places the pad east of the mill (WorldPlan sell offset).
		local sell = BuildingArt.SellStation(WorldPlan.SellPadWidth, WorldPlan.SellPadDepth)
		sell:PivotTo(CF.new(53, 0, 1))
		sell.Parent = root

		local overlay = roblox.Instance.new("Model")
		overlay.Name = "LaneOverlay"
		if process.env.T411_LANES == "1" then
			overlay.Parent = root
		end
		for _, lane in ipairs(LaneData.Boxes.Sawmill) do
			local size = lane.max - lane.min
			local box = Kit.part(
				overlay,
				"Lane_" .. lane.name,
				size,
				CF.new((lane.min + lane.max) / 2),
				C3.fromRGB(210, 48, 42),
				Enum.Material.Neon
			)
			box.Transparency = 0.55
			box.CanCollide = false
		end
		-- The truck bay the acceptance measures: 14 wide, inside the 28 x 32 pad.
		local bay = Kit.part(
			overlay,
			"Lane_bay",
			V3.new(14, 6, 26),
			CF.new(53, 3.2, 1),
			C3.fromRGB(210, 48, 42),
			Enum.Material.Neon
		)
		bay.Transparency = 0.72
		bay.CanCollide = false

		return {
			root = root,
			shadowRadius = 140,
			cameras = {
				{
					pos = { 48, 8, -6 },
					target = { 22, 3, -1 },
					label = "east slip and carriage, square oak on the slip",
					fov = 42,
				},
				{
					pos = { -22, 5, -28 },
					target = { -21, 6, -12 },
					label = "cabin front door open",
					fov = 40,
				},
				{
					-- From the cabin door, looking at the shed's west opening. The cabin's
					-- outer west wall is solid; the clear outfeed is that opening.
					pos = { -21, 5, -20 },
					target = { -16, 3, -1 },
					label = "west outfeed clear",
					fov = 42,
				},
				{
					pos = { 53, 7, -28 },
					target = { 53, 3, 2 },
					label = "empty truck bay, edge rails only",
					fov = 48,
				},
				{
					pos = { 53, 8, -99 },
					target = { 64, 16, 6 },
					label = "scale tower from the spawn approach, 100 studs",
					fov = 32,
				},
				{
					pos = { 10, 18, -48 },
					target = { 28, 6, 4 },
					label = "mill to sell, phone crop",
					fov = 55,
				},
				{
					pos = { 20, 130, 8 },
					target = { 20, 0, 8 },
					label = "top-down, overlaps in red",
					fov = 50,
				},
			},
		}
	end,
}
