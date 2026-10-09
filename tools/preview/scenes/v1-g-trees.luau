--!nocheck
-- Lane G trees, the live look: TreeGen skeletons dressed by
-- TreeArt.FromSkeleton (what players chop). One of each wood, readable
-- near 50 studs, plus night views of the glowing woods.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local TreeGen = ctx.shared("TreeGen")
		local WoodData = ctx.shared("WoodData")
		local root = roblox.Instance.new("Model")
		local woods = WoodData.All()
		local gap = 36
		local width = (#woods - 1) * gap
		Common.ground(ctx, root, width + 80, nil, V3.new(width / 2, -0.5, 8))

		local function label(text, at)
			local sign =
				Kit.part(root, "Label", V3.new(8, 1.6, 0.3), CF.new(at), C3.fromRGB(110, 74, 44), Enum.Material.Wood)
			Kit.signText(sign, text, C3.fromRGB(250, 240, 220), { Enum.NormalId.Front })
		end

		local cams = {}
		local function cam(pos, target, text, extra)
			local c = { pos = pos, target = target, label = text }
			for k, v in pairs(extra or {}) do
				c[k] = v
			end
			table.insert(cams, c)
		end

		for i, def in ipairs(woods) do
			local x = (i - 1) * gap
			local skel = TreeGen.Skeleton(def.id, 1, 1)
			local tree = TreeArt.FromSkeleton(def, skel)
			Kit.placeAt(tree, CF.new(x, 0, 0))
			tree.Parent = root
			label(def.displayName, V3.new(x, 0.9, -14))
			cam({ x, 8, -52 }, { x, 12, 0 }, def.id .. " at 50", { fov = 38 })
		end

		local mid = width / 2
		table.insert(cams, 1, { pos = { mid, 28, -150 }, target = { mid, 14, 0 }, label = "lineup", fov = 50 })

		-- Glowing woods, a second row, shot at night.
		local nightIds = { "lanternwood", "emberwood", "phantomwood", "lumenwood" }
		for i, id in ipairs(nightIds) do
			local def = WoodData.Get(id)
			local x = (i - 1) * gap
			local skel = TreeGen.Skeleton(def.id, 2, 1)
			local tree = TreeArt.FromSkeleton(def, skel)
			Kit.placeAt(tree, CF.new(x, 0, 40))
			tree.Parent = root
			cam({ x, 10, -8 }, { x, 12, 40 }, id .. " night", { fov = 40, night = true })
		end

		return {
			root = root,
			shadowRadius = 220,
			cameras = cams,
		}
	end,
}
