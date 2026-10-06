--!nocheck
-- The dealership showroom hall: the building, the real vehicles on their
-- plinths in price order, each behind its packaged box, as MapBuilder
-- stands them. The roof is off for the overhead views. Views: 1 from above,
-- 2 from the lobby door looking down the front row, 3 a bay close up (the
-- Pickup, behind its box), 4 the back row, 5 the outside, roof on, door
-- shut, 6 the lobby and counter.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local BoxArt = ctx.art("BoxArt")
		local DealershipLot = ctx.art("DealershipLot")
		local StoreStock = ctx.shared("StoreStock")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 600, C3.fromRGB(116, 164, 84), V3.new(0, -0.5, 0))

		local hall = DealershipLot.Hall()
		local shop = BuildingArt.Shop("Dealership", "DEALERSHIP", C3.fromRGB(47, 109, 181))
		local roof = {}
		for _, d in ipairs(shop:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Roof" then
				table.insert(roof, d)
			end
		end
		for _, d in ipairs(roof) do
			d:Destroy()
		end
		Kit.placeAt(shop, CF.new(0, 0, 0))
		shop.Parent = root

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
					kind = kind,
					color = C3.fromHex(slot.color),
				})
				m.Parent = root
				d:Destroy()
			end
		end

		local hx, hz = hall.innerW / 2, hall.innerD / 2
		local lobbyX = -hx + 8
		local bays = BuildingArt.DealershipBays()
		local first, back = bays[1], bays[#bays]
		local cameras = {
			{ pos = { 0, 200, -22 }, target = { 0, 0, 0 }, label = "1 the showroom from above", fov = 62 },
			{
				pos = { lobbyX + 2, 9, -hz + 4 },
				target = { 10, 3, 0 },
				label = "2 from the lobby door, down the clear central walkway",
				fov = 75,
			},
			{
				pos = { first.x + 10, 8, first.aisleZ + 9 },
				target = { first.x, 3, first.z },
				label = "3 a bay close up: the box on the plinth, the vehicle beside it",
				fov = 70,
			},
			{
				pos = { back.x - 18, 9, back.aisleZ - 10 },
				target = { back.x, 3, back.z },
				label = "4 the back row from the aisle",
				fov = 70,
			},
			{
				pos = { lobbyX, 7, -hz - 20 },
				target = { lobbyX, 5, -hz },
				label = "5 the lobby door from outside",
				fov = 70,
			},
			{
				pos = { lobbyX + 2, 10, -hz + 16 },
				target = { lobbyX, 3, hz - 4 },
				label = "6 the lobby and counter",
				fov = 75,
			},
		}
		return { root = root, shadowRadius = 260, cameras = cameras }
	end,
}
