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

	---------------------------------------------------------------------------
	-- The v2 loop's hints (V2_PLAN.md §4)
	---------------------------------------------------------------------------

	t.test("v2: every device has a line for every v2 context: one line, short on a phone, no tokens", function()
		t.eq(#HintLogic.ContextsV2, 10)
		for _, device in ipairs(HintLogic.Devices) do
			for _, context in ipairs(HintLogic.ContextsV2) do
				local line = HintLogic.PickV2(device, context)
				local where = device .. " x " .. context
				t.ok(type(line) == "string" and #line > 0, where .. ": no line")
				local length = utf8.len(line)
				t.ok(
					length and length <= HintLogic.MaxLength,
					string.format("%s: %q is %s characters", where, line, tostring(length))
				)
				t.ok(not HintLogic.HasToken(line), where .. ": a token left in the hint")
				if device == "phone" then
					t.ok(
						#line <= HintLogic.PhoneMaxBytes,
						string.format("%s: %q is longer than a phone hint gets", where, line)
					)
				end
			end
		end
		-- PhoneMaxBytes is the longest v1 phone hint, the one HudLayout.spec fits.
		local longest = 0
		for _, context in ipairs(HintLogic.Contexts) do
			longest = math.max(longest, #HintLogic.Pick("phone", context))
		end
		t.eq(HintLogic.PhoneMaxBytes, longest)
	end)

	t.test("v2: chopping, driving and building read as in v1; the drag hints are each device's own", function()
		for _, device in ipairs(HintLogic.Devices) do
			for _, context in ipairs({ "chop", "driving", "build" }) do
				t.eq(HintLogic.PickV2(device, context), HintLogic.Pick(device, context), device .. " x " .. context)
			end
		end
		for _, context in ipairs({ "drag", "unequip", "holding" }) do
			local seen = {}
			for _, device in ipairs(HintLogic.Devices) do
				local line = HintLogic.PickV2(device, context)
				t.ok(not seen[line], context .. ": two devices share a line")
				seen[line] = true
			end
		end
		for _, context in ipairs(HintLogic.ContextsV2) do
			t.ok(not string.find(string.lower(HintLogic.PickV2("phone", context)), "click"), context)
			t.ok(not string.find(string.lower(HintLogic.PickV2("desktop", context)), "tap"), context)
			t.ok(not string.find(string.lower(HintLogic.PickV2("console", context)), "tap"), context)
		end
		t.eq(HintLogic.PickV2("desktop", "nope"), HintLogic.Pick("desktop", "chop"), "unknown: the chopping line")
		-- What each says.
		t.ok(string.find(HintLogic.PickV2("desktop", "unequip"), "axe away", 1, true))
		t.ok(string.find(HintLogic.PickV2("console", "unequip"), "LB + RB", 1, true), "the backpack's unequip")
		t.ok(string.find(HintLogic.PickV2("desktop", "holding"), "Scroll", 1, true), "distance by the wheel")
		t.ok(string.find(HintLogic.PickV2("phone", "holding"), "+/-", 1, true), "distance by the buttons")
		t.ok(string.find(HintLogic.PickV2("console", "holding"), "D-pad", 1, true), "distance by the D-pad")
		t.ok(string.find(HintLogic.PickV2("phone", "tooLong"), "shorter to fit your bed", 1, true))
		t.ok(string.find(HintLogic.PickV2("console", "backUp"), "sell the bed", 1, true))
		t.ok(string.find(HintLogic.PickV2("desktop", "tooHard"), "better", 1, true))
		t.eq(HintLogic.PickV2("phone", "thick"), "Thicker cuts take longer")
		t.eq(HintLogic.PickV2("desktop", "thick"), "Thicker cuts take longer")
		t.eq(HintLogic.PickV2("console", "thick"), "Thicker cuts take longer")
	end)

	t.test("v2: which context wins: driving, then a held piece, then an axe out, else dragging", function()
		local function state(over)
			local s = {
				driving = false,
				axeOut = false,
				holding = false,
				onWood = false,
				tooHard = false,
				thick = false,
				tooLong = false,
				bedVolume = 0,
				nearPad = false,
			}
			for k, v in pairs(over) do
				s[k] = v
			end
			return s
		end
		t.eq(HintLogic.ContextForV2(state({})), "drag", "empty hands: how to drag")
		t.eq(HintLogic.ContextForV2(state({ onWood = true })), "drag")
		t.eq(HintLogic.ContextForV2(state({ axeOut = true })), "chop")
		t.eq(HintLogic.ContextForV2(state({ axeOut = true, onWood = true })), "unequip", "an axe out over loose wood")
		t.eq(HintLogic.ContextForV2(state({ axeOut = true, tooHard = true })), "tooHard")
		t.eq(
			HintLogic.ContextForV2(state({ axeOut = true, thick = true })),
			"thick",
			"a thick face, an axe that can cut it"
		)
		t.eq(
			HintLogic.ContextForV2(state({ axeOut = true, thick = true, tooHard = true })),
			"tooHard",
			"too hard wins over thick"
		)
		t.eq(
			HintLogic.ContextForV2(state({ axeOut = true, onWood = true, thick = true })),
			"unequip",
			"a loose piece is dragged, thick or not"
		)
		t.eq(
			HintLogic.ContextForV2(state({ axeOut = true, onWood = true, tooHard = true })),
			"unequip",
			"you can still drag it"
		)
		t.eq(HintLogic.ContextForV2(state({ holding = true })), "holding")
		t.eq(HintLogic.ContextForV2(state({ holding = true, tooLong = true })), "tooLong")
		t.eq(HintLogic.ContextForV2(state({ holding = true, axeOut = true, onWood = true })), "holding")
		t.eq(HintLogic.ContextForV2(state({ driving = true })), "driving")
		t.eq(
			HintLogic.ContextForV2(state({ driving = true, nearPad = true })),
			"driving",
			"an empty bed: nothing to sell"
		)
		t.eq(HintLogic.ContextForV2(state({ driving = true, bedVolume = 4 })), "driving", "loaded, far from the pad")
		t.eq(HintLogic.ContextForV2(state({ driving = true, bedVolume = 4, nearPad = true })), "backUp")
		t.eq(
			HintLogic.ContextForV2(state({ driving = true, bedVolume = 0 / 0, nearPad = true })),
			"driving",
			"NaN: empty"
		)
		t.eq(HintLogic.ContextForV2(state({ driving = true, holding = true, axeOut = true })), "driving")
	end)

	t.test("v2: too long for the bed, too hard for the axe, near the pad", function()
		t.eq(HintLogic.TooLong(12, 10), true)
		t.eq(HintLogic.TooLong(10, 10), false, "exactly the bed's length fits")
		t.eq(HintLogic.TooLong(4, 10), false)
		t.eq(HintLogic.TooLong(12, nil), false, "no truck: nothing to fit")
		t.eq(HintLogic.TooLong(12, 0), false, "a bed-less truck")
		t.eq(HintLogic.TooLong(0 / 0, 10), false)
		t.eq(HintLogic.TooLong(12, 0 / 0), false)
		t.eq(HintLogic.TooLong("12", 10), false)

		local FieldGuide = t.shared("FieldGuide")
		t.eq(HintLogic.TooHardHits, 2 * FieldGuide.UsefulHitsV2)
		t.eq(HintLogic.TooHard(HintLogic.TooHardHits), false)
		t.eq(HintLogic.TooHard(HintLogic.TooHardHits + 1), true)
		t.eq(HintLogic.TooHard(math.huge), true, "an axe that can't cut it at all")
		t.eq(HintLogic.TooHard(0 / 0), false, "not known: no hint")

		local ItemCatalog = t.shared("ItemCatalog")
		local WoodData = t.shared("WoodData")
		local steel = ItemCatalog.GetAxe("SteelAxe")
		local rusty = ItemCatalog.GetAxe("RustyAxe")
		t.eq(HintLogic.Underpowered(steel.damage, WoodData.Get("frostwood").hardness), true, "a Steel Axe on frostwood")
		t.eq(HintLogic.Underpowered(rusty.damage, WoodData.Get("oak").hardness), false, "the tutorial oak")
		t.eq(HintLogic.Underpowered(rusty.damage, WoodData.Get("birch").hardness), false, "birch is slow, not too weak")
		t.eq(HintLogic.Underpowered(0 / 0, 10), false, "not a number: no hint")

		t.eq(HintLogic.ThickStuds, 2)
		t.eq(HintLogic.Thicker(2.6, 2.6), true, "a pine base")
		t.eq(HintLogic.Thicker(1.2, 1.2), false, "a thin top")
		t.eq(HintLogic.Thicker(2, 4), true, "the narrow side still counts")
		t.eq(HintLogic.Thicker(0 / 0, 3), false)

		local GameConfig = t.shared("GameConfig")
		t.eq(HintLogic.NearPad(GameConfig.SellTruckRange), true, "the range itself counts, as the sell prompt's")
		t.eq(HintLogic.NearPad(GameConfig.SellTruckRange + 0.5), false)
		t.eq(HintLogic.NearPad(nil), false, "no truck streamed in")
	end)

	t.test("v2: the too-hard hint never fires on wood the Field Guide calls a useful pace", function()
		local FieldGuide = t.shared("FieldGuide")
		local ItemCatalog = t.shared("ItemCatalog")
		local WoodData = t.shared("WoodData")
		local slow = 0
		for _, axe in ipairs(ItemCatalog.AxeLadder()) do
			for _, wood in ipairs(WoodData.All()) do
				local hits = FieldGuide.TrunkHits(axe, wood)
				if hits <= FieldGuide.UsefulHitsV2 then
					t.ok(not HintLogic.TooHard(hits), axe.id .. " on " .. wood.id)
				elseif HintLogic.TooHard(hits) then
					slow += 1
				end
			end
		end
		t.ok(slow > 0, "some wood is too hard for some axe")
		local starter = ItemCatalog.AxeLadder()[1]
		t.ok(not HintLogic.TooHard(FieldGuide.TrunkHits(starter, WoodData.Get("oak"))), "the tutorial's oak")
		t.ok(not HintLogic.TooHard(FieldGuide.TrunkHits(starter, WoodData.Get("birch"))), "birch is slow, not too hard")
	end)

	t.test("v2: {unequip} and {grab} are each device's words, capitalised at a sentence start", function()
		t.eq(HintLogic.Expand("Put it away ({unequip}).", "desktop"), "Put it away (press 1).")
		t.eq(HintLogic.Expand("Put it away ({unequip}).", "phone"), "Put it away (tap your axe).")
		t.eq(HintLogic.Expand("Put it away ({unequip}).", "console"), "Put it away (press LB + RB).")
		t.eq(HintLogic.Expand("{Unequip} first.", "console"), "Press LB + RB first.")
		t.eq(HintLogic.Expand("Then {grab} on a log.", "desktop"), "Then click and hold on a log.")
		t.eq(HintLogic.Expand("Then {grab} on a log.", "phone"), "Then tap and hold on a log.")
		t.eq(HintLogic.Expand("Then {grab} on a log.", "console"), "Then hold LT on a log.")
		t.eq(HintLogic.Expand("{Grab} on a log.", "phone"), "Tap and hold on a log.")
		t.eq(HintLogic.Expand("{Grab} on a log.", "console"), "Hold LT on a log.")
		for _, device in ipairs(HintLogic.Devices) do
			t.ok(not HintLogic.HasToken(HintLogic.Expand("{unequip} {Grab}", device)), device)
		end
		t.ok(not string.find(HintLogic.Expand("{grab}", "phone"), "click"), "a phone never clicks")
		t.ok(not string.find(HintLogic.Expand("{unequip}", "desktop"), "tap"), "a computer never taps")
	end)
end
