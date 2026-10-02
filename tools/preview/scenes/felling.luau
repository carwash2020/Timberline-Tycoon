--!nocheck
-- A felling in the v2 loop (V2_PLAN.md M1.3), moment by moment, built the
-- way SectionTrees and WoodService build it: an oak cut at knee height by
-- a 5-stud figure (CharacterArt), left to right along +X:
--   1  standing, the notch half through on the face toward you
--   2  cut through: the stub with its cut face, the trunk tipped 4 degrees
--      over the far edge of the cut (WoodService.FellTilt)
--   3  half way down, 4  landed with its crown, 5  its leaves dropped
--      (LeafDropSec) and pooled leaves fluttering down,
--   6  bucked: the trunk cut in two (cut faces on both ends),
--      beside the stub.
-- Views: 1 the whole sequence, 2 the notch close up, 3 landed and bare,
-- 4 the bucked pieces close up.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local CharacterArt = ctx.art("CharacterArt")
		local TreeGen = ctx.shared("TreeGen")
		local SectionLogic = ctx.shared("SectionLogic")
		local WoodData = ctx.shared("WoodData")
		local Common = require("./_common")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 600, nil, V3.new(110, -0.5, 0))

		local def = WoodData.Get("oak")
		local SEED, H, TILT = 11, 1.4, math.rad(4)
		local GAP = 44

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
			Kit.placeAt(fig, CF.new(at) * CF.Angles(0, turn or 0, 0))
			fig.Parent = root
		end

		-- The skeleton split at the cut: the stub's (section 1 cut at H) and
		-- the felled piece's (the rest, section 1's top half standing in).
		local skel = TreeGen.Skeleton("oak", SEED, 1)
		local newId = #skel.sections + 1
		local low, high = SectionLogic.SplitSection(skel.sections[1], H, newId)
		local function withSections(changed)
			local copy = table.clone(skel)
			local list = table.clone(skel.sections)
			for id, sec in pairs(changed) do
				list[id] = sec
			end
			copy.sections = list
			return copy
		end
		local stubSkel = withSections({
			[1] = {
				id = 1,
				children = {},
				depth = 0,
				cf = low.cf,
				length = low.length,
				thickness = low.thickness,
				dress = skel.sections[1].dress,
			},
		})
		local pieceSkel = withSections({
			[1] = {
				id = 1,
				children = high.children,
				depth = 0,
				cf = high.cf,
				length = high.length,
				thickness = high.thickness,
				dress = {},
			},
		})
		local pivotLocal = V3.new(0, H, 0) -- the cut's centre, in the tree's space
		local dir = V3.new(1, 0, 0) -- it falls along +X, away from the cutter at -X
		local axis = V3.new(0, 1, 0):Cross(dir)

		local function stub(x)
			local m = TreeArt.FromSkeleton(def, stubSkel, { only = { [1] = true } })
			Kit.placeAt(m, CF.new(x, 0, 0))
			m.Parent = root
			TreeArt.CutFace(def, m.PrimaryPart, true)
			return m
		end

		-- The felled piece turned `angle` about the far edge of its cut.
		local function piece(x, angle, leafless)
			local m = TreeArt.FromSkeleton(def, pieceSkel)
			Kit.placeAt(m, CF.new(x, 0, 0))
			local edge = V3.new(x, 0, 0) + pivotLocal + dir * (high.thickness / 2)
			local turn = CF.new(edge) * CF.fromAxisAngle(axis, angle) * CF.new(-edge)
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.CFrame = turn * d.CFrame
				end
			end
			m.Parent = root
			TreeArt.CutFace(def, m.PrimaryPart, false)
			if leafless then
				for _, c in ipairs(m:GetChildren()) do
					if c.Name == "Leaves" or (c:IsA("Model") and c.Name == "Tier") then
						c:Destroy()
					end
				end
			end
			return m
		end

		-- 1: standing, notch half through, the cutter at its -X side.
		local standing = TreeArt.FromSkeleton(def, skel)
		Kit.placeAt(standing, CF.new(0, 0, 0))
		standing.Parent = root
		local s1 = standing.PrimaryPart
		local req = SectionLogic.Required(def.v2.hardness, s1.Size.X, s1.Size.Z)
		TreeArt.Notch(def, s1, H, V3.new(-1, 0, 0), req * 0.5, req)
		figure(V3.new(-3.2, 0, 0.6), -math.pi / 2)

		-- 2-5: the fall.
		local angles = { TILT, math.rad(45), math.rad(86), math.rad(86) }
		for k, angle in ipairs(angles) do
			local x = k * GAP
			stub(x)
			piece(x, angle, k == 4)
			figure(V3.new(x - 3.2, 0, 0.6), -math.pi / 2)
		end
		-- 5: a few pooled leaves fluttering down over the bare crown.
		local leafColors = {}
		for _, h in ipairs(def.v2.shape.leafColors) do
			table.insert(leafColors, C3.fromHex(h))
		end
		local rng = Kit.rng(5)
		for i = 1, 14 do
			local at = V3.new(4 * GAP + 8 + rng:range(0, 16), rng:range(1, 7), rng:range(-6, 6))
			local leaf = Kit.wedge(
				root,
				"FallingLeaf",
				V3.new(0.08, 0.55, 0.75),
				CF.new(at) * CF.Angles(rng:range(-1, 1), rng:range(0, 6), math.pi / 2 + rng:range(-0.6, 0.6)),
				leafColors[(i - 1) % #leafColors + 1],
				roblox.Enum.Material.SmoothPlastic
			)
			Kit.decor(leaf, false)
		end

		-- 6: bucked. The trunk's second section cut in half (two pieces, a
		-- cut face each side) and the lowest limb cut where it joins.
		do
			local x = 5 * GAP
			stub(x)
			local id2 = 2
			local s2 = pieceSkel.sections[id2]
			local graph = {}
			for _, sec in ipairs(pieceSkel.sections) do
				graph[sec.id] = sec
			end
			local cutId = #pieceSkel.sections + 1
			local a, b = SectionLogic.SplitGraph(graph, id2, s2.length / 2, cutId)
			local lo, hi = SectionLogic.SplitSection(s2, s2.length / 2, cutId)
			local sections = table.clone(pieceSkel.sections)
			sections[id2] = {
				id = id2,
				parent = s2.parent,
				children = {},
				depth = s2.depth,
				cf = lo.cf,
				length = lo.length,
				thickness = lo.thickness,
				dress = {},
			}
			sections[cutId] = {
				id = cutId,
				children = hi.children,
				depth = s2.depth,
				cf = hi.cf,
				length = hi.length,
				thickness = hi.thickness,
				dress = s2.dress,
			}
			local bucked = table.clone(pieceSkel)
			bucked.sections = sections
			local function only(set)
				local o = {}
				for id in pairs(set) do
					o[id] = true
				end
				return o
			end
			for k, side in ipairs({ a, b }) do
				local m = TreeArt.FromSkeleton(def, bucked, { only = only(side) })
				Kit.placeAt(m, CF.new(x, 0, 0))
				local edge = V3.new(x, 0, 0) + pivotLocal + dir * (high.thickness / 2)
				-- Lying down; the far piece slid on a little after the cut.
				local turn = CF.new(dir * (if k == 2 then 1.6 else 0))
					* CF.new(edge)
					* CF.fromAxisAngle(axis, math.rad(88))
					* CF.new(-edge)
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") then
						d.CFrame = turn * d.CFrame
					end
				end
				for _, c in ipairs(m:GetChildren()) do
					if c.Name == "Leaves" then
						c:Destroy()
					end
				end
				m.Parent = root
				for _, p in ipairs(m:GetChildren()) do
					if p.Name == "Section" then
						local id = p:GetAttribute("Section")
						if id == id2 then
							TreeArt.CutFace(def, p, true)
						elseif id == cutId then
							TreeArt.CutFace(def, p, false)
						elseif id == 1 then
							TreeArt.CutFace(def, p, false)
						end
					end
				end
			end
			figure(V3.new(x + 9, 0, 3), math.pi)
		end

		local mid = 2.5 * GAP
		return {
			root = root,
			shadowRadius = 400,
			cameras = {
				{ pos = { mid, 30, -175 }, target = { mid, 6, 0 }, label = "1 a felling, moment by moment", fov = 50 },
				{ pos = { -7, 3.2, -6 }, target = { 0, 1.6, 0 }, label = "2 the notch half through", fov = 55 },
				{
					pos = { 4 * GAP + 6, 9, -26 },
					target = { 4 * GAP + 14, 1.5, 0 },
					label = "3 landed, its leaves dropped",
					fov = 60,
				},
				{
					pos = { 5 * GAP + 4, 7, -20 },
					target = { 5 * GAP + 10, 1.2, 0 },
					label = "4 bucked in two",
					fov = 60,
				},
			},
		}
	end,
}
