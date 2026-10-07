--!nocheck
-- The dealership's showroom: every vehicle on its own plinth inside the hall,
-- behind its box, looks only, priced like the server, ordered by price, and
-- nothing parked outside.
return function(t)
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local ShopLogic = t.shared("ShopLogic")
	local HoverTag = t.shared("HoverTag")
	local ItemCatalog = t.shared("ItemCatalog")
	local Util = t.shared("Util")
	local GameConfig = t.shared("GameConfig")
	local CoreLoop = t.shared("CoreLoop")
	local BoxSize = t.shared("BoxSize")
	local StoreStock = t.shared("StoreStock")

	-- Same rule as DealershipLot's signs: the published loop when MapBuilder
	-- has set it, otherwise the configured one (tests have no workspace).
	local function priceLoop()
		local ok, n = pcall(function()
			return CoreLoop.Active()
		end)
		if
			ok
			and (n == 1 or n == 2)
			and workspace ~= nil
			and workspace:GetAttribute(CoreLoop.ActiveAttribute) ~= nil
		then
			return n
		end
		return if GameConfig.CoreLoop == 2 then 2 else 1
	end

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function aabb(part)
		local cf, size = part.CFrame, part.Size
		local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
		local hx = (math.abs(r.X) * size.X + math.abs(u.X) * size.Y + math.abs(l.X) * size.Z) / 2
		local hy = (math.abs(r.Y) * size.X + math.abs(u.Y) * size.Y + math.abs(l.Y) * size.Z) / 2
		local hz = (math.abs(r.Z) * size.X + math.abs(u.Z) * size.Y + math.abs(l.Z) * size.Z) / 2
		local p = cf.Position
		return p.X - hx, p.X + hx, p.Y - hy, p.Y + hy, p.Z - hz, p.Z + hz
	end

	local function displays(lot)
		local out = {}
		for _, child in ipairs(lot:GetChildren()) do
			if child:IsA("Model") and child:GetAttribute("ItemId") then
				table.insert(out, child)
			end
		end
		return out
	end

	t.test(
		"every display is the real vehicle, anchored, scriptless, looks only, named, with the real price one aim away",
		function()
			local lot = DealershipLot.Build()
			local list = displays(lot)
			t.eq(#list, 8, "5 trucks and 3 trailers")
			for _, child in ipairs(list) do
				t.eq(child.ModelStreamingMode, t.roblox.Enum.ModelStreamingMode.Atomic, child.Name)
				local id = child:GetAttribute("ItemId")
				local item = ItemCatalog.GetTruck(id) or ItemCatalog.GetTrailer(id)
				for _, d in ipairs(child:GetDescendants()) do
					if d:IsA("BasePart") then
						t.eq(d.Anchored, true, child.Name .. " " .. d.Name .. " anchored")
						t.eq(d.CanCollide, false, child.Name .. " " .. d.Name .. " is decoration")
						t.eq(d.CanQuery, false, child.Name .. " " .. d.Name .. " cannot be clicked")
						t.eq(d.CanTouch, false, child.Name .. " " .. d.Name .. " cannot be touched")
					end
					t.eq(d.ClassName == "Script" or d.ClassName == "LocalScript", false, child.Name)
					if d:IsA("VehicleSeat") or d:IsA("Seat") then
						t.eq(d.Disabled, true, child.Name .. " cannot be sat in or driven")
					end
				end
				-- Correct paint: the body carries the vehicle's own colour.
				local painted = false
				for _, d in ipairs(child:GetDescendants()) do
					if d:IsA("BasePart") and d.Color == t.roblox.Color3.fromHex(item.look.color) then
						painted = true
					end
				end
				t.ok(painted, child.Name .. " wears its own paint")
				-- The sign beside it names the vehicle; the price is NOT printed (Connor:
				-- prices show when you aim at an item). The tag's price is the server's.
				local sign = child:FindFirstChild("NameSign", true)
				t.ok(sign and sign:IsA("BasePart"), child.Name .. " name sign")
				t.eq(child:FindFirstChild("PriceSign", true), nil, child.Name .. " has no price sign")
				t.eq(sign:FindFirstChild("BuyPrompt", true), nil, child.Name .. " has no buy prompt")
				local text = nil
				for _, d in ipairs(sign:GetDescendants()) do
					if d:IsA("TextLabel") then
						text = d.Text
					end
				end
				t.ok(text and string.find(text, item.displayName, 1, true), child.Name .. " sign names it")
				t.eq(string.find(text, "$", 1, true), nil, child.Name .. " sign has no price")
				local spec = HoverTag.SpecOf(child)
				t.ok(spec ~= nil, child.Name .. " is aimable")
				t.eq(spec.shop, "Dealership")
				t.eq(spec.itemId, id)
				t.eq(spec.name, item.displayName)
				t.eq(
					HoverTag.Price(spec, priceLoop()),
					ShopLogic.Price(item, priceLoop()),
					child.Name .. " tag price is real"
				)
			end
			t.eq(lot:FindFirstChild("BuyPrompt", true), nil, "the lot has no buy prompt")
		end
	)

	t.test(
		"a box stands on every plinth at the aisle edge, sized by the vehicle, with the vehicle beside it, and the aisle stays clear",
		function()
			local lot = DealershipLot.Build()
			local layout = DealershipLot.Layout()
			local spots = {}
			for _, d in ipairs(lot:GetDescendants()) do
				if d.Name == "BoxSpot" then
					spots[d:GetAttribute("ItemId")] = d
				end
			end
			local plinths = {}
			for _, d in ipairs(lot:GetChildren()) do
				if d.Name == "Plinth" then
					plinths[d:GetAttribute("ItemId")] = d
				end
			end
			-- The clear central walkway: from the front row's aisle edge to the back row's.
			local aisleLo, aisleHi = -math.huge, math.huge
			for _, bay in ipairs(layout.bays) do
				local p = plinths[bay.id]
				local _, _, _, _, pz0, pz1 = aabb(p)
				if bay.row == 1 then
					aisleLo = math.max(aisleLo, pz1)
				else
					aisleHi = math.min(aisleHi, pz0)
				end
			end
			t.ok(
				aisleHi - aisleLo >= DealershipLot.Aisle - 0.01,
				"a central walkway at least " .. DealershipLot.Aisle .. " wide"
			)
			t.ok(aisleHi - aisleLo >= 12, "and never narrower than 12 studs")
			for _, child in ipairs(displays(lot)) do
				local id = child:GetAttribute("ItemId")
				local kind = child:GetAttribute("Category")
				local spot, plinth = spots[id], plinths[id]
				t.ok(spot and plinth, id .. " has a box spot and a plinth")
				local class = BoxSize.Class(StoreStock.VehicleClass(kind, id))
				t.ok((spot.Size - class.size).Magnitude < 0.01, id .. " box is its class")
				t.ok(class.vehicle and class.size.X >= 9, id .. " vehicle boxes are the biggest")
				local sx0, sx1, sy0, sy1, sz0, sz1 = aabb(spot)
				local px0, px1, py0, py1, pz0, pz1 = aabb(plinth)
				-- On the plinth, within it, and out of the aisle.
				t.ok(sx0 >= px0 - 0.01 and sx1 <= px1 + 0.01, id .. " box is within the plinth's width")
				t.ok(sz0 >= pz0 - 0.01 and sz1 <= pz1 + 0.01, id .. " box is within the plinth's depth")
				t.ok(math.abs(sy0 - py1) < 0.01, id .. " box stands on the plinth")
				local row = 1
				for _, bay in ipairs(layout.bays) do
					if bay.id == id then
						row = bay.row
					end
				end
				if row == 1 then
					t.ok(sz1 <= aisleLo + 0.01, id .. " box is out of the walking aisle (front row)")
				else
					t.ok(sz0 >= aisleHi - 0.01, id .. " box is out of the walking aisle (back row)")
				end
				-- The vehicle sits on the plinth, wholly over it.
				local vx0, vx1, vy0, vy1, vz0, vz1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
				for _, d in ipairs(parts(child)) do
					if d.Name ~= "NameSign" then
						local a, b, c, e, f, g = aabb(d)
						vx0, vx1, vy0, vy1 = math.min(vx0, a), math.max(vx1, b), math.min(vy0, c), math.max(vy1, e)
						vz0, vz1 = math.min(vz0, f), math.max(vz1, g)
					end
				end
				t.ok(vy0 >= py1 - 0.3, id .. " rests on the plinth: " .. vy0 .. " vs " .. py1)
				t.ok(vx0 >= px0 - 0.5 and vx1 <= px1 + 0.5, id .. " is within its plinth in x")
				t.ok(vz0 >= pz0 - 0.5 and vz1 <= pz1 + 0.5, id .. " is within its plinth in z")
				-- Beside the box (behind it from the aisle): no overlap in z.
				t.ok(vz1 <= sz0 + 0.05 or vz0 >= sz1 - 0.05, id .. " is beside its box, not under it")
			end
			-- Nothing but a name sign (a thin board at a plinth's edge) stands in the aisle.
			for _, p in ipairs(parts(lot)) do
				if p.Name ~= "NameSign" and p.Name ~= "BoxSpot" then
					local _, _, _, _, z0, z1 = aabb(p)
					t.ok(z1 <= aisleLo + 0.01 or z0 >= aisleHi - 0.01, p.Name .. " keeps out of the aisle")
				end
			end
		end
	)

	t.test("bays are ordered by price, left to right, front row then back row, and never overlap", function()
		local layout = DealershipLot.Layout()
		local last = -1
		for _, bay in ipairs(layout.bays) do
			local item = ItemCatalog.GetTruck(bay.id) or ItemCatalog.GetTrailer(bay.id)
			local price = item.v2.price
			t.ok(price > last, bay.id .. " is dearer than the one before")
			last = price
		end
		t.eq(#layout.bays, 8)
		t.eq(layout.bays[1].id, "Rustbucket", "the cheapest first")
		t.eq(layout.bays[#layout.bays].id, "LoggingRig", "the dearest last")
		for i, a in ipairs(layout.bays) do
			for j = i + 1, #layout.bays do
				local b = layout.bays[j]
				local dx = math.abs(a.x - b.x) - (a.width + b.width) / 2
				local dz = math.abs(a.z - b.z) - (a.depth + b.depth) / 2
				t.ok(dx >= 0.5 - 1e-6 or dz >= 0.5 - 1e-6, a.id .. " and " .. b.id .. " plinths keep a gap")
				local bdx = math.abs(a.x - b.x) - (a.box.X + b.box.X) / 2
				local bdz = math.abs(a.boxZ - b.boxZ) - (a.box.Z + b.box.Z) / 2
				t.ok(bdx >= 0 or bdz >= 0, a.id .. " and " .. b.id .. " boxes do not overlap")
			end
			t.ok(
				a.x - a.width / 2 >= -layout.width / 2 and a.x + a.width / 2 <= layout.width / 2,
				a.id .. " inside the lot in x"
			)
			t.ok(a.z + a.depth / 2 <= layout.depth + 1e-6, a.id .. " inside the lot in z")
		end
	end)

	t.test(
		"nothing is parked outside: the vehicles and boxes are all inside the hall, which sits in the reserved lawn",
		function()
			local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
			local town = WorldPlan.Town()
			local hall = DealershipLot.Hall()
			local spot = nil
			for _, s in ipairs(town.shops) do
				if s.kind == "Dealership" then
					spot = s
				end
			end
			t.ok(spot ~= nil, "the town has a Dealership")
			t.ok(
				math.abs(spot.cframe.Position.X - hall.cx) < 1e-3 and math.abs(spot.cframe.Position.Z - hall.cz) < 1e-3
			)
			local lot = DealershipLot.Build()
			Kit.placeAt(lot, town.displayLot)
			local x0, x1 = hall.cx - hall.innerW / 2, hall.cx + hall.innerW / 2
			local z0, z1 = hall.cz - hall.innerD / 2, hall.cz + hall.innerD / 2
			for _, p in ipairs(parts(lot)) do
				local a, b, _, _, c, d = aabb(p)
				t.ok(
					a >= x0 - 0.01 and b <= x1 + 0.01 and c >= z0 - 0.01 and d <= z1 + 0.01,
					p.Name .. " is inside the hall"
				)
			end
			-- The hall (walls included) is inside the lawn the layout reserves for it.
			-- (the hall spans the old approach lawn and the lot: both are reserved)
			local reserved = { x0 = math.huge, x1 = -math.huge, z0 = math.huge, z1 = -math.huge }
			for _, box in ipairs(WorldLayout.Reserved) do
				if box.name == "DealershipLot" or box.name == "DealershipApproach" then
					reserved.x0, reserved.x1 = math.min(reserved.x0, box.x0), math.max(reserved.x1, box.x1)
					reserved.z0, reserved.z1 = math.min(reserved.z0, box.z0), math.max(reserved.z1, box.z1)
				end
			end
			local wall = DealershipLot.HallWallThick
			t.ok(
				x0 - wall >= reserved.x0 - 0.01 and x1 + wall <= reserved.x1,
				"the hall is inside the reserved lawn in x"
			)
			t.ok(
				z0 - wall >= reserved.z0 + 6 - 0.01 and z1 + wall <= reserved.z1,
				"and in z, clear of the road along its front"
			)
		end
	)

	t.test("the hall and the lot stay off the street, plaza and paths", function()
		local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
		local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
		local town = WorldPlan.Town()
		local models = {}
		for _, spot in ipairs(town.shops) do
			if spot.kind == "HearthAndHome" or spot.kind == "Dealership" then
				local model = BuildingArt.Shop(spot.kind, spot.title, spot.accent)
				Kit.placeAt(model, spot.cframe)
				table.insert(models, model)
			end
		end
		local lot = DealershipLot.Build()
		Kit.placeAt(lot, town.displayLot)
		table.insert(models, lot)
		local banned = {
			Plaza = true,
			MainStreet = true,
			HearthAndHomePath = true,
			ToolShedPath = true,
			DealershipPath = true,
			SpawnWalk = true,
			GondolaPath = true,
			TruckLotPath = true,
		}
		local function hits(part, area)
			local p = part.CFrame.Position
			local h = part.Size / 2
			return p.X + h.X > area.x0 and p.X - h.X < area.x1 and p.Z + h.Z > area.z0 and p.Z - h.Z < area.z1
		end
		for _, model in ipairs(models) do
			for _, part in ipairs(parts(model)) do
				if part.CanCollide then
					for _, area in ipairs(WorldLayout.TownPaint) do
						if banned[area.name] then
							t.eq(hits(part, area), false, model.Name .. " " .. part.Name .. " on " .. area.name)
						end
					end
				end
			end
		end
	end)
end
