--!nocheck
-- T414d shop interiors. Written first. Aisles, doors, seated stock, one hero.
-- Do not loosen these to make a build pass.
return function(t)
	local roblox = t.roblox
	local fs = require("@lune/fs")
	local ShopPlace = t.load("ReplicatedStorage/Shared/Art/ShopPlace")
	local ShopBounds = t.load("ReplicatedStorage/Shared/World/ShopBounds")
	local ShopShelf = t.load("ReplicatedStorage/Shared/Art/ShopShelf")
	local ShopCounter = t.load("ReplicatedStorage/Shared/Art/ShopCounter")
	local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")
	local NPCData = t.load("ReplicatedStorage/Shared/NPCData")

	-- Land Office and Sparkworks stay as they are. Cloud shops are not dressed.
	local SHOPS = {
		"ToolShed",
		"HearthAndHome",
		"Dealership",
		"CoatKiosk",
		"HeatBoots",
		"OddsAndEnds",
		"SecretShop",
	}

	local function build(kind)
		return ShopPlace.Build(kind, kind, roblox.Color3.fromRGB(196, 154, 99))
	end

	local function findPart(model, name)
		local inst = model:FindFirstChild(name, true)
		if inst and inst:IsA("BasePart") then
			return inst
		end
		return nil
	end

	local function partsNamed(model, name)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == name then
				table.insert(out, d)
			end
		end
		return out
	end

	-- The opening's own frame. Furniture is not on this list.
	local FRAME = {
		Wall = true,
		DoorJamb = true,
		DoorHeader = true,
		DoorTrack = true,
		DoorFrame = true,
	}

	t.test("every dressed shop has an 8 by 10 door, an 8-wide walk, and clear shoulders", function()
		for _, kind in ipairs(SHOPS) do
			local model = build(kind)
			local door = ShopBounds.Door(model)
			t.ok(door ~= nil, kind .. " door")
			t.ok(door.size.X >= ShopBounds.DoorMinW, kind .. " door width " .. door.size.X)
			t.ok(door.size.Y >= ShopBounds.DoorMinH, kind .. " door height " .. door.size.Y)
			local walk = ShopBounds.Walk(model)
			t.ok(walk ~= nil, kind .. " walk")
			t.ok(walk.size.X >= ShopBounds.AisleMin, kind .. " aisle width " .. walk.size.X)
			t.ok(walk.size.Z >= ShopBounds.WalkMin, kind .. " aisle length " .. walk.size.Z)
			local blocked = ShopBounds.Hits(model, walk, FRAME)
			t.eq(#blocked, 0, kind .. " solid in the aisle: " .. (blocked[1] and blocked[1].Name or ""))
			local counter = model:FindFirstChild("Counter")
			t.ok(counter and counter:IsA("BasePart"), kind .. " counter")
			for _, shoulder in ipairs(ShopBounds.Shoulders(door, counter.CFrame.Position.Z, ShopBounds.Shoulder)) do
				t.ok(shoulder.size.X >= ShopBounds.Shoulder, kind .. " shoulder")
				local snag = ShopBounds.Hits(model, shoulder, FRAME)
				t.eq(#snag, 0, kind .. " solid beside the door: " .. (snag[1] and snag[1].Name or ""))
			end
			local doorHits = ShopBounds.Hits(model, door, FRAME)
			t.eq(#doorHits, 0, kind .. " solid in the door: " .. (doorHits[1] and doorHits[1].Name or ""))
		end
	end)

	t.test("each shop has one shelf, one counter fit, one warm hero, and seated stock", function()
		for _, kind in ipairs(SHOPS) do
			local model = build(kind)
			local shelf = model:FindFirstChild("ShopShelf", true)
			local fit = model:FindFirstChild("ShopCounter", true)
			t.ok(shelf and shelf:IsA("Model"), kind .. " ShopShelf")
			t.ok(fit and fit:IsA("Model"), kind .. " ShopCounter")
			t.eq(shelf:GetAttribute("MeshId"), 0, kind .. " shelf mesh")
			t.eq(fit:GetAttribute("MeshId"), 0, kind .. " counter mesh")
			local heroes = partsNamed(model, "Hero")
			t.eq(#heroes, 1, kind .. " heroes " .. #heroes)
			t.ok(heroes[1]:FindFirstChildOfClass("PointLight") ~= nil, kind .. " hero light")
			local board = nil
			for _, d in ipairs(shelf:GetDescendants()) do
				if d:IsA("BasePart") and d.Name == "ShelfBoard" then
					board = d
				end
			end
			t.ok(board ~= nil, kind .. " shelf board")
			t.eq(board.Color, Palette.PlankHoney, kind .. " honey shelf")
			local items = partsNamed(model, "ShopItem")
			t.ok(#items >= 2, kind .. " stock " .. #items)
			for _, item in ipairs(items) do
				local gap = ShopBounds.RestGap(item, board)
				t.ok(gap >= -1e-4 and gap <= 0.05, kind .. " rest gap " .. gap)
			end
			for i = 1, #items do
				for j = i + 1, #items do
					local pen = ShopBounds.Penetration(items[i], items[j])
					t.eq(pen, 0, kind .. " items clip by " .. pen)
				end
			end
			local tagged = false
			for _, d in ipairs(shelf:GetDescendants()) do
				if d:IsA("BasePart") and d.Name == "ShelfPrice" then
					t.eq(d.Color, Palette.SignCream, kind .. " cream tag")
					local label = d:FindFirstChildWhichIsA("TextLabel", true)
					t.ok(label ~= nil, kind .. " price")
					t.eq(label.TextColor3, Palette.CoinGold, kind .. " gold price")
					tagged = true
				end
			end
			t.eq(tagged, true, kind .. " price tag")
			t.ok(model:FindFirstChild("Counter") ~= nil, kind .. " counter stays a direct child")
			t.eq(model:FindFirstChild("Counter"):IsA("BasePart"), true)
		end
	end)

	t.test("no shopkeeper stands in the door", function()
		for _, kind in ipairs(SHOPS) do
			local model = build(kind)
			local npc = NPCData.ForShop(kind)
			if npc == nil then
				continue
			end
			local door = ShopBounds.Door(model)
			local spot = NPCData.SpotFor(npc, function(modelName, partName)
				if modelName ~= kind then
					return nil, nil
				end
				local part = model:FindFirstChild(partName)
				if part and part:IsA("BasePart") then
					return part.CFrame, part.Size
				end
				return nil, nil
			end)
			local feet = spot.Position
			local body = roblox.Vector3.new(feet.X, feet.Y + 3, feet.Z)
			local function inside(point)
				local p = door.cf:PointToObjectSpace(point)
				local h = door.size / 2
				return math.abs(p.X) < h.X and math.abs(p.Y) < h.Y and math.abs(p.Z) < h.Z
			end
			t.eq(inside(feet), false, kind .. " keeper feet in the door")
			t.eq(inside(body), false, kind .. " keeper in the door")
		end
	end)

	t.test("the names other code reads are still there", function()
		t.eq(type(ShopShelf.Add), "function")
		t.eq(type(ShopShelf.Seat), "function")
		t.eq(type(ShopCounter.Add), "function")
		t.eq(type(ShopBounds.Walk), "function")
		t.eq(type(ShopBounds.Door), "function")
		t.eq(type(ShopBounds.Shoulders), "function")
		local tree = fs.readFile("src/ServerScriptService/TreeService.luau")
		t.ok(string.find(tree, 'AddTag(stump, "Stump")', 1, true) ~= nil, "TreeService stump tag")
		local shop = fs.readFile("src/ServerScriptService/ShopService.luau")
		t.ok(string.find(shop, 'FindFirstChild("Counter")', 1, true) ~= nil, "ShopService counter find")
		local model = build("HearthAndHome")
		t.ok(model:FindFirstChild("Counter") ~= nil)
		t.ok(findPart(model, "DoorBlock") ~= nil or findPart(model, "DoorOpening") ~= nil)
	end)
end
