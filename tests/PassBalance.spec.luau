--!nocheck
-- QA G3, narrowed: the new passes don't change stats, sell value, or cash.
-- 2x Cash is exactly 2x within $1. Lux tags any swing, children keep the
-- tag, and Lux plus 2x Cash is 2.2x within $1.
return function(t)
	local ClassicGauge = t.shared("ClassicGauge")
	local GameConfig = t.shared("GameConfig")
	local Handling = t.shared("Handling")
	local ItemCatalog = t.shared("ItemCatalog")
	local PaintShop = t.shared("PaintShop")
	local SaveSlotLogic = t.shared("SaveSlotLogic")
	local SellLogic = t.shared("SellLogic")
	local ShopLogic = t.shared("ShopLogic")
	local StoreData = t.shared("StoreData")
	local TutorialData = t.shared("TutorialData")
	local TruckArt = t.shared("Art/TruckArt")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")

	local function statsOf(truck)
		return {
			bedCapacity = truck.bedCapacity,
			priceCash = truck.priceCash,
			topSpeed = truck.topSpeed,
			turnRate = truck.turnRate,
			width = truck.look.width,
			bedLength = truck.look.bedLength,
			bedWalls = truck.look.bedWalls,
			v2 = truck.v2.price,
		}
	end

	t.test("G3a: new passes change no stats, sell value, or cash", function()
		local pickup = ItemCatalog.GetTruck("Pickup")
		local classic = ItemCatalog.GetTruck("TimberClassic")
		t.eq(statsOf(classic), statsOf(pickup), "Timber Classic is the Pickup's tier")
		t.eq(classic.note, "Same stats as the Pickup")
		local feelA, feelB = Handling.For("TimberClassic"), Handling.For("Pickup")
		for _, key in ipairs({ "accel", "brake", "coast", "climb", "tipResist", "steerLow", "steerHigh", "suspension" }) do
			t.eq(feelA[key], feelB[key], key)
		end
		-- Tow Service costs 0. It does not pay the player, and a plain sale
		-- is still the base payout (these passes are not 2x Cash).
		for _, id in ipairs({ "Pickup", "TimberClassic", "Flatbed", "LoggingRig" }) do
			t.eq(ShopLogic.RecallFee(ItemCatalog.GetTruck(id), 1, true), 0, id .. " v1")
			t.eq(ShopLogic.RecallFee(ItemCatalog.GetTruck(id), 2, true), 0, id .. " v2")
		end
		t.eq(ShopLogic.RecallFee(ItemCatalog.GetTruck("Rustbucket"), 2, false), 5, "the Rustbucket pays the minimum")
		t.eq(ShopLogic.TruckForCash(classic), false, "the Classic is not a cash purchase")
		t.eq(ShopLogic.TruckForCash(pickup), true)
		local bare = SellLogic.PieceValue("oak", "log", 10, nil, 1, false)
		t.eq(SellLogic.Payout(bare, 1), SellLogic.Payout(bare, 1))
		t.ok(bare > 0)
		-- Paint and the Classic grant no cash of their own.
		t.eq(StoreData.Pass("PaintShop").cash, nil)
		t.eq(StoreData.Pass("TowService").cash, nil)
		t.eq(StoreData.Pass("TimberClassic").cash, nil)
	end)

	t.test("G3b: 2x Cash pays exactly 2x within $1, and axe and truck stats stay put", function()
		local axes = {}
		for id, axe in pairs(ItemCatalog.Axes) do
			axes[id] = {
				damage = axe.damage,
				cooldown = if axe.v2 then axe.v2.cooldown else nil,
				v2 = if axe.v2 then axe.v2.damage else nil,
			}
		end
		local trucks = {}
		for id, truck in pairs(ItemCatalog.Trucks) do
			trucks[id] = { topSpeed = truck.topSpeed, turnRate = truck.turnRate, bed = truck.bedCapacity }
		end
		local bare = SellLogic.PieceValue("oak", "log", 10, nil, 1, false)
		local once = SellLogic.Payout(bare, 1)
		local twice = SellLogic.Payout(bare, 2)
		t.ok(math.abs(twice - once * 2) <= 1, string.format("paid %d vs 2x %d", twice, once))
		local awkward = SellLogic.PieceValue("oak", "log", 1, nil, 1, false)
		local onceA = SellLogic.Payout(awkward, 1)
		local twiceA = SellLogic.Payout(awkward, 2)
		t.ok(math.abs(twiceA - onceA * 2) <= 1, string.format("rounding %d vs 2x %d", twiceA, onceA))
		for id, axe in pairs(ItemCatalog.Axes) do
			t.eq(axe.damage, axes[id].damage, id)
			t.eq(if axe.v2 then axe.v2.damage else nil, axes[id].v2, id .. " v2")
			t.eq(if axe.v2 then axe.v2.cooldown else nil, axes[id].cooldown, id .. " cooldown")
		end
		for id, truck in pairs(ItemCatalog.Trucks) do
			t.eq(truck.topSpeed, trucks[id].topSpeed, id)
			t.eq(truck.turnRate, trucks[id].turnRate, id)
			t.eq(truck.bedCapacity, trucks[id].bed, id)
		end
		t.eq(GameConfig.LuxPerkLine(), "Wood you cut with it sells for 10% more.")
	end)

	t.test("G3c: Lux stats, any swing tags, children keep it, 1.10x, untagged unchanged", function()
		local lux = ItemCatalog.GetAxe("LuxAxe").v2
		t.eq(lux.damage, 5.5)
		t.eq(lux.range, 15)
		t.eq(lux.cooldown, 0.42)
		t.eq(SellLogic.InheritLux(false, true), true, "any Lux swing tags")
		t.eq(SellLogic.InheritLux(nil, true), true)
		t.eq(SellLogic.InheritLux(true, false), true, "a child keeps the parent's tag")
		t.eq(SellLogic.InheritLux(true, true), true)
		t.eq(SellLogic.InheritLux(false, false), false)
		t.eq(SellLogic.InheritLux(nil, nil), false)
		local bare = SellLogic.PieceValue("oak", "log", 20, nil, 1, false)
		local tagged = SellLogic.PieceValue("oak", "log", 20, nil, 1, true)
		t.ok(math.abs(tagged - bare * 1.1) < 1e-6, string.format("%s vs 1.10x %s", tagged, bare))
		t.eq(tagged, bare * GameConfig.LuxSellBonus)
		t.eq(SellLogic.PieceValue("oak", "log", 20, nil, 1, false), bare, "untagged is unchanged")
		t.eq(SellLogic.Payout(tagged, 1), SellLogic.Payout(bare * 1.1, 1))
	end)

	t.test("G3d: Lux-tagged wood plus 2x Cash is 2.2x within $1", function()
		for _, volume in ipairs({ 1, 10, 20 }) do
			local bare = SellLogic.PieceValue("oak", "log", volume, nil, 1, false)
			local tagged = SellLogic.PieceValue("oak", "log", volume, nil, 1, true)
			local paid = SellLogic.Payout(tagged, 2)
			local ideal = bare * 2.2
			t.ok(math.abs(paid - ideal) <= 1, string.format("volume %s paid %s, 2.2x is %s", volume, paid, ideal))
		end
	end)

	t.test("the dash estimate matches a Wood Dropoff sale, 2x Cash on and off", function()
		local loose = SellLogic.PieceValue("oak", "log", 6, nil, 1, false)
		local welded = SellLogic.PieceValue("oak", "log", 4, nil, 1, true)
		for _, mult in ipairs({ 1, 2 }) do
			local estimate = ClassicGauge.Estimate({ loose, welded }, mult)
			t.eq(estimate, SellLogic.Payout(loose + welded, mult), "multiplier " .. mult)
		end
		t.eq(ClassicGauge.Phrase, "estimate at the Wood Dropoff")
		t.ok(string.find(StoreData.Pass("TimberClassic").description, ClassicGauge.Phrase, 1, true))
		t.ok(string.find(ClassicGauge.Readout(12), ClassicGauge.Phrase, 1, true))
		t.eq(ClassicGauge.Show("TimberClassic", 7, 7), true)
		t.eq(ClassicGauge.Show("TimberClassic", 7, 8), false, "a passenger")
		t.eq(ClassicGauge.Show("TimberClassic", 7, nil), false)
		t.eq(ClassicGauge.Show("Pickup", 7, 7), false, "any other truck")
	end)

	t.test("the Classic's doors and gauge are on the truck, and the gauge starts hidden", function()
		local longName = "AVeryLongDisplayNameThatMustStillFit"
		local model = TruckArt.Build(ItemCatalog.GetTruck("TimberClassic"), nil, nil, nil, { doorName = longName })
		local names = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == "DoorName" and d:IsA("TextLabel") then
				names += 1
				t.eq(d.Text, longName)
				t.eq(d.TextScaled, true)
				t.eq(d.TextWrapped, true)
				t.eq(d.Parent.MaxDistance, 60)
				t.eq(d.Parent.ClipsDescendants, true)
			end
		end
		t.eq(names, 2)
		local gauge = model:FindFirstChild("LoadGauge", true)
		t.ok(gauge and gauge:IsA("BasePart"))
		local gui = gauge:FindFirstChild("GaugeGui")
		t.ok(gui and gui:IsA("SurfaceGui"))
		t.eq(gui.Enabled, false)
		t.ok(string.find(gui.Readout.Text, ClassicGauge.Phrase, 1, true))
		t.eq(model:FindFirstChild("LoadGauge"), gauge, "the gauge stays a direct child")
	end)

	t.test("Paint Shop rejects a bad color, someone else's truck, and a second change inside 2 seconds", function()
		local swatch = PaintShop.Palette[1]
		local function req(over)
			local base = {
				ownsPass = true,
				ownsTruck = true,
				callerUserId = 4,
				ownerUserId = 4,
				color = swatch,
				now = 100,
				lastAt = nil,
			}
			for k, v in pairs(over) do
				base[k] = v
			end
			return base
		end
		local ok, color = PaintShop.Decide(req({}))
		t.eq(ok, true)
		t.eq(color, swatch)
		local bad, why = PaintShop.Decide(req({ color = "#123456" }))
		t.eq(bad, false)
		t.ok(why)
		local other, whyOther = PaintShop.Decide(req({ callerUserId = 4, ownerUserId = 9 }))
		t.eq(other, false)
		t.eq(whyOther, "That's not your truck.")
		local notOwned = PaintShop.Decide(req({ ownsTruck = false }))
		t.eq(notOwned, false)
		local spam, whySpam = PaintShop.Decide(req({ lastAt = 99, now = 100 }))
		t.eq(spam, false)
		t.eq(whySpam, "Give the paint a moment.")
		local later = PaintShop.Decide(req({ lastAt = 98, now = 100 }))
		t.eq(later, true)
		local noPass = PaintShop.Decide(req({ ownsPass = false }))
		t.eq(noPass, false)
	end)

	t.test("a fresh game that owns the Classic is still fresh, and still has no Rustbucket", function()
		local data = Util.deepCopy(Schema.Template)
		data.passes.TimberClassic = true
		SaveSlotLogic.GrantPassTrucks(data)
		t.eq(SaveSlotLogic.IsFreshGame(data), true)
		t.eq(SaveSlotLogic.GrantStarterTruck(data, true), false)
		t.eq(data.ownedTrucks, { "TimberClassic" })
		t.eq(table.find(data.ownedTrucks, "Rustbucket"), nil)
		local truckStep = nil
		for _, step in ipairs(TutorialData.Steps) do
			if step.event == "truckBought" then
				truckStep = step
				break
			end
		end
		t.ok(truckStep, "the tutorial has a truck step")
		t.eq(TutorialData.AlreadyDone(truckStep, 1, false, #data.ownedTrucks > 0), true)
	end)

	t.test("id 0 stays hidden: 2x Wood and Instant Delivery are not listed", function()
		t.eq(StoreData.IsForSale(0), false)
		for _, product in ipairs(StoreData.ListedProducts()) do
			t.ok(product.key ~= "DoubleWood" and product.key ~= "InstantDelivery", product.key)
			t.ok(product.id > 0)
		end
		for _, pass in ipairs(StoreData.ListedPasses()) do
			t.ok(pass.id > 0, pass.key)
		end
	end)
end
