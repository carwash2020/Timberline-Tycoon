--!nocheck
-- Who may visit a plot, and which of those flags a door will honour.
return function(t)
	local PermissionLogic = t.shared("PermissionLogic")
	local DoorLogic = t.shared("DoorLogic")

	t.test("visit starts on, build starts off, and build covers taking a piece apart", function()
		t.eq(PermissionLogic.Allows({}, 9, "visit"), true)
		t.eq(PermissionLogic.Allows({}, 9, "collisions"), true)
		t.eq(PermissionLogic.Allows({}, 9, "build"), false)
		t.eq(PermissionLogic.Allows({}, 9, "destroy"), false)
		t.eq(PermissionLogic.Allows({}, 9, "grab"), false)
		t.eq(PermissionLogic.MustLeave({}, 9, 1), false)
		t.eq(PermissionLogic.MustLeave({}, 1, 1), false)

		local sheet = {}
		t.ok(PermissionLogic.Set(sheet, "anyone", "visit", false))
		t.ok(PermissionLogic.Set(sheet, "anyone", "build", true))
		t.ok(PermissionLogic.Set(sheet, "15", "grab", true))
		t.eq(PermissionLogic.Allows(sheet, 15, "build"), true)
		t.eq(PermissionLogic.Allows(sheet, 15, "destroy"), true)
		t.eq(PermissionLogic.Allows(sheet, 15, "grab"), true)
		t.eq(PermissionLogic.Allows(sheet, 99, "grab"), false)
		t.eq(PermissionLogic.Allows(sheet, 99, "destroy"), true)
		t.eq(PermissionLogic.MustLeave(sheet, 99, 1), true)
		t.eq(PermissionLogic.MustLeave(sheet, 1, 1), false)
		-- The toggle shows the stored bit, not the destroy bit that build implies.
		t.eq(PermissionLogic.Stored(sheet, "anyone", "destroy"), false)
		t.eq(PermissionLogic.Stored(sheet, "anyone", "build"), true)
		t.eq(PermissionLogic.Stored(sheet, "15", "grab"), true)
		t.eq(PermissionLogic.Stored(sheet, "15", "visit"), false)

		local text = PermissionLogic.Encode(sheet)
		local back = PermissionLogic.Decode(text)
		t.eq(back.anyone.visit, false)
		t.eq(back.anyone.build, true)
		t.eq(back["15"].grab, true)
		t.eq(PermissionLogic.Encode(back), text)
	end)

	t.test("a named list stops at MaxPeople, and a bad flag is ignored", function()
		local sheet = {}
		for i = 1, PermissionLogic.MaxPeople do
			t.ok(PermissionLogic.Set(sheet, tostring(i), "sit", true), tostring(i))
		end
		t.ok(not PermissionLogic.Set(sheet, tostring(PermissionLogic.MaxPeople + 1), "sit", true))
		t.ok(PermissionLogic.Set(sheet, "1", "sit", false))
		t.ok(not PermissionLogic.Set(sheet, "anyone", "fly", true))
		t.eq(sheet.anyone, nil)
	end)

	t.test("a door opens for the owner, and for someone they allowed to interact", function()
		local ok, why = DoorLogic.MayToggle(1, 2, 10, nil, nil)
		t.eq(ok, false)
		t.eq(why, "owner")
		t.eq(DoorLogic.MayToggle(1, 2, 10, nil, false), false)
		t.eq(DoorLogic.MayToggle(1, 2, 10, nil, true), true)
		t.eq(DoorLogic.MayToggle(1, 1, 10, nil, false), true)
	end)

	t.test("grab is one of the flags a later service can ask about", function()
		local sheet = {}
		t.eq(PermissionLogic.Allows(sheet, 9, "grab"), false)
		PermissionLogic.Set(sheet, "anyone", "grab", true)
		t.eq(PermissionLogic.Allows(sheet, 9, "grab"), true)
		t.eq(PermissionLogic.IsFlag("grab"), true)
	end)

	t.test("CanVisit: never your own plot, and only while the visit flag lets you in", function()
		t.eq(PermissionLogic.CanVisit({}, 2, 1), true, "visit starts on")
		t.eq(PermissionLogic.CanVisit({}, 1, 1), false, "not your own")
		t.eq(PermissionLogic.CanVisit({ anyone = { visit = false } }, 2, 1), false)
		t.eq(PermissionLogic.CanVisit({ anyone = { visit = false }, ["2"] = { visit = true } }, 2, 1), true)
		t.eq(PermissionLogic.CanVisit({ ["2"] = { visit = false } }, 2, 1), false)
		t.eq(PermissionLogic.CanVisit({ ["2"] = { visit = false } }, 3, 1), true)
		t.eq(PermissionLogic.CanVisit("junk", 2, 1), true, "a bad sheet falls back to the default")
	end)

	t.test("VisitList: owners of plots who let you in, sorted by name, without you", function()
		local list = PermissionLogic.VisitList({
			{ userId = 5, name = "cara", hasPlot = true, permissions = {} },
			{ userId = 2, name = "Bob", hasPlot = true, permissions = {} },
			{ userId = 1, name = "Me", hasPlot = true, permissions = {} },
			{ userId = 3, name = "Dan", hasPlot = false, permissions = {} },
			{ userId = 4, name = "Eve", hasPlot = true, permissions = { anyone = { visit = false } } },
			{
				userId = 6,
				name = "Fay",
				hasPlot = true,
				permissions = { anyone = { visit = false }, ["1"] = { visit = true } },
			},
			{ userId = 7, name = "Bob", hasPlot = true, permissions = {} },
		}, 1)
		local seen = {}
		for _, entry in ipairs(list) do
			table.insert(seen, entry.name .. entry.userId)
		end
		t.eq(seen, { "Bob2", "Bob7", "cara5", "Fay6" })
		t.eq(PermissionLogic.VisitList({}, 1), {})
	end)

	t.test("VisitTarget takes only a whole user id", function()
		t.eq(PermissionLogic.VisitTarget(12), 12)
		for _, bad in ipairs({ "12", 0, -3, 1.5, 0 / 0, math.huge, 2e15, true, {} }) do
			t.eq(PermissionLogic.VisitTarget(bad), nil, tostring(bad))
		end
		t.eq(PermissionLogic.VisitTarget(nil), nil)
	end)
end
