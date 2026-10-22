--!nocheck
-- T420: the stump a felled section tree leaves. Flat-colour preview, not
-- Studio. Back row: today's stump (a straight post, TreeArt.Stump). Front
-- row: the new one (StumpLogic shape from the real trunk, TreeArt.StumpDress),
-- cut 3 studs up; the front-most row is cut 4.2 up. Views:
--   1  before: today's stumps         2  after: the new stumps (3 studs)
--   3  before and after side by side  4  close-up of one new stump (oak)
--   5  the cut at 2.5 up against 4.2 up (taper and end-grain cap)
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local CharacterArt = ctx.art("CharacterArt")
		local TreeGen = ctx.shared("TreeGen")
		local StumpLogic = ctx.shared("StumpLogic")
		local WoodData = ctx.shared("WoodData")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 400, nil, V3.new(60, -0.5, 0))

		local ids = { "oak", "birch", "pine", "maple", "frostwood", "emberwood" }
		local GAP = 12
		local function segsOf(woodId, seed)
			local skel = TreeGen.Skeleton(woodId, seed, 1, {})
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
		local function newStump(def, seed, h, at)
			local shape = StumpLogic.Shape(segsOf(def.id, seed), h)
			local model = roblox.Instance.new("Model")
			TreeArt.StumpDress(def, model, CF.new(at), shape)
			model.Parent = root
		end
		for i, id in ipairs(ids) do
			local def = WoodData.Get(id)
			local x = (i - 1) * GAP
			local old = TreeArt.Stump(def, i, 1)
			Kit.placeAt(old, CF.new(x, 0, 10))
			old.Parent = root
			newStump(def, i, 3, V3.new(x, 0, -4))
			newStump(def, i, 4.2, V3.new(x, 0, -16))
			local sign = Kit.part(
				root,
				"Label",
				V3.new(7, 1.6, 0.3),
				CF.new(x, 1, -24),
				C3.fromRGB(110, 74, 44),
				Enum.Material.Wood
			)
			Kit.signText(sign, def.displayName, C3.fromRGB(250, 240, 220), { Enum.NormalId.Front })
		end
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
		Kit.placeAt(fig, CF.new(-5, 0, -4))
		fig.Parent = root
		local mid = (#ids - 1) * GAP / 2
		return {
			root = root,
			shadowRadius = 120,
			cameras = {
				{ pos = { mid, 9, 36 }, target = { mid, 1, 10 }, label = "before: today's stumps" },
				{ pos = { mid, 9, 12 }, target = { mid, 1, -4 }, label = "after: the new stumps, cut 3 up" },
				{ pos = { mid, 22, 40 }, target = { mid, 0, -2 }, label = "before (back) and after (front)" },
				{ pos = { 4, 5, 6 }, target = { 0, 1.5, -4 }, label = "oak, close up" },
				{ pos = { 6, 6, -6 }, target = { 0, 2, -16 }, label = "oak cut 4.2 up" },
			},
		}
	end,
}
