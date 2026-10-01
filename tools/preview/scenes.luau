--!nocheck
-- Preview scenes for tools/preview/export.luau. Each scene's build(ctx)
-- returns { root = Instance, cameras = {...}, lighting = {...}?,
-- terrain = {...}? }. ctx.art(name) loads Shared/Art/<name>, ctx.shared(name)
-- a Shared module, ctx.roblox is @lune/roblox.
--
-- cameras: { { pos = {x,y,z}, target = {x,y,z}, label = "..." }, ... }
-- terrain: { x0, z0, x1, z1, step, sample = function(x, z) -> (height,
--   materialName), colors = { [materialName] = "RRGGBB" }, water = y? }

local scenes = {}

local function ground(ctx, root, size, color)
	local roblox = ctx.roblox
	local Kit = ctx.art("Kit")
	Kit.part(
		root,
		"Ground",
		roblox.Vector3.new(size, 1, size),
		roblox.CFrame.new(0, -0.5, 0),
		color or roblox.Color3.fromRGB(110, 160, 80),
		roblox.Enum.Material.Grass
	)
end

scenes.kit = {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local root = roblox.Instance.new("Model")
		ground(ctx, root, 80)
		-- A lone triangle (two wedges) and a faceted cone: if the wedge
		-- geometry were wrong, these would show gaps and spikes.
		Kit.triangle(root, V3.new(-20, 1, 0), V3.new(-12, 1, 0), V3.new(-16, 9, 0), C3.fromRGB(230, 120, 60), nil, 0.2)
		local rng = Kit.rng(7)
		Kit.cone(root, CF.new(-4, 0, 0), 4, 9, 7, function(i)
			return Kit.shade(C3.fromRGB(60, 130, 70), (i % 2) * 0.12)
		end, nil, 0.1)
		Kit.blob(root, "Leaves", CF.new(8, 6, 0), V3.new(7, 6, 7), 6, rng, { C3.fromRGB(110, 170, 70), C3.fromRGB(90, 150, 60) })
		-- A tiny cabin.
		local cabin = CF.new(0, 0, 18)
		Kit.plankWall(root, "Wall", cabin * CF.new(0, 3, -4), 10, 6, 0.6, 6, rng, { C3.fromRGB(140, 95, 60), C3.fromRGB(125, 85, 52) })
		Kit.plankWall(root, "Wall", cabin * CF.new(0, 3, 4), 10, 6, 0.6, 6, rng, { C3.fromRGB(140, 95, 60) })
		Kit.plankWall(root, "Wall", cabin * CF.new(-5, 3, 0) * CF.Angles(0, math.pi / 2, 0), 8, 6, 0.6, 6, rng, { C3.fromRGB(140, 95, 60) })
		Kit.plankWall(root, "Wall", cabin * CF.new(5, 3, 0) * CF.Angles(0, math.pi / 2, 0), 8, 6, 0.6, 6, rng, { C3.fromRGB(140, 95, 60) })
		Kit.gableRoof(root, "Roof", cabin * CF.new(0, 6, 0), 12, 10, 3.5, C3.fromRGB(110, 70, 50), roblox.Enum.Material.WoodPlanks)
		Kit.window(root, cabin * CF.new(2.5, 3.2, -4.4), 2, 2, C3.fromRGB(90, 60, 40), true)
		Kit.lantern(root, cabin * CF.new(-2.5, 4.5, -4.9))
		local sign = Kit.part(root, "Sign", V3.new(6, 2, 0.3), CF.new(0, 4, 10), C3.fromRGB(120, 80, 50), roblox.Enum.Material.Wood)
		Kit.signText(sign, "KIT TEST", C3.fromRGB(250, 240, 220))
		Kit.rock(root, CF.new(14, 0, 10), 3, rng, { C3.fromRGB(130, 128, 120) })
		return {
			root = root,
			cameras = {
				{ pos = { 0, 18, -38 }, target = { 0, 4, 6 }, label = "front" },
				{ pos = { 30, 22, 40 }, target = { 0, 3, 10 }, label = "back" },
			},
		}
	end,
}

-- Every wood in a row (plus a big and small variant of each), with its
-- stump, sapling and log in front: the Field Guide's line-up.
scenes.trees = {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local WoodData = ctx.shared("WoodData")
		local root = roblox.Instance.new("Model")
		local woods = WoodData.All()
		local spacing = 26
		local width = (#woods - 1) * spacing
		Kit.part(root, "Ground", V3.new(width + 80, 1, 110), CF.new(width / 2, -0.5, 10), C3.fromRGB(110, 160, 80), roblox.Enum.Material.Grass)
		for i, def in ipairs(woods) do
			local x = (i - 1) * spacing
			local tree = TreeArt.Build(def, i * 11, 1)
			Kit.placeAt(tree, CF.new(x, 0, 0))
			tree.Parent = root
			local big = TreeArt.Build(def, i * 11 + 3, 1.25)
			Kit.placeAt(big, CF.new(x, 0, 30))
			big.Parent = root
			local stump = TreeArt.Stump(def, i, 1)
			Kit.placeAt(stump, CF.new(x - 5, 0, -14))
			stump.Parent = root
			local sapling = TreeArt.Sapling(def, i)
			Kit.placeAt(sapling, CF.new(x + 5, 0, -14))
			sapling.Parent = root
			local log = TreeArt.Log(def, 3, 1.2)
			log:PivotTo(CF.new(x, 0.6, -20) * CF.Angles(0, 0.3, 0))
			log.Parent = root
			local sign = Kit.part(root, "Label", V3.new(8, 2, 0.3), CF.new(x, 1.5, -26), C3.fromRGB(120, 80, 50), roblox.Enum.Material.Wood)
			Kit.signText(sign, def.displayName, C3.fromRGB(250, 240, 220), { roblox.Enum.NormalId.Front })
		end
		return {
			root = root,
			shadowRadius = 260,
			cameras = {
				{ pos = { width / 2, 40, -150 }, target = { width / 2, 10, 0 }, label = "line-up" },
				{ pos = { -20, 18, -60 }, target = { 40, 10, 0 }, label = "starter woods" },
				{ pos = { 60, 18, -55 }, target = { 100, 10, 0 }, label = "hills + island" },
				{ pos = { 130, 20, -60 }, target = { 170, 11, 0 }, label = "snow + volcano + grove" },
				{ pos = { 170, 24, -50 }, target = { 208, 14, 0 }, label = "lumenwood" },
				{ pos = { 30, 6, -38 }, target = { 40, 1, -18 }, label = "stumps, saplings, logs" },
			},
		}
	end,
}

-- The whole 3,000-stud map: terrain, water, and where everything sits.
local function terrainOf(ctx, x0, z0, x1, z1, step)
	local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
	local colors = {}
	for name, c in pairs(TerrainGen.MaterialColors) do
		colors[name] = c:ToHex()
	end
	local WorldLayout = ctx.load("ReplicatedStorage/Shared/World/WorldLayout")
	return {
		x0 = x0,
		z0 = z0,
		x1 = x1,
		z1 = z1,
		step = step,
		colors = colors,
		water = WorldLayout.LakeLevel,
		waterColor = "#3f9ac2",
		sample = function(x, z)
			return TerrainGen.Sample(x, z)
		end,
	}
end

scenes.terrain = {
	build = function(ctx)
		local roblox = ctx.roblox
		local root = roblox.Instance.new("Model")
		return {
			root = root,
			terrain = terrainOf(ctx, -1500, -1500, 1500, 1500, 12),
			shadowRadius = 1600,
			lighting = { fogNear = 2500, fogFar = 9000 },
			fov = 50,
			cameras = {
				{ pos = { 0, 2600, -1900 }, target = { 0, 0, 100 }, label = "whole map from the south" },
				{ pos = { 0, 3800, 1 }, target = { 0, 0, 0 }, label = "top down" },
				{ pos = { 300, 260, -420 }, target = { 0, 0, 110 }, label = "town + starter forest" },
				{ pos = { -150, 300, 300 }, target = { -500, 20, 300 }, label = "hills + river" },
				{ pos = { 400, 400, 700 }, target = { 1150, 60, 1250 }, label = "volcano" },
				{ pos = { -250, 220, -150 }, target = { -600, 0, -400 }, label = "grove + lake" },
			},
		}
	end,
}

return scenes
