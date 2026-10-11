--!nocheck
-- The Dealership showroom hall (store interior polish). The hall is at the
-- origin with its roof off, the real vehicles on their plinths (DealershipLot,
-- placed the way MapBuilder places them, each behind its packaged box), the
-- keeper at the counter and a person in the aisle. Views: 1 entrance (just
-- inside the door), 2 tier stand (a plinth's T-flag, band and name sign from the
-- aisle), 3 phone (667x375, from the door), 4 night. See _store.luau.
local Store = require("./_store")

return Store.scene({
	kind = "Dealership",
	title = "DEALERSHIP",
	accent = { 47, 109, 181 },
	keeper = "Dale",
	walker = { -56, -1 },
	populate = function(ctx, root, _shop)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BoxArt = ctx.art("BoxArt")
		local DealershipLot = ctx.art("DealershipLot")
		local StoreStock = ctx.shared("StoreStock")
		local hall = DealershipLot.Hall()
		-- The lot sits where MapBuilder puts it, relative to the hall.
		local width, depth = DealershipLot.Size()
		local lot = DealershipLot.Build()
		Kit.placeAt(
			lot,
			CF.new(
				DealershipLot.OriginX + width / 2 - hall.cx,
				DealershipLot.FloorY,
				DealershipLot.OriginZ + depth / 2 - hall.cz
			)
		)
		lot.Parent = root
		-- Each vehicle's box, dressed the way BoxService does.
		for _, d in ipairs(lot:GetDescendants()) do
			if d.Name == "BoxSpot" then
				local kind, id = d:GetAttribute("Category"), d:GetAttribute("ItemId")
				local slot = StoreStock.Vehicle(id)
				local m = roblox.Instance.new("Model")
				local body =
					Kit.part(m, "Box", d.Size, d.CFrame, C3.fromHex(slot.color), roblox.Enum.Material.SmoothPlastic)
				body.CanCollide = false
				BoxArt.Dress(m, body, {
					name = slot.displayName,
					itemId = id,
					kind = kind,
					color = C3.fromHex(slot.color),
				})
				m.Parent = root
				d:Destroy()
			end
		end
	end,
	cameras = function()
		return {
			entrance = { pos = { -69, 9, -28.6 }, target = { -40, 8, 3 }, fov = 62 },
			tierStand = { pos = { -27, 5.2, 2.5 }, target = { -38, 3.8, -9 }, fov = 58 },
			phone = { pos = { -69, 9, -28.6 }, target = { -40, 8, 3 }, fov = 62 },
			night = { pos = { -69, 9, -28.6 }, target = { -40, 8, 3 }, fov = 62 },
			extra = {
				{ pos = { 0, 150, -20 }, target = { 0, 0, 0 }, fov = 62, label = "the hall from above" },
				{ pos = { -58, 8, 6 }, target = { 30, 6, 0 }, fov = 70, label = "down the aisle" },
				{ pos = { -62, 9, 4 }, target = { -64, 5, 25 }, fov = 72, label = "counter and keeper" },
				{ pos = { 20, 9, 0 }, target = { 20, 6, 18 }, fov = 70, label = "back row from the aisle" },
				{ pos = { -50, 9, 3 }, target = { -40, 9, 9 }, fov = 64, label = "a header close up" },
				{ pos = { 4, 8, -2 }, target = { 20, 4, -12 }, fov = 62, label = "front row stands" },
			},
		}
	end,
})
