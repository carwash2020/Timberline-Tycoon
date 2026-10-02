--!nocheck
-- One corner of the world, close up (phase 10, STY-*): the terrain over a
-- rectangle sampled finely (the world scene's 8-stud grid blurs a 14-stud
-- road), with what MapBuilder builds there: the trees, boulders, scenery
-- and road signs whose spot is inside it. A helper (files starting with _
-- aren't scenes): Site.build(ctx, x0, z0, x1, z1, step) returns everything
-- a scene returns but the cameras; Site.eye(ctx, x, z) is a player's eye
-- (5.5 studs over the ground) at (x, z).

local Common = require("./_common")

local Site = {}

function Site.eye(ctx, x, z)
	local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
	local y = math.max(TerrainGen.HeightAt(x, z), TerrainGen.WaterLevelAt(x, z) or -math.huge)
	return { x, y + 5.5, z }
end

function Site.build(ctx, x0, z0, x1, z1, step)
	local roblox = ctx.roblox
	local CF = roblox.CFrame
	local Kit = ctx.art("Kit")
	local TreeArt = ctx.art("TreeArt")
	local BuildingArt = ctx.art("BuildingArt")
	local PropArt = ctx.art("PropArt")
	local WoodData = ctx.shared("WoodData")
	local TreeLogic = ctx.shared("TreeLogic")
	local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
	local root = roblox.Instance.new("Model")

	local margin = 30
	local function inside(p)
		return p.X > x0 - margin and p.X < x1 + margin and p.Z > z0 - margin and p.Z < z1 + margin
	end
	local function place(model, cf)
		Kit.placeAt(model, cf)
		model.Parent = root
		return model
	end

	-- Trees, as TreeService builds them (world.luau does the same).
	for _, spot in ipairs(WorldPlan.Trees()) do
		local p = spot.position
		if inside(p) then
			local seed = Kit.seedAt(p.X, p.Z)
			local size = TreeLogic.SizeFor(Kit.rng(seed + 101):next())
			local tree = TreeArt.Build(WoodData.Get(spot.woodId), seed, size.scale)
			place(tree, CF.new(p) * CF.Angles(0, Kit.rng(seed + 202):range(0, math.pi * 2), 0))
		end
	end
	-- Boulders, as MapBuilder's "5. The boulders" turns them.
	for _, b in ipairs(WorldPlan.Boulders()) do
		if inside(b.position) then
			place(PropArt.Rock(b.size, b.seed), CF.new(b.position) * CF.Angles(0, b.seed % 6, 0))
		end
	end
	for _, sign in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
		if inside(sign.cframe.Position) then
			place(BuildingArt.Signpost(sign.text), sign.cframe)
		end
	end
	for _, spot in ipairs(WorldPlan.Scenery()) do
		if inside(spot.center) then
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
	end

	return {
		root = root,
		terrain = Common.terrain(ctx, x0, z0, x1, z1, step),
		shadowRadius = math.max(x1 - x0, z1 - z0),
		lighting = { fogNear = 600, fogFar = 2500 },
		fov = 70,
	}
end

return Site
