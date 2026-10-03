--!nocheck
-- SaveFlush: every listener runs, in order, and one that errors doesn't
-- stop the rest. ProfileService calls Run from OnSave and OnLastSave,
-- which both fire before ProfileStore copies the profile.
return function(t)
	t.test("listeners run in the order they were added", function()
		local SaveFlush = t.loader():server("SaveFlush")
		local player = { Name = "Ada" }
		local seen = {}
		SaveFlush.Add(function(p)
			table.insert(seen, "a:" .. p.Name)
		end)
		SaveFlush.Add(function(p)
			table.insert(seen, "b:" .. p.Name)
		end)
		SaveFlush.Run(player)
		t.eq(seen, { "a:Ada", "b:Ada" })
		t.eq(SaveFlush.Count(), 2)
	end)

	t.test("a listener that errors is warned and the next one still runs", function()
		local loader = t.loader()
		local SaveFlush = loader:server("SaveFlush")
		local ran = false
		SaveFlush.Add(function()
			error("boom")
		end)
		SaveFlush.Add(function()
			ran = true
		end)
		SaveFlush.Run({ Name = "Bea" })
		t.eq(ran, true)
		t.ok(loader.warnings[1] and string.find(loader.warnings[1], "boom", 1, true) ~= nil, loader.warnings[1])
	end)
end
