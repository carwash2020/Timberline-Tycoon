--!nocheck
-- The settings panel binds gamepad keys only while it is open, and never
-- takes the axe's RT.
return function(t)
	t.test("the panel unbinds on close and does not take RT", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/LogicPanelUI.luau")
		t.ok(string.find(src, "UnbindAction", 1, true), "keys are unbound")
		t.ok(string.find(src, "GamepadNav.Restore", 1, true), "B gives the selection back")
		t.ok(string.find(src, "Enum.KeyCode.ButtonB", 1, true), "B closes")
		t.eq(string.find(src, "ButtonR2", 1, true), nil)
		t.ok(string.find(src, 'FindFirstChild("LogicSet")', 1, true), "no wait for a remote that is not there yet")
		t.ok(string.find(src, 'text = "-"', 1, true), "minus is labelled")
		t.ok(string.find(src, 'text = "+"', 1, true), "plus is labelled")
		t.ok(string.find(src, 'text = "Done"', 1, true), "done is labelled")
		t.ok(string.find(src, "TextScaled = true", 1, true), "labels scale to the face")
		t.ok(string.find(src, "SparkworksTheme", 1, true), "the layer lives in this module")
		local theme = fs.readFile("src/StarterPlayer/StarterPlayerScripts/UITheme.luau")
		t.eq(string.find(theme, "LogicPanel", 1, true), nil, "UITheme is Lane U's")
	end)
end
