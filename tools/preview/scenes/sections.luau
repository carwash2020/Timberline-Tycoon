--!nocheck
-- The v2 section trees (V2_PLAN.md §3j), built the way the game will
-- build them: Shared/TreeGen skeletons dressed by TreeArt.FromSkeleton.
-- A 5-stud figure (CharacterArt) stands by them for scale. Views:
--   1  every wood mature, eye level         2  the same from 50+ studs
--   3  small / normal / large: oak, pine, maple
--   4  growth: sapling, 0.25, 0.5, 0.75, 1 (oak, pine)
--   5  Elders: oak, pine, frostwood         6  a felled oak, its stub, cut faces, a notch
--   7  bucked logs on each truck tier's bed (V2_PLAN §4c sizes)
--   8  a Starter Forest patch from the real WorldPlan spots, eye level
--   9  night: emberwood, gloamwood, lumenwood glowing
--  10  every wood at 3 seeds                11  every wood at 3 growth stages
--  12  before / after: today's tree beside the new one, per wood
--  13  a cut face and a notch, close up    14-16  close-ups of the line-up
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local CharacterArt = ctx.art("CharacterArt")
		local TreeGen = ctx.shared("TreeGen")
		local SectionLogic = ctx.shared("SectionLogic")
		local TreeLogic = ctx.shared("TreeLogic")
		local WoodData = ctx.shared("WoodData")
		local ForestData = ctx.shared("ForestData")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 4800, nil, V3.new(200, -0.5, 1500))

		local function place(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
			return model
		end
		local function figure(at, turn)
			local fig = CharacterArt.Build({
				name = "Dummy",
				skin = C3.fromHex("#E8B994"),
				shirt = C3.fromHex("#B8382E"),
				pants = C3.fromHex("#3D5A8C"),
				hair = C3.fromHex("#5A3A22"),
				hat = "cap",
				hatColor = C3.fromHex("#4C7A3E"),
				tag = false,
			})
			return place(fig, CF.new(at) * CF.Angles(0, turn or 0, 0))
		end
		local function tree(def, seed, scale, at, opts)
			local skel = TreeGen.Skeleton(def.id, seed, scale, opts)
			return place(TreeArt.FromSkeleton(def, skel), CF.new(at)), skel
		end
		local function label(text, at)
			local sign =
				Kit.part(root, "Label", V3.new(7, 1.6, 0.3), CF.new(at), C3.fromRGB(110, 74, 44), Enum.Material.Wood)
			Kit.signText(sign, text, C3.fromRGB(250, 240, 220), { Enum.NormalId.Front })
		end

		local woods = WoodData.All()
		local GAP = 46
		local cams = {}
		local function cam(pos, target, text, extra)
			local c = { pos = pos, target = target, label = text }
			for k, v in pairs(extra or {}) do
				c[k] = v
			end
			table.insert(cams, c)
		end

		-- Row A (z = 0): every wood, mature, seed 1, normal size.
		for i, def in ipairs(woods) do
			local x = (i - 1) * GAP
			tree(def, 1, 1, V3.new(x, 0, 0))
			figure(V3.new(x + 5, 0, -6))
			label(def.displayName, V3.new(x, 0.8, -12))
		end
		local mid = (#woods - 1) * GAP / 2
		cam({ mid, 6, -235 }, { mid, 24, 0 }, "1 every wood, eye level", { fov = 62 })
		cam({ mid, 60, -330 }, { mid, 18, 0 }, "2 every wood from afar")

		-- Row B (z = 200): small, normal, large of oak, pine, maple.
		local zB = 300
		for j, id in ipairs({ "oak", "pine", "maple" }) do
			for k, scale in ipairs({ TreeGen.SizeLo, 1, TreeGen.SizeHi }) do
				local x = (j - 1) * 120 + (k - 1) * 38
				tree(WoodData.Get(id), 7, scale, V3.new(x, 0, zB))
				figure(V3.new(x + 4, 0, zB - 6))
			end
		end
		cam({ 120, 8, zB - 170 }, { 120, 22, zB }, "3 small, normal, large", { fov = 62 })

		-- Row C (z = 400): growth of oak and pine.
		local zC = 550
		for j, id in ipairs({ "oak", "pine" }) do
			local def = WoodData.Get(id)
			local base = TreeGen.Skeleton(id, 5, 1)
			local x0 = (j - 1) * 150
			place(TreeArt.Sapling(def, 5, 0.3), CF.new(x0, 0, zC))
			place(TreeArt.Sapling(def, 5, 1), CF.new(x0 + 12, 0, zC))
			for k, s in ipairs(TreeGen.Stages) do
				local x = x0 + 12 + k * (if id == "pine" then 24 else 26)
				place(TreeArt.FromSkeleton(def, TreeGen.AtStage(base, s)), CF.new(x, 0, zC))
			end
			figure(V3.new(x0 + 5, 0, zC - 5))
		end
		cam({ 130, 7, zC - 130 }, { 130, 16, zC }, "4 growth: sapling to mature", { fov = 62 })

		-- Row D (z = 600): Elders with a figure.
		local zD = 800
		for j, id in ipairs({ "oak", "pine", "frostwood" }) do
			local x = (j - 1) * 70
			tree(WoodData.Get(id), 3, ForestData.Elder.scale, V3.new(x, 0, zD), { elder = true })
			figure(V3.new(x + 6, 0, zD - 8))
		end
		cam({ 70, 8, zD - 190 }, { 70, 38, zD }, "5 Elders", { fov = 62 })

		-- Row E (z = 800): a felled oak with its stub, cut faces and a notch.
		local zE = 1050
		do
			local def = WoodData.Get("oak")
			local skel = TreeGen.Skeleton("oak", 11, 1)
			local h = 1.4
			local low, high = SectionLogic.SplitSection(skel.sections[1], h, #skel.sections + 1)
			-- The stub: section 1 cut at h, its flares kept.
			local stubSkel = table.clone(skel)
			local stubSections = table.clone(skel.sections)
			stubSections[1] = {
				id = 1,
				children = {},
				depth = 0,
				cf = low.cf,
				length = low.length,
				thickness = low.thickness,
				dress = skel.sections[1].dress,
			}
			stubSkel.sections = stubSections
			local stub = TreeArt.FromSkeleton(def, stubSkel, { only = { [1] = true } })
			place(stub, CF.new(0, 0, zE))
			TreeArt.CutFace(def, stub.PrimaryPart, true)
			-- The felled piece: the upper part and everything above, lying down
			-- along +X from the stub (rotated about the cut).
			-- The high half stands in for section 1 (without the flares, which
			-- stay on the stub); everything above rides along.
			local pieceSections = table.clone(skel.sections)
			pieceSections[1] = {
				id = 1,
				children = high.children,
				depth = 0,
				cf = high.cf,
				length = high.length,
				thickness = high.thickness,
				dress = {},
			}
			local pieceSkel = table.clone(skel)
			pieceSkel.sections = pieceSections
			local piece = TreeArt.FromSkeleton(def, pieceSkel)
			local t = skel.sections[1].thickness
			local fallCf = CF.new(2.2, t / 2 + 0.6, zE) * CF.Angles(0, 0, -math.rad(84)) * CF.new(0, -h, 0)
			Kit.placeAt(piece, fallCf)
			piece.Parent = root
			TreeArt.CutFace(def, piece.PrimaryPart, false)
			-- A half-done notch on the fallen trunk, one on the stub's neighbour.
			local trunk2
			for _, p in ipairs(piece:GetChildren()) do
				if p.Name == "Section" and p:GetAttribute("Section") == 2 then
					trunk2 = p
				end
			end
			if trunk2 then
				local req = SectionLogic.Required(def.v2.hardness, trunk2.Size.X, trunk2.Size.Z)
				TreeArt.Notch(def, trunk2, trunk2.Size.Y * 0.5, V3.new(0, 1, -0.2), req * 0.5, req)
			end
			figure(V3.new(-3, 0, zE + 4), 0.6)
			-- A standing oak with a notch half way through, for comparison.
			local standing = tree(def, 12, 1, V3.new(-40, 0, zE))
			local s1 = standing.PrimaryPart
			local req = SectionLogic.Required(def.v2.hardness, s1.Size.X, s1.Size.Z)
			TreeArt.Notch(def, s1, 1.3, V3.new(0, 0, -1), req * 0.5, req)
			figure(V3.new(-37, 0, zE - 5), -0.4)
		end
		cam({ -10, 9, zE - 40 }, { 4, 3, zE }, "6 a felled oak: stub, cut faces, notches", { fov = 60 })

		-- Row F (z = 1000): bucked logs on each truck tier's bed (§4c targets).
		local zF = 1250
		do
			local beds = {
				{ "Rustbucket", 10, 5.6, 1.4, 3.0, "oak", 9 },
				{ "Pickup", 12, 6.0, 1.6, 3.1, "birch", 11 },
				{ "Flatbed", 18, 6.8, 2.5, 3.3, "pine", 17 },
				{ "Logging Rig", 26, 7.2, 3.2, 4.0, "pine", 25 },
			}
			for j, b in ipairs(beds) do
				local name, L, W, wall, floorY, woodId, logLen = table.unpack(b)
				local x = (j - 1) * 22
				local bedColor = C3.fromRGB(120, 100, 82)
				Kit.part(
					root,
					"Bed",
					V3.new(W, 0.4, L),
					CF.new(x, floorY - 0.2, zF),
					bedColor,
					Enum.Material.WoodPlanks
				)
				for _, sx in ipairs({ -1, 1 }) do
					Kit.part(
						root,
						"Wall",
						V3.new(0.25, wall, L),
						CF.new(x + sx * (W / 2 - 0.12), floorY + wall / 2, zF),
						C3.fromRGB(70, 70, 76),
						Enum.Material.Metal
					)
				end
				label(name, V3.new(x, 0.8, zF - L / 2 - 4))
				-- Real trunk pieces: the wood's base thickness, bucked to fit.
				local def = WoodData.Get(woodId)
				local skel = TreeGen.Skeleton(woodId, 2, 1)
				local t = skel.sections[1].thickness
				local across = math.max(1, math.floor((W - 0.4) / (t + 0.1)))
				for n = 1, across do
					local fake = {
						woodId = woodId,
						seed = n,
						scale = 1,
						stage = 1,
						elder = false,
						trunkSegments = 1,
						maxDepth = 0,
						height = t,
						width = t,
						stretch = 1,
						sections = {
							{
								id = 1,
								children = {},
								depth = 0,
								cf = CF.identity,
								length = logLen,
								thickness = t,
								dress = {},
							},
						},
					}
					local log = TreeArt.FromSkeleton(def, fake)
					local xOff = -W / 2 + 0.2 + (n - 0.5) * (W - 0.4) / across
					Kit.placeAt(log, CF.new(x + xOff, floorY + t / 2, zF - logLen / 2) * CF.Angles(math.pi / 2, 0, 0))
					log.Parent = root
					TreeArt.CutFace(def, log.PrimaryPart, true)
					TreeArt.CutFace(def, log.PrimaryPart, false)
				end
			end
			figure(V3.new(-8, 0, zF - 4))
		end
		cam({ 33, 26, zF - 48 }, { 33, 2, zF }, "7 bucked logs on each bed", { fov = 60 })

		-- Row G (z = 1300): a patch of the real Starter Forest.
		local zG = 1550
		do
			local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
			local spots = {}
			for _, spot in ipairs(WorldPlan.Trees()) do
				if spot.biome == "starter" then
					table.insert(spots, spot)
				end
			end
			-- The densest 140-stud square: centred on the spot with most neighbours.
			local best, bestN = spots[1], 0
			for _, a in ipairs(spots) do
				local n = 0
				for _, b in ipairs(spots) do
					if math.abs(a.position.X - b.position.X) < 70 and math.abs(a.position.Z - b.position.Z) < 70 then
						n += 1
					end
				end
				if n > bestN then
					best, bestN = a, n
				end
			end
			local c = best.position
			local count = 0
			for _, spot in ipairs(spots) do
				local p = spot.position
				local d = V3.new(p.X - c.X, 0, p.Z - c.Z)
				if math.abs(d.X) < 70 and math.abs(d.Z) < 70 then
					local seed = Kit.seedAt(p.X, p.Z)
					local size = TreeLogic.SizeFor(Kit.rng(seed + 101):next())
					local scale = TreeGen.ScaleFor(size.name)
					local skel = TreeGen.Skeleton(spot.woodId, seed, scale)
					local m = TreeArt.FromSkeleton(WoodData.Get(spot.woodId), skel)
					place(m, CF.new(d.X, 0, zG + d.Z) * CF.Angles(0, Kit.rng(seed + 202):range(0, math.pi * 2), 0))
					count += 1
				end
			end
			figure(V3.new(-7, 0, zG - 66), 0.5)
		end
		cam({ 0, 5.5, zG - 84 }, { 0, 12, zG }, "8 Starter Forest patch, eye level", { fov = 70 })

		-- 9: night glow (row A's ember, gloam and lumen).
		local function xOf(id)
			for i, def in ipairs(woods) do
				if def.id == id then
					return (i - 1) * GAP
				end
			end
			return 0
		end
		local glowMid = (xOf("emberwood") + xOf("lumenwood")) / 2
		cam({ glowMid, 8, -110 }, { glowMid, 20, 0 }, "9 night: ember, gloam, lumen", { fov = 60, night = true })

		-- Row H (z = -250): every wood at 3 more seeds.
		local zH = 2000
		for i, def in ipairs(woods) do
			for k, seed in ipairs({ 2, 3, 4 }) do
				tree(def, seed, 1, V3.new((i - 1) * GAP, 0, zH - (k - 1) * 46))
			end
		end
		cam({ mid, 70, zH + 230 }, { mid, 10, zH - 46 }, "10 every wood at 3 seeds")

		-- Row I (z = -500): every wood at 3 growth stages.
		local zI = 2400
		for i, def in ipairs(woods) do
			local base = TreeGen.Skeleton(def.id, 1, 1)
			for k, s in ipairs({ 0.25, 0.5, 0.75 }) do
				place(TreeArt.FromSkeleton(def, TreeGen.AtStage(base, s)), CF.new((i - 1) * GAP, 0, zI - (k - 1) * 30))
			end
			figure(V3.new((i - 1) * GAP + 4, 0, zI + 6))
		end
		cam({ mid, 40, zI + 150 }, { mid, 6, zI - 30 }, "11 every wood at 3 growth stages")

		-- Row J (z = -800): today's tree beside the new one.
		local zJ = 2700
		for i, def in ipairs(woods) do
			local x = (i - 1) * GAP
			place(TreeArt.Build(def, i * 11, 1), CF.new(x - 10, 0, zJ))
			tree(def, 1, 1, V3.new(x + 9, 0, zJ))
			figure(V3.new(x, 0, zJ - 6))
		end
		cam(
			{ GAP * 1, 7, zJ - 105 },
			{ GAP * 1, 16, zJ },
			"12 before / after: oak, birch, pine (today's on the right)",
			{ fov = 62 }
		)

		-- 13: a cut face and a notch, close up (row E's stub and standing oak).
		cam({ 4.5, 3.6, zE - 5.5 }, { 0, 1.1, zE }, "13 cut face close up", { fov = 50 })

		-- 14-16: closer looks along row A; 17-25: each wood from 50 studs.
		cam({ GAP * 1, 6, -95 }, { GAP * 1, 18, 0 }, "14 oak, birch, pine close", { fov = 60 })
		cam({ GAP * 4, 6, -95 }, { GAP * 4, 18, 0 }, "15 maple, palm, frostwood close", { fov = 60 })
		cam({ GAP * 7, 6, -95 }, { GAP * 7, 18, 0 }, "16 ember, gloam, lumen close", { fov = 60 })
		for i, def in ipairs(woods) do
			local x = (i - 1) * GAP
			local skel = TreeGen.Skeleton(def.id, 1, 1)
			local h = skel.height
			cam(
				{ x - 18, 7, -47 },
				{ x, h * 0.5, 0 },
				string.format("%d %s from 50 studs", 16 + i, def.displayName),
				{ fov = 65 }
			)
		end
		cam({ GAP * 4, 7, zJ - 105 }, { GAP * 4, 16, zJ }, "26 before / after: maple, palm, frostwood", { fov = 62 })
		cam({ GAP * 7, 7, zJ - 105 }, { GAP * 7, 16, zJ }, "27 before / after: ember, gloam, lumen", { fov = 62 })

		-- Row K (z = 3000): Hidden Grain clues on section trees (ForestArt.SectionClue
		-- on the second trunk section), one figure per tree.
		local zK = 3000
		local ForestArt = ctx.art("ForestArt")
		local figures = { "curly", "birdseye", "quilted", "burl", "starfall", "stormgrain" }
		for i, figureId in ipairs(figures) do
			local id = if i % 2 == 1 then "maple" else "oak"
			local def = WoodData.Get(id)
			local m = TreeArt.FromSkeleton(def, TreeGen.Skeleton(id, 20 + i, 1))
			local section = ForestArt.ClueSection(m)
			if section then
				ForestArt.SectionClue(m, section, def, figureId, i)
			end
			place(m, CF.new((i - 1) * 24, 0, zK))
			label(figureId, V3.new((i - 1) * 24, 0.8, zK - 8))
		end
		cam({ 60, 6, zK - 52 }, { 60, 8, zK }, "28 Hidden Grain clues on section trunks", { fov = 62 })

		return {
			root = root,
			shadowRadius = 500,
			cameras = cams,
		}
	end,
}
