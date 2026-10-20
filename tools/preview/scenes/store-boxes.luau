--!nocheck
-- Store boxes built all round (Shared/Art/BoxArt: floor, back wall, far wall, aisle pane, glass
-- front and top, rim, name strip, price tag plate, brass plate) with the real item inside
-- (ItemModel, StoreModelSlots). A row of boxes on a shop table, each with its aisle pane on the
-- east (+X) side. Views: 1 the row at front three-quarter (the contact sheet), then for the Switch
-- Belt and the Wood Detector: from the top, the front, the aisle side.
--   bash tools/preview/shoot.sh store-boxes
local ITEMS = {
	{ "Axe", "SteelAxe", "Steel Axe" },
	{ "Machine", "SwitchBelt", "Switch Belt" },
	{ "Machine", "WoodDetector", "Wood Detector" },
	{ "Machine", "TiltedBelt", "Tilted Belt" },
	{ "Machine", "ConveyorStraight", "Straight Belt" },
	{ "Machine", "SkyBin", "Sky Bin" },
	{ "Gear", "Lantern", "Lantern" },
	{ "Blueprint", "Barrel", "Barrel" },
}

return {
	ITEMS = ITEMS,
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local BoxArt = ctx.art("BoxArt")
		local ItemBox = ctx.shared("ItemBox")
		local StoreStock = ctx.shared("StoreStock")
		local Common = require("./_common")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 200, C3.fromRGB(196, 170, 130))

		local TOP = StoreStock.TableTop
		local GAP = 1.6
		local sizes = {}
		local total = 0
		for i, row in ipairs(ITEMS) do
			sizes[i] = ItemBox.Size(row[1], row[2])
			total += sizes[i].X + GAP
		end
		local tableW = total + 1.5
		Kit.part(
			root,
			"TableTop",
			V3.new(tableW, 0.4, 7),
			CF.new(0, TOP - 0.2, 0),
			C3.fromHex("#7A5230"),
			Enum.Material.Wood
		)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				Kit.part(
					root,
					"TableLeg",
					V3.new(0.5, TOP - 0.4, 0.5),
					CF.new(sx * (tableW / 2 - 0.5), (TOP - 0.4) / 2, sz * 3),
					C3.fromHex("#5E3F26"),
					Enum.Material.Wood
				)
			end
		end
		Kit.part(
			root,
			"Wall",
			V3.new(tableW + 14, 14, 0.5),
			CF.new(0, 7, 4.4),
			C3.fromHex("#E6D3A8"),
			Enum.Material.SmoothPlastic
		)

		local cursor = -total / 2 + 0.8
		local centres = {}
		for i, row in ipairs(ITEMS) do
			local size = sizes[i]
			local x = cursor + size.X / 2
			cursor += size.X + GAP
			local model = roblox.Instance.new("Model")
			model.Name = row[2]
			local body = Kit.part(
				model,
				"Box",
				size,
				CF.new(x, TOP + size.Y / 2, 0),
				C3.fromRGB(34, 36, 41),
				Enum.Material.SmoothPlastic
			)
			body.CanCollide = false
			BoxArt.Dress(model, body, { name = row[3], kind = row[1], itemId = row[2], side = "Right" })
			model.Parent = root
			centres[row[2]] = { x = x, y = TOP + size.Y / 2, size = size }
		end

		local cameras = {}
		table.insert(cameras, {
			pos = { total * 0.12, TOP + 8, -(total * 0.78) },
			target = { 0, TOP + 1.2, 0 },
			fov = 56,
			label = "the row, front three-quarter",
		})
		for _, id in ipairs({ "SwitchBelt", "WoodDetector" }) do
			local c = centres[id]
			local reach = math.max(c.size.X, c.size.Y, c.size.Z) * 1.5 + 2
			table.insert(cameras, {
				pos = { c.x, c.y + reach, -0.01 - c.size.Z * 0.35 },
				target = { c.x, c.y, 0 },
				fov = 44,
				label = id .. " from the top",
			})
			table.insert(cameras, {
				pos = { c.x, c.y + c.size.Y * 0.2, -reach },
				target = { c.x, c.y, 0 },
				fov = 44,
				label = id .. " front",
			})
			table.insert(cameras, {
				pos = { c.x + reach, c.y + c.size.Y * 0.2, -c.size.Z * 0.2 },
				target = { c.x, c.y, 0 },
				fov = 44,
				label = id .. " aisle side",
			})
		end
		return { root = root, cameras = cameras }
	end,
}
