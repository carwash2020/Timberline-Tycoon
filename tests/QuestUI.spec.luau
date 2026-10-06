--!nocheck
-- The tutorial beacon's fixed targets (QuestUI.BeaconPaths) against the
-- town as MapBuilder builds it: the sell area (SellZone, with the pad's art
-- placed inside it) and the shops (each named by its kind, Counter inside).
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, Color3, CFrame = roblox.Instance, roblox.Vector3, roblox.Color3, roblox.CFrame
	local gui = {}
	local loader = t.loader({
		services = {
			Players = { LocalPlayer = {} },
			GuiService = gui,
			TextChatService = {},
			TweenService = {},
			UserInputService = {},
		},
	})
	local QuestUI = loader:load("StarterPlayer/StarterPlayerScripts/QuestUI")
	local TutorialData = loader:shared("TutorialData")
	local BuildingArt = loader:shared("Art/BuildingArt")
	local Kit = loader:shared("Art/Kit")
	local WorldPlan = loader:shared("World/WorldPlan")

	-- Beacons that follow something that moves, found by tag instead.
	local MOVING = { tree = true, log = true, truck = true, stump = true }

	local town = WorldPlan.Town()

	-- TimberlineMap's sell area and shops, the way MapBuilder makes them.
	local function townMap()
		local map = Instance.new("Model")
		map.Name = "TimberlineMap"
		local sellArea = Instance.new("Model")
		sellArea.Name = "SellArea"
		Kit.part(sellArea, "SellZone", WorldPlan.SellZoneSize, town.sellZone, Color3.new(1, 1, 1))
		local pad = BuildingArt.SellPad(24, 18)
		Kit.placeAt(pad, town.sellPad)
		pad.Parent = sellArea
		sellArea.Parent = map
		for _, spot in ipairs(town.shops) do
			local shop = BuildingArt.Shop(spot.kind, spot.title, spot.accent)
			shop.Name = spot.kind
			Kit.placeAt(shop, spot.cframe)
			shop.Parent = map
		end
		local grove = Instance.new("Model")
		grove.Name = "TutorialGrove"
		Kit.part(grove, "CartZone", Vector3.new(7, 12, 7), CFrame.new(-13, 6, 42), Color3.new(1, 1, 1))
		grove.Parent = map
		local plots = Instance.new("Model")
		plots.Name = "Plots"
		local plot = Instance.new("Model")
		plot.Name = "Plot_1"
		plot.Parent = plots
		Kit.part(plot, "Sign", Vector3.new(8, 3.5, 0.4), CFrame.new(), Color3.new(1, 1, 1))
		plots.Parent = map
		-- PlotService's Land Office counter (it sells the first plot).
		local office = Instance.new("Model")
		office.Name = "LandOffice"
		Kit.part(office, "Counter", Vector3.new(7, 3.4, 2.6), CFrame.new(147, 1.7, 86), Color3.new(1, 1, 1))
		office.Parent = map
		return map
	end

	t.test("every tutorial beacon is either found by tag or has a path that resolves", function()
		local map = townMap()
		for _, step in ipairs(TutorialData.Steps) do
			local beacon = step.beacon
			if beacon and not MOVING[beacon] then
				t.ok(QuestUI.BeaconPaths[beacon], step.id .. ": no path for beacon " .. beacon)
				local part = QuestUI.FindBeaconPart(map, beacon)
				t.ok(part and part:IsA("BasePart"), step.id .. ": beacon " .. beacon .. " finds no part")
			end
		end
	end)

	t.test("the sell step's beacon hangs over the pad, on the zone the server sells from", function()
		local map = townMap()
		local part = QuestUI.FindBeaconPart(map, "sellPad")
		t.ok(part, "found")
		t.eq(part.Name, "SellZone")
		t.eq(part.Parent.Name, "SellArea")
		-- The pad is art, one model down: a path straight to it breaks.
		t.eq(map.SellArea:FindFirstChild("SellPad"), nil)
		local pad = map.SellArea:FindFirstChild("SellPad", true)
		t.ok(pad, "the pad is in the sell area")
		-- Over the pad: the zone's middle is on it, 4 studs south of the pad's
		-- own since M1.5 deepened the zone south over the street (z 69 to 95;
		-- 40 deep round that middle since phase 12, z 62 to 102).
		local a, b = pad.CFrame.Position, part.CFrame.Position
		t.ok(math.abs(a.X - b.X) < 0.01, "right over it, across")
		t.ok(math.abs(a.Z - b.Z) <= 4 + 0.01 and math.abs(b.Z - a.Z) < pad.Size.Z / 2, "over the pad, along")
	end)

	t.test("the Tool Shed beacon is its counter", function()
		local part = QuestUI.FindBeaconPart(townMap(), "toolShed")
		t.ok(part, "found")
		t.eq(part.Name, "Counter")
		t.eq(part.Parent.Name, "ToolShed")
	end)

	-- PLAY-03: the plant step's fallback (and the first step's tree) never
	-- point at an Elder: it leaves no stump to plant in.
	t.test("the tutorial's trees: standing ones, never an Elder", function()
		local function tree(attrs)
			local model = Instance.new("Model")
			for key, value in pairs(attrs) do
				model:SetAttribute(key, value)
			end
			return model
		end
		t.eq(QuestUI.TutorialTree(tree({ HP = 40, Uid = "a" }), ""), true, "a standing oak")
		t.eq(QuestUI.TutorialTree(tree({ HP = 40, Uid = "a" }), nil), true, "no Elder awake (attribute unset)")
		t.eq(QuestUI.TutorialTree(tree({ HP = 0, Uid = "a" }), ""), false, "felled")
		t.eq(QuestUI.TutorialTree(tree({ Uid = "a" }), ""), false, "no HP yet")
		t.eq(QuestUI.TutorialTree(tree({ HP = 40, Dormant = true }), ""), false, "the Phantom Grove by day")
		t.eq(QuestUI.TutorialTree(tree({ HP = 4000, Elder = true, Uid = "e" }), ""), false, "an Elder")
		t.eq(QuestUI.TutorialTree(tree({ HP = 4000, Uid = "e" }), "e"), false, "the Elder before its attribute lands")
		-- A tree someone else is cutting (ClaimedBy/ClaimedAt): the beacon finds another.
		local here = function(id)
			return id == 7 or id == 9
		end
		local claimed = tree({ HP = 1, Uid = "c", ClaimedBy = 9, ClaimedAt = 1000 })
		t.eq(QuestUI.ClaimedByOther(claimed, 7, 1010, here), true, "someone else's, fresh")
		t.eq(QuestUI.ClaimedByOther(claimed, 9, 1010, here), false, "your own")
		t.eq(QuestUI.ClaimedByOther(claimed, 7, 1060, here), false, "lapsed")
		t.eq(QuestUI.ClaimedByOther(tree({ HP = 1, ClaimedBy = 0 }), 7, 1010, here), false, "nobody's")
		t.eq(QuestUI.ClaimedByOther(tree({ HP = 1 }), 7, 1010, here), false, "never claimed")
		-- The tracker's title, and on a returning player's refresher.
		t.eq(QuestUI.TrackerTitle(2, 7, false), "TUTORIAL · 2/7")
		t.eq(
			QuestUI.TrackerTitle(2, 7, true),
			string.format("WHAT'S NEW · 2/%d", TutorialData.RefresherLast),
			"the refresher ends at the cart"
		)
		t.eq(QuestUI.TutorialTree(tree({ HP = 40, Uid = "a" }), "e"), true, "any other tree while one is awake")
		t.eq(QuestUI.TutorialTree(tree({ HP = 40, Elder = false, Uid = "a" }), ""), true)
	end)

	t.test("every tree the beacon looks for goes through TutorialTree", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/QuestUI.luau")
		local searches = 0
		local at = 1
		while true do
			local _, stop = string.find(source, 'nearestTagged("Tree", from, ', at, true)
			if not stop then
				break
			end
			searches += 1
			-- Its filter: the name, or an inline function's first line.
			local filter = string.match(string.sub(source, stop + 1), "^function%([^)]*%)%s*\n%s*([^\n]*)")
				or string.match(string.sub(source, stop + 1), "^([^\n]*)")
			t.ok(string.find(filter, "choppable", 1, true), "a tree search without the Elder check: " .. filter)
			at = stop + 1
		end
		t.ok(searches >= 3, "the tree step and the plant step's two fallbacks")
	end)

	t.test("Skip asks again in the device's word", function()
		local HintLogic = loader:shared("HintLogic")
		t.eq(HintLogic.Expand(QuestUI.SkipArmed, "phone"), "Tap again to skip")
		t.eq(HintLogic.Expand(QuestUI.SkipArmed, "desktop"), "Click again to skip")
		t.eq(HintLogic.Expand(QuestUI.SkipArmed, "console"), "Press again to skip")
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/QuestUI.luau")
		t.ok(not string.find(source, 'SetText("Tap again to skip")', 1, true), "no fixed Tap left")
		t.ok(string.find(source, "HintLogic.Expand(QuestUI.SkipArmed, UITheme.Device())", 1, true), "worded per device")
	end)

	-- UI-19: Skip isn't on screen from a new player's first second.
	t.test("Skip shows from the second step on, and the tracker starts with it hidden", function()
		t.eq(QuestUI.ShowSkip(0), false, "done or skipped (the tracker is hidden anyway)")
		t.eq(QuestUI.ShowSkip(1), false, "the first step: no Skip")
		for index = 2, #TutorialData.Steps do
			t.eq(QuestUI.ShowSkip(index), true, "step " .. index)
		end
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/QuestUI.luau")
		t.ok(string.find(source, "skip.root.Visible = false", 1, true), "built hidden")
		t.ok(string.find(source, "skipRoot.Visible = showSkip", 1, true), "refresh shows it")
	end)

	-- UI-12: the arrow is shapes, not stacked glyphs, so it's centred.
	t.test("the beacon arrow is a clipped 45-degree square, centred over the distance pill", function()
		local arrow = QuestUI.BeaconArrow()
		local square = arrow:FindFirstChild("Square")
		local rim = arrow:FindFirstChild("Rim")
		t.eq(arrow.ClipsDescendants, true, "the clip cuts the square's top half off")
		t.eq(arrow.AnchorPoint, roblox.Vector2.new(0.5, 0))
		t.eq({ arrow.Position.X.Scale, arrow.Position.X.Offset }, { 0.5, 0 }, "centred across the beacon")
		t.eq(square.Rotation, 45)
		t.eq(square.AnchorPoint, roblox.Vector2.new(0.5, 0.5))
		t.eq({ square.Position.X.Scale, square.Position.X.Offset }, { 0.5, 0 }, "centred in the clip")
		t.eq({ square.Position.Y.Scale, square.Position.Y.Offset }, { 0, 0 }, "on its top edge")
		t.eq(square.Size.X.Offset, square.Size.Y.Offset, "a square")
		t.eq(square.BackgroundColor3, Color3.fromHex("#FFB840"), "Amber")
		local stroke = square:FindFirstChildOfClass("UIStroke")
		t.ok(stroke and stroke.Color == Color3.fromHex("#3C2814"), "an Ink rim")
		t.eq(rim.BackgroundColor3, Color3.fromHex("#3C2814"), "the top edge's rim")
		t.eq(rim.Size.Y.Offset, QuestUI.ArrowRim)
		-- The whole triangle, rim and all, is inside the clip, and an even
		-- width either side of its tip.
		local half = square.Size.X.Offset * math.sqrt(2) / 2
		local reach = QuestUI.ArrowRim * math.sqrt(2)
		t.ok(arrow.Size.X.Offset >= 2 * (half + reach) - 1, "as wide as the triangle and its rim")
		t.ok(arrow.Size.Y.Offset >= half + reach - 1, "as tall")
		t.ok(arrow.Size.Y.Offset <= half + reach + 1, "and no taller")
		-- Above the pill (20 tall, 8 off the 80 px beacon's bottom), at
		-- any distance: the beacon is drawn the same size in pixels.
		t.ok(arrow.Position.Y.Offset + arrow.Size.Y.Offset <= 80 - 8 - 20 - 4, "clear of the pill")
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/QuestUI.luau")
		t.ok(not string.find(source, "▼", 1, true), "no glyph arrows left")
		t.ok(string.find(source, "b.Size = UDim2.fromOffset(64, 80)", 1, true), "a fixed-pixel beacon")
	end)

	t.test("nothing to find: no map yet, or a beacon that moves", function()
		t.eq(QuestUI.FindBeaconPart(nil, "sellPad"), nil)
		t.eq(QuestUI.FindBeaconPart(townMap(), "tree"), nil)
		t.eq(QuestUI.FindBeaconPart(Instance.new("Model"), "toolShed"), nil)
	end)

	---------------------------------------------------------------------------
	-- The v2 loop (TutorialData.StepsV2)
	---------------------------------------------------------------------------

	t.test("v2: every beacon is found by tag (wood, your truck's bed) or has a path that resolves", function()
		local V2_MOVING = { tree = true, wood = true, truckBed = true, stump = true }
		local map = townMap()
		local seen = {}
		for _, step in ipairs(TutorialData.StepsV2) do
			local beacon = step.beacon
			if beacon then
				seen[beacon] = true
				if not V2_MOVING[beacon] then
					local part = QuestUI.FindBeaconPart(map, beacon)
					t.ok(part and part:IsA("BasePart"), step.id .. ": beacon " .. beacon .. " finds no part")
				end
			end
		end
		t.ok(seen.wood and seen.truckBed, "the drag and load steps point at wood and the bed")
		t.ok(
			seen.landOffice and seen.tree and seen.murphCart and seen.dealership,
			"chop, sell at the cart, buy a plot at the Land Office, then buy the truck"
		)
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/QuestUI.luau")
		t.ok(string.find(source, 'target == "wood"', 1, true), "QuestUI finds the wood beacon")
		t.ok(string.find(source, 'target == "truckBed"', 1, true), "and the bed")
		t.ok(string.find(source, "TutorialData.ForLoop(CoreLoop.Active())", 1, true), "the loop's steps")
		t.ok(not string.find(source, "TutorialData.Steps[", 1, true), "no step read from v1's list alone")
	end)

	t.test("v2: section trees (no HP) stand by Felled; v1 trees still by HP", function()
		local function tree(attrs)
			local model = Instance.new("Model")
			for key, value in pairs(attrs) do
				model:SetAttribute(key, value)
			end
			return model
		end
		t.eq(QuestUI.TutorialTree(tree({ Felled = false, Uid = "a" }), ""), true, "a standing section tree")
		t.eq(QuestUI.TutorialTree(tree({ Felled = true, Uid = "a" }), ""), false, "a felled one (its stub)")
		t.eq(QuestUI.TutorialTree(tree({ Uid = "a" }), ""), false, "attributes not here yet")
		t.eq(QuestUI.TutorialTree(tree({ Felled = false, Dormant = true }), ""), false, "Gloam Hollow by day")
		t.eq(QuestUI.TutorialTree(tree({ Felled = false, Elder = true, Uid = "e" }), ""), false, "an Elder")
		t.eq(QuestUI.TutorialTree(tree({ Felled = false, Uid = "e" }), "e"), false, "the Elder before its attribute")
		-- A v1 tree has both: HP decides, as before.
		t.eq(QuestUI.TutorialTree(tree({ HP = 0, Felled = false, Uid = "a" }), ""), false, "v1: HP 0 is felled")
		t.eq(QuestUI.TutorialTree(tree({ HP = 40, Felled = false, Uid = "a" }), ""), true)
	end)

	t.test("v2: the drag step points at your own loose piece first, then anyone's to take", function()
		local function piece(attrs)
			local model = Instance.new("Model")
			for key, value in pairs(attrs) do
				model:SetAttribute(key, value)
			end
			return model
		end
		local me = 7
		t.eq(QuestUI.WoodRank(piece({ Owner = me, HeldBy = 0 }), me), 1, "yours")
		t.eq(QuestUI.WoodRank(piece({ Owner = me, HeldBy = me }), me), 1, "yours, in your hands")
		t.eq(QuestUI.WoodRank(piece({ Owner = 0, HeldBy = 0 }), me), 2, "nobody's: yours to take")
		t.eq(QuestUI.WoodRank(piece({ Owner = 9, HeldBy = 0 }), me), nil, "someone else's")
		t.eq(QuestUI.WoodRank(piece({ Owner = me, HeldBy = 9 }), me), nil, "in someone else's hands")
		t.eq(QuestUI.WoodRank(piece({ Owner = 0, HeldBy = 9 }), me), nil)
		t.eq(QuestUI.WoodRank(piece({}), me), nil, "attributes not here yet")
	end)

	t.test("v2: the load step's beacon hangs over your truck's bed floor", function()
		local truck = Instance.new("Model")
		local chassis = Instance.new("Part")
		chassis.Name = "Chassis"
		chassis.Parent = truck
		truck.PrimaryPart = chassis
		t.eq(QuestUI.BedPart(truck), chassis, "no bed (the Scout ATV): the truck itself")
		local bed = Instance.new("Part")
		bed.Name = "BedFloor"
		bed.Parent = truck
		t.eq(QuestUI.BedPart(truck), bed)
		local fs = require("@lune/fs")
		local art = fs.readFile("src/ReplicatedStorage/Shared/Art/TruckArt.luau")
		t.ok(string.find(art, 'bedFloor(m, "BedFloor"', 1, true), "TruckArt still names its bed floor BedFloor")
	end)

	t.test("opening Murph's card selects Dismiss, and B or Esc clears it", function()
		local button = roblox.Instance.new("TextButton")
		button.Name = "Dismiss"
		QuestUI._open(button)
		t.eq(gui.SelectedObject, button)
		t.eq(QuestUI.ApplyKey(roblox.Enum.KeyCode.ButtonB), "close")
		t.eq(gui.SelectedObject, nil)
		QuestUI._open(button)
		t.eq(QuestUI.ApplyKey(roblox.Enum.KeyCode.Escape), "close")
		t.eq(gui.SelectedObject, nil)
	end)
end
