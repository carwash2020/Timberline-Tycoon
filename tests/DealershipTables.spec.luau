--!nocheck
-- T390 add-on, the Dealership's display tables: none looks empty.
--
-- The tables in the hall:
--   vehicle pads    the 8 plinths (one per Showroom entry): each holds its own vehicle model and its box.
--                   The vehicles stand on plinths, there is no separate vehicle table to dress.
--   event tables    EventDisplay1..3 in the roped event room (the EventExpansion zone). Each carries a
--                   "Coming soon" card on an easel until an event loads, and, hidden, the parcel it holds
--                   once one does (ShopEventKit.SetTablesShown; the server opens the room with
--                   SetZoneActive). While StoreEventData.Events holds no event for the store the tables are
--                   skipped: nothing is shown on them but the card.
--   lobby tables    Reception (a desk) and Finance (brochures): furniture, not displays.
return function(t)
	-- T421: these specs check the stocked Dealership, so every vehicle mesh has a (made-up) id. With the real, empty ids the
	-- trailers are not stocked (tests/VehicleMeshesMissing.spec.luau).
	local roblox = t.roblox
	local Color3 = roblox.Color3
	local KIND = "Dealership"
	local ACCENT = Color3.fromRGB(47, 109, 181)

	local function fresh(events)
		local loader = t.loader()
		t.support("VehicleStock")(function(path)
			return loader:load(path)
		end, t.roblox)
		local data = loader:shared("StoreEventData")
		for _, event in ipairs(events or {}) do
			table.insert(data.Events, event)
		end
		local m = {
			loader = loader,
			kit = loader:load("ReplicatedStorage/Shared/Art/ShopEventKit"),
			lot = loader:load("ReplicatedStorage/Shared/Art/DealershipLot"),
			shopKit = loader:load("ReplicatedStorage/Shared/Art/ShopKit"),
			catalog = loader:shared("ItemCatalog"),
			box = loader:shared("ItemBox"),
		}
		m.shop = loader:load("ReplicatedStorage/Shared/Art/BuildingArt").Shop(KIND, KIND, ACCENT)
		for _, d in ipairs(m.shop:GetDescendants()) do
			if d:IsA("Model") and d.Name == "EventExpansion" then
				m.zone = d
			end
		end
		return m
	end

	local function partsOf(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function named(root, name)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == name then
				table.insert(out, d)
			end
		end
		return out
	end

	local function withRole(root, role)
		local out = {}
		for _, p in ipairs(partsOf(root)) do
			if p:GetAttribute("EventRole") == role then
				table.insert(out, p)
			end
		end
		return out
	end

	local function visible(part)
		return part.Transparency < 1
	end

	local EVENT = { store = "Dealership", startsAt = "2026-12-01", endsAt = "2026-12-15", enabled = true, items = {} }

	---------------------------------------------------------------------------
	-- 1. every vehicle pad holds a model
	---------------------------------------------------------------------------

	t.test("every vehicle pad (plinth) holds a non-empty vehicle model", function()
		local m = fresh()
		local lot = m.lot.Build()
		local bays = m.lot.Layout().bays
		t.eq(#bays, #m.box.Showroom, "a pad per vehicle")
		local plinths = named(lot, "Plinth")
		t.eq(#plinths, #bays, "a plinth per bay")
		local models = {}
		for _, d in ipairs(lot:GetChildren()) do
			if d:IsA("Model") and d:GetAttribute("ItemId") ~= nil then
				models[d:GetAttribute("ItemId")] = d
			end
		end
		for _, bay in ipairs(bays) do
			local model = models[bay.id]
			t.ok(model, bay.id .. " has a vehicle on its pad")
			t.ok(#partsOf(model) >= 10, bay.id .. " is a real model: " .. #partsOf(model) .. " parts")
			t.eq(model:GetAttribute("Category"), bay.kind)
		end
	end)

	---------------------------------------------------------------------------
	-- 2. event tables: skipped while no event, full once one is active
	---------------------------------------------------------------------------

	t.test("the event tables are skipped while StoreEventData.Events is empty", function()
		local m = fresh()
		t.ok(m.zone, "an EventExpansion zone")
		t.eq(m.kit.HoldsEvent(m.loader:shared("StoreEventData").Events, KIND), false)
		local held = withRole(m.shop, "held")
		t.eq(#held, 3, "a parcel waits for each table")
		for _, p in ipairs(held) do
			t.eq(visible(p), false, p.Name .. " is not placed while no event is on")
		end
		for _, p in ipairs(withRole(m.shop, "card")) do
			t.eq(visible(p), true, p.Name .. " shows")
		end
	end)

	t.test("once an event is active each event table holds a non-empty model and its card is hidden", function()
		local m = fresh({ EVENT })
		t.eq(m.kit.HoldsEvent(m.loader:shared("StoreEventData").Events, KIND), true)
		for i = 1, 3 do
			local model = m.shop:FindFirstChild("EventHeld" .. i, true)
			t.ok(model and model:IsA("Model"), "table " .. i .. " has a held model")
			local ps = partsOf(model)
			t.ok(#ps >= 1, "table " .. i .. " holds something")
			for _, p in ipairs(ps) do
				t.eq(visible(p), true, p.Name .. " shows")
			end
		end
		for _, p in ipairs(withRole(m.shop, "card")) do
			t.eq(visible(p), false, p.Name .. " is hidden")
			for _, gui in ipairs(p:GetChildren()) do
				if gui:IsA("SurfaceGui") then
					t.eq(gui.Enabled, false, "and so is its text")
				end
			end
		end
		-- a disabled event does not count
		local off = fresh({ { store = "Dealership", enabled = false } })
		t.eq(#withRole(off.shop, "held"), 3)
		for _, p in ipairs(withRole(off.shop, "held")) do
			t.eq(visible(p), false, "a switched-off event holds nothing")
		end
		-- another store's event does not count
		local other = fresh({ { store = "ToolShed", enabled = true } })
		for _, p in ipairs(withRole(other.shop, "card")) do
			t.eq(visible(p), true, "another store's event leaves the cards up")
		end
	end)

	t.test("the server opening and closing the room swaps the card and the table's model", function()
		local m = fresh()
		m.kit.SetZoneActive(m.zone, true)
		for _, p in ipairs(withRole(m.shop, "held")) do
			t.eq(visible(p), true, p.Name .. " shows when the room opens")
		end
		for _, p in ipairs(withRole(m.shop, "card")) do
			t.eq(visible(p), false, p.Name .. " is hidden when the room opens")
		end
		m.kit.SetZoneActive(m.zone, false)
		for _, p in ipairs(withRole(m.shop, "held")) do
			t.eq(visible(p), false, p.Name .. " goes when the room closes")
		end
		for _, p in ipairs(withRole(m.shop, "card")) do
			t.eq(visible(p), true, p.Name .. " is back when the room closes")
		end
	end)

	---------------------------------------------------------------------------
	-- 3. while no event is active: exactly one card per table, no prompt, no price
	---------------------------------------------------------------------------

	t.test("while no event is active each event table has exactly one card, with no prompt and no price", function()
		local m = fresh()
		local ink, cream, brass = Color3.fromHex("#2A2420"), Color3.fromHex("#F3E7C9"), Color3.fromHex("#C9A24A")
		local boards = {}
		for i = 1, 3 do
			local top = named(m.shop, "EventDisplay" .. i .. "Top")[1]
			t.ok(top, "table " .. i)
			local board = named(m.shop, "EventCard" .. i .. "Board")
			t.eq(#board, 1, "table " .. i .. " has exactly one card")
			table.insert(boards, board[1])
			t.eq(board[1].Color, cream, "SignCream board")
			local frameParts = named(m.shop, "EventCard" .. i .. "Frame")
			t.eq(#frameParts, 1)
			t.eq(frameParts[1].Color, brass, "Brass frame")
			t.ok(math.abs(board[1].Size.X - 2) < 0.01 and math.abs(board[1].Size.Y - 1.2) < 0.01, "about 2 x 1.2 studs")
			-- tilted 15 degrees on an easel standing on the table
			local tilt =
				math.deg(math.acos(math.clamp(board[1].CFrame.UpVector:Dot(roblox.Vector3.new(0, 1, 0)), -1, 1)))
			t.ok(math.abs(tilt - 15) < 0.5, "tilted 15 degrees: " .. tilt)
			t.ok(#named(m.shop, "EventCard" .. i .. "Leg") == 1, "on an easel")
			local topY = top.CFrame.Position.Y + top.Size.Y / 2
			t.ok(board[1].CFrame.Position.Y > topY, "the card is on the table")
			local labels = {}
			for _, d in ipairs(board[1]:GetDescendants()) do
				if d:IsA("TextLabel") then
					table.insert(labels, d)
				end
			end
			t.ok(#labels >= 1)
			for _, label in ipairs(labels) do
				t.eq(label.Text, "Coming soon")
				t.eq(label.Font.Name, "FredokaOne")
				t.eq(label.TextColor3, ink, "SignInk")
			end
		end
		t.eq(#withRole(m.shop, "card"), 9, "three parts a card, nothing else")
		-- decoration only
		for _, p in ipairs(withRole(m.shop, "card")) do
			t.eq(p.CanCollide, false, p.Name .. " CanCollide")
			t.eq(p.CanQuery, false, p.Name .. " CanQuery")
			t.eq(p.CanTouch, false, p.Name .. " CanTouch")
			t.eq(p.CastShadow, false, p.Name .. " CastShadow")
			t.eq(p:FindFirstChildWhichIsA("ProximityPrompt", true), nil, p.Name .. " has no prompt")
		end
		-- no prompt, no price anywhere in the event room
		for _, d in ipairs(m.zone:GetDescendants()) do
			t.ok(not d:IsA("ProximityPrompt"), "a prompt in the event room")
		end
		for _, p in ipairs(withRole(m.shop, "card")) do
			for _, d in ipairs(p:GetDescendants()) do
				t.ok(not d:IsA("ProximityPrompt"), "a prompt on a card")
				if d:IsA("TextLabel") then
					t.ok(not string.find(d.Text, "[%$%d]"), "a price on a card: " .. d.Text)
				end
			end
			for _, attr in ipairs({ "ItemId", "Price", "ForSale", "SlotId" }) do
				t.eq(p:GetAttribute(attr), nil)
			end
		end
	end)
end
