--!nocheck
-- The whole world as MapBuilder builds it (Shared/World/WorldPlan + the art
-- modules): terrain, every tree, the town, boulders, the Skyroot and isles.
-- Client-side decoration (flowers, critters) isn't part of it.
-- A helper (files starting with _ aren't scenes): world.luau and
-- world-eye.luau are this build with their own cameras. World.build(ctx)
-- returns everything a scene returns but the cameras.

local Common = require("./_common")

local World = {}

function World.build(ctx)
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
	-- The lava filling the volcano crater's pool, with its glow.
	local pool, poolRadius = WorldPlan.Crater()
	local lava = Kit.decor(
		Kit.cylinder(
			root,
			"CraterLava",
			1,
			poolRadius * 2,
			CF.new(pool + V3.new(0, 0.5, 0)) * CF.Angles(0, 0, math.pi / 2),
			roblox.Color3.fromRGB(255, 106, 26),
			roblox.Enum.Material.Neon
		),
		false
	)
	local glow = roblox.Instance.new("PointLight")
	glow.Color = roblox.Color3.fromRGB(255, 120, 40)
	glow.Range = 60
	glow.Brightness = 4
	glow.Parent = lava

	-- The town.
	local town = WorldPlan.Town()
	place(BuildingArt.Sawmill(), town.sawmill)
	place(BuildingArt.SellPad(24, 18), town.sellPad)
	for _, spot in ipairs(town.shops) do
		place(BuildingArt.Shop(spot.kind, spot.title, spot.accent), spot.cframe)
	end
	local townStation = place(BuildingArt.GondolaStation(), town.gondola)
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
	for _, g in ipairs(town.greenery) do
		place(BuildingArt.Greenery(g.kind, g.size, g.seed, g.woodId), g.cframe)
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
	-- The biome signs where the roads arrive, saying what MapBuilder's say.
	for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
		place(BuildingArt.Signpost(sign.text), sign.cframe)
	end

	-- The Skyroot and the isles.
	local sky = WorldPlan.Sky()
	if sky then
		local fall = sky.waterfall
		local fromRoot = WorldPlan.IslesFromRoot(sky)
		place(IsleArt.Skyroot(sky.trunkHeight, fromRoot, sky.main.dir, fall.top - sky.root), CF.new(sky.root))
		place(
			IsleArt.Isle(sky.main.radius, 1, { clear = WorldPlan.IsleClearPoints(sky, sky.main.center) }),
			CF.new(sky.main.center)
		)
		for i, isle in ipairs(sky.isles) do
			local options = {
				clear = WorldPlan.IsleClearPoints(sky, isle.center),
				spout = if i == fall.isle then fall.dir else nil,
			}
			place(IsleArt.Isle(isle.radius, i + 1, options), CF.new(isle.center))
		end
		for _, bridge in ipairs(sky.bridges) do
			BuildingArt.Bridge(bridge.a, bridge.b, 6).Parent = root
			for k, at in ipairs({ bridge.a, bridge.b }) do
				local along = (bridge.b - bridge.a).Unit * (if k == 1 then 1 else -1)
				local side = V3.new(-along.Z, 0, along.X)
				place(IsleArt.LanternPost(k), CF.lookAt(at - along * 2 + side * 4.2, at + along))
			end
		end
		for i, spot in ipairs(IsleArt.CloudSpots(fromRoot, sky.trunkHeight, 99, sky.main.dir)) do
			place(IsleArt.CloudBank(spot.size, i), CF.new(sky.root) * spot.cframe)
		end
		place(IsleArt.Waterfall(fall.top.Y - fall.bottom.Y, 10), CF.lookAt(fall.top, fall.top + fall.dir))
		for i, pos in ipairs(sky.lumenwood) do
			place(TreeArt.Build(WoodData.Get("lumenwood"), i, 1), CF.new(pos))
		end
		for _, cf in ipairs(sky.chutes) do
			place(BuildingArt.CloudChute(), cf)
			local from, to = WorldPlan.ChuteFlume(cf) -- out off the isle, as MapBuilder draws it
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
		local top = place(BuildingArt.GondolaStation(), sky.gondolaTop)
		local base = place(BuildingArt.GondolaStation(), sky.gondolaBase)
		-- The cables, along the cabins' route as MapBuilder draws them.
		for _, station in ipairs({ townStation, base }) do
			local platform = station.PrimaryPart
			local to = top.PrimaryPart.CFrame.Position
			local path = WorldPlan.GondolaPath(sky, platform.CFrame.Position, platform.CFrame.ZVector, to)
			for _, piece in ipairs(WorldPlan.GondolaCable(path, platform.CFrame.ZVector)) do
				Kit.decor(
					Kit.rod(
						root,
						"GondolaCable",
						piece[1],
						piece[2],
						0.4,
						roblox.Color3.fromRGB(70, 70, 75),
						roblox.Enum.Material.Metal
					),
					false
				)
			end
		end
	end

	return {
		root = root,
		terrain = Common.terrain(ctx, -1500, -1500, 1500, 1500, 8),
		shadowRadius = 700,
		lighting = { fogNear = 1500, fogFar = 7000 },
		fov = 50,
	}
end

return World
