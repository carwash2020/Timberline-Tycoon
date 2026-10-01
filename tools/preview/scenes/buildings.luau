--!nocheck
-- Every BuildingArt builder on its own, on a grid with labels, with a close
-- camera on each (the town scene shows them in place).
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 520, C3.fromRGB(116, 164, 84), V3.new(110, -0.5, 80))

		local cameras = {}
		local function label(text, x, z)
			local sign = Kit.part(root, "Label", V3.new(7, 1.3, 0.3), CF.new(x, 0.65, z), C3.fromRGB(120, 80, 50))
			Kit.signText(sign, text, C3.fromRGB(250, 240, 220), { roblox.Enum.NormalId.Front })
		end
		local function place(model, x, z, text, labelZ, cam)
			Kit.placeAt(model, CF.new(x, 0, z))
			model.Parent = root
			label(text, x, z + labelZ)
			if cam then
				table.insert(cameras, {
					pos = { x + cam[1], cam[2], z + cam[3] },
					target = { x, cam[4], z },
					label = text,
				})
			end
		end

		-- Row 1: the sawmill and the three shops.
		place(BuildingArt.Sawmill(), 0, 0, "Sawmill", -18, { -26, 18, -46, 8 })
		place(
			BuildingArt.Shop("ToolShed", "TOOL SHED", C3.fromRGB(150, 62, 44)),
			55,
			0,
			"ToolShed",
			-14,
			{ -13, 9, -26, 5 }
		)
		place(
			BuildingArt.Shop("Dealership", "DEALERSHIP", C3.fromRGB(47, 109, 181)),
			85,
			0,
			"Dealership",
			-14,
			{ 13, 9, -26, 5 }
		)
		place(
			BuildingArt.Shop("HearthAndHome", "HEARTH & HOME", C3.fromRGB(122, 90, 60)),
			115,
			0,
			"HearthAndHome",
			-14,
			{ -12, 8, -26, 5 }
		)

		-- Row 2: the station, Murph's camp, the isle pieces, street furniture.
		place(BuildingArt.GondolaStation(), 0, 60, "GondolaStation", -11, { -14, 10, -20, 6 })
		place(BuildingArt.Campsite(), 30, 60, "Campsite", -7, { -9, 7, -14, 2 })
		place(BuildingArt.CloudChute(), 55, 60, "CloudChute", -6, { -12, 7, -10, 1 })
		place(BuildingArt.StarfallForge(), 78, 60, "StarfallForge", -6, { -9, 6, -10, 3 })
		place(BuildingArt.Signpost("TO THE WOODS\nHills 400\nSnow 1200"), 100, 60, "Signpost", -4, { -6, 7, -12, 6 })
		place(BuildingArt.LampPost(), 114, 60, "LampPost", -4, { -6, 7, -9, 6 })
		place(BuildingArt.Fence(18), 132, 60, "Fence", -4, { -6, 5, -12, 2 })
		place(BuildingArt.Campfire(), 155, 60, "Campfire", -4, { -3, 4, -5, 1 })
		place(BuildingArt.SkyBin(), 170, 60, "SkyBin", -5, { -7, 7, -10, 4 })

		-- Row 3: the sell pad, every prop, a bridge between two rocks.
		place(BuildingArt.SellPad(24, 18), 0, 110, "SellPad", -12, { 0, 16, -20, 0 })
		local names = BuildingArt.PropNames()
		for i, name in ipairs(names) do
			local x = 22 + (i - 1) * 11
			place(BuildingArt.Prop(name, i * 7), x, 110, name, -5, nil)
		end
		table.insert(cameras, { pos = { 36, 12, 84 }, target = { 50, 3, 110 }, label = "props 1" })
		table.insert(cameras, { pos = { 92, 12, 84 }, target = { 106, 3, 110 }, label = "props 2" })
		table.insert(cameras, { pos = { 146, 14, 84 }, target = { 160, 4, 110 }, label = "props 3" })
		for _, z in ipairs({ 140, 178 }) do
			Kit.part(
				root,
				"Cliff",
				V3.new(14, 8, 8),
				CF.new(20, 4, z),
				C3.fromRGB(150, 140, 125),
				roblox.Enum.Material.Slate
			)
		end
		BuildingArt.Bridge(V3.new(20, 8, 144), V3.new(20, 9, 174), 6).Parent = root
		table.insert(cameras, { pos = { 4, 14, 128 }, target = { 20, 7, 160 }, label = "Bridge" })

		table.insert(cameras, 1, { pos = { 60, 70, -90 }, target = { 70, 0, 60 }, label = "overview" })
		return {
			root = root,
			shadowRadius = 220,
			cameras = cameras,
		}
	end,
}
