--!nocheck
-- The store bulletin board stays off the roads, the spawn walk, the
-- tutorial grove, the parking lot, Murph's camp and Old Bram's route.
return function(t)
	local StoreBoard = t.shared("StoreBoard")
	local WorldLayout = t.shared("World/WorldLayout")
	local TutorialGrove = t.shared("TutorialGrove")
	local NPCData = t.shared("NPCData")

	local function overlaps(x0, x1, z0, z1)
		return StoreBoard.Overlaps(x0, x1, z0, z1)
	end

	t.test("the board is clear of town paint, the grove, the lot and Bram", function()
		local x0, x1, z0, z1 = StoreBoard.Footprint()
		t.ok(x1 > x0 and z1 > z0)
		for _, paint in ipairs(WorldLayout.TownPaint) do
			t.ok(not overlaps(paint.x0, paint.x1, paint.z0, paint.z1), paint.name)
		end
		local lot = WorldLayout.ParkingLot
		t.ok(not overlaps(lot.x0, lot.x1, lot.z0, lot.z1), "parking lot")
		local half = TutorialGrove.ZoneSize.X / 2
		local cart = TutorialGrove.Cart
		t.ok(not overlaps(cart.x - half, cart.x + half, cart.z - half, cart.z + half), "cart")
		for _, tree in ipairs(TutorialGrove.Trees) do
			t.ok(not overlaps(tree.x - 2, tree.x + 2, tree.z - 2, tree.z + 2), "grove tree")
		end
		-- Murph's camp, radius 12 around (-28, 45): the footprint's closest
		-- corner stays outside it.
		local campX, campZ, campR = -28, 45, 12
		local nearX = math.clamp(campX, x0, x1)
		local nearZ = math.clamp(campZ, z0, z1)
		local dx, dz = nearX - campX, nearZ - campZ
		t.ok(dx * dx + dz * dz > campR * campR, "camp")
		local bram = NPCData.Get("Bram")
		t.ok(bram and bram.route, "Bram's route")
		for i = 1, #bram.route - 1 do
			local a, b = bram.route[i], bram.route[i + 1]
			local steps = 8
			for s = 0, steps do
				local u = s / steps
				local x = a.x + (b.x - a.x) * u
				local z = a.z + (b.z - a.z) * u
				local inside = x >= x0 - 2 and x <= x1 + 2 and z >= z0 - 2 and z <= z1 + 2
				t.ok(not inside, string.format("Bram at %.1f, %.1f", x, z))
			end
		end
	end)

	t.test("the board has a store prompt, and posters only for items on sale", function()
		local model = StoreBoard.Build()
		local prompt = model:FindFirstChild("StorePrompt", true)
		t.ok(prompt, "prompt")
		t.eq(prompt.ActionText, "Browse")
		t.eq(prompt.KeyboardKeyCode.Name, "E")
		t.eq(prompt.GamepadKeyCode.Name, "ButtonX")
		t.eq(prompt.RequiresLineOfSight, false)
		t.eq(model:FindFirstChild("ComingSoon", true), nil, "items are on sale, so no coming-soon label")
		local StoreData = t.shared("StoreData")
		local posters = 0
		for _, pass in ipairs(StoreData.ListedPasses()) do
			t.ok(model:FindFirstChild(pass.name, true), pass.name)
			posters += 1
		end
		for _, product in ipairs(StoreData.ListedProducts()) do
			t.ok(model:FindFirstChild(product.name, true), product.name)
			posters += 1
		end
		t.eq(posters, 4, "two passes and two cash packs; off-sale passes are not posted")
		t.eq(model:FindFirstChild("2x Wood (48 hours)", true), nil)
		t.eq(model:FindFirstChild("Instant Delivery", true), nil)
	end)

	t.test("poster descriptions are 14 px, wrapped, and at most two lines", function()
		local Enum = t.roblox.Enum
		local model = StoreBoard.Build()
		local gui = model:FindFirstChild("Posters", true)
		local width = StoreBoard.BodyWidth(gui.CanvasSize.X)
		local StoreData = t.shared("StoreData")
		local function check(item)
			local card = model:FindFirstChild(item.name, true)
			local body = card:FindFirstChild("Description")
			t.eq(body.TextSize, 14, item.name)
			t.eq(body.TextWrapped, true, item.name)
			t.eq(body.TextTruncate, Enum.TextTruncate.AtEnd, item.name)
			t.eq(body.Size.Y.Offset, 28, item.name)
			t.ok(StoreBoard.LineCount(body.Text, width, 14) <= 2, item.name)
			if StoreBoard.LineCount(item.description, width, 14) <= 2 then
				t.eq(body.Text, item.description, item.name .. " fits whole")
			else
				t.ok(string.sub(body.Text, -#"…") == "…", item.name .. " clips")
			end
			local title = nil
			for _, d in ipairs(card:GetChildren()) do
				if d:IsA("TextLabel") and d.Text == item.name then
					title = d
				end
			end
			t.eq(title.TextSize, 16, item.name .. " title")
		end
		for _, pass in ipairs(StoreData.ListedPasses()) do
			check(pass)
		end
		for _, product in ipairs(StoreData.ListedProducts()) do
			check(product)
		end
	end)
end
