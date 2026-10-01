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
		local function state(driving, inSellZone, carrying)
			return { driving = driving, inSellZone = inSellZone, carrying = carrying }
		end
		t.eq(HintLogic.ContextFor(state(false, false, false)), "chop")
		t.eq(HintLogic.ContextFor(state(false, false, true)), "carrying")
		t.eq(HintLogic.ContextFor(state(false, true, true)), "sellPad", "on the pad with logs: sell them")
		t.eq(HintLogic.ContextFor(state(false, true, false)), "sellPad")
		t.eq(HintLogic.ContextFor(state(true, true, true)), "driving", "parked on the pad: hop out first")
		t.eq(HintLogic.ContextFor(state(true, false, false)), "driving")
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
end
