--!nocheck
-- JoinPickLogic: which join screens open, for which save, in which order.
return function(t)
	local Join = t.shared("JoinPickLogic")
	local PickerSequence = t.shared("PickerSequence")

	local function state(over)
		local s = { slotChosen = false, onBase = false, needsQuality = false, pickedHasPlot = false }
		for k, v in pairs(over or {}) do
			s[k] = v
		end
		return s
	end

	t.test("a first join: quality, then the save picker; the plot picker waits for a pick", function()
		t.eq(Join.Screens(state({ needsQuality = true })), { "quality", "slot" })
		t.eq(Join.Screens(state()), { "slot" })
	end)

	t.test("only a chosen save WITH a plot leads to the plot picker", function()
		t.eq(Join.Screens(state({ slotChosen = true, pickedHasPlot = true })), { "plot" })
		t.eq(Join.Screens(state({ slotChosen = true, pickedHasPlot = false })), {}, "no plot: straight into the world")
		t.eq(
			Join.Screens(state({ slotChosen = true, pickedHasPlot = true, needsQuality = true })),
			{ "quality", "plot" }
		)
	end)

	t.test("a player already standing on a base is not asked again", function()
		t.eq(Join.Screens(state({ onBase = true })), {})
		t.eq(Join.Screens(state({ onBase = true, slotChosen = true, pickedHasPlot = true })), {})
		t.eq(Join.NeedsSlotPick(false, true), false)
		t.eq(Join.NeedsPlotPick(true, true, true), false)
	end)

	t.test("nobody is put into a save they did not pick", function()
		t.eq(Join.NeedsSlotPick(false, false), true)
		t.eq(Join.NeedsPlotPick(false, false, true), false, "a plot picker for a save nobody chose never opens")
	end)

	t.test("the screens take turns in the shared sequence: quality, save, plot", function()
		t.eq(PickerSequence.Order, { "quality", "slot", "plot" })
		local seq = PickerSequence.new()
		seq.Request("plot")
		seq.Request("slot")
		seq.Request("quality")
		t.eq(seq.Active(), "quality")
		seq.Done("quality")
		t.eq(seq.Active(), "slot", "the save picker is never under the plot picker")
		seq.Done("slot")
		t.eq(seq.Active(), "plot")
	end)

	t.test("the save picker's words: Last played before a pick, no wipe button on the list", function()
		t.eq(Join.ActiveBadge(true), "Last played")
		t.eq(Join.ActiveBadge(false), "Playing")
		t.eq(Join.PlayLabel(true, false, true), "PLAY")
		t.eq(Join.PlayLabel(true, true, false), "START")
		t.eq(Join.PlayLabel(false, false, false), "LOAD")
		t.eq(Join.PlayLabel(false, true, false), "START")
		t.eq(Join.PlayLabel(false, false, true), nil, "the playing save has no button (Restart save is in Settings)")
		local fs = require("@lune/fs")
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/SaveSlotUI.luau")
		t.eq(string.find(ui, "REDO", 1, true), nil)
		t.eq(string.find(ui, "Redo", 1, true), nil)
	end)

	t.test("a save row says whether it has a plot", function()
		t.eq(Join.PlotText(false, 0, 0), "No plot yet")
		t.eq(Join.PlotText(true, 1, 0), "Plot, 1 piece")
		t.eq(Join.PlotText(true, 12, 2), "Plot, 12 pieces, 2 packed")
	end)
end
