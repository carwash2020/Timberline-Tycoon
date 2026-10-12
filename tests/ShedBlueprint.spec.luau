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
		t.eq(PlotLogic.Source(bp, 0, true, true), "fee", "after, it is placed for the kit fee")
		t.eq(PlotLogic.PlacePrice(bp, true), 60 * PlotData.KitCashPerUnit)
		t.eq(PlotLogic.FreeToPlace(bp), false, "no longer a free, prebuilt shed")
		local ghost = { uid = "a", blueprintId = "Shed", x = 0, z = 0, rot = 0, fill = { units = 0 }, paid = 240 }
		t.eq(PlotLogic.IsBuilt(bp, ghost), false, "a placed plan is an empty ghost")
		local half = { uid = "b", blueprintId = "Shed", x = 0, z = 0, rot = 0, fill = { units = 30 }, paid = 240 }
		t.eq(PlotLogic.IsBuilt(bp, half), false)
		local done = { uid = "c", blueprintId = "Shed", x = 0, z = 0, rot = 0, fill = { units = 60 }, paid = 240 }
		t.eq(PlotLogic.IsBuilt(bp, done), true, "filled with its own planks, it is built")
		t.eq(BuildCost.Of(bp).woodUnits, 60)
		t.eq(BuildCost.Of(bp).cash, 240)
		t.eq(PlotLogic.SellPlan(bp, ghost).cash, 240, "an empty ghost refunds its fee")
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
