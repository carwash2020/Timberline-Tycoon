--!nocheck
-- One price per shelf item. A shop box shows its price once, on its own label
-- (BoxArt); there is no floating billboard over it and no plaque on the table
-- or shelf under it, because two prices for one item (or two items' prices
-- drawn on the same plaque, which is what side-by-side boxes did) read as
-- "$520 over $320". The price shown is the item's real price.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

	local loader = t.loader({
		mocks = {
			ShopService = {
				Loop = function()
					return 2
				end,
				ChargeAndGrant = function()
					return true, "thanks", nil
				end,
			},
			ProfileService = {
				GetProfile = function()
					return nil
				end,
			},
		},
	})
	local Box = loader:server("BoxService")
	local StoreStock = loader:shared("StoreStock")
	local GameConfig = loader:shared("GameConfig")
	local Util = loader:shared("Util")
	local BoxArt = loader:shared("Art/BoxArt")
	local BuildingArt = loader:load("ReplicatedStorage/Shared/Art/BuildingArt")

	local function isPriceText(text)
		return string.match(text, "^%$[%d,]+$") ~= nil or text == "FREE"
	end

	local function labelsOf(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("TextLabel") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function boxesOf(shop)
		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.Size = Vector3.new(10, 2, 6)
		counter.CFrame = CFrame.new(0, 3, 0)
		local out = {}
		for _, place in ipairs(StoreStock.Placements(shop)) do
			local slot = StoreStock.Get(place.slotId)
			for i = 1, place.count do
				local along = (i - (place.count + 1) / 2) * place.pitch
				local rec = Box.Make({
					uid = place.slotId .. "#" .. i,
					slotId = place.slotId,
					shop = slot.shop,
					itemKind = slot.itemKind,
					itemId = slot.itemId,
					displayName = slot.displayName,
					limited = slot.limited,
					cf = CFrame.new(place.x, place.y, place.z + along),
					counter = counter,
					zoneCf = CFrame.new(),
					zoneSize = Vector3.new(60, 1, 60),
					onShelf = true,
				})
				table.insert(out, { rec = rec, place = place, slot = slot })
			end
		end
		return out
	end

	t.test("every shelf box shows exactly one price, the item's real one, and nothing floats over it", function()
		local seen = 0
		for _, shop in ipairs({ "ToolShed", "HearthAndHome" }) do
			for _, entry in ipairs(boxesOf(shop)) do
				seen += 1
				local slot, rec = entry.slot, entry.rec
				local prices = {}
				for _, label in ipairs(labelsOf(rec.model)) do
					if label.Name == "Price" then
						table.insert(prices, label.Text)
					end
				end
				local expected = StoreStock.UnitPrice(slot.itemKind, slot.itemId, slot.limited, 2)
				t.ok(expected ~= nil and expected > 0, slot.slotId .. " has a price")
				t.eq(prices, { Util.formatCash(expected) }, slot.slotId .. " shows its real price once")
				t.eq(rec.price, expected, slot.slotId .. " charges what it shows")
				for _, d in ipairs(rec.model:GetDescendants()) do
					t.ok(not d:IsA("BillboardGui"), slot.slotId .. " has no floating tag")
				end
				-- The price line sits under the name on the same panel: no overlap.
				local name, price
				for _, label in ipairs(labelsOf(rec.model)) do
					if label.Parent.Name == "NameMark" and label.Parent.Parent.Name == "Label" then
						if label.Name == "Name" then
							name = label
						elseif label.Name == "Price" then
							price = label
						end
					end
				end
				t.ok(name ~= nil and price ~= nil, slot.slotId .. " has a name line and a price line")
				local nameBottom = name.Position.Y.Scale + name.Size.Y.Scale
				t.ok(nameBottom <= price.Position.Y.Scale + 1e-6, slot.slotId .. " name and price do not overlap")
				t.ok(
					price.Position.Y.Scale + price.Size.Y.Scale <= 1 + 1e-6,
					slot.slotId .. " price stays on the panel"
				)
			end
		end
		t.ok(seen >= 35, "checked every box on both shops' shelves: " .. seen)
	end)

	t.test("no two labels of different boxes overlap on a shelf", function()
		for _, shop in ipairs({ "ToolShed", "HearthAndHome" }) do
			local panels = {}
			for _, entry in ipairs(boxesOf(shop)) do
				for _, d in ipairs(entry.rec.model:GetChildren()) do
					if d.Name == "Label" or d.Name == "SideLabel" then
						local half = d.Size / 2
						table.insert(panels, {
							id = entry.rec.uid .. " " .. d.Name,
							box = entry.rec.uid,
							lo = d.CFrame.Position - half,
							hi = d.CFrame.Position + half,
						})
					end
				end
			end
			for i = 1, #panels do
				for j = i + 1, #panels do
					local a, b = panels[i], panels[j]
					if a.box ~= b.box then
						local apart = a.hi.X <= b.lo.X + 1e-6
							or b.hi.X <= a.lo.X + 1e-6
							or a.hi.Y <= b.lo.Y + 1e-6
							or b.hi.Y <= a.lo.Y + 1e-6
							or a.hi.Z <= b.lo.Z + 1e-6
							or b.hi.Z <= a.lo.Z + 1e-6
						t.ok(apart, shop .. ": " .. a.id .. " and " .. b.id .. " do not overlap")
					end
				end
			end
		end
	end)

	t.test("the tables and shelves carry no price plaques of their own", function()
		local shops = {
			{ kind = "ToolShed", title = "TOOL SHED", accent = roblox.Color3.fromRGB(150, 62, 44) },
			{ kind = "HearthAndHome", title = "HEARTH & HOME", accent = roblox.Color3.fromRGB(122, 90, 60) },
		}
		for _, shop in ipairs(shops) do
			local model = BuildingArt.Shop(shop.kind, shop.title, shop.accent)
			for _, label in ipairs(labelsOf(model)) do
				t.ok(not isPriceText(label.Text), shop.kind .. " has a stand-alone price plaque: " .. label.Text)
			end
		end
	end)

	t.test("a vehicle's box carries no price: the showroom's price sign is its one price", function()
		local counter = Instance.new("Part")
		counter.Name = "Counter"
		counter.Size = Vector3.new(10, 2, 6)
		counter.CFrame = CFrame.new(0, 3, 0)
		local rec = Box.Make({
			uid = "truck-box",
			shop = "Dealership",
			itemKind = "Truck",
			itemId = "Rustbucket",
			displayName = "Rustbucket",
			cf = CFrame.new(0, 3, 0),
			counter = counter,
			onShelf = true,
		})
		for _, label in ipairs(labelsOf(rec.model)) do
			t.ok(label.Name ~= "Price", "no price line on a vehicle box")
		end
		t.ok(BoxArt ~= nil and GameConfig ~= nil)
	end)
end
