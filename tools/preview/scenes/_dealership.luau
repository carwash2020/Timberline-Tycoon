--!nocheck
-- Shared by the Dealership's interior scenes (store-dealership, store-dealership-event): the hall at the origin with its
-- roof off, the real vehicles on their plinths (DealershipLot, placed the way MapBuilder places them, each behind its
-- packaged box), the keeper at the counter and a person in the aisle. `opts.active` shows the event room as it looks while
-- an event runs (ropes down, lamp on, banner up); `opts.cameras` are the views (see _store.luau).
local Store = require("./_store")

local Dealer = {}

function Dealer.scene(opts)
	return Store.scene({
		kind = "Dealership",
		title = "DEALERSHIP",
		accent = { 47, 109, 181 },
		keeper = "Dale",
		walker = { -56, -1 },
		populate = function(ctx, root, shop)
			local roblox = ctx.roblox
			local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
			local Kit = ctx.art("Kit")
			local BoxArt = ctx.art("BoxArt")
			local DealershipLot = ctx.art("DealershipLot")
			local StoreStock = ctx.shared("StoreStock")
			local hall = DealershipLot.Hall()
			-- The roof is off in these views, so the roof units would hang in the air: drop them too.
			for _, d in ipairs(shop:GetDescendants()) do
				if d.Name == "RoofUnit" then
					d:Destroy()
				end
			end
			if opts.active then
				local EventKit = ctx.art("ShopEventKit")
				for _, d in ipairs(shop:GetDescendants()) do
					if d.Name == "EventExpansion" then
						EventKit.SetZoneActive(d, true)
					elseif d.Name == "EventBanner" and d:IsA("BasePart") then
						EventKit.SetBannerActive(d, true, "TEST DAY")
					end
				end
			end
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
						wood = true, -- (BoxService: the showroom's boxes wear the wood base, as the General Store's)
					})
					m.Parent = root
					d:Destroy()
				end
			end
		end,
		cameras = opts.cameras,
	})
end

return Dealer
