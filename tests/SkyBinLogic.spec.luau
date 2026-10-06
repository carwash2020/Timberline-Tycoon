--!nocheck
-- SkyBinLogic: the Sky Bin as an item (boxed at the Tool Shed for $400, one
-- per player, placed on your plot, sold from; the Cloud Chute is locked
-- without one). The rules are pure; the services' specs prove the wiring
-- (ShopService, PlotService, AetherServiceV2, ProfileSchema).
return function(t)
	local Logic = t.shared("SkyBinLogic")
	local ItemCatalog = t.shared("ItemCatalog")
	local NoticePolicy = t.shared("NoticePolicy")
	local PlotLogic = t.shared("PlotLogic")
	local ShopLogic = t.shared("ShopLogic")
	local BoxUnpack = t.shared("BoxUnpack")
	local HammerLogic = t.shared("HammerLogic")

	local PLACED = { { uid = "a", blueprintId = "Chair" }, { uid = "b", blueprintId = "SkyBin" } }

	t.test("the Sky Bin is a $400 Tool Shed machine, and no other machine is its blueprint", function()
		local def = ItemCatalog.GetMachine("SkyBin")
		t.eq(def.priceCash, 400)
		t.eq(def.priceCash, ItemCatalog.SkyBinPrice)
		t.eq(def.shop, "ToolShed")
		t.eq(def.displayName, "Sky Bin")
		local bp = Logic.Blueprint("SkyBin")
		t.eq(bp.id, "SkyBin")
		t.eq(bp.category, "Machine")
		t.eq(bp.footprint, Logic.Footprint())
		t.eq(Logic.Blueprint("ChopSaw"), nil)
		t.eq(Logic.Blueprint("Chair"), nil)
		-- The chop saw's blueprint is the chop saw's alone now.
		local ChopSawLogic = t.shared("ChopSawLogic")
		t.eq(ChopSawLogic.Blueprint("SkyBin"), nil)
		t.ok(ChopSawLogic.Blueprint("ChopSaw") ~= nil)
		-- The plot places it like any other blueprint.
		t.eq(PlotLogic.Blueprint("SkyBin").id, "SkyBin")
		t.eq(PlotLogic.Source(PlotLogic.Blueprint("SkyBin"), 0, false, true), "toolShed")
		t.eq(PlotLogic.Source(PlotLogic.Blueprint("SkyBin"), 1, false, true), "place")
	end)

	t.test("owning one: the saved flag, a bin in stock, or a bin on the plot", function()
		t.eq(Logic.Owns({}), false)
		t.eq(Logic.Owns({ skyBinOwned = false, sawmillStock = {}, placed = {} }), false)
		t.eq(Logic.Owns({ skyBinOwned = true }), true)
		t.eq(Logic.Owns({ sawmillStock = { "SawmillRickety", "SkyBin" } }), true)
		t.eq(Logic.Owns({ placed = PLACED }), true)
		t.eq(Logic.Owns({ sawmillStock = "junk", placed = "junk" }), false, "bad data owns nothing")
		t.eq(Logic.Exists({ skyBinOwned = true }), false, "the flag alone is not a bin you can place")
		t.eq(Logic.Exists({ sawmillStock = { "SkyBin" } }), true)
		t.eq(Logic.Exists({ placed = PLACED }), true)
	end)

	t.test("the chute is locked until the bin is placed: buy first, then place", function()
		t.eq(Logic.ChuteLock({}), "buy")
		t.eq(Logic.ChuteLock({ skyBinOwned = true, sawmillStock = { "SkyBin" } }), "place")
		t.eq(Logic.ChuteLock({ skyBinOwned = true }), "place")
		t.eq(Logic.ChuteLock({ skyBinOwned = true, placed = PLACED }), nil)
		t.eq(Logic.ChuteLock({ placed = PLACED }), nil)
		t.ok(string.find(Logic.LockLine("buy"), "Tool Shed", 1, true) ~= nil)
		t.ok(string.find(Logic.LockLine("buy"), "$400", 1, true) ~= nil)
		t.ok(string.find(Logic.LockLine("place"), "on your plot", 1, true) ~= nil)
		t.ok(string.find(Logic.LockLine("place"), "Tool Shed", 1, true) == nil)
		for _, lock in ipairs({ "buy", "place" }) do
			t.ok(string.find(Logic.LockLine(lock), "nothing is lost", 1, true) ~= nil)
			-- A refusal the player caused: NoticePolicy shows it, not a low-key tip.
			t.eq(NoticePolicy.Classify(Logic.LockLine(lock)), "critical", lock)
		end
		t.eq(NoticePolicy.Classify(ShopLogic.SkyBinOwnedLine), "critical")
		t.eq(NoticePolicy.Classify(Logic.OnePerPlotLine), "critical")
		t.eq(
			Logic.ChuteInfo(nil, "3/120"),
			"Lay wood in the Cloud Chute and it goes down to your Sky Bin on your plot. Sky Bin 3/120."
		)
		t.eq(Logic.ChuteInfo("buy", "3/120"), Logic.LockLine("buy"))
	end)

	t.test("one per plot, and only the plot's owner puts one down", function()
		t.eq(Logic.PlaceRefusal("SkyBin", true, {}), nil)
		t.eq(Logic.PlaceRefusal("SkyBin", true, PLACED), Logic.OnePerPlotLine)
		t.eq(Logic.PlaceRefusal("SkyBin", false, {}), Logic.OnlyOwnerLine)
		t.eq(Logic.PlaceRefusal("Chair", false, PLACED), nil, "nothing else is limited")
		t.eq(Logic.PlaceRefusal("ChopSaw", true, PLACED), nil)
	end)

	t.test("selling needs YOUR bin and standing beside it", function()
		local REACH = Logic.PromptRange + 3
		t.eq({ Logic.CanSell({ binOwnerId = 7, userId = 7, distance = 5, reach = REACH }) }, { true, nil })
		t.eq({ Logic.CanSell({ binOwnerId = 7, userId = 8, distance = 1, reach = REACH }) }, { false, "notYours" })
		t.eq({ Logic.CanSell({ binOwnerId = nil, userId = 8, distance = 1, reach = REACH }) }, { false, "notYours" })
		t.eq({ Logic.CanSell({ binOwnerId = 7, userId = 7, distance = REACH + 0.1, reach = REACH }) }, { false, "far" })
		t.eq({ Logic.CanSell({ binOwnerId = 7, userId = 7, distance = nil, reach = REACH }) }, { false, "far" })
		t.eq({ Logic.CanSell({ binOwnerId = 7, userId = 7, distance = REACH, reach = REACH }) }, { true, nil })
	end)

	t.test("a second box is refused at the counter, one unopened box at a time", function()
		t.eq(ShopLogic.MachineRefusal("SkyBin", true), "You already own a Sky Bin.")
		t.eq(ShopLogic.MachineRefusal("SkyBin", false), nil)
		t.eq(ShopLogic.MachineRefusal("ChopSaw", true), nil, "only the bin is limited")
		t.eq(ShopLogic.SkyBinStatusOf(true), "owned")
		t.eq(ShopLogic.SkyBinStatusOf(false), "buy")
		t.eq(BoxUnpack.OneAtATime("Machine", "SkyBin"), true)
		t.eq(BoxUnpack.OneAtATime("Machine", "ChopSaw"), false)
		t.eq(BoxUnpack.OneAtATime("Machine"), false)
		t.eq(BoxUnpack.Mode("Machine"), "stock", "opening the box puts it in your stock")
	end)

	t.test("the hammer's sheet calls it Take back, and it never pays cash", function()
		local bp = PlotLogic.Blueprint("SkyBin")
		local item = { uid = "x", blueprintId = "SkyBin", x = 0, z = 0, rot = 0 }
		t.eq(PlotLogic.SellPlan(bp, item), { cash = 0, planks = 0, wood = nil })
		t.eq(PlotLogic.SellValue(bp), 0)
		local sheet = HammerLogic.PieceActions(bp, item)
		t.eq(sheet[3].id, "sell")
		t.eq(sheet[3].label, "Take back")
		-- The chop saw still sells for half.
		local saw = PlotLogic.Blueprint("ChopSaw")
		t.ok(
			string.find(
				HammerLogic.PieceActions(saw, { uid = "y", blueprintId = "ChopSaw" })[3].label,
				"Sell +",
				1,
				true
			) ~= nil
		)
	end)

	t.test("Migrate: wood waiting in a bin that is no longer a place gives the owner a bin", function()
		-- v2 save: wood in the bin, no bin item.
		local data = { skyWood = { { w = "oak", v = 5 } }, sawmillStock = {}, plot = { placed = {} } }
		t.eq(Logic.Migrate(data), "granted")
		t.eq(data.skyBinOwned, true)
		t.eq(data.sawmillStock, { "SkyBin" }, "a free bin, to place with the hammer")
		t.eq(data.skyWood, { { w = "oak", v = 5 } }, "the wood is untouched, nothing is paid out")
		-- Idempotent: again changes nothing, and never a second bin.
		local before = { skyBinOwned = true, sawmillStock = { "SkyBin" } }
		t.eq(Logic.Migrate(data), nil)
		t.eq(data.sawmillStock, { "SkyBin" })
		t.eq(before.skyBinOwned, data.skyBinOwned)
		-- Once placed it stays one bin.
		data.sawmillStock = {}
		data.plot.placed = { { uid = "b", blueprintId = "SkyBin" } }
		t.eq(Logic.Migrate(data), nil)
		t.eq(data.sawmillStock, {})
	end)

	t.test("Migrate: nothing in the bin and no bin leaves a new player owning nothing", function()
		local data = { skyWood = {}, sawmillStock = {}, plot = { placed = {} } }
		t.eq(Logic.Migrate(data), nil)
		t.eq(data.skyBinOwned, false)
		t.eq(data.sawmillStock, {})
		-- A missing plot or stock is tolerated.
		local bare = {}
		t.eq(Logic.Migrate(bare), nil)
		t.eq(bare.skyBinOwned, false)
	end)

	t.test(
		"Migrate: an owner whose bin is nowhere (a wiped plot) is given one back; a bin on the plot counts",
		function()
			local lost = { skyBinOwned = true, sawmillStock = {}, plot = { placed = {} } }
			t.eq(Logic.Migrate(lost), "granted")
			t.eq(lost.sawmillStock, { "SkyBin" })
			local placed = { sawmillStock = {}, plot = { placed = PLACED } }
			t.eq(Logic.Migrate(placed), nil)
			t.eq(placed.skyBinOwned, true, "a bin on the plot means an owner")
			local stocked = { sawmillStock = { "SkyBin" }, plot = { placed = {} } }
			t.eq(Logic.Migrate(stocked), nil)
			t.eq(stocked.skyBinOwned, true)
		end
	)

	t.test("the fixed Sky Bin is gone from the sawmill's sell station", function()
		local fs = require("@lune/fs")
		local function has(path, needle)
			return string.find(fs.readFile(path), needle, 1, true) ~= nil
		end
		t.ok(not has("src/ServerScriptService/MapBuilder.server.luau", "SkyBin"), "MapBuilder builds none")
		t.ok(not has("src/ServerScriptService/GameServer.server.luau", "skyBinPart"), "GameServer finds none")
		t.ok(not has("src/ReplicatedStorage/Shared/World/WorldPlan.luau", "skyBin:"), "WorldPlan places none")
		t.ok(not has("src/ServerScriptService/AetherService.luau", "d.skyBin"), "AetherService has no fixed bin dep")
		local WorldPlan = t.shared("World/WorldPlan")
		t.eq(WorldPlan.Town().skyBin, nil)
	end)
end
