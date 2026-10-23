--!nocheck
-- HammerPicker (T420): the blueprint picker the hammer opens. Six tabs (Walls,
-- Floors, Doors, Roofs, Fences, Supports), one card per print that says what it
-- is and what it costs (from the existing data), and the pad keys: bumpers
-- change tab, the D-pad moves over the cards, A picks, B closes. No wire here:
-- wire is its own item (WireSupply).
return function(t)
	local HammerPicker = t.shared("HammerPicker")
	local BlueprintBook = t.shared("BlueprintBook")
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local BuildMenuLogic = t.shared("BuildMenuLogic")
	local Enum = t.roblox.Enum

	local function everything()
		local book = BlueprintBook.Starter()
		for _, bp in ipairs(PlotData.Blueprints) do
			if bp.kit == true and not table.find(book, bp.id) then
				table.insert(book, bp.id)
			end
		end
		return BlueprintBook.Entries(book, {}, true)
	end
	local ctx = { tier = 5, cash = 100000, boxed = false }

	t.test("the six tabs come first, in order, then any extra ones that have something", function()
		t.eq(HammerPicker.Tabs, { "Walls", "Floors", "Doors", "Roofs", "Fences", "Supports" })
		local tabs = HammerPicker.TabList(everything())
		for i, label in ipairs(HammerPicker.Tabs) do
			t.eq(tabs[i].id, label)
			t.eq(tabs[i].label, label)
		end
		t.ok(#tabs >= 6)
		-- An empty list still shows the six (the picker does not jump about as you learn plans).
		local none = HammerPicker.TabList({})
		t.eq(#none, 6)
		for _, tab in ipairs(none) do
			t.eq(#tab.entries, 0)
		end
	end)

	t.test("Supports holds the posts and beams; glass walls are walls; overhang roofs are roofs", function()
		local tabs = HammerPicker.TabList(everything())
		local function ids(label)
			local out = {}
			for _, tab in ipairs(tabs) do
				if tab.id == label then
					for _, e in ipairs(tab.entries) do
						out[e.id] = true
					end
				end
			end
			return out
		end
		local supports = ids("Supports")
		t.ok(supports.Post and supports.Beam8, "post and beam")
		t.ok(not ids("Fences").Post and not ids("Roofs").Beam8, "each piece is on one tab only")
		t.ok(ids("Walls").PictureWall8 and ids("Walls").GlassDoorWall8)
		t.ok(ids("Roofs").FlatRoofOver8 and ids("Roofs").Fascia8)
		t.ok(ids("Floors").Balcony8)
		t.ok(ids("Fences").Fence and ids("Fences").Railing8)
		t.ok(ids("Doors").Door and ids("Doors").Window)
	end)

	t.test("every entry lands on exactly one tab", function()
		local entries = everything()
		local seen, total = {}, 0
		for _, tab in ipairs(HammerPicker.TabList(entries)) do
			for _, e in ipairs(tab.entries) do
				t.ok(not seen[e.id], e.id .. " is on one tab only")
				seen[e.id] = true
				total += 1
			end
		end
		t.eq(total, #entries)
	end)

	t.test("no wire, spool or Wire Tool card is in the picker: wire is not a print", function()
		for _, tab in ipairs(HammerPicker.TabList(everything())) do
			t.ok(tab.id ~= "Wire" and tab.id ~= "Wiring")
		end
		t.ok(not HammerPicker.IsPrint("Wire"))
		t.ok(not HammerPicker.IsPrint("WireSpool"))
		t.ok(HammerPicker.IsPrint("Wall"))
	end)

	t.test("a card explains the piece in words and has a size, a name and a cost line", function()
		local checked = 0
		for _, tab in ipairs(HammerPicker.TabList(everything())) do
			for _, e in ipairs(tab.entries) do
				local card = HammerPicker.Card(e, ctx)
				t.ok(type(card.name) == "string" and card.name ~= "", e.id .. " name")
				t.ok(type(card.blurb) == "string" and #card.blurb >= 12, e.id .. " explains itself")
				t.ok(#card.blurb <= 66, e.id .. " blurb fits three short lines: " .. #card.blurb)
				t.ok(string.find(card.sizeText, "studs", 1, true), e.id .. " size")
				t.ok(type(card.costText) == "string" and card.costText ~= "", e.id .. " cost")
				checked += 1
			end
		end
		t.ok(checked >= 30, "checked a real list: " .. checked)
	end)

	t.test("the cost on a card is the existing data: fee from PlotData.Price, planks from the plan", function()
		local function entryOf(id)
			return { id = id, bp = PlotLogic.Blueprint(id), group = "Buildings", stock = 0 }
		end
		local wall = HammerPicker.Card(entryOf("Wall"), ctx)
		local bp = PlotData.Blueprint("Wall")
		t.eq(wall.fee, PlotData.Price(bp))
		t.ok(
			string.find(wall.costText, tostring(bp.woodUnits) .. " u", 1, true),
			"the planks it needs: " .. wall.costText
		)
		t.ok(string.find(wall.costText, "$" .. tostring(PlotData.Price(bp)), 1, true), "the fee: " .. wall.costText)
		-- A free piece says so.
		local free = HammerPicker.Card(entryOf("Post"), ctx)
		t.ok(free.fee == PlotData.Price(PlotData.Blueprint("Post")))
		-- Stock in hand costs nothing more.
		local stocked = HammerPicker.Card({ id = "Wall", bp = bp, group = "Buildings", stock = 2 }, ctx)
		t.eq(stocked.fee, 0)
	end)

	t.test("a card too dear or locked says so and a plain card is ready", function()
		local bp = PlotData.Blueprint("Wall")
		local entry = { id = "Wall", bp = bp, group = "Buildings", stock = 0 }
		t.eq(HammerPicker.Card(entry, ctx).state, "ready")
		t.eq(HammerPicker.Card(entry, { tier = 5, cash = 0, boxed = false }).state, "cant")
		local locked = HammerPicker.Card({ id = "Wall", bp = bp, group = "Buildings", stock = 0, unlockStage = 3 }, ctx)
		t.eq(locked.state, "locked")
		t.ok(type(locked.message) == "string")
	end)

	t.test("every piece has its own sentence in the six tabs (no card falls back to the generic line)", function()
		for _, tab in ipairs(HammerPicker.TabList(everything())) do
			if table.find(HammerPicker.Tabs, tab.id) then
				for _, e in ipairs(tab.entries) do
					t.ok(HammerPicker.HasBlurb(e.id), e.id .. " has its own sentence")
				end
			end
		end
	end)

	t.test("the stick and D-pad move over the cards and stay on the grid", function()
		-- 7 cards, 3 columns: rows of 3, 3, 1.
		t.eq(HammerPicker.Step(7, 3, 1, "right"), 2)
		t.eq(HammerPicker.Step(7, 3, 3, "right"), 3, "the row ends")
		t.eq(HammerPicker.Step(7, 3, 2, "down"), 5)
		t.eq(HammerPicker.Step(7, 3, 6, "down"), 7, "a short last row takes you to its last card")
		t.eq(HammerPicker.Step(7, 3, 7, "down"), 7)
		t.eq(HammerPicker.Step(7, 3, 5, "up"), 2)
		t.eq(HammerPicker.Step(7, 3, 1, "up"), 1)
		t.eq(HammerPicker.Step(0, 3, 1, "down"), 0)
	end)

	t.test("bumpers change tab and wrap, and pick the first card of the new tab", function()
		local state = { tab = 1, card = 4 }
		local counts = { 5, 3, 0, 2, 6, 2 }
		local nextState = HammerPicker.Navigate(state, "tabNext", counts, 3)
		t.eq(nextState.tab, 2)
		t.eq(nextState.card, 1)
		t.eq(HammerPicker.Navigate({ tab = 6, card = 2 }, "tabNext", counts, 3).tab, 1, "wraps forward")
		t.eq(HammerPicker.Navigate({ tab = 1, card = 2 }, "tabPrev", counts, 3).tab, 6, "wraps back")
		t.eq(HammerPicker.Navigate({ tab = 2, card = 1 }, "tabNext", counts, 3).card, 0, "an empty tab has no card")
	end)

	t.test("the D-pad actions move the card; A picks it; B closes", function()
		local counts = { 7 }
		local s = { tab = 1, card = 1 }
		s = HammerPicker.Navigate(s, "right", counts, 3)
		s = HammerPicker.Navigate(s, "down", counts, 3)
		t.eq(s.card, 5)
		t.eq(HammerPicker.Navigate(s, "left", counts, 3).card, 4)
		local picked = HammerPicker.Navigate(s, "select", counts, 3)
		t.eq(picked.effect, "pick")
		t.eq(picked.card, 5)
		t.eq(HammerPicker.Navigate(s, "close", counts, 3).effect, "close")
		t.eq(
			HammerPicker.Navigate({ tab = 2, card = 0 }, "select", { 3, 0 }, 3).effect,
			nil,
			"nothing to pick on an empty tab"
		)
	end)

	t.test("pad keys map to actions and the right trigger is never one of them", function()
		local K = Enum.KeyCode
		t.eq(HammerPicker.ActionOf(K.ButtonL1), "tabPrev")
		t.eq(HammerPicker.ActionOf(K.ButtonR1), "tabNext")
		t.eq(HammerPicker.ActionOf(K.DPadUp), "up")
		t.eq(HammerPicker.ActionOf(K.DPadDown), "down")
		t.eq(HammerPicker.ActionOf(K.DPadLeft), "left")
		t.eq(HammerPicker.ActionOf(K.DPadRight), "right")
		t.eq(HammerPicker.ActionOf(K.ButtonA), "select")
		t.eq(HammerPicker.ActionOf(K.ButtonB), "close")
		t.eq(HammerPicker.ActionOf(K.Escape), "close")
		t.eq(HammerPicker.ActionOf(K.ButtonR2), nil, "RT is grab and chop, never a menu key")
		t.eq(HammerPicker.ActionOf(K.ButtonL2), nil)
		for _, key in ipairs(HammerPicker.Keys) do
			t.ok(key ~= K.ButtonR2, "no ButtonR2 in the picker's keys")
		end
	end)

	t.test(
		"equipping the hammer on your plot opens the picker once; a placer, a panel or another place does not",
		function()
			t.ok(HammerPicker.OpensOnEquip({ onPlot = true, placing = false, panelOpen = false, pickerOpen = false }))
			t.ok(
				not HammerPicker.OpensOnEquip({ onPlot = false, placing = false, panelOpen = false, pickerOpen = false })
			)
			t.ok(
				not HammerPicker.OpensOnEquip({ onPlot = true, placing = true, panelOpen = false, pickerOpen = false })
			)
			t.ok(
				not HammerPicker.OpensOnEquip({ onPlot = true, placing = false, panelOpen = true, pickerOpen = false })
			)
			t.ok(
				not HammerPicker.OpensOnEquip({ onPlot = true, placing = false, panelOpen = false, pickerOpen = true })
			)
		end
	)

	t.test("the picker lays out the same blueprint rules as the build menu (nothing re-priced)", function()
		-- A card's state and fee are BuildMenuLogic.Tile's, which is BlueprintBook.Row's.
		for _, e in ipairs(everything()) do
			local tile = BuildMenuLogic.Tile(e, ctx)
			local card = HammerPicker.Card(e, ctx)
			t.eq(card.state, tile.state, e.id)
			t.eq(card.fee, tile.cost, e.id)
		end
	end)
end
