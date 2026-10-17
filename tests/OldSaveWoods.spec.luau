--!nocheck
-- Old saves load unchanged (WORLD-T323): woods are saved by index and by id, and
-- Cherry and Willow went on the end, so every index and id an old save holds
-- still names the same wood; a plot piece filled with an old wood keeps it.
return function(t)
	local WoodData = t.shared("WoodData")
	local Automation = t.shared("AutomationLogic")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")

	local OLD = {
		"oak",
		"birch",
		"pine",
		"maple",
		"palmwood",
		"frostwood",
		"lanternwood",
		"emberwood",
		"phantomwood",
		"lumenwood",
		"bogcypress",
		"ironwood",
	}

	t.test("the detector filter's saved indices still name the same twelve woods; the new two follow", function()
		for i, id in ipairs(OLD) do
			t.eq(WoodData.All()[i].id, id, "index " .. i)
			t.eq(Automation.FilterMatches(i, id), true, "filter " .. i .. " matches " .. id)
			t.eq(Automation.FilterMatches(i, "cherry"), false)
		end
		t.eq(Automation.FilterMatches(13, "cherry"), true)
		t.eq(Automation.FilterMatches(14, "willow"), true)
		t.eq(Automation.CleanFilter(12), 12)
		t.eq(Automation.CleanFilter(0), 0, "any wood is still 0")
	end)

	t.test("a plot piece saved with an old wood keeps it through Migrate; a new wood is valid too", function()
		local data = Util.deepCopy(Schema.Template)
		data.plot.placed = {}
		for i, id in ipairs(OLD) do
			table.insert(
				data.plot.placed,
				{ uid = "w" .. i, blueprintId = "Wall", x = i, z = 2, rot = 0, y = 0.4, wood = id, paid = 32 }
			)
		end
		table.insert(
			data.plot.placed,
			{ uid = "c", blueprintId = "Wall", x = 20, z = 2, rot = 0, y = 0.4, wood = "cherry", paid = 32 }
		)
		table.insert(
			data.plot.placed,
			{ uid = "x", blueprintId = "Wall", x = 21, z = 2, rot = 0, y = 0.4, wood = "not-a-wood", paid = 32 }
		)
		Schema.Migrate(data)
		for i, id in ipairs(OLD) do
			t.eq(data.plot.placed[i].wood, id, id)
		end
		t.eq(data.plot.placed[#OLD + 1].wood, "cherry")
		t.eq(data.plot.placed[#OLD + 2].wood, nil, "an unknown wood is still cleared")
	end)
end
