--!nocheck
-- T414e: a shop box beside the item it holds. Before T414e the box is a dark shell with glass windows
-- and the item inside; after it, taped kraft cardboard with the item standing next to it.
-- 1 the row, front three-quarter, 2 the axe box and its axe close, 3 top-down.
local Common = require("./_common")

local ITEMS = {
	{ "Axe", "SteelAxe", "Steel Axe" },
	{ "Gear", "Lantern", "Lantern" },
	{ "Sawmill", "Millmaster100", "Millmaster 100" },
}

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BoxArt = ctx.art("BoxArt")
		local ItemModel = ctx.art("ItemModel")
		local ItemBox = ctx.shared("ItemBox")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 120, C3.fromRGB(196, 170, 130))
		local x = -6
		local firstX
		for i, row in ipairs(ITEMS) do
			local size = ItemBox.Size(row[1], row[2])
			local model = roblox.Instance.new("Model")
			model.Name = row[2]
			local body = Kit.part(
				model,
				"Box",
				size,
				CF.new(x + size.X / 2, size.Y / 2, 0),
				C3.fromRGB(34, 36, 41),
				roblox.Enum.Material.SmoothPlastic
			)
			body.CanCollide = false
			BoxArt.Dress(model, body, { name = row[3], kind = row[1], itemId = row[2], price = 120 })
			model.Parent = root
			-- The item itself, on the ground beside its box.
			local display = ItemModel.Get(row[1], row[2])
			local holder = roblox.Instance.new("Model")
			holder.Name = row[2] .. "Item"
			local inner = display.extent
			ItemModel.Place(display, holder, CF.new(x + size.X / 2, inner.Y / 2, -size.Z / 2 - inner.Z / 2 - 1.2), 1)
			holder.Parent = root
			if i == 1 then
				firstX = x + size.X / 2
			end
			x += size.X + 4
		end
		return {
			root = root,
			fov = 50,
			cameras = {
				{ pos = { 4, 7, -22 }, target = { 4, 1.5, -2 }, label = "the row, three-quarter" },
				{
					pos = { firstX + 3, 3.5, -9 },
					target = { firstX, 0.9, -2 },
					label = "the axe box and its axe",
					fov = 45,
				},
				{ pos = { 4, 30, -3 }, target = { 4, 0, -3 }, label = "top-down", fov = 50 },
			},
		}
	end,
}
