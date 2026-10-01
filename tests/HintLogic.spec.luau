--!nocheck
-- The control hint (HUD) and the device words in Murph's lines.
return function(t)
	local HintLogic = t.shared("HintLogic")

	t.test("every device has a line for every context, none over 40 characters", function()
		t.eq(HintLogic.MaxLength, 40)
		t.eq(#HintLogic.Devices, 3)
		t.eq(#HintLogic.Contexts, 5)
		for _, device in ipairs(HintLogic.Devices) do
			for _, context in ipairs(HintLogic.Contexts) do
				local line = HintLogic.Pick(device, context)
				local where = device .. " x " .. context
				t.ok(type(line) == "string" and #line > 0, where .. ": no line")
				local length = utf8.len(line)
				t.ok(length and length <= 40, string.format("%s: %q is %s characters", where, line, tostring(length)))
				t.ok(not HintLogic.HasToken(line), where .. ": a token left in the hint")
			end
		end
	end)

	t.test("each device gets its own words", function()
		t.eq(HintLogic.Pick("phone", "driving"), "Stick to drive · Jump to hop out")
		t.eq(HintLogic.Pick("desktop", "driving"), "WASD to drive · Space to hop out")
		t.eq(HintLogic.Pick("console", "driving"), "Left stick to drive · A to hop out")
		t.eq(HintLogic.Pick("desktop", "carrying"), "Take logs to your truck's tailgate")
		t.eq(HintLogic.Pick("phone", "chop"), "Tap a tree to swing your axe")
		t.eq(HintLogic.Pick("desktop", "chop"), "Click a tree to swing · E to interact")
		t.eq(HintLogic.Pick("console", "chop"), "RT to swing · X to interact")
		for _, context in ipairs({ "chop", "driving", "sellPad", "build" }) do
			local seen = {}
			for _, device in ipairs(HintLogic.Devices) do
				local line = HintLogic.Pick(device, context)
				t.ok(not seen[line], context .. ": two devices share a line")
				seen[line] = true
			end
		end
		-- The touch lines never say click; the computer ones never say tap.
		for _, context in ipairs(HintLogic.Contexts) do
			t.ok(not string.find(string.lower(HintLogic.Pick("phone", context)), "click"), context)
			t.ok(not string.find(string.lower(HintLogic.Pick("desktop", context)), "tap"), context)
			t.ok(not string.find(string.lower(HintLogic.Pick("console", context)), "tap"), context)
		end
	end)

	t.test("which context wins: driving, then the sell pad, then logs in hand, else chopping", function()
		local function state(driving, inSellZone, carrying, sellable)
			return {
				driving = driving,
				inSellZone = inSellZone,
				carrying = carrying,
				sellable = sellable or (if carrying then 2 else 0),
			}
		end
		t.eq(HintLogic.ContextFor(state(false, false, false)), "chop")
		t.eq(HintLogic.ContextFor(state(false, false, true)), "carrying")
		t.eq(HintLogic.ContextFor(state(false, true, true)), "sellPad", "on the pad with logs: sell them")
		t.eq(
			HintLogic.ContextFor(state(false, true, false, 6)),
			"sellPad",
			"empty hands, a full bed parked by the mill"
		)
		t.eq(HintLogic.ContextFor(state(true, true, true)), "driving", "parked on the pad: hop out first")
		t.eq(HintLogic.ContextFor(state(true, false, false)), "driving")
	end)

	-- UI-05: "Press E to sell your logs" only when the Sell prompt is up.
	t.test("on the sell pad with nothing to sell, the hint is the usual one", function()
		local empty = { driving = false, inSellZone = true, carrying = false, sellable = 0 }
		t.eq(HintLogic.ContextFor(empty), "chop", "nothing in hand, bed or Sky Bin")
		local far = { driving = false, inSellZone = false, carrying = false, sellable = 6 }
		t.eq(HintLogic.ContextFor(far), "chop", "off the pad, a load doesn't make it the sell hint")
	end)

	t.test("what the pad would sell: hands, the bed only with the truck in range, the Sky Bin", function()
		local GameConfig = t.shared("GameConfig")
		local RANGE = GameConfig.SellTruckRange
		t.eq(HintLogic.SellCount(0, 0, nil, 0, RANGE), 0)
		t.eq(HintLogic.SellCount(nil, nil, nil, nil, RANGE), 0, "the save still loading")
		t.eq(HintLogic.SellCount(2, 0, nil, 0, RANGE), 2, "logs in hand")
		t.eq(HintLogic.SellCount(0, 6, 20, 0, RANGE), 6, "the truck parked by the mill")
		t.eq(HintLogic.SellCount(0, 6, RANGE, 0, RANGE), 6, "right at the range still counts (as the server's <=)")
		t.eq(HintLogic.SellCount(0, 6, RANGE + 0.5, 0, RANGE), 0, "the truck too far: its bed doesn't sell")
		t.eq(HintLogic.SellCount(0, 6, nil, 0, RANGE), 0, "no truck streamed in")
		t.eq(HintLogic.SellCount(0, 0, 10, 3, RANGE), 3, "the Sky Bin sells from the pad")
		t.eq(HintLogic.SellCount(2, 6, 10, 3, RANGE), 11, "all three")
		t.eq(HintLogic.SellCount("2", 0 / 0, 0 / 0, -4, RANGE), 0, "odd values count for nothing")
		t.eq(HintLogic.SellCount(1.7, 0, nil, 0, RANGE), 1, "whole logs")
	end)

	t.test("SellCount counts what CarryController's Sell prompt counts", function()
		-- CarryController belongs to another stream: if its sell rule loses
		-- or gains an ingredient, SellCount (and this) should follow.
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/CarryController.luau")
		local sell = string.match(source, "local function setupSellPrompt%(%).-\nend\n")
		t.ok(sell, "CarryController's setupSellPrompt moved")
		for _, ingredient in ipairs({ "carried()", "bedCount()", "GameConfig.SellTruckRange", '"SkyBin"', "n > 0" }) do
			t.ok(string.find(sell, ingredient, 1, true), "the Sell prompt no longer uses " .. ingredient)
		end
	end)

	t.test("{click} and {tap} become each device's word, capitalised at a sentence start", function()
		t.eq(HintLogic.Expand("{Click}, or hold.", "phone"), "Tap, or hold.")
		t.eq(HintLogic.Expand("{Click}, or hold.", "desktop"), "Click, or hold.")
		t.eq(HintLogic.Expand("{Click}, or hold.", "console"), "Press RT, or hold.")
		t.eq(HintLogic.Expand("Just {click} it.", "phone"), "Just tap it.")
		t.eq(HintLogic.Expand("Just {tap} it.", "desktop"), "Just click it.")
		t.eq(HintLogic.Expand("Just {tap} it.", "console"), "Just press RT it.")
		t.eq(HintLogic.Expand("{Tap} twice", "desktop"), "Click twice")
		t.eq(HintLogic.Expand("No tokens here.", "phone"), "No tokens here.")
		t.eq(HintLogic.Expand("{nope} stays", "phone"), "{nope} stays", "unknown words are left alone")
		t.ok(HintLogic.HasToken("{nope} stays"))
	end)

	t.test("{press} is pressing a button on the screen: a gamepad presses it with A, not RT", function()
		t.eq(HintLogic.Expand("{Press} again to skip", "phone"), "Tap again to skip")
		t.eq(HintLogic.Expand("{Press} again to skip", "desktop"), "Click again to skip")
		t.eq(HintLogic.Expand("{Press} again to skip", "console"), "Press again to skip")
		t.eq(HintLogic.Expand("Then {press} it.", "console"), "Then press it.")
		t.eq(HintLogic.Expand("{Press} or {click}", "console"), "Press or press RT", "two tokens, two meanings")
		t.ok(not HintLogic.HasToken(HintLogic.Expand("{Press} again", "phone")))
	end)
end
