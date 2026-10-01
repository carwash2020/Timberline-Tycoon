--!nocheck
-- The tutorial beacon's fixed targets (QuestUI.BeaconPaths) against the
-- town as MapBuilder builds it: the sell area (SellZone, with the pad's art
-- placed inside it) and the shops (each named by its kind, Counter inside).
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, Color3 = roblox.Instance, roblox.Vector3, roblox.Color3
	local loader = t.loader({
		services = {
			Players = { LocalPlayer = {} },
			GuiService = {},
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
		Kit.part(sellArea, "SellZone", Vector3.new(24, 12, 18), town.sellZone, Color3.new(1, 1, 1))
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
		local a, b = pad.CFrame.Position, part.CFrame.Position
		t.ok(math.abs(a.X - b.X) < 0.01 and math.abs(a.Z - b.Z) < 0.01, "right over it")
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

	t.test("nothing to find: no map yet, or a beacon that moves", function()
		t.eq(QuestUI.FindBeaconPart(nil, "sellPad"), nil)
		t.eq(QuestUI.FindBeaconPart(townMap(), "tree"), nil)
		t.eq(QuestUI.FindBeaconPart(Instance.new("Model"), "toolShed"), nil)
	end)
end
