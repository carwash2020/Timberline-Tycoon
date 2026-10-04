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
end
