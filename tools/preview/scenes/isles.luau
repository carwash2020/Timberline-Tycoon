--!nocheck
-- The Skyroot and the Aether Isles at their real places (WorldPlan.Sky),
-- dressed the way MapBuilder dresses them: isles, bridges, Lumenwood, the
-- Cloud Chutes and their flumes, the Starfall Forge, the gondola stations
-- and cables, the waterfall, cloud banks, lantern posts. Terrain around
-- the Skyroot's foot.

local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local CF, V3, C3 = roblox.CFrame, roblox.Vector3, roblox.Color3
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local BuildingArt = ctx.art("BuildingArt")
		local IsleArt = ctx.art("IsleArt")
		local PropArt = ctx.art("PropArt")
		local WoodData = ctx.shared("WoodData")
		local TreeLogic = ctx.shared("TreeLogic")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local root = roblox.Instance.new("Model")
		local sky = WorldPlan.Sky()

		-- CFrame.lookAt from fromMatrix (Lune 0.10's lookAt is wrong).
		local function lookAt(at, target)
			local look = (target - at).Unit
			local right = look:Cross(V3.yAxis).Unit
			return CF.fromMatrix(at, right, right:Cross(look), -look)
		end

		local function place(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
			return model
		end

		-- The isles relative to the Skyroot's foot, and the gondola's side.
		local rel = { sky.main.center - sky.root }
		for _, isle in ipairs(sky.isles) do
			table.insert(rel, isle.center - sky.root)
		end
		place(IsleArt.Skyroot(sky.trunkHeight, rel, sky.main.dir, sky.waterfall.top - sky.root), CF.new(sky.root))

		-- The waterfall's isle: the one whose centre is nearest the fall.
		local fall = sky.waterfall
		local fallIsle, fallDir = nil, nil
		for _, isle in ipairs(sky.isles) do
			local d = V3.new(fall.top.X - isle.center.X, 0, fall.top.Z - isle.center.Z)
			if d.Magnitude <= isle.radius then
				fallIsle, fallDir = isle, d.Unit
			end
		end

		-- Isles, keeping decoration off the bridge ends, chutes and stations.
		local function clearFor(center)
			local out = {}
			for _, b in ipairs(sky.bridges) do
				table.insert(out, b.a - center)
				table.insert(out, b.b - center)
			end
			for _, cf in ipairs(sky.chutes) do
				table.insert(out, cf.Position - center)
			end
			table.insert(out, sky.forge.Position - center)
			table.insert(out, sky.gondolaTop.Position - center)
			return out
		end
		place(IsleArt.Isle(sky.main.radius, 1, { clear = clearFor(sky.main.center) }), CF.new(sky.main.center))
		for i, isle in ipairs(sky.isles) do
			local opts = { clear = clearFor(isle.center) }
			if isle == fallIsle then
				opts.spout = fallDir
			end
			place(IsleArt.Isle(isle.radius, i + 1, opts), CF.new(isle.center))
		end
		for _, bridge in ipairs(sky.bridges) do
			BuildingArt.Bridge(bridge.a, bridge.b, 6).Parent = root
			for k, at in ipairs({ bridge.a, bridge.b }) do
				local along = (bridge.b - bridge.a).Unit * (if k == 1 then 1 else -1)
				local side = V3.new(-along.Z, 0, along.X)
				place(IsleArt.LanternPost(k), lookAt(at - along * 2 + side * 4.2, at + along))
			end
		end
		local lumen = WoodData.Get("lumenwood")
		for _, pos in ipairs(sky.lumenwood) do
			local seed = Kit.seedAt(pos.X, pos.Z)
			local size = TreeLogic.SizeFor(Kit.rng(seed + 101):next())
			place(
				TreeArt.Build(lumen, seed, size.scale),
				CF.new(pos) * CF.Angles(0, Kit.rng(seed + 202):range(0, math.pi * 2), 0)
			)
		end
		for i, pos in ipairs(sky.shards) do
			place(PropArt.Crystal(i, C3.fromRGB(159, 230, 255), 2.2), CF.new(pos))
		end
		-- (Kit.rod / Kit.beam lean on CFrame.lookAt, which Lune gets wrong; these
		-- build the same parts MapBuilder's calls make in Roblox.)
		local function rod(name, a, b, d, color, material)
			local cf = lookAt((a + b) / 2, b) * CF.Angles(0, math.pi / 2, 0)
			return Kit.cylinder(root, name, (b - a).Magnitude, d, cf, color, material)
		end
		local function beam(name, a, b, w, h, color, material)
			return Kit.part(root, name, V3.new(w, h, (b - a).Magnitude), lookAt((a + b) / 2, b), color, material)
		end
		for _, cf in ipairs(sky.chutes) do
			place(BuildingArt.CloudChute(), cf)
			local from = cf.Position + V3.new(0, 1, 0)
			local to = cf.Position + cf.LookVector * 40 - V3.new(0, 60, 0)
			Kit.decor(beam("Flume", from, to, 2.4, 1.2, C3.fromRGB(90, 62, 38), roblox.Enum.Material.WoodPlanks))
		end
		place(BuildingArt.StarfallForge(), sky.forge)
		local top = place(BuildingArt.GondolaStation(), sky.gondolaTop)
		local base = place(BuildingArt.GondolaStation(), sky.gondolaBase)
		rod(
			"GondolaCable",
			base.PrimaryPart.CFrame.Position + V3.new(0, 8.5, 0),
			top.PrimaryPart.CFrame.Position + V3.new(0, 8.5, 0),
			0.4,
			C3.fromRGB(70, 70, 75),
			roblox.Enum.Material.Metal
		)
		-- The cable from town, as far as this scene reaches.
		do
			local town = ctx.load("ReplicatedStorage/Shared/World/WorldPlan").Town().gondola.Position
			local a = top.PrimaryPart.CFrame.Position + V3.new(0, 8.5, 0)
			local b = town + V3.new(0, 9.5, 0)
			rod("GondolaCable", a, a:Lerp(b, 0.45), 0.4, C3.fromRGB(70, 70, 75), roblox.Enum.Material.Metal)
		end

		-- The waterfall, from the isle's rim down to the river's spring.
		if fallIsle then
			local lip = fallIsle.center + fallDir * (fallIsle.radius + 1) - V3.new(0, 0.4, 0)
			place(IsleArt.Waterfall(lip.Y - fall.bottom.Y, 10), lookAt(lip, lip + fallDir))
		end

		-- Cloud banks drifting under and between the isles.
		for i, spot in ipairs(IsleArt.CloudSpots(rel, sky.trunkHeight, 99, sky.main.dir)) do
			place(IsleArt.CloudBank(spot.size, i), CF.new(sky.root) * spot.cframe)
		end

		-- People for scale (about 5 studs tall).
		local function person(at)
			Kit.part(root, "Person", V3.new(2, 5, 1), CF.new(at + V3.new(0, 2.5, 0)), C3.fromRGB(200, 60, 50))
		end
		person(sky.gondolaBase.Position + V3.new(-8, 0, 6))
		person(sky.main.center + sky.main.dir * 24)

		local r = sky.root
		local town = sky.main.dir
		local side = V3.new(-town.Z, 0, town.X)
		local isle1, isle3 = sky.isles[1].center, sky.isles[3].center
		local fd = fallDir or V3.new(1, 0, 0)
		local fp = V3.new(-fd.Z, 0, fd.X)
		local function off(p, v)
			return { p.X + v.X, p.Y + v.Y, p.Z + v.Z }
		end
		return {
			root = root,
			terrain = Common.terrain(ctx, r.X - 700, r.Z - 700, r.X + 700, r.Z + 700, 10),
			shadowRadius = 900,
			lighting = {
				sunDir = { 0.35, 0.75, -0.55 },
				sunColor = "#fff0cc",
				skyTop = "#86b9ea",
				skyBottom = "#fbe7c2",
				fog = "#efe6d4",
				fogNear = 900,
				fogFar = 5200,
			},
			fov = 55,
			cameras = {
				{
					pos = off(r, town * 300 + side * 60 + V3.new(0, 10, 0)),
					target = off(r, V3.new(0, 360, 0)),
					label = "from the ground, 300 studs out",
				},
				{
					pos = off(r, town * 1200 + V3.new(0, 140, 0)),
					target = off(r, V3.new(0, 400, 0)),
					label = "the landmark from 1200 studs",
				},
				{
					pos = off(sky.main.center, town * 30 + side * 8 + V3.new(0, 5, 0)),
					target = off(isle1, V3.new(0, 4, 0)),
					label = "standing on the main isle",
				},
				{
					pos = off(isle3, fd * 170 - fp * 210 - V3.new(0, 40, 0)),
					target = off(isle3, fd * 40 - V3.new(0, 110, 0)),
					label = "the waterfall isle",
				},
				{
					pos = off(r, town * 105 + side * 12 + V3.new(0, 5, 0)),
					target = off(r, V3.new(0, 170, 0)),
					label = "at the foot, by the gondola",
				},
				{
					pos = off(r, town * 260 - side * 140 + V3.new(0, 560, 0)),
					target = off(r, V3.new(0, 640, 0)),
					label = "under the isles",
				},
				{
					pos = off(r, -town * 520 + V3.new(0, 900, 0)),
					target = off(r, V3.new(0, 650, 0)),
					label = "from above",
				},
				{
					pos = off(isle1, V3.new(40, 4, -30)),
					target = off(sky.main.center, V3.new(0, 4, 0)),
					label = "an outer isle, looking back",
				},
				{
					pos = off(sky.isles[2].center, sky.isles[2].dir * 130 - V3.new(0, 45, 0)),
					target = off(sky.isles[2].center, V3.new(0, -25, 0)),
					label = "an isle's underside: roots, crystals, drifting rocks",
				},
			},
		}
	end,
}
