--!nocheck
-- PickerSequence: the quality screen and the plot picker take turns on a
-- first join (they used to open together, the quality backdrop over the plot
-- picker's buttons, both holding a movement lock).
return function(t)
	local PickerSequence = t.shared("PickerSequence")
	local fs = require("@lune/fs")

	t.test("quality goes first, whichever asks first, and the plot picker opens when it is done", function()
		local seq = PickerSequence.new()
		local seen = {}
		seq.OnChange(function(active)
			table.insert(seen, active or "none")
		end)
		t.eq(seq.Request("plot"), true, "alone, the plot picker opens")
		t.eq(seq.Request("quality"), true, "the quality screen takes the front")
		t.eq(seq.Active(), "quality")
		t.ok(seq.Waiting("plot"), "the plot picker waits")
		t.ok(not seq.IsActive("plot"))
		seq.Done("quality")
		t.eq(seq.Active(), "plot", "its turn")
		t.ok(not seq.Waiting("plot"))
		seq.Done("plot")
		t.eq(seq.Active(), nil)
		t.eq(seen, { "plot", "quality", "plot", "none" })
	end)

	t.test("regression: the two are never up at once", function()
		-- Both asked in the same breath (ProfileLoaded and the plot offer arrive together).
		local seq = PickerSequence.new()
		local up = 0
		local function count()
			up = 0
			for _, id in ipairs(PickerSequence.Order) do
				if seq.IsActive(id) then
					up += 1
				end
			end
			return up
		end
		seq.Request("quality")
		seq.Request("plot")
		t.eq(count(), 1)
		seq.Done("quality")
		t.eq(count(), 1)
		seq.Done("plot")
		t.eq(count(), 0)
	end)

	t.test("asking twice is harmless, finishing something never asked is too, and unknown ids never show", function()
		local seq = PickerSequence.new()
		local changes = 0
		seq.OnChange(function()
			changes += 1
		end)
		seq.Request("quality")
		seq.Request("quality")
		t.eq(changes, 1, "one change")
		seq.Done("plot")
		t.eq(changes, 1)
		t.eq(seq.Request("tutorial"), false)
		t.eq(seq.Active(), "quality")
		seq.Done("quality")
		seq.Done("quality")
		t.eq(changes, 2)
	end)

	t.test("a listener that errors does not stop the next one or the sequence", function()
		local seq = PickerSequence.new()
		local heard = false
		seq.OnChange(function()
			error("boom")
		end)
		seq.OnChange(function()
			heard = true
		end)
		seq.Request("quality")
		t.ok(heard)
		t.eq(seq.Active(), "quality")
	end)

	t.test("the shared one is one table", function()
		t.ok(PickerSequence.Shared() == PickerSequence.Shared())
	end)

	t.test("the two screens use it: ask when shown, done when closed", function()
		local quality = fs.readFile("src/StarterPlayer/StarterPlayerScripts/QualityPickerUI.luau")
		t.ok(string.find(quality, 'sequence.Request("quality")', 1, true))
		t.ok(string.find(quality, 'sequence.Done("quality")', 1, true))
		local plot = fs.readFile("src/StarterPlayer/StarterPlayerScripts/PlotPickerUI.luau")
		t.ok(string.find(plot, 'sequence.Request("plot")', 1, true), "the plot picker asks for its turn")
		t.ok(string.find(plot, 'sequence.Done("plot")', 1, true), "and gives it back")
		t.ok(string.find(plot, "sequence.OnChange", 1, true), "and opens when the quality screen is done")
		t.ok(string.find(plot, "pendingOffer", 1, true), "keeping the newest offer meanwhile")
	end)
end
