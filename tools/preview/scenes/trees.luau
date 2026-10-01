--!nocheck
-- Every wood in a row (plus a big variant), with its stump, sapling and log.
local Common = require("./_common")

return {
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
		Kit.part(
			root,
			"Ground",
			V3.new(width + 80, 1, 110),
			CF.new(width / 2, -0.5, 10),
			C3.fromRGB(110, 160, 80),
			roblox.Enum.Material.Grass
		)
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
			local sign = Kit.part(
				root,
				"Label",
				V3.new(8, 2, 0.3),
				CF.new(x, 1.5, -26),
				C3.fromRGB(120, 80, 50),
				roblox.Enum.Material.Wood
			)
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
