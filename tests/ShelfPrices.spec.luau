--!nocheck
-- No price is printed on the world any more (Connor, 7 October 2026: "not lose
-- prices, just show prices when hovering over an item"). A shop box's label,
-- the Tool Shed's axe-rack plates and the General Store's offer boards carry
-- NAMES only; the price appears in a tag when a player aims at the item
-- (Shared/HoverTag, drawn by the client's HoverTagUI, one tag at a time). The
-- price the tag shows is the item's real one: the same StoreStock.UnitPrice
-- the server charges with.
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
	local HoverTag = loader:shared("HoverTag")
	local Util = loader:shared("Util")
	local BoxArt = loader:shared("Art/BoxArt")
	local BuildingArt = loader:load("ReplicatedStorage/Shared/Art/BuildingArt")

	local function printsPrice(text)
		return string.find(text, "$", 1, true) ~= nil or string.find(text, "FREE", 1, true) ~= nil
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

	t.test("no shelf box prints a price or floats a tag; the hover tag has the item's real one", function()
		local seen = 0
		for _, shop in ipairs({ "ToolShed", "HearthAndHome" }) do
			for _, entry in ipairs(boxesOf(shop)) do
				seen += 1
				local slot, rec = entry.slot, entry.rec
				for _, label in ipairs(labelsOf(rec.model)) do
					t.ok(label.Name ~= "Price", slot.slotId .. " has a price line")
					t.ok(not printsPrice(label.Text), slot.slotId .. " prints a price: " .. label.Text)
				end
				for _, d in ipairs(rec.model:GetDescendants()) do
					t.ok(not d:IsA("BillboardGui"), slot.slotId .. " has no floating tag")
				end
				-- The name is still on the label.
				local named = false
				for _, label in ipairs(labelsOf(rec.model)) do
					if label.Name == "Name" and string.find(label.Text, slot.displayName, 1, true) then
						named = true
					end
				end
				t.ok(named, slot.slotId .. " keeps its name on the label")
				-- The tag: the real price, from the same function the counter charges with.
				local expected = StoreStock.UnitPrice(slot.itemKind, slot.itemId, slot.limited, 2)
				t.ok(expected ~= nil and expected > 0, slot.slotId .. " has a price")
				local spec = HoverTag.SpecOf(rec.model)
				t.ok(spec ~= nil, slot.slotId .. " can be aimed at")
				local name, line = HoverTag.Lines(spec, { hour = spec.shop == "ToolShed" and 12 or 12, loop = 2 })
				t.eq(name, slot.displayName)
				t.eq(line, Util.formatCash(expected), slot.slotId .. " tag shows its real price")
				t.eq(rec.price, expected, slot.slotId .. " charges what the tag shows")
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

	t.test("the tables, shelves, axe rack and offer boards print no prices, only names", function()
		local shops = {
			{ kind = "ToolShed", title = "TOOL SHED", accent = roblox.Color3.fromRGB(150, 62, 44) },
			{ kind = "HearthAndHome", title = "HEARTH & HOME", accent = roblox.Color3.fromRGB(122, 90, 60) },
		}
		for _, shop in ipairs(shops) do
			local model = BuildingArt.Shop(shop.kind, shop.title, shop.accent)
			for _, label in ipairs(labelsOf(model)) do
				t.ok(not printsPrice(label.Text), shop.kind .. " prints a price: " .. label.Text)
			end
		end
	end)

	t.test("the Tool Shed's axe rack: a name plate per axe, and each axe tags its real price", function()
		local ItemCatalog = loader:shared("ItemCatalog")
		local model = BuildingArt.Shop("ToolShed", "TOOL SHED", roblox.Color3.fromRGB(150, 62, 44))
		local racks, plates = {}, {}
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == "RackAxe" then
				racks[d:GetAttribute("ItemId")] = d
			elseif d.Name == "AxePlate" then
				table.insert(plates, d)
			end
		end
		local n = 0
		for _, axe in ipairs(ItemCatalog.AxeLadder()) do
			if axe.sold ~= false then
				n += 1
				local rack = racks[axe.id]
				t.ok(rack ~= nil, axe.id .. " hangs on the rack")
				local spec = HoverTag.SpecOf(rack)
				t.eq(spec.shop, "ToolShed")
				t.eq(spec.name, axe.displayName)
				t.eq(spec.anchor, true, "the tag sits over the axe, not its plate")
				t.eq(HoverTag.Price(spec, 2), StoreStock.UnitPrice("Axe", axe.id, false, 2), axe.id .. " real price")
			end
		end
		t.eq(#plates, n, "a plate per axe")
		for _, plate in ipairs(plates) do
			local texts = {}
			for _, label in ipairs(labelsOf(plate)) do
				table.insert(texts, label.Text)
			end
			t.eq(#texts >= 1, true)
			t.ok(not printsPrice(table.concat(texts, " ")), "the plate names the axe only")
			t.ok(HoverTag.SpecOf(plate) ~= nil, "aiming at the plate shows the tag too")
		end
	end)

	t.test("the General Store's offer boards name the item; the tag has its real price", function()
		local model = BuildingArt.Shop("HearthAndHome", "HEARTH & HOME", roblox.Color3.fromRGB(122, 90, 60))
		local boards = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == "PriceTag" and d:IsA("BasePart") then
				table.insert(boards, d)
			end
		end
		t.eq(#boards, 4, "four offer boards")
		for _, board in ipairs(boards) do
			local spec = HoverTag.SpecOf(board)
			t.ok(spec ~= nil, "a board can be aimed at")
			t.eq(spec.shop, "HearthAndHome")
			t.eq(spec.anchor, true)
			local slot = StoreStock.Find(spec.kind, spec.itemId)
			t.eq(spec.name, slot.displayName)
			t.eq(
				HoverTag.Price(spec, 2),
				StoreStock.UnitPrice(spec.kind, spec.itemId, slot.limited, 2),
				spec.itemId .. " real price"
			)
			for _, label in ipairs(labelsOf(board)) do
				t.ok(string.find(label.Text, string.upper(slot.displayName), 1, true) ~= nil, "the board names it")
				t.ok(not printsPrice(label.Text), "and prints no price")
			end
		end
	end)

	t.test("a vehicle's box carries no price either; it tags the real vehicle price when aimed at", function()
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
			t.ok(not printsPrice(label.Text), "no price text on a vehicle box")
		end
		local spec = HoverTag.SpecOf(rec.model)
		t.eq(spec.shop, "Dealership")
		t.eq(HoverTag.Price(spec, 2), StoreStock.UnitPrice("Truck", "Rustbucket", false, 2))
		t.ok(BoxArt ~= nil and GameConfig ~= nil)
	end)
end
