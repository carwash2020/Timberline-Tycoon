--!nocheck
-- NPCDialogue: which line is said when you talk (progress, weather, and the
-- hour, else a general line), the no-repeat shuffle, and the name-tag sizes.
-- There are no floating speech bubbles any more: every talk is the dialogue box.

return function(t)
	local NPCDialogue = t.shared("NPCDialogue")
	local NPCData = t.shared("NPCData")
	local TutorialData = t.shared("TutorialData")

	local function ctx(progress, band, weather)
		return {
			band = band or "day",
			weather = weather or "Clear",
			progress = progress,
		}
	end

	local fresh = {
		loaded = true,
		sold = false,
		upgradedAxe = false,
		sawmill = false,
	}
	local veteran = {
		loaded = true,
		sold = true,
		upgradedAxe = true,
		sawmill = true,
	}

	t.test("the hour splits into morning, day, evening, and night", function()
		t.eq(NPCDialogue.BandOf(5), "morning")
		t.eq(NPCDialogue.BandOf(10.9), "morning")
		t.eq(NPCDialogue.BandOf(11), "day")
		t.eq(NPCDialogue.BandOf(16.9), "day")
		t.eq(NPCDialogue.BandOf(17), "evening")
		t.eq(NPCDialogue.BandOf(19), "night")
		t.eq(NPCDialogue.BandOf(2), "night")
		t.eq(NPCDialogue.BandOf(24), "night")
		t.eq(NPCDialogue.WeatherKey("Rain"), "rain")
		t.eq(NPCDialogue.WeatherKey("Snow"), "rain")
		t.eq(NPCDialogue.WeatherKey("Storm"), "storm")
		t.eq(NPCDialogue.WeatherKey("Blizzard"), "storm")
		t.eq(NPCDialogue.WeatherKey("Fog"), "fog")
		t.eq(NPCDialogue.WeatherKey("Clear"), nil)
	end)

	t.test("progress comes off the attributes a client can actually see", function()
		local unknown = NPCDialogue.ProgressOf({
			loaded = false,
			tutorialStep = 0,
			tutorialRefresher = false,
			bestAxeTier = 9,
			sawmillStock = "SawmillRickety",
			placedSawmill = true,
		})
		t.eq(unknown.loaded, false)
		t.eq(unknown.sold, false)
		local newbie = NPCDialogue.ProgressOf({
			loaded = true,
			tutorialStep = 2,
			tutorialRefresher = nil,
			bestAxeTier = 1,
			sawmillStock = "",
			placedSawmill = false,
		})
		t.eq(newbie.sold, false)
		t.eq(newbie.upgradedAxe, false)
		t.eq(newbie.sawmill, false)
		-- The first sale is the sell step. Standing on the step hasn't sold yet.
		local onSellStep = NPCDialogue.ProgressOf({
			loaded = true,
			tutorialStep = TutorialData.RefresherLast,
			tutorialRefresher = false,
			bestAxeTier = 1,
			sawmillStock = nil,
			placedSawmill = false,
		})
		t.eq(onSellStep.sold, false)
		local sold = NPCDialogue.ProgressOf({
			loaded = true,
			tutorialStep = TutorialData.RefresherLast + 1,
			tutorialRefresher = false,
			bestAxeTier = 2,
			sawmillStock = nil,
			placedSawmill = false,
		})
		t.eq(sold.sold, true)
		t.eq(sold.upgradedAxe, true)
		local done = NPCDialogue.ProgressOf({
			loaded = true,
			tutorialStep = 0,
			tutorialRefresher = false,
			bestAxeTier = 1,
			sawmillStock = "SawmillRickety",
			placedSawmill = false,
		})
		t.eq(done.sold, true)
		t.eq(done.sawmill, true)
		local placed = NPCDialogue.ProgressOf({
			loaded = true,
			tutorialStep = 0,
			tutorialRefresher = false,
			bestAxeTier = 1,
			sawmillStock = "",
			placedSawmill = true,
		})
		t.eq(placed.sawmill, true)
		local refresher = NPCDialogue.ProgressOf({
			loaded = true,
			tutorialStep = 1,
			tutorialRefresher = true,
			bestAxeTier = 3,
			sawmillStock = "",
		})
		t.eq(refresher.sold, true)
	end)

	t.test("Murph's tips are no longer a pool: his Talk is QuestUI's, tips and all", function()
		local murph = NPCData.Get("Murph")
		t.ok(murph.tips and #murph.tips >= 1, "the onboarding tips still exist as data")
		for _, line in ipairs(murph.tips) do
			t.ok(#line <= NPCDialogue.ReactMax, "a tip fits a dialogue page: " .. line)
		end
		-- A new player's high roll is a general line, never a "tip" pool.
		local fresh = { loaded = true, sold = false, upgradedAxe = false, sawmill = false }
		t.eq(NPCDialogue.PoolFor(murph, ctx(fresh), 0.99).kind, "line")
	end)

	t.test("a low roll prefers progress, then weather, then the hour", function()
		local millie = NPCData.Get("Millie")
		t.eq(NPCDialogue.PoolFor(millie, ctx(fresh), 0).kind, "unsold")
		local withSaw = {
			loaded = true,
			sold = true,
			upgradedAxe = true,
			sawmill = true,
		}
		t.eq(NPCDialogue.PoolFor(millie, ctx(withSaw), 0).kind, "sawmill")
		local rustySold = {
			loaded = true,
			sold = true,
			upgradedAxe = false,
			sawmill = false,
		}
		-- Still on the starter axe: that beats a sale line.
		t.eq(NPCDialogue.PoolFor(millie, ctx(rustySold), 0).kind, "rusty")
		local tink = NPCData.Get("Tink")
		t.eq(NPCDialogue.PoolFor(tink, ctx(rustySold), 0).kind, "rusty")
		local rainy = {
			loaded = true,
			sold = true,
			upgradedAxe = true,
			sawmill = false,
		}
		-- Dale has no sawmill lines; rain beats the hour when both could apply.
		local dale = NPCData.Get("Dale")
		t.eq(NPCDialogue.PoolFor(dale, ctx(rainy, "morning", "Rain"), 0).kind, "axe")
		local noAxe = {
			loaded = true,
			sold = true,
			upgradedAxe = false,
			sawmill = false,
		}
		-- Rosa has no rusty or sale lines, so rain wins, then the morning.
		local rosa = NPCData.Get("Rosa")
		t.eq(NPCDialogue.PoolFor(rosa, ctx(noAxe, "morning", "Rain"), 0).kind, "sale")
		-- Wait, Rosa has sale lines. Use a weather-only case: Gus in fog with no matching progress.
		-- veteran has sawmill; Gus has sawmill lines? He doesn't. He has sale and axe.
		t.eq(NPCDialogue.PoolFor(NPCData.Get("Gus"), ctx(veteran, "night", "Fog"), 0).kind, "axe")
		local fogOnly = NPCDialogue.PoolFor(NPCData.Get("Hazel"), ctx(veteran, "day", "Fog"), 0)
		-- Hazel has no sawmill or axe lines. Veteran is sold and upgraded, so sale, else fog.
		t.eq(fogOnly.kind, "sale")
		local clearMorning = {
			loaded = true,
			sold = true,
			upgradedAxe = true,
			sawmill = false,
		}
		-- Bram has axe lines, so progress wins over morning.
		t.eq(NPCDialogue.PoolFor(NPCData.Get("Bram"), ctx(clearMorning, "morning", "Clear"), 0).kind, "axe")
		-- No progress match: Murph's morning, on a clear day, for a veteran without using sawmill.
		-- Murph has sawmill, axe, sale. Strip by using a fake npc.
		local quiet = {
			id = "Test",
			name = "Test",
			role = "Test",
			lines = { "general" },
			greetings = { "hi" },
			react = { morning = { "dawn" }, rain = { "wet" }, sale = { "sold" } },
		}
		t.eq(NPCDialogue.PoolFor(quiet, ctx(clearMorning, "morning", "Rain"), 0).kind, "sale")
		local noSale = {
			loaded = true,
			sold = true,
			upgradedAxe = true,
			sawmill = false,
		}
		local hourNpc = {
			id = "Test",
			name = "Test",
			role = "Test",
			lines = { "general" },
			greetings = { "hi" },
			react = { morning = { "dawn" }, rain = { "wet" } },
		}
		t.eq(NPCDialogue.PoolFor(hourNpc, ctx(noSale, "morning", "Clear"), 0).kind, "morning")
		t.eq(NPCDialogue.PoolFor(hourNpc, ctx(noSale, "morning", "Storm"), 0).kind, "morning")
		t.eq(NPCDialogue.PoolFor(hourNpc, ctx(noSale, "day", "Rain"), 0).kind, "rain")
		t.eq(NPCDialogue.PoolFor(hourNpc, ctx(noSale, "day", "Clear"), 0.99).kind, "line")
	end)

	t.test("a shuffle says every line once before repeating", function()
		local rng = {
			NextInteger = function(_self, a, _b)
				return a
			end,
		}
		local lines = { "a", "b", "c", "d" }
		local bag = {}
		local seen = {}
		for _ = 1, #lines do
			local line
			line, bag = NPCDialogue.Draw(lines, bag, rng)
			t.ok(not seen[line], "repeated " .. tostring(line))
			seen[line] = true
		end
		t.eq(seen.a and seen.b and seen.c and seen.d, true)
		t.eq(#bag, 0)
		-- A bag from a longer pool is thrown out.
		local again
		again, bag = NPCDialogue.Draw({ "only" }, { 4, 2 }, rng)
		t.eq(again, "only")
		t.eq(NPCDialogue.Draw({}, {}, rng), nil)
	end)

	t.test("name tags are smaller on a phone and don't reach across the plaza", function()
		t.eq(NPCDialogue.IsPhone(true, false, 800), true)
		t.eq(NPCDialogue.IsPhone(true, false, 900), false)
		t.eq(NPCDialogue.IsPhone(true, true, 400), false)
		t.eq(NPCDialogue.IsPhone(false, false, 400), false)
		local Vector2 = t.roblox.Vector2
		local phone = NPCDialogue.LayoutFor(true)
		local desk = NPCDialogue.LayoutFor(false)
		t.eq(phone.tagSize, Vector2.new(160, 38))
		t.eq(phone.tagName, 18)
		t.eq(phone.tagRole, 14)
		t.eq(phone.tagDistance, 40)
		t.eq(desk.tagRole, 14)
		t.eq(NPCDialogue.LayoutFor(false, true).tagRole, 18, "a TV role line")
		t.eq(NPCDialogue.LayoutFor(true, true).tagRole, 14, "a phone stays 14 even on a big screen")
		t.eq(desk.tagDistance, 60)
		t.eq(desk.tagSize, Vector2.new(220, 50))
		t.ok(NPCDialogue.PromptCooldown >= 1, "Talk is rate limited (the box needs a press to go anyway)")
	end)

	t.test("no NPC has a speech bubble: nothing builds one, and no bubble code or data is left", function()
		local fs = require("@lune/fs")
		local controller = fs.readFile("src/StarterPlayer/StarterPlayerScripts/NPCController.luau")
		for _, word in ipairs({
			"SpeechBubble",
			"closeBubble",
			"placeBubble",
			"BubbleClearance",
			"autoSay",
			"AutoBubbles",
		}) do
			t.eq(string.find(controller, word, 1, true), nil, word .. " is gone from NPCController")
		end
		for _, name in ipairs({
			"BubbleSeconds",
			"BubbleStudsOffset",
			"BubbleNudge",
			"BubbleFov",
			"TailScreen",
			"AmbientGap",
			"AutoBubbles",
			"BubbleClearance",
		}) do
			t.eq(NPCDialogue[name], nil, name .. " is gone from NPCDialogue")
		end
		-- The name tag stays, wall-safe through TextAnchor.
		t.ok(string.find(controller, "TextAnchor.NextHidden", 1, true) ~= nil)
		-- Nothing is left frozen or switched off: Talk is the prompt's Triggered
		-- and the gesture is only a pose.
		t.ok(string.find(controller, "prompt.Triggered:Connect", 1, true) ~= nil, "the Talk prompt stays")
		t.eq(string.find(controller, "Enabled = false", 1, true), nil, "no prompt or tag is disabled by hand here")
		-- A talk plays the murmur.
		t.ok(string.find(controller, 'SoundData.PlayAt("NPCChatter"', 1, true) ~= nil)
	end)

	t.test("a chop saw waiting in stock is not a sawmill waiting in stock", function()
		local function mill(stock)
			return NPCDialogue.ProgressOf({
				loaded = true,
				tutorialStep = 0,
				tutorialRefresher = false,
				bestAxeTier = 1,
				sawmillStock = stock,
				placedSawmill = false,
			}).sawmill
		end
		t.eq(mill("ChopSaw"), false)
		t.eq(mill("ChopSaw,Millmaster100"), true)
		t.eq(mill("Millmaster200L"), true)
		t.eq(mill(""), false)
		t.eq(mill(nil), false)
	end)
end
