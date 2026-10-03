--!nocheck
-- The whole world as MapBuilder builds it (Shared/World/WorldPlan + the art
-- modules): terrain, every tree, the town, boulders, the Skyroot and isles,
-- and the backdrop beyond the walls; with `opts.forest`, the forest ring's
-- filler trees too, which every client builds round its camera (FOR-02:
-- World.forest, every one of them here). Other client-side decoration
-- (flowers, critters) isn't part of it.
-- A helper (files starting with _ aren't scenes): world.luau and
-- world-eye.luau are this build (with the forest) with their own cameras.
-- World.build(ctx, opts?) returns everything a scene returns but the
-- cameras.

local Common = require("./_common")

local World = {}

-- WorldPlan.Backdrop()'s pieces into `root`, the way MapBuilder's "7. The
-- backdrop" step builds them (isles.luau draws them too).
function World.backdrop(ctx, root)
	local Kit = ctx.art("Kit")
	local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
	for _, piece in ipairs(WorldPlan.Backdrop()) do
		local part
		if piece.kind == "Wedge" then
			part = Kit.wedge(root, piece.name, piece.size, piece.cframe, piece.color, piece.material)
		elseif piece.kind == "Cylinder" then
			part = Kit.cylinder(root, piece.name, piece.size.X, piece.size.Y, piece.cframe, piece.color, piece.material)
		else
			part = Kit.part(root, piece.name, piece.size, piece.cframe, piece.color, piece.material)
		end
		part.Transparency = piece.transparency
		Kit.decor(part, false)
	end
end

-- What MapBuilder's "5. The landmarks" step builds (phase 10, STY-*) into
-- `root`: the boulder clusters, the footbridge and its sign, the docks with
-- their rowboats (and the lake's sign) and the lighthouse, the ones
-- `inside(position)` keeps (all of them when it's nil).
function World.landmarks(ctx, root, inside)
	local CF = ctx.roblox.CFrame
	local Kit = ctx.art("Kit")
	local LandmarkArt = ctx.art("LandmarkArt")
	local BuildingArt = ctx.art("BuildingArt")
	local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
	local function keep(cf)
		return inside == nil or inside(cf.Position)
	end
	local function place(model, cf)
		Kit.placeAt(model, cf)
		model.Parent = root
	end
	for _, spot in ipairs(WorldPlan.BoulderClusters()) do
		if inside == nil or inside(spot.center) then
			for _, r in ipairs(spot.rocks) do
				place(
					LandmarkArt.BrownRock(r.size, r.seed, spot.tone, r.mossy),
					CF.new(r.position) * CF.Angles(0, r.yaw, 0)
				)
			end
		end
	end
	local bridge = WorldPlan.Footbridge()
	if bridge and keep(bridge.cframe) then
		place(LandmarkArt.Footbridge(bridge.span, bridge.drop, bridge.width, bridge.rise, bridge.beds), bridge.cframe)
		if bridge.sign then
			place(BuildingArt.Signpost(WorldPlan.BridgeText), bridge.sign)
		end
	end
	for i, dock in ipairs(WorldPlan.Docks()) do
		if keep(dock.cframe) then
			place(LandmarkArt.Dock(dock.length, dock.width, dock.deck, dock.water, dock.beds), dock.cframe)
			place(LandmarkArt.Rowboat(i * 17), dock.boat)
			if dock.sign then
				place(BuildingArt.Signpost(WorldPlan.LakeDockText), dock.sign)
			end
		end
	end
	local lighthouse = WorldPlan.Lighthouse()
	if lighthouse and keep(lighthouse.cframe) then
		place(LandmarkArt.Lighthouse(), lighthouse.cframe)
	end
end

-- One ForestFiller tree (FOR-02) into `root`, built the way the client
-- builds it: PropArt.FillerTree's look, scaled about its foot, turned and
-- stood on its spot.
local fillerLooks = {}
function World.fillerTree(ctx, root, tree)
	local CF = ctx.roblox.CFrame
	local PropArt = ctx.art("PropArt")
	local key = tree.kind .. "/" .. tree.variant
	local look = fillerLooks[key]
	if not look then
		look = {}
		for _, p in ipairs(PropArt.FillerTree(tree.kind, tree.variant):GetDescendants()) do
			if p:IsA("BasePart") then
				table.insert(look, p)
			end
		end
		fillerLooks[key] = look
	end
	local s = tree.scale
	local base = CF.new(tree.x, tree.y, tree.z) * CF.Angles(0, tree.yaw, 0)
	for _, template in ipairs(look) do
		local p = template:Clone()
		local cf = template.CFrame
		p.Size = template.Size * s
		p.CFrame = base * CF.new(cf.Position * s) * (cf - cf.Position)
		p.Parent = root
	end
end

-- The forest's filler into `root`: with `eye` (a Vector3) and a tier's
-- budget, exactly what ForestFiller loads round a camera there (trees
-- within FillerNear, stand-in blocks out to FillerFar); without, every
-- filler tree on the map (how the forest looks with all of it near).
function World.forest(ctx, root, eye, budget)
	local Kit = ctx.art("Kit")
	local PropArt = ctx.art("PropArt")
	local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = ctx.load("ReplicatedStorage/Shared/World/WorldLayout")
	local Enum = ctx.roblox.Enum
	for _, step in ipairs(WorldPlan.FillerSteps) do
		step()
	end
	local count = 0
	if eye then
		for key, mode in pairs(WorldPlan.FillerPlanAround(eye.X, eye.Y, eye.Z, budget.FillerNear, budget.FillerFar)) do
			local cx, cz = WorldPlan.FillerCellOf(key)
			if mode == "near" then
				for _, tree in ipairs(WorldPlan.FillerCellTrees(cx, cz)) do
					World.fillerTree(ctx, root, tree)
					count += 1
				end
			else
				for _, b in ipairs(WorldPlan.FillerFarCell(cx, cz)) do
					local p = Kit.part(
						root,
						"FillerFar",
						b.size,
						b.cframe,
						PropArt.FillerFarColor(b.kind),
						Enum.Material.SmoothPlastic
					)
					Kit.decor(p, false)
				end
			end
		end
	else
		local half = WorldLayout.WorldHalf // WorldPlan.FillerCellSize
		for cx = -half, half - 1 do
			for cz = -half, half - 1 do
				for _, tree in ipairs(WorldPlan.FillerCellTrees(cx, cz)) do
					World.fillerTree(ctx, root, tree)
					count += 1
				end
			end
		end
	end
	return count
end

-- The grass tufts (FOR-04) ForestFiller builds round each of `eyes`
-- (Vector3s) within `near` studs, as it builds them: one of eight
-- PropArt.GrassTuft looks per grass tint, turned and stood on its spot.
function World.tufts(ctx, root, eyes, near)
	local CF = ctx.roblox.CFrame
	local PropArt = ctx.art("PropArt")
	local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
	for _, step in ipairs(WorldPlan.FillerSteps) do
		step()
	end
	local done, looks = {}, {}
	for _, eye in ipairs(eyes) do
		for key in pairs(WorldPlan.TuftPlanAround(eye.X, eye.Y, eye.Z, near)) do
			if not done[key] then
				done[key] = true
				local cx, cz = WorldPlan.FillerCellOf(key)
				for _, tuft in ipairs(WorldPlan.TuftCell(cx, cz)) do
					local variant = tuft.seed % 8 + 1
					local id = tuft.biome .. "/" .. variant
					local look = looks[id]
					if not look then
						look = {}
						for _, p in
							ipairs(
								PropArt.GrassTuft(variant * 37 + 5, PropArt.Tints(tuft.biome).grass):GetDescendants()
							)
						do
							if p:IsA("BasePart") then
								table.insert(look, p)
							end
						end
						looks[id] = look
					end
					local base = CF.new(tuft.x, tuft.y, tuft.z) * CF.Angles(0, tuft.yaw, 0)
					for _, template in ipairs(look) do
						local p = template:Clone()
						p.CFrame = base * template.CFrame
						p.Parent = root
					end
				end
			end
		end
	end
end

function World.build(ctx, opts)
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

	-- With `opts.v2`, the v2 loop's section trees, exactly as SectionTrees
	-- plants them at boot (GrowLogic.BootTree: most mature, some young).
	local function sectionTree(woodId, p)
		local GrowLogic = ctx.shared("GrowLogic")
		local TreeGen = ctx.shared("TreeGen")
		local def = WoodData.Get(woodId)
		local boot = GrowLogic.BootTree(def, p)
		local skel = if boot.stage < 1 then TreeGen.AtStage(boot.skel, boot.stage) else boot.skel
		place(TreeArt.FromSkeleton(def, skel), CF.new(p) * CF.Angles(0, boot.yaw, 0))
	end

	-- Trees, exactly as TreeService builds them (seed and size from the spot).
	for _, spot in ipairs(WorldPlan.Trees()) do
		local def = WoodData.Get(spot.woodId)
		local p = spot.position
		if opts and opts.v2 then
			sectionTree(spot.woodId, p)
			continue
		end
		local seed = Kit.seedAt(p.X, p.Z)
		local size = TreeLogic.SizeFor(Kit.rng(seed + 101):next())
		local tree = TreeArt.Build(def, seed, size.scale)
		place(tree, CF.new(p) * CF.Angles(0, Kit.rng(seed + 202):range(0, math.pi * 2), 0))
	end
	-- Coloured and turned as MapBuilder does them.
	local C3 = roblox.Color3
	local SNOWY = { C3.fromRGB(232, 238, 245), C3.fromRGB(200, 208, 218), C3.fromRGB(150, 150, 156) }
	local DARK = { C3.fromRGB(58, 52, 50), C3.fromRGB(44, 40, 40), C3.fromRGB(72, 64, 60) }
	for _, b in ipairs(WorldPlan.Boulders()) do
		local colors = if b.snowy then SNOWY elseif b.dark then DARK else PropArt.BrownTones[b.seed % 2 + 1]
		local moss = if colors ~= SNOWY and colors ~= DARK and b.seed % 3 == 0 then PropArt.Moss else nil
		place(PropArt.Rock(b.size, b.seed, colors, moss), CF.new(b.position) * CF.Angles(0, b.seed % 6, 0))
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
		place(BuildingArt.Signpost(sign.text, sign.lit), sign.cframe)
	end
	for _, g in ipairs(town.greenery) do
		place(BuildingArt.Greenery(g.kind, g.size, g.seed, g.woodId), g.cframe)
	end
	for _, cf in ipairs(town.pathRounds) do
		place(BuildingArt.PathRound(), cf)
	end
	for index, cf in ipairs(town.parkingSlots) do
		local slot = Kit.part(
			root,
			"Slot",
			town.parkingSizes[index] or WorldPlan.ParkingSlotSize,
			cf,
			roblox.Color3.fromRGB(186, 168, 140),
			roblox.Enum.Material.Slate
		)
		BuildingArt.ParkingBay(slot, index)
	end
	-- The biome signs where the roads arrive, saying what MapBuilder's say.
	for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
		place(BuildingArt.Signpost(sign.text), sign.cframe)
	end
	-- The open country's scenery (WLD-01), as MapBuilder's "5. The scenery" builds it.
	for _, spot in ipairs(WorldPlan.Scenery()) do
		for _, item in ipairs(spot.items) do
			local model
			if item.builder == "Fence" then
				model = BuildingArt.Fence(item.size)
			elseif item.builder == "LogPile" or item.builder == "Haybale" then
				model = BuildingArt.Prop(item.builder, item.seed)
			else
				model = PropArt.SetPiece(item.builder, item.seed)
			end
			if model then
				place(model, item.cframe)
			end
		end
	end

	-- The landscape's landmarks (STY-*), as MapBuilder's "5. The landmarks" builds them.
	World.landmarks(ctx, root)

	-- The forest ring's filler (FOR-02), when asked for: every tree of it.
	if opts and opts.forest then
		World.forest(ctx, root)
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
			if opts and opts.v2 then
				sectionTree("lumenwood", pos)
			else
				place(TreeArt.Build(WoodData.Get("lumenwood"), i, 1), CF.new(pos))
			end
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

	-- The backdrop beyond the walls (WLD-02, WLD-09), as MapBuilder builds it.
	World.backdrop(ctx, root)

	return {
		root = root,
		terrain = Common.terrain(ctx, -1500, -1500, 1500, 1500, 8),
		shadowRadius = 700,
		lighting = { fogNear = 1500, fogFar = 7000 },
		fov = 50,
	}
end

return World
