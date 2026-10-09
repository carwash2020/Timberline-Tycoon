--!nocheck
-- The spawn area with its trees: town.luau's town (spawn pad, shops, the
-- Land Office, the showroom hall and its lot, the parking lot, roads) plus
-- every choppable section tree WorldPlan.Trees() plants inside the window
-- below, as SectionTrees plants them at boot. Compare renders before and
-- after a change to TreeFill.TownRings (or any tree planner): the cameras
-- are the spawn pad, the street, the dealership, the lot and the town edge.

local Common = require("./_common")
local Town = require("./town")

local X0, Z0, X1, Z1 = -300, -140, 520, 380

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local CF = roblox.CFrame
		local built = Town.build(ctx)
		local root = built.root
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local WoodData = ctx.shared("WoodData")
		local GrowLogic = ctx.shared("GrowLogic")
		local TreeGen = ctx.shared("TreeGen")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local count = 0
		local function plant(woodId, p)
			local def = WoodData.Get(woodId)
			local boot = GrowLogic.BootTree(def, p)
			local skel = if boot.stage < 1 then TreeGen.AtStage(boot.skel, boot.stage) else boot.skel
			local model = TreeArt.FromSkeleton(def, skel)
			Kit.placeAt(model, CF.new(p) * CF.Angles(0, boot.yaw, 0))
			model.Parent = root
			count += 1
		end
		for _, spot in ipairs(WorldPlan.Trees()) do
			local p = spot.position
			if p.X >= X0 and p.X <= X1 and p.Z >= Z0 and p.Z <= Z1 then
				plant(spot.woodId, p)
			end
		end
		print(string.format("[spawn-trees] %d trees in the window", count))
		built.terrain = Common.terrain(ctx, X0, Z0, X1, Z1, 6)
		built.cameras = {
			{ pos = { 2, 6.5, 32 }, target = { 0, 9, 110 }, label = "from the spawn pad" },
			{ pos = { 0, 5, 18 }, target = { 0, 7, -60 }, label = "spawn pad, looking south" },
			{ pos = { -60, 7, 40 }, target = { 40, 9, 60 }, label = "spawn pad, wide from the west" },
			{ pos = { 190, 9, 62 }, target = { 205, 8, 104 }, label = "dealership door" },
			{ pos = { 150, 14, 40 }, target = { 240, 10, 110 }, label = "dealership and Land Office from the lot" },
			{ pos = { 80, 14, 24 }, target = { 0, 9, 100 }, label = "from the lot" },
			{ pos = { 0, 330, 90 }, target = { 0, 0, 91 }, fov = 62, label = "top down, the town" },
			{ pos = { 150, 190, 150 }, target = { 150, 0, 80 }, fov = 62, label = "top down, the dealership side" },
			{ pos = { -95, 105, -20 }, target = { -10, 0, 100 }, label = "aerial" },
			{ pos = { -118, 8.5, 140 }, target = { -102, 8, 172 }, label = "Hearth & Home" },
		}
		built.shadowRadius = 260
		return built
	end,
}
