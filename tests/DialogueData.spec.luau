--!nocheck
-- Each shopkeeper has their own lines. The offer names the item and the price.
return function(t)
	local DialogueData = t.shared("DialogueData")
	local fs = require("@lune/fs")

	t.test("the three counters do not share a script, and the buttons fit a thumb", function()
		t.ok(DialogueData.ButtonPx >= 44)
		local shed = DialogueData.Line("greet", { shop = "ToolShed" })
		local hearth = DialogueData.Line("greet", { shop = "HearthAndHome" })
		local lot = DialogueData.Line("greet", { shop = "Dealership" })
		t.ok(shed ~= hearth and hearth ~= lot and shed ~= lot)
		local keys =
			{ "greet", "offer", "broke", "declined", "missing", "alreadyOwned", "needsLand", "thanks", "locked" }
		for _, key in ipairs(keys) do
			t.ok(#DialogueData.Line(key, { shop = "ToolShed", name = "Steel Axe", price = "$160" }) > 0, key)
		end
		local offer = DialogueData.Line("offer", { shop = "ToolShed", name = "Steel Axe", price = "$160" })
		t.ok(string.find(offer, "Steel Axe", 1, true) ~= nil, offer)
		t.ok(string.find(offer, "$160", 1, true) ~= nil, offer)
		t.ok(DialogueData.Line("offer", { shop = "HearthAndHome", name = "Coat", price = "$500" }) ~= offer)
	end)

	t.test("the card and the keeper module never lock walking", function()
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DialogueUI.luau")
		local drag = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DragController.luau")
		t.ok(string.find(ui, "SelectedObject", 1, true) ~= nil)
		t.ok(string.find(ui, "NextSelectionLeft", 1, true) ~= nil)
		t.ok(string.find(ui, "NextSelectionRight", 1, true) ~= nil)
		t.ok(string.find(ui, "ButtonB", 1, true) ~= nil)
		t.ok(string.find(ui, "ButtonX", 1, true) ~= nil)
		t.eq(string.find(ui, "DPadLeft", 1, true), nil)
		t.eq(string.find(ui, "DPadRight", 1, true), nil)
		t.eq(string.find(ui, "WalkSpeed", 1, true), nil)
		t.eq(string.find(fs.readFile("src/ServerScriptService/DialogueService.luau"), "WalkSpeed", 1, true), nil)
		t.ok(string.find(drag, "ShopBox", 1, true) ~= nil, "carry watches shop boxes")
	end)
end
