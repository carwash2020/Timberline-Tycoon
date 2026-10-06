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
		t.eq(
			DialogueData.Line("needsPlot", { shop = "Dealership" }),
			"Buy a plot at the Land Office first, then open this."
		)
		t.eq(DialogueData.Card("needsPlot").noLabel, "Cancel")
		t.eq(DialogueData.Card("needsPlot").choice, true)
		t.eq(DialogueData.Card("offer").noLabel, "No")
	end)

	t.test("the card and the keeper module never lock walking", function()
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DialogueUI.luau")
		local drag = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DragController.luau")
		t.ok(
			string.find(ui, "GamepadNav.Focus(yes, column)", 1, true) ~= nil,
			"Yes is selected through the shared helper"
		)
		t.ok(string.find(ui, "GamepadNav.Restore(column)", 1, true) ~= nil, "and the selection is given back on close")
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

	t.test("the Robux shelf has a keeper line for the ask and for Yes, and the ask is a choice", function()
		local ask = DialogueData.Line("robuxOffer", { shop = "ToolShed", name = "2x Cash", price = "" })
		t.ok(string.find(ask, "2x Cash", 1, true) ~= nil, ask)
		t.ok(#DialogueData.Line("robuxAsk", { shop = "ToolShed" }) > 0)
		t.eq(DialogueData.Card("robuxOffer").choice, true)
		t.eq(DialogueData.Card("robuxOffer").noLabel, "No")
		t.eq(DialogueData.Card("robuxAsk").choice, false)
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DialogueUI.luau")
		t.ok(string.find(ui, 'Net.Remote("BuyRobuxItem"):FireServer(robux.kind, robux.key)', 1, true) ~= nil)
	end)

	t.test("the card stands above Roblox's hotbar on every device", function()
		-- UITheme.Bottom() is 82 (PC), 70 (phone), 106 (TV): the card clears each.
		for _, bottom in ipairs({ 82, 70, 106 }) do
			t.ok(DialogueData.CardBottom(bottom) >= bottom + 36, "clear of the hotbar at " .. bottom)
		end
		t.eq(DialogueData.CardBottom(-5), DialogueData.CardAboveHotbar, "a bad input never goes under")
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DialogueUI.luau")
		t.ok(string.find(ui, "DialogueData.CardBottom(UITheme.Bottom())", 1, true) ~= nil, "the card uses it")
		t.eq(string.find(ui, "1, -36", 1, true), nil, "the old fixed 36 px offset is gone")
	end)
end
