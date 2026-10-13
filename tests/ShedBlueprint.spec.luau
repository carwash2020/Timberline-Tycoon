--!nocheck
-- The General Store's shed is a plan you build yourself: "Shed Blueprint" at the old $600. Buying it
-- hands you the blueprint (the hammer's plan item); placing it puts down a GHOST you fill with your own
-- planks (a kit piece, 60 plank units). The save id stays "Shed", so an old save that owned the plan or
-- had a shed standing loads unchanged. No "Small Shed" is left in the game's strings.
local fs = require("@lune/fs")

return function(t)
	local roblox = t.roblox
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local StoreStock = t.shared("StoreStock")
	local BuildCost = t.shared("BuildCost")
	local BlueprintBook = t.shared("BlueprintBook")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")

	t.test("the item is 'Shed Blueprint' at the old $600, on the General Store's plan shelf", function()
		local slot = StoreStock.FindInShop("HearthAndHome", "Shed")
		t.ok(slot, "the slot exists")
		t.eq(slot.displayName, "Shed Blueprint")
		t.eq(slot.itemKind, "Blueprint")
		for _, loop in ipairs({ 1, 2 }) do
			t.eq(StoreStock.UnitPrice("Blueprint", "Shed", false, loop), 600, "the shelf price, loop " .. loop)
		end
		local bp = PlotData.Blueprint("Shed")
		t.eq(bp.priceCash, 600, "the legacy price field is untouched")
		t.eq(bp.id, "Shed", "the save id did not change")
		t.eq(bp.unlock, true, "still bought once, at the store")
	end)

	t.test("buying it is a plan you carry; placing it is a ghost you fill with 60 plank units", function()
		local bp = PlotData.Blueprint("Shed")
		t.eq(bp.kit, true, "a kit piece: filled with planks")
		t.eq(bp.woodUnits, 60)
		t.eq(PlotLogic.Source(bp, 0, false, true), "store", "before you own it, it is the store's plan")
		t.eq(PlotLogic.Source(bp, 0, true, true), "fee", "after, it is placed through the fee path, which is $0")
		t.eq(PlotLogic.PlacePrice(bp, true), 0, "placing costs nothing")
		t.eq(PlotLogic.FreeToPlace(bp), false, "no longer a free, prebuilt shed")
		local ghost = { uid = "a", blueprintId = "Shed", x = 0, z = 0, rot = 0, fill = { units = 0 }, paid = 0 }
		t.eq(PlotLogic.IsBuilt(bp, ghost), false, "a placed plan is an empty ghost")
		local half = { uid = "b", blueprintId = "Shed", x = 0, z = 0, rot = 0, fill = { units = 30 }, paid = 240 }
		t.eq(PlotLogic.IsBuilt(bp, half), false)
		local done = { uid = "c", blueprintId = "Shed", x = 0, z = 0, rot = 0, fill = { units = 60 }, paid = 240 }
		t.eq(PlotLogic.IsBuilt(bp, done), true, "filled with its own planks, it is built")
		t.eq(BuildCost.Of(bp).woodUnits, 60)
		t.eq(BuildCost.Of(bp).cash, 0)
		t.eq(PlotLogic.SellPlan(bp, ghost).cash, 0, "an empty ghost placed for $0 refunds $0")
	end)

	t.test(
		"Connor 13 Oct 2026: placing the Shed Blueprint costs $0; the shelf price and the 60-unit fill stay",
		function()
			local bp = PlotData.Blueprint("Shed")
			t.eq(PlotData.Price(bp), 0)
			t.eq(PlotData.StorePrice(bp), 600)
			t.eq(StoreStock.UnitPrice("Blueprint", "Shed", false, 2), 600)
			t.eq(bp.woodUnits, 60)
			t.eq(BuildCost.Of(bp).woodUnits, 60)
			t.eq(BuildCost.NewFill(bp).units, 0, "a new ghost starts empty")
			t.eq(t.server("PlotFill").Fee(bp), 0, "the fee written onto the new ghost")
			t.eq(t.shared("EditLogic").Fee(bp, nil), 0)
		end
	)

	t.test("a shed placed for $0 sells back $0; old paid values sell back sensibly and never mint cash", function()
		local bp = PlotData.Blueprint("Shed")
		local function item(fill, paid)
			return { uid = "s", blueprintId = "Shed", x = 0, z = 0, rot = 0, fill = fill, paid = paid }
		end
		for _, undo in ipairs({ false, true }) do
			t.eq(PlotLogic.SellPlan(bp, item({ units = 0 }, 0), undo).cash, 0, "empty, paid 0")
			t.eq(PlotLogic.SellPlan(bp, item({ units = 30 }, 0), undo).cash, 0, "part filled, paid 0")
			t.eq(PlotLogic.SellPlan(bp, item(nil, 0), undo).cash, 0, "finished, paid 0")
		end
		-- old saves: paid 240 refunds at most what was paid
		t.eq(PlotLogic.SellPlan(bp, item({ units = 0 }, 240)).cash, 240, "an old empty ghost gets its $240 back")
		t.eq(PlotLogic.SellPlan(bp, item(nil, 240)).cash, 120, "an old finished shed: half of $240")
		t.eq(PlotLogic.SellPlan(bp, item(nil, 240), true).cash, 240, "inside undo: what was paid")
		-- old saves: no paid. An empty ghost refunds the new price (0); a finished shed the legacy half.
		t.eq(PlotLogic.SellPlan(bp, item({ units = 0 }, nil)).cash, 0, "no paid, empty ghost")
		t.eq(PlotLogic.SellPlan(bp, item({ units = 30 }, nil)).cash, 0, "no paid, part filled")
		t.eq(PlotLogic.SellPlan(bp, item(nil, nil)).cash, 300, "no paid, finished: half the old $600, as before")
		-- Migrate keeps an old paid of 240 and clamps junk
		local data = Util.deepCopy(Schema.Template)
		data.plot.claimed = true
		data.plot.placed = {
			{ uid = "a", blueprintId = "Shed", x = 0, z = 0, rot = 0, fill = { units = 10 }, paid = 240 },
			{ uid = "b", blueprintId = "Shed", x = 20, z = 0, rot = 0, fill = { units = 10 }, paid = 9999 },
			{ uid = "c", blueprintId = "Shed", x = 40, z = 0, rot = 0, fill = { units = 10 }, paid = 0 },
		}
		Schema.Migrate(data)
		local byUid = {}
		for _, p in ipairs(data.plot.placed) do
			byUid[p.uid] = p
		end
		t.eq(byUid.a.paid, 240, "an old paid of $240 survives")
		t.eq(byUid.b.paid, 240, "a paid above the old fee is clamped to it")
		t.eq(byUid.c.paid, 0)
	end)

	t.test("no other plan's placing price moved", function()
		local OLD_RULE = function(bp)
			if bp.kit == true and type(bp.woodUnits) == "number" then
				if bp.woodUnits == 0 then
					return bp.priceCash
				end
				return bp.woodUnits * PlotData.KitCashPerUnit
			end
			if type(bp.woodUnits) == "number" then
				return bp.woodUnits * 10
			end
			return bp.priceCash
		end
		local n = 0
		for _, bp in ipairs(PlotData.Blueprints) do
			n += 1
			if bp.id == "Shed" then
				t.eq(PlotData.Price(bp), 0)
			else
				t.eq(PlotData.Price(bp), OLD_RULE(bp), bp.id .. " price")
				t.eq(bp.placeFee, nil, bp.id .. " has no placeFee")
			end
		end
		t.ok(n > 20, "plans checked: " .. n)
	end)

	t.test(
		"an old save that owned the Small Shed plan, a plan item or a standing shed loads and keeps all of it",
		function()
			local data = Util.deepCopy(Schema.Template)
			data.blueprintBook = nil
			data.furnitureBlueprints = { Shed = true }
			data.blueprintItems = { { uid = "plan-1", id = "Shed" } }
			data.plot.claimed = true
			-- a shed placed before it was a kit piece: no fill field, standing and finished
			data.plot.placed = { { uid = "old-shed", blueprintId = "Shed", x = 10, z = 0, rot = 0 } }
			Schema.Migrate(data)
			t.ok(BlueprintBook.Has(data.blueprintBook, "Shed"), "the plan you owned is in your book")
			t.eq(data.blueprintItems, { { uid = "plan-1", id = "Shed" } }, "the plan you carried is still carried")
			t.eq(#data.plot.placed, 1, "the shed is still there")
			local shed = data.plot.placed[1]
			t.eq(shed.blueprintId, "Shed")
			t.eq(shed.fill, nil, "no fill: it stays a finished shed, not a ghost")
			t.eq(PlotLogic.IsBuilt(PlotData.Blueprint("Shed"), shed), true)
			local again = Util.deepCopy(data)
			Schema.Migrate(again)
			t.eq(again.plot.placed, data.plot.placed, "migrating again changes nothing")
			t.eq(again.blueprintBook, data.blueprintBook)
			t.eq(again.blueprintItems, data.blueprintItems)
		end
	)

	local function read(path)
		return fs.readFile(path)
	end

	local function sourceFiles(dir, out)
		for _, name in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				if name ~= "Vendor" then
					sourceFiles(path, out)
				end
			elseif string.sub(name, -5) == ".luau" then
				table.insert(out, path)
			end
		end
		return out
	end

	t.test("no 'Small Shed' string is left in the game's source, UI or signs", function()
		local files = sourceFiles("src", {})
		t.ok(#files > 300, "files scanned: " .. #files)
		local bad = {}
		for _, path in ipairs(files) do
			local text = string.lower(read(path))
			if string.find(text, "small shed", 1, true) or string.find(text, "smallshed", 1, true) then
				table.insert(bad, path)
			end
		end
		t.eq(#bad, 0, "still says Small Shed: " .. table.concat(bad, ", "))
	end)

	t.test("the shop's back-wall sign says SHED BLUEPRINT, and nothing in the shop says SMALL SHED", function()
		local model = BuildingArt.Shop("HearthAndHome", "HEARTH & HOME", roblox.Color3.fromRGB(47, 93, 58))
		local texts = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("TextLabel") then
				table.insert(texts, string.upper(d.Text))
			end
		end
		local found = false
		for _, text in ipairs(texts) do
			t.ok(not string.find(text, "SMALL SHED", 1, true), "a sign still says: " .. text)
			if string.find(string.gsub(text, "%s+", " "), "SHED BLUEPRINT", 1, true) then
				found = true
			end
		end
		t.ok(found, "a sign says SHED BLUEPRINT")
	end)
end
