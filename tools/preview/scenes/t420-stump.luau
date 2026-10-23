--!nocheck
-- T420: stumps next to the round trunks they were cut from. PREVIEW ONLY:
-- this tool cannot load the 16 uploaded frustum MeshParts (InsertService),
-- so the stump body here is a stand-in of 14 stacked discs per sleeve between the
-- real radii (StumpLogic.Shape), drawn only so the
-- taper and the colours can be judged. The cap, the ring, the radii, the
-- heights and the weathering colours are the game's own code (TreeArt.StumpDress,
-- StumpLogic). Lit by the viewer's sun and sky with shadows (three.js), not
-- by Roblox: no material textures. Views:
--   1  oak stump, cut 4.2 up              2  pine stump, cut 4.2 up
--   3  oak trunk and its stump together   4  oak stump weathered, 150 s (next to a fresh one)
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local TreeGen = ctx.shared("TreeGen")
		local StumpLogic = ctx.shared("StumpLogic")
		local WoodData = ctx.shared("WoodData")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 500, nil, V3.new(80, -0.5, 0))

		local function segsOf(skel)
			local trunk = {}
			for _, sec in ipairs(skel.sections) do
				if sec.depth < skel.trunkSegments then
					table.insert(trunk, sec)
				end
			end
			table.sort(trunk, function(a, b)
				return a.depth < b.depth
			end)
			local segs = {}
			for _, sec in ipairs(trunk) do
				table.insert(segs, { length = sec.length, thickness = sec.thickness })
			end
			return segs
		end

		-- A stump at `at`: the stand-in body, the game's cap and ring.
		local function stump(woodId, seed, h, at, weather, scale, elder)
			local def = WoodData.Get(woodId)
			local skel = TreeGen.Skeleton(woodId, seed, scale or 1, { elder = elder == true })
			local segs = segsOf(skel)
			local shape = StumpLogic.Shape(segs, h)
			local bark = Kit.vary(TreeArt.Palette(def).bark or def.trunkColor, Kit.rng(1), 0)
			local model = roblox.Instance.new("Model")
			model.Parent = root
			local templates = {}
			for i = 1, #shape.sleeves do
				local template = roblox.Instance.new("MeshPart")
				template.Size = V3.new(2, 2, 2)
				templates[i] = template
			end
			local base = CF.new(at)
			local parts = TreeArt.StumpDress(def, model, base, shape, templates, bark)
			for _, d in ipairs(parts) do
				if d.Name == "StumpMesh" then
					d:Destroy()
				elseif d.Name == "StumpCap" then
					d.Color = StumpLogic.CapColor(d.Color, weather)
				end
			end
			local n = 14
			for _, sleeve in ipairs(shape.sleeves) do
				local length = sleeve.y1 - sleeve.y0
				for i = 1, n do
					local u0, u1 = (i - 1) / n, i / n
					local r = sleeve.baseRadius + (sleeve.topRadius - sleeve.baseRadius) * (u0 + u1) / 2
					local disc = Kit.cylinder(
						model,
						"PreviewStandIn",
						length / n + 0.01,
						r * 2,
						base * CF.new(0, sleeve.y0 + length * (u0 + u1) / 2, 0) * CF.Angles(0, 0, math.pi / 2),
						StumpLogic.BarkColor(bark, weather),
						TreeArt.BarkMaterial(def)
					)
					Kit.decor(disc)
				end
			end
			return shape, skel
		end
		local function label(text, at)
			local sign =
				Kit.part(root, "Label", V3.new(9, 1.6, 0.3), CF.new(at), C3.fromRGB(110, 74, 44), Enum.Material.Wood)
			Kit.signText(sign, text, C3.fromRGB(250, 240, 220), { Enum.NormalId.Front })
		end

		stump("oak", 7, 4.2, V3.new(0, 0, 0), 0)
		label("oak, cut 4.2 up", V3.new(0, 0.8, 5))
		stump("pine", 11, 4.2, V3.new(30, 0, 0), 0)
		label("pine, cut 4.2 up", V3.new(30, 0.8, 5))
		-- Trunk and stump together: the standing oak's trunk, and its stump beside it.
		local def = WoodData.Get("oak")
		local skel = TreeGen.Skeleton("oak", 7, 1, {})
		local tree = TreeArt.FromSkeleton(def, skel)
		Kit.placeAt(tree, CF.new(60, 0, 0))
		tree.Parent = root
		stump("oak", 7, 4.2, V3.new(66, 0, 0), 0)
		label("oak: trunk | stump", V3.new(63, 0.8, 6))
		-- Weathered at 150 s (0.75 weathered), beside a fresh one.
		local w = StumpLogic.Weathering(150)
		stump("oak", 7, 4.2, V3.new(90, 0, 0), 0)
		stump("oak", 7, 4.2, V3.new(96, 0, 0), w)
		label("fresh | 150 s", V3.new(93, 0.8, 5))
		-- A 15 stud cut (large pine): two stacked sleeves, no clamp.
		stump("pine", 7, 15, V3.new(120, 0, 0), 0)
		label("pine, cut 15 up: 2 sleeves", V3.new(120, 0.8, 6))
		-- An Elder (scale 1.7, base radius about 2.49: the R22 set), cut 4.2 up, beside a normal pine.
		stump("pine", 7, 4.2, V3.new(150, 0, 0), 0, 1.7, true)
		stump("pine", 7, 4.2, V3.new(158, 0, 0), 0)
		label("Elder pine (R22) | normal pine (R13)", V3.new(154, 0.8, 6))
		return {
			root = root,
			shadowRadius = 160,
			cameras = {
				{ pos = { 5, 8.5, -9 }, target = { 0, 3.2, 0 }, label = "oak stump, cut 4.2 up (stand-in body)" },
				{ pos = { 35, 8.5, -9 }, target = { 30, 3.2, 0 }, label = "pine stump, cut 4.2 up (stand-in body)" },
				{ pos = { 63, 6, -20 }, target = { 63, 4, 0 }, label = "oak trunk and stump, same taper" },
				{ pos = { 93, 9, -10 }, target = { 93, 3, 0 }, label = "stump at 150 s (right) beside fresh (left)" },
				{
					pos = { 154, 7, -16 },
					target = { 154, 3, 0 },
					label = "Elder pine stump (R22) beside a normal pine (R13), cut 4.2 up (stand-in body)",
				},
				{
					pos = { 128, 12, -18 },
					target = { 120, 7, 0 },
					label = "pine cut 15 up: stacked sleeves (stand-in body)",
				},
			},
		}
	end,
}
