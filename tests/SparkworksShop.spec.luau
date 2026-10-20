--!nocheck
-- The Sparkworks shop in the world: where it stands, what is on its shelves,
-- who keeps the counter, and what the counter charges. The stock data and the
-- buy rules are SparkworksStock.spec and ShopService.spec; this is the part
-- that was missing from main (a building, a keeper and shelves), so the
-- automation pieces can be bought in a normal game.
return function(t)
	local roblox = t.roblox
	local Color3, CFrame, Instance, Vector3 = roblox.Color3, roblox.CFrame, roblox.Instance, roblox.Vector3
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")
	local ItemModel = t.load("ReplicatedStorage/Shared/Art/ItemModel")
	local NPCData = t.shared("NPCData")
	local DialogueData = t.shared("DialogueData")
	local StoreStock = t.shared("StoreStock")
	local SparkworksStock = t.shared("SparkworksStock")
	local ItemCatalog = t.shared("ItemCatalog")
	local GameConfig = t.shared("GameConfig")
	local PlotData = t.shared("PlotData")
	local ShopHoursLogic = t.shared("ShopHoursLogic")
	local BoxUnpack = t.shared("BoxUnpack")
	local NewsLogic = t.shared("NewsLogic")
	local TownTreeData = t.shared("TownTreeData")

	local town = WorldPlan.Town()
	local spot
	for _, s in ipairs(town.shops) do
		if s.kind == "Sparkworks" then
			spot = s
		end
	end

	local function placedShop()
		local model = BuildingArt.Shop(spot.kind, spot.title, spot.accent)
		Kit.placeAt(model, spot.cframe)
		return model
	end

	-- The street dressing out front that a body bumps into (T385): not part of the building.
	local DRESSING = {
		LampPost = true,
		LampPostBase = true,
		Planter = true,
		PlanterBand = true,
		BenchSeat = true,
		BenchBack = true,
		AwningPost = true,
	}

	-- The footprint (x0, x1, z0, z1) of a built model's colliding parts.
	local function footprint(model)
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.CanCollide and not DRESSING[d.Name] then
				local cf, size = d.CFrame, d.Size
				for _, sx in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = cf * Vector3.new(sx * size.X / 2, 0, sz * size.Z / 2)
						x0, x1 = math.min(x0, p.X), math.max(x1, p.X)
						z0, z1 = math.min(z0, p.Z), math.max(z1, p.Z)
					end
				end
			end
		end
		return x0, x1, z0, z1
	end

	-- Slots: every Sparkworks item is a Slot of the shop's stock, once.
	local function expectedItems()
		local list = {}
		for _, row in ipairs(SparkworksStock.List()) do
			table.insert(list, { kind = "Logic", id = row.id, price = row.price })
		end
		for _, machine in ipairs(ItemCatalog.MachineList()) do
			if machine.shop == "Sparkworks" then
				table.insert(list, { kind = "Machine", id = machine.id, price = machine.priceCash })
			end
		end
		return list
	end

	---------------------------------------------------------------------------
	-- The world: where it stands
	---------------------------------------------------------------------------

	t.test("WorldPlan has the Sparkworks shop, once, east of the Mill Road and north of the East Link", function()
		t.ok(spot ~= nil, "town.shops lists Sparkworks")
		local count = 0
		for _, s in ipairs(town.shops) do
			if s.kind == "Sparkworks" then
				count += 1
			end
		end
		t.eq(count, 1)
		t.eq(spot.title, "SPARKWORKS")
		local at = spot.cframe.Position
		t.eq(at.Y, 0)
		t.ok(spot.cframe.LookVector.Z < -0.999, "its front (-Z) faces the East Link and the street")
		t.eq(BuildingArt.Scale.Sparkworks, 1.5)
	end)

	t.test("it stands on dry, level ground, off every road and every plot", function()
		local model = placedShop()
		local x0, x1, z0, z1 = footprint(model)
		-- 36 x 36 once scaled; the walls and the counter are all there is to it.
		t.ok(x1 - x0 >= 35 and x1 - x0 <= 40, "width " .. (x1 - x0))
		t.ok(z1 - z0 >= 35 and z1 - z0 <= 40, "depth " .. (z1 - z0))
		local lowest, highest = math.huge, -math.huge
		for _, x in ipairs({ x0, (x0 + x1) / 2, x1 }) do
			for _, z in ipairs({ z0, (z0 + z1) / 2, z1 }) do
				local h = TerrainGen.HeightAt(x, z)
				lowest, highest = math.min(lowest, h), math.max(highest, h)
				t.eq(TerrainGen.WaterLevelAt(x, z), nil, string.format("dry at (%.0f, %.0f)", x, z))
				t.ok(
					TerrainGen.RoadClearance(x, z) >= 2,
					string.format("2 studs off the roads at (%.0f, %.0f): %.1f", x, z, TerrainGen.RoadClearance(x, z))
				)
			end
		end
		t.ok(highest - lowest < 0.5, "level under the floor: " .. (highest - lowest))
		local half = PlotData.Tiers[#PlotData.Tiers].size / 2
		for _, slot in ipairs(PlotData.Slots) do
			local clear = x1 < slot.X - half or x0 > slot.X + half or z1 < slot.Y - half or z0 > slot.Y + half
			t.ok(clear, "not on plot slot " .. tostring(slot))
		end
	end)

	t.test("it is clear of the other shops, the lamps, props, signs, fences and greenery", function()
		local x0, x1, z0, z1 = footprint(placedShop())
		local pad = 3
		local function inside(x, z, margin)
			return x > x0 - margin and x < x1 + margin and z > z0 - margin and z < z1 + margin
		end
		for _, cf in ipairs(town.lamps) do
			t.ok(not inside(cf.X, cf.Z, 1), string.format("lamp at (%.0f, %.0f)", cf.X, cf.Z))
		end
		for _, prop in ipairs(town.props) do
			t.ok(not inside(prop.cframe.X, prop.cframe.Z, 1), prop.name)
		end
		for _, sign in ipairs(town.signs) do
			t.ok(not inside(sign.cframe.X, sign.cframe.Z, 3), string.sub(sign.text, 1, 12))
		end
		for _, fence in ipairs(town.fences) do
			t.ok(not inside(fence.cframe.X, fence.cframe.Z, 1), "fence")
		end
		for _, g in ipairs(town.greenery) do
			t.ok(
				not inside(g.cframe.X, g.cframe.Z, 4),
				string.format("%s at (%.0f, %.0f)", g.kind, g.cframe.X, g.cframe.Z)
			)
		end
		for _, other in ipairs(town.shops) do
			if other.kind ~= "Sparkworks" then
				local o = BuildingArt.Shop(other.kind, other.title, other.accent)
				Kit.placeAt(o, other.cframe)
				local a0, a1, b0, b1 = footprint(o)
				local gapX = math.max(a0 - x1, x0 - a1)
				local gapZ = math.max(b0 - z1, z0 - b1)
				t.ok(math.max(gapX, gapZ) >= 8, other.kind .. " keeps 8 studs from Sparkworks")
			end
		end
		-- The Land Office kiosk (PlotService.LandOfficeAt) and the lot.
		t.ok(x1 + pad < 140 or z0 - pad > 90 or x0 - pad > 154, "off the Land Office counter")
		local lot = WorldLayout.DealershipLoadingPad
		t.ok(x1 + pad < lot.x0 or z1 + pad < lot.z0 or z0 - pad > lot.z1, "off the showroom's loading pad")
	end)

	t.test("a path runs from the East Link to the door, and the town trees leave it alone", function()
		local door = spot.cframe * Vector3.new(0, 0, -18)
		local path
		for _, paint in ipairs(WorldLayout.TownPaint) do
			if paint.name == "SparkworksPath" then
				path = paint
			end
		end
		t.ok(path ~= nil, "a SparkworksPath paint")
		t.ok(door.X > path.x0 and door.X < path.x1, "the path is as wide as the door's front")
		t.ok(door.Z >= path.z0 and door.Z <= path.z1 + 0.5, "the path reaches the door at z " .. door.Z)
		-- Its far end meets the road: the East Link's edge is within a stud of the path's end.
		t.ok(TerrainGen.RoadClearance(door.X, path.z0) <= 1.5, "the path ends at the road")
		-- Nothing solid on the walk: the path and the strip in front of the door are bare.
		for _, g in ipairs(town.greenery) do
			t.ok(
				not (
						g.cframe.X > path.x0 - 3
						and g.cframe.X < path.x1 + 3
						and g.cframe.Z > path.z0
						and g.cframe.Z < path.z1
					),
				"nothing planted on the path"
			)
		end
		-- A floor of packed dirt under the building, so no grass grows through it.
		local floor
		for _, paint in ipairs(WorldLayout.TownFloors) do
			if paint.name == "SparkworksFloor" then
				floor = paint
			end
		end
		t.ok(floor ~= nil, "a SparkworksFloor")
		local x0, x1, z0, z1 = footprint(placedShop())
		t.ok(floor.x0 <= x0 and floor.x1 >= x1 and floor.z0 <= z0 and floor.z1 >= z1, "the floor covers the walls")
		-- The tree planner keeps its building and its door clear.
		local found = 0
		for _, b in ipairs(TownTreeData.Buildings) do
			if b.name == "Sparkworks" then
				found += 1
				t.ok(b.x0 <= x0 and b.x1 >= x1 and b.z0 <= z0 and b.z1 >= z1, "TownTreeData's box covers the shop")
			end
		end
		t.eq(found, 1)
		local doorBox
		for _, r in ipairs(TownTreeData.Empty) do
			if r.name == "SparkworksDoor" then
				doorBox = r
			end
		end
		t.ok(doorBox ~= nil and door.X > doorBox.x0 and door.X < doorBox.x1, "no town tree at the door")
	end)

	---------------------------------------------------------------------------
	-- The building: counter, shelves, door, sign
	---------------------------------------------------------------------------

	t.test("the building has its counter at the back facing the door, and a readable name board", function()
		local model = placedShop()
		local counter = model:FindFirstChild("Counter")
		t.ok(counter ~= nil and counter:IsA("BasePart"), "a Counter")
		t.ok(counter.CFrame.LookVector.Z < -0.99, "the customer side faces the door")
		local rel = spot.cframe:PointToObjectSpace(counter.CFrame.Position)
		t.ok(rel.Z > 8 and rel.Z < 14, "the counter is in the back third: z " .. rel.Z)
		local sign = model:FindFirstChild("Sign")
		t.ok(sign ~= nil, "the name board")
		local text
		for _, d in ipairs(sign:GetDescendants()) do
			if d:IsA("TextLabel") then
				text = d.Text
			end
		end
		t.eq(text, "SPARKWORKS")
		local gui = sign:FindFirstChildOfClass("SurfaceGui")
		t.ok(gui ~= nil and gui.PixelsPerStud >= 10, "the letters are sized to the board")
		t.ok(sign.CFrame.LookVector.Z < -0.99, "the board reads from the street")
		-- The roof is above the sign's base, and the sign stands over the front wall, not inside it.
		local frontZ = spot.cframe.Position.Z - 18
		t.ok(sign.CFrame.Position.Z < frontZ, "the board is in front of the front wall")
		-- A door, a sensor and a blocker exist like the other shops' (ShopDoor).
		t.ok(model:FindFirstChild("ShopDoor") ~= nil, "a front door")
		-- No hours: the board over the door says so, and the keeper never sleeps.
		t.eq(ShopHoursLogic.Span("Sparkworks"), nil)
		t.eq(ShopHoursLogic.IsOpen("Sparkworks", 3), true)
		t.eq(ShopHoursLogic.SignText("Sparkworks", 3), "Open all day")
	end)

	t.test("every item the Sparkworks counter sells has a shelf slot, and nothing overflows", function()
		local model = BuildingArt.Shop(spot.kind, spot.title, spot.accent)
		local counter = model:FindFirstChild("Counter")
		local slotIds, seen = {}, {}
		for _, att in ipairs(counter:GetChildren()) do
			if att.Name == "ShelfSlot" then
				local id = att:GetAttribute("SlotId")
				t.eq(seen[id], nil, "one slot per item: " .. tostring(id))
				seen[id] = true
				table.insert(slotIds, id)
			end
		end
		local items = expectedItems()
		t.eq(#items, 21, "17 logic pieces and 4 belt pieces")
		t.eq(#slotIds, #items)
		for _, item in ipairs(items) do
			local slot = StoreStock.FindInShop("Sparkworks", item.id)
			t.ok(slot ~= nil, item.id .. " is stock")
			t.eq(slot.itemKind, item.kind, item.id)
			t.ok(seen["sparkworks-" .. item.id], item.id .. " has a shelf slot")
			t.eq(StoreStock.UnitPrice(item.kind, item.id, false, 2), item.price, item.id .. " price")
			t.ok(item.price > 0, item.id .. " costs something")
		end
		t.eq(#StoreStock.Overflow("Sparkworks"), 0, "every box fits its shelf")
		-- Placements stay on the shelves: inside the shop's walls and short of the counter.
		for _, place in ipairs(StoreStock.Placements("Sparkworks")) do
			t.ok(math.abs(place.x) < 17.5, place.slotId .. " inside the side walls")
			t.ok(place.z > -17.5 and place.z < 10, place.slotId .. " short of the counter")
		end
		t.ok(StoreStock.AisleGap("Sparkworks") >= GameConfig.ShelfAisleMin, "an aisle wide enough to carry a box")
		-- The zone is the floor the boxes may be carried in.
		local zone = StoreStock.Zone("Sparkworks")
		t.eq(model:GetAttribute("ZoneSizeX"), zone.size.X * BuildingArt.Scale.Sparkworks)
		t.eq(model:GetAttribute("ZoneSizeZ"), zone.size.Z * BuildingArt.Scale.Sparkworks)
	end)

	t.test("the shop's parts and boxes stay in the store budget, and Sparkworks is not in the interior list", function()
		local model = BuildingArt.Shop(spot.kind, spot.title, spot.accent)
		local parts = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		local boxParts = 0
		for _, slot in ipairs(StoreStock.ForShop("Sparkworks")) do
			boxParts += StoreStock.PartsOf(slot)
		end
		t.ok(parts + boxParts <= GameConfig.StorePartBudget, string.format("%d + %d parts", parts, boxParts))
		for _, slot in ipairs(StoreStock.All()) do
			t.ok(slot.shop ~= "Sparkworks", "StoreStock.All is the other two shops' budget")
		end
	end)

	t.test("each box shows its own piece, not a parcel, and opens into the buyer's stock", function()
		for _, item in ipairs(expectedItems()) do
			local display = ItemModel.Get(item.kind, item.id)
			t.ok(#display.parts >= 1, item.id .. " has parts")
			t.ok(#display.parts <= ItemModel.ModelBudget[item.kind], item.id .. " is within the display budget")
			t.ok(display.extent.X > 0 and display.extent.Y > 0, item.id .. " has an extent")
		end
		t.eq(BoxUnpack.Mode("Logic", "Lever"), "stock", "a logic piece goes to stock and the hammer places it")
		t.eq(BoxUnpack.Mode("Machine", "SwitchBelt"), "place", "a belt piece opens into a placement ghost")
	end)

	---------------------------------------------------------------------------
	-- The keeper
	---------------------------------------------------------------------------

	t.test("Juno keeps the counter: behind it, facing the customers and the door", function()
		local juno = NPCData.ForShop("Sparkworks")
		t.ok(juno ~= nil and juno.id == "Juno", "Juno is the Sparkworks keeper")
		t.eq(juno.spot.kind, "counter")
		t.eq(juno.spot.model, "Sparkworks")
		t.ok(table.find(NPCData.Shops, "Sparkworks") ~= nil, "NPCData.Shops lists it")
		local model = placedShop()
		local counter = model:FindFirstChild("Counter")
		local function find(modelName, partName)
			if modelName == "Sparkworks" and partName == "Counter" then
				return counter.CFrame, counter.Size
			end
			return nil, nil
		end
		local feet = NPCData.SpotFor(juno, find)
		local rel = counter.CFrame:PointToObjectSpace(feet.Position)
		t.ok(rel.Z > counter.Size.Z / 2 + 0.6, "behind the counter")
		t.ok(math.abs(rel.X) < 1e-3, "in the middle of it")
		local x0, x1, z0, z1 = footprint(model)
		t.ok(feet.Position.X > x0 and feet.Position.X < x1 and feet.Position.Z > z0 and feet.Position.Z < z1, "inside")
		t.ok(feet.Position.Z < z1 - 1, "not in the back wall")
		-- Facing the customers: the door is toward -Z, so is she.
		t.ok(feet.LookVector.Z < -0.99, "facing the door")
		-- The fallback (the shop is not built) lands on the same spot to within a stud.
		local fallback = NPCData.SpotFor(juno, function()
			return nil, nil
		end)
		t.ok((fallback.Position - feet.Position).Magnitude < 1.5, "the fallback is behind the counter too")
		t.eq(juno.shop, "Sparkworks")
	end)

	t.test("Juno has a talk box like the other keepers: greetings, lines, reactions, every counter line", function()
		local juno = NPCData.ForShop("Sparkworks")
		t.ok(#juno.greetings >= 1 and #juno.lines >= 4)
		for _, line in ipairs(juno.lines) do
			t.ok(#line <= 110, "short enough for the box: " .. line)
		end
		for _, key in ipairs({
			"greet",
			"offer",
			"broke",
			"declined",
			"missing",
			"alreadyOwned",
			"needsLand",
			"needsPlot",
			"thanks",
			"locked",
		}) do
			local text = DialogueData.Line(key, { shop = "Sparkworks", name = "Lever", price = "$320" })
			t.ok(#text > 0 and #text <= 130, key .. ": " .. text)
			t.ok(
				text ~= DialogueData.Line(key, { shop = "ToolShed", name = "Lever", price = "$320" })
					or key == "needsLand",
				key
			)
		end
		t.ok(
			string.find(
				DialogueData.Line("offer", { shop = "Sparkworks", name = "Lever", price = "$320" }),
				"$320",
				1,
				true
			)
		)
		t.eq(#DialogueData.Idles("Sparkworks"), 3)
		t.ok(table.find(DialogueData.Shops(), "Sparkworks") ~= nil)
		-- Open all day: the sleepy line is never used, but it exists.
		t.ok(#DialogueData.Sleepy("Sparkworks", 3) > 0)
	end)

	t.test("the keeper's Talk prompt opens the Sparkworks counter, and a made-up shop is refused", function()
		local sent = {}
		local handler
		local remote = {
			OnServerEvent = {
				Connect = function(_, fn)
					handler = fn
					return { Disconnect = function() end }
				end,
			},
			FireClient = function(_, _player, payload)
				table.insert(sent, payload)
			end,
		}
		local loader = t.loader({
			mocks = {
				ShopService = {
					Loop = function()
						return 2
					end,
					Hour = function()
						return 3 -- three in the morning: the other shops are shut
					end,
				},
				ProfileService = {
					GetProfile = function()
						return { cash = 5000, plot = { claimed = true } }
					end,
				},
			},
		})
		local Dialogue = loader:server("DialogueService")
		Dialogue.Init(remote)
		local player = { Name = "Tester", UserId = 7 }
		handler(player, "open", "Sparkworks")
		t.eq(#sent, 1, "the keeper answers")
		t.eq(sent[1].line, "greet", "no box on the counter yet, so the greeting, not the sleepy line")
		t.eq(sent[1].speaker, "Juno")
		handler(player, "open", "Nowhere")
		t.eq(#sent, 1, "a shop that is not one is dropped")
		-- The Talk prompt on the keeper's model is wired to her shop.
		local src = require("@lune/fs").readFile("src/ServerScriptService/DialogueService.luau")
		t.ok(string.find(src, 'Juno = "Sparkworks"', 1, true) ~= nil)
	end)

	---------------------------------------------------------------------------
	-- The counter: boxes and the buy path
	---------------------------------------------------------------------------

	local function boxBoot()
		local charged = {}
		local profile = { cash = 5000, storage = {}, materials = {}, plot = { claimed = true } }
		local loader = t.loader({
			globals = {
				task = {
					delay = function() end,
				},
			},
			mocks = {
				ShopService = {
					Loop = function()
						return 2
					end,
					Hour = function()
						return 3
					end,
					ChargeAndGrant = function(_, box)
						table.insert(charged, box)
						return true, "thanks", nil
					end,
					GrantItem = function()
						return true, nil
					end,
				},
				ProfileService = {
					GetProfile = function(p)
						return if p and p.UserId == 7 then profile else nil
					end,
				},
			},
		})
		return loader:server("BoxService"), charged, profile
	end

	local function person(at)
		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.CFrame = CFrame.new(at)
		local char = Instance.new("Model")
		hrp.Parent = char
		return {
			Name = "Tester",
			UserId = 7,
			Character = char,
			FindFirstChild = function()
				return nil
			end,
		}
	end

	t.test("BoxService stocks the Sparkworks shelves from the map, one priced box per piece", function()
		local Box = boxBoot()
		local map = Instance.new("Folder")
		local model = BuildingArt.Shop(spot.kind, spot.title, spot.accent)
		model.Parent = map
		Box.StockMap(map)
		local byItem, count = {}, 0
		for _, rec in ipairs(Box.Each()) do
			if rec.shop == "Sparkworks" then
				count += 1
				byItem[rec.itemId] = rec
			end
		end
		t.eq(count, 21, "a box for every piece")
		for _, item in ipairs(expectedItems()) do
			local rec = byItem[item.id]
			t.ok(rec ~= nil, item.id .. " is on a shelf")
			t.eq(rec.itemKind, item.kind, item.id)
			t.eq(rec.price, item.price, item.id .. " is on the shelf at its one price")
			t.eq(rec.slotId, "sparkworks-" .. item.id)
			t.ok(rec.onShelf, item.id .. " stands on the shelf")
		end
	end)

	t.test("paying a Sparkworks box at the counter charges that piece, as Sparkworks", function()
		local Box, charged = boxBoot()
		local model = BuildingArt.Shop(spot.kind, spot.title, spot.accent)
		local map = Instance.new("Folder")
		model.Parent = map
		Box.StockMap(map)
		local rec
		for _, r in ipairs(Box.Each()) do
			if r.itemId == "Lever" then
				rec = r
			end
		end
		t.ok(rec ~= nil)
		-- Carried onto the counter, in the zone in front of it, the buyer beside it.
		local counter = model:FindFirstChild("Counter")
		local onCounter = counter.CFrame * Vector3.new(0, counter.Size.Y / 2 + 1.5, 0)
		rec.part.CFrame = CFrame.new(onCounter)
		local player = person(onCounter + Vector3.new(0, 0, -3))
		local ok, line = Box.Pay(player, rec.uid)
		t.eq({ ok, line }, { true, "thanks" })
		t.eq(#charged, 1)
		t.eq(charged[1].shop, "Sparkworks")
		t.eq(charged[1].kind, "Logic")
		t.eq(charged[1].itemId, "Lever")
		t.eq(charged[1].deferGrant, true, "the buyer is handed the box and opens it on the plot")
		-- Too far from the counter: nothing is charged.
		local far = person(onCounter + Vector3.new(0, 0, -60))
		local again = Box.Pay(far, rec.uid)
		t.eq(again, false)
		t.eq(#charged, 1)
	end)

	t.test("ShopService charges every Sparkworks piece its one price, with a plot, in the v2 loop only", function()
		local Vector3b = Vector3
		local function boot(cash, loop, claimed)
			local profile = {
				cash = cash,
				totalEarned = 0,
				bestAxeTier = 1,
				ownedTrucks = { "Rustbucket" },
				gear = {},
				ownedTrailers = {},
				equippedTrailer = "",
				equippedTruck = "Rustbucket",
				plot = { claimed = claimed, tier = 1, placed = {}, squares = {} },
				storage = {},
			}
			local player = { Name = "Tester", UserId = 1, SetAttribute = function() end }
			local toasts = {}
			local loader = t.loader({
				mocks = {
					ProfileService = {
						GetProfile = function(p)
							return if p == player then profile else nil
						end,
					},
					AxeService = {
						OwnedCounts = function()
							return { RustyAxe = 1 }, 1
						end,
						Grant = function() end,
					},
					BlueprintService = { Publish = function() end, CanGrant = function() end, Grant = function() end },
					MilestoneService = { Mark = function() end },
					QuestService = { Event = function() end, RefreshNextGoal = function() end },
					VehicleService = { Equip = function() end },
				},
			})
			local Shop = loader:server("ShopService")
			local function remote()
				return { OnServerEvent = { Connect = function() end } }
			end
			Shop.Init({ FindFirstChild = function() end }, remote(), remote(), function(_, message)
				table.insert(toasts, message)
			end, loop)
			return Shop, player, profile, toasts
		end
		local _ = Vector3b
		local n = 0
		for _, item in ipairs(expectedItems()) do
			n += 1
			local Shop, player, profile = boot(10000, 2, true)
			local ok, line = Shop.ChargeAndGrant(player, { uid = "u" .. n, kind = item.kind, itemId = item.id })
			t.eq({ ok, line }, { true, "thanks" }, item.id)
			t.eq(profile.cash, 10000 - item.price, item.id .. " cost exactly its price")
			t.eq(profile.sawmillStock, { item.id }, item.id .. " is in the buyer's stock")
			-- No plot: nothing is taken.
			local NoPlot, p2, prof2 = boot(10000, 2, false)
			local ok2, line2 = NoPlot.ChargeAndGrant(p2, { uid = "n" .. n, kind = item.kind, itemId = item.id })
			t.eq({ ok2, line2 }, { false, "needsLand" }, item.id)
			t.eq(prof2.cash, 10000)
			-- Too poor: nothing is taken.
			local Poor, p3, prof3 = boot(item.price - 1, 2, true)
			local ok3, line3 = Poor.ChargeAndGrant(p3, { uid = "p" .. n, kind = item.kind, itemId = item.id })
			t.eq({ ok3, line3 }, { false, "broke" }, item.id)
			t.eq(prof3.cash, item.price - 1)
			-- The v1 loop does not sell it.
			local V1, p4, prof4 = boot(10000, 1, true)
			t.eq(V1.ChargeAndGrant(p4, { uid = "v" .. n, kind = item.kind, itemId = item.id }), false, item.id)
			t.eq(prof4.cash, 10000)
		end
	end)

	---------------------------------------------------------------------------
	-- What's New matches the shelves
	---------------------------------------------------------------------------

	t.test("What's New names what the Sparkworks counter sells, and nothing it does not", function()
		local line, detail
		for _, entry in ipairs(NewsLogic.Entries) do
			if string.find(entry.line, "Sparkworks", 1, true) then
				line, detail = entry.line, entry.detail
			end
		end
		t.ok(line ~= nil, "a Sparkworks headline")
		local lower = string.lower(line .. " " .. detail)
		-- Each thing it promises is on the shelves.
		local function sells(word)
			for _, item in ipairs(expectedItems()) do
				local name = string.lower(item.id)
				local slot = StoreStock.FindInShop("Sparkworks", item.id)
				if string.find(name, word, 1, true) or string.find(string.lower(slot.displayName), word, 1, true) then
					return true
				end
			end
			return false
		end
		t.ok(string.find(lower, "logic", 1, true) and sells("gate") and sells("lever"), "logic pieces")
		t.ok(string.find(lower, "belt", 1, true) and sells("belt"), "belts")
		t.ok(string.find(lower, "laser", 1, true) and sells("laser"), "lasers")
		-- And the plot rule it states is the one the counter enforces (needsLand).
		t.ok(string.find(lower, "plot", 1, true), "a plot first")
		t.ok(not string.find(lower, "$", 1, true), "no price in a headline")
		t.ok(not string.find(lower, "free", 1, true), "nothing is free")
	end)
end
