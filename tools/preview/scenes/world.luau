--!nocheck
-- The whole world as MapBuilder builds it (Shared/World/WorldPlan + the art
-- modules): terrain, every tree, the town, boulders, the Skyroot and isles.
-- Client-side decoration (flowers, critters) isn't part of it.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local CF, V3 = roblox.CFrame, roblox.Vector3
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local BuildingArt = ctx.art("BuildingArt")
		local IsleArt = ctx.art("IsleArt")
		local PropArt = ctx.art("PropArt")
		local WoodData = ctx.shared("WoodData")
		local TreeLogic = ctx.shared("TreeLogic")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local root = roblox.Instance.new("Model")

		local function place(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
			return model
		end

		-- Trees, exactly as TreeService builds them (seed and size from the spot).
		for _, spot in ipairs(WorldPlan.Trees()) do
			local def = WoodData.Get(spot.woodId)
			local p = spot.position
			local seed = Kit.seedAt(p.X, p.Z)
			local size = TreeLogic.SizeFor(Kit.rng(seed + 101):next())
			local tree = TreeArt.Build(def, seed, size.scale)
			place(tree, CF.new(p) * CF.Angles(0, Kit.rng(seed + 202):range(0, math.pi * 2), 0))
		end
		for _, b in ipairs(WorldPlan.Boulders()) do
			place(PropArt.Rock(b.size, b.seed), CF.new(b.position))
		end
		for i, cf in ipairs(WorldPlan.GroveMushrooms()) do
			place(PropArt.Mushroom(i, true), cf)
		end
		local palm = WoodData.Get("palmwood")
		for i, pos in ipairs(WorldPlan.IslandPalms()) do
			place(TreeArt.Build(palm, 3000 + i, 0.9 + (i % 3) * 0.1), CF.new(pos))
		end

		-- The town.
		local town = WorldPlan.Town()
		place(BuildingArt.Sawmill(), town.sawmill)
		place(BuildingArt.SellPad(24, 18), town.sellPad)
		for _, spot in ipairs(town.shops) do
			place(BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe)
		end
		place(BuildingArt.GondolaStation(), town.gondola)
		place(BuildingArt.Campsite(), town.campsite)
		for _, cf in ipairs(town.lamps) do
			place(BuildingArt.LampPost(), cf)
		end
		for _, fence in ipairs(town.fences) do
			place(BuildingArt.Fence(fence.length), fence.cframe)
		end
		for _, prop in ipairs(town.props) do
			place(BuildingArt.Prop(prop.name, prop.seed), prop.cframe)
		end
		place(BuildingArt.SkyBin(), town.skyBin * CF.new(0, -2, 0))
		place(BuildingArt.Signpost("SKYROOT GONDOLA\nto the Aether Isles\n$250 a ride"), town.gondolaSign)
		for _, sign in ipairs(town.signs) do
			place(BuildingArt.Signpost(sign.text), sign.cframe)
		end
		for _, cf in ipairs(town.parkingSlots) do
			Kit.part(
				root,
				"Slot",
				V3.new(6.5, 0.2, 37),
				cf,
				roblox.Color3.fromRGB(186, 168, 140),
				roblox.Enum.Material.Slate
			)
		end
		for _, sign in
			ipairs(WorldPlan.RoadSigns(function(id)
				return string.upper(id)
			end))
		do
			place(BuildingArt.Signpost(sign.text), sign.cframe)
		end

		-- The Skyroot and the isles.
		local sky = WorldPlan.Sky()
		if sky then
			place(IsleArt.Skyroot(sky.trunkHeight), CF.new(sky.root))
			place(IsleArt.Isle(sky.main.radius, 1), CF.new(sky.main.center))
			for i, isle in ipairs(sky.isles) do
				place(IsleArt.Isle(isle.radius, i + 1), CF.new(isle.center))
			end
			for _, bridge in ipairs(sky.bridges) do
				BuildingArt.Bridge(bridge.a, bridge.b, 6).Parent = root
			end
			for i, pos in ipairs(sky.lumenwood) do
				place(TreeArt.Build(WoodData.Get("lumenwood"), i, 1), CF.new(pos))
			end
			for _, cf in ipairs(sky.chutes) do
				place(BuildingArt.CloudChute(), cf)
				local from = (cf * CF.new(0, -2.6, 13.6)).Position
				local to = from + cf.LookVector * -36 - V3.new(0, 60, 0)
				Kit.beam(
					root,
					"Flume",
					from,
					to,
					2.4,
					1.2,
					roblox.Color3.fromRGB(90, 62, 38),
					roblox.Enum.Material.WoodPlanks
				)
			end
			place(BuildingArt.StarfallForge(), sky.forge)
			place(BuildingArt.GondolaStation(), sky.gondolaTop)
			place(BuildingArt.GondolaStation(), sky.gondolaBase)
			local fall = sky.waterfall
			Kit.part(
				root,
				"Waterfall",
				V3.new(7, fall.top.Y - fall.bottom.Y, 3.5),
				CF.new((fall.top + fall.bottom) / 2),
				roblox.Color3.fromRGB(150, 205, 235),
				roblox.Enum.Material.Glass
			).Transparency =
				0.35
		end

		return {
			root = root,
			terrain = Common.terrain(ctx, -1500, -1500, 1500, 1500, 8),
			shadowRadius = 700,
			lighting = { fogNear = 1500, fogFar = 7000 },
			fov = 50,
			cameras = {
				{ pos = { 60, 45, -10 }, target = { 0, 8, 110 }, label = "from the spawn: the town and sawmill" },
				{ pos = { 260, 220, -260 }, target = { 0, 0, 60 }, label = "town and starter forest from above" },
				{ pos = { 20, 24, -60 }, target = { 0, 6, -120 }, label = "into the Starter Forest" },
				{ pos = { -250, 60, 30 }, target = { -420, 20, 110 }, label = "the Hills" },
				{ pos = { 120, 90, 900 }, target = { 0, 30, 1240 }, label = "the Snowfields" },
				{ pos = { 850, 100, 900 }, target = { 1150, 60, 1250 }, label = "the Volcano" },
				{ pos = { -700, 400, 650 }, target = { -1050, 500, 1050 }, label = "the Skyroot and the isles" },
				{ pos = { -1000, 740, 960 }, target = { -1050, 700, 1050 }, label = "on the isles" },
				{ pos = { 0, 2400, -1800 }, target = { 0, 0, 100 }, label = "the whole map" },
			},
		}
	end,
}
