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

	-- Lane P (8 Oct 2026): the board Connor approved (handoff
	-- assets/store-board-mockup.jpg): a TIMBERLINE header on two posts and a
	-- cork field of cream cards, one per item, each with a pin, an art
	-- disc, a title, one short line and an "R$" pill the client prices.
	-- Replaces the old arch-and-banner checks (4 posters, 2-line copy,
	-- lanterns): the mockup has none of those.
	local StoreData = t.shared("StoreData")
	local StoreCopy = t.shared("Store/StoreCopy")

	local function cards(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Frame") and d:GetAttribute("RobuxKey") ~= nil then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("the board has a store prompt, and a card for every item until Roblox says no", function()
		local model = StoreBoard.Build()
		local prompt = model:FindFirstChild("StorePrompt", true)
		t.ok(prompt, "prompt")
		t.eq(prompt.ActionText, "Browse Store")
		t.eq(prompt.KeyboardKeyCode.Name, "E")
		t.eq(prompt.GamepadKeyCode.Name, "ButtonX")
		t.ok(prompt.GamepadKeyCode.Name ~= "ButtonR2")
		t.eq(prompt.RequiresLineOfSight, false)
		t.eq(model:FindFirstChild("ComingSoon", true), nil, "nothing answered no, so no strip")
		t.eq(#cards(model), #StoreData.Ordered(), "one card per item with an id")
		for _, entry in ipairs(StoreData.Ordered()) do
			t.ok(model:FindFirstChild(entry.item.name, true), entry.item.name)
		end
	end)

	t.test("an item Roblox says isn't for sale leaves the cards for the Coming soon strip", function()
		local function saleCheck(kind, key)
			return not (kind == "Pass" and key == "DoubleCash")
		end
		local model = StoreBoard.Build(saleCheck)
		t.eq(#cards(model), #StoreData.Ordered() - 1)
		local name = StoreData.Pass("DoubleCash").name
		t.eq(model:FindFirstChild(name, true), nil, "no card for it")
		local strip = model:FindFirstChild("ComingSoon", true)
		t.ok(strip, "the strip")
		local words = strip:FindFirstChild("Words").Text
		t.ok(string.find(words, StoreCopy.Soon, 1, true) == 1, words)
		t.ok(string.find(words, name, 1, true) ~= nil, "named on the strip")
		local _, soon = StoreBoard.Split(function()
			return false
		end)
		t.eq(#soon, #StoreData.Ordered(), "all soon")
		-- Refilling in place (StoreSaleService on a change) leaves no stale cards.
		local list = model:FindFirstChild("List", true)
		StoreBoard.FillPosters(list, nil)
		t.eq(#cards(model), #StoreData.Ordered())
		t.eq(model:FindFirstChild("ComingSoon", true), nil)
	end)

	t.test("a card is a title, one short line, a pin, an art disc and an R$ pill with no number", function()
		local Enum = t.roblox.Enum
		local model = StoreBoard.Build()
		local gui = model:FindFirstChild("Posters", true)
		local width = StoreBoard.BodyWidth(gui.CanvasSize.X)
		local titleW = StoreBoard.TitleWidth(gui.CanvasSize.X)
		for _, card in ipairs(cards(model)) do
			local key = card:GetAttribute("RobuxKey")
			local body = card:FindFirstChild("Description")
			t.ok(body.TextSize >= 14, key)
			t.eq(body.TextTruncate, Enum.TextTruncate.AtEnd, key)
			t.ok(
				StoreBoard.LineCount(body.Text, width, body.TextSize) <= StoreBoard.DescLines,
				key .. ": " .. body.Text
			)
			t.ok(StoreCopy.BoardLines[key] ~= nil, key .. " has a board line")
			t.eq(body.Text, StoreCopy.BoardLines[key], key .. " fits whole")
			local title = card:FindFirstChild("Title")
			t.ok(title.TextSize >= 16, key)
			t.eq(title.Text, card.Name, key .. ": the whole name fits")
			t.ok(StoreBoard.LineCount(title.Text, titleW, title.TextSize) <= StoreBoard.TitleLines, key)
			t.ok(card:FindFirstChild("Pin") ~= nil and card:FindFirstChild("Art") ~= nil, key)
			local price = card:FindFirstChild("Price", true)
			t.eq(price.Text, "R$", key .. ": the server never writes a price")
			t.ok(price:HasTag("StorePricePill"), key)
		end
	end)

	t.test("three cards a page; the board turns the page and wraps round", function()
		local model = StoreBoard.Build()
		local list = model:FindFirstChild("List", true)
		local pages = StoreBoard.PageCount(#StoreData.Ordered())
		t.eq(list:GetAttribute("Pages"), pages)
		local function shown()
			local out = {}
			for _, child in ipairs(list:GetChildren()) do
				if child:GetAttribute("Page") ~= nil and child.Visible then
					table.insert(out, child.Name)
				end
			end
			return out
		end
		t.eq(shown(), { "Page1" })
		t.eq(#list:FindFirstChild("Page1"):GetChildren() - 1, 3, "three cards and a grid layout")
		StoreBoard.NextPage(list)
		t.eq(shown(), { "Page2" })
		for _ = 2, pages do
			StoreBoard.NextPage(list)
		end
		t.eq(shown(), { "Page1" }, "wraps")
		t.eq(#list:FindFirstChild("Dots"):GetChildren() - 1, pages)
		local one = StoreBoard.Build(function(_, key)
			return key == "DoubleCash"
		end)
		t.eq(one:FindFirstChild("List", true):GetAttribute("Pages"), 1)
		t.eq(one:FindFirstChild("Dots", true), nil, "no dots for one page")
	end)

	t.test("the board is big and easy to find: a TIMBERLINE header on two posts over a wide field", function()
		local Enum = t.roblox.Enum
		local size = StoreBoard.BoardSize
		t.ok(size.X >= 5, "at least 5 wide")
		local model = StoreBoard.Build()
		local board = model:FindFirstChild("Board")
		t.ok((board.Size - size).Magnitude < 1e-3)
		t.eq(board.Material, Enum.Material.Fabric, "cork")
		local gui = model:FindFirstChild("Posters", true)
		t.ok(math.abs(gui.CanvasSize.Y / gui.CanvasSize.X - size.Y / size.X) < 0.01, "the canvas has the face's shape")
		local ground = board.CFrame.Position.Y - StoreBoard.FieldBottom - size.Y / 2
		local posts = 0
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == "Post" then
				posts += 1
				t.ok(d.CanCollide, "posts are solid")
				t.ok(d.CFrame.Position.Y + d.Size.Y / 2 - ground >= 7, "7 studs tall overall")
				t.ok(math.abs(d.CFrame.Position.Y - d.Size.Y / 2 - ground) < 1e-3, "on the ground")
			end
		end
		t.eq(posts, 2)
		local header = model:FindFirstChild("Header")
		t.eq(header.CanCollide, false)
		t.ok(header.CFrame.Position.Y - header.Size.Y / 2 > board.CFrame.Position.Y + size.Y / 2, "over the field")
		local faces = 0
		for _, d in ipairs(header:GetChildren()) do
			if d:IsA("SurfaceGui") then
				t.eq(d:FindFirstChildWhichIsA("TextLabel").Text, "TIMBERLINE")
				faces += 1
			end
		end
		t.eq(faces, 2, "reads from both sides")
		local lamps = 0
		for _, d in ipairs(model:GetChildren()) do
			if d.Name == "LanternGlow" then
				lamps += 1
				t.eq(d.CanCollide, false)
				local light = d:FindFirstChildWhichIsA("PointLight")
				t.ok(light ~= nil and light.Enabled == false, "off by day; LightingController lights it after dark")
			end
		end
		t.eq(lamps, 2, "a lantern on each post")
		local parts = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		t.ok(parts <= StoreBoard.PartCap and parts <= 16, "the board stays cheap: " .. parts)
	end)

	t.test("the footprint covers the arch and stays out of the camp and off the spawn walk", function()
		local x0, x1, z0, z1 = StoreBoard.Footprint()
		t.ok(z1 - z0 >= 2 * StoreBoard.ArchHalf, "the arch's posts are inside it")
		t.ok(z1 <= 62, "south of the street")
		t.ok(x1 < -15, "west of the spawn walk")
		-- Murph's camp ring (radius 12 round (-28, 45)).
		local nearX = math.clamp(-28, x0, x1)
		local nearZ = math.clamp(45, z0, z1)
		t.ok((nearX + 28) ^ 2 + (nearZ - 45) ^ 2 > 12 ^ 2, "camp")
	end)
end
