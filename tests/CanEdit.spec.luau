--!nocheck
-- Lane F: PlotLogic.CanEdit, the one edit-rights rule (QA BL4).
return function(t)
	local PlotLogic = t.shared("PlotLogic")
	local PermissionLogic = t.shared("PermissionLogic")

	t.test("the owner may always edit; a stranger may not by default", function()
		local perms = {}
		for _, flag in ipairs({ "build", "destroy", "interact", "paint", "grab" }) do
			t.eq(PlotLogic.CanEdit(perms, 7, 7, flag), true, "owner " .. flag)
			t.eq(PlotLogic.CanEdit(perms, 9, 7, flag), false, "stranger " .. flag)
		end
	end)

	t.test("a friend with build may build, paint and destroy, not grab", function()
		local perms = {}
		t.eq(PermissionLogic.Set(perms, "9", "build", true), true)
		t.eq(PlotLogic.CanEdit(perms, 9, 7, "build"), true)
		t.eq(PlotLogic.CanEdit(perms, 9, 7, "paint"), true, "paint rides on build")
		t.eq(PlotLogic.CanEdit(perms, 9, 7, "destroy"), true, "build implies destroy")
		t.eq(PlotLogic.CanEdit(perms, 9, 7, "grab"), false)
		t.eq(PlotLogic.CanEdit(perms, 10, 7, "build"), false, "only that friend")
	end)

	t.test("junk is refused", function()
		t.eq(PlotLogic.CanEdit({}, 9, 7, "launch"), false)
		t.eq(PlotLogic.CanEdit({}, "9", 7, "build"), false)
		t.eq(PlotLogic.CanEdit({}, 0, 0, "build"), false, "no owner, no rights")
		t.eq(PlotLogic.CanEdit(nil, 9, 7, "build"), false)
	end)
end
