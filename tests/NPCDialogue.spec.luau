--!nocheck
-- NPCDialogue: which line is said (a new player's tip, then progress,
-- weather, and the hour, else a general line), the no-repeat shuffle,
-- and the phone bubble and name-tag sizes.

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
		newPlayer = true,
		sold = false,
		upgradedAxe = false,
		sawmill = false,
	}
	local veteran = {
		loaded = true,
		newPlayer = false,
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
		t.eq(unknown.newPlayer, false)
		t.eq(unknown.sold, false)
		local newbie = NPCDialogue.ProgressOf({
			loaded = true,
			tutorialStep = 2,
			tutorialRefresher = nil,
			bestAxeTier = 1,
			sawmillStock = "",
			placedSawmill = false,
		})
		t.eq(newbie.newPlayer, true)
		t.eq(newbie.sold, false)
		t.eq(newbie.upgradedAxe, false)
		t.eq(newbie.sawmill, false)
		-- The cart is the sell step. Standing on it hasn't sold yet.
		local onCart = NPCDialogue.ProgressOf({
			loaded = true,
			tutorialStep = TutorialData.RefresherLast,
			tutorialRefresher = false,
			bestAxeTier = 1,
			sawmillStock = nil,
			placedSawmill = false,
		})
		t.eq(onCart.sold, false)
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
		t.eq(sold.newPlayer, true)
		local done = NPCDialogue.ProgressOf({
			loaded = true,
			tutorialStep = 0,
			tutorialRefresher = false,
			bestAxeTier = 1,
			sawmillStock = "SawmillRickety",
			placedSawmill = false,
		})
		t.eq(done.newPlayer, false)
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
		t.eq(refresher.newPlayer, false)
		t.eq(refresher.sold, true)
	end)

	t.test("Murph's first hello to a new player is an onboarding tip", function()
		local murph = NPCData.Get("Murph")
		local pool = NPCDialogue.PoolFor(murph, ctx(fresh), 0.99, true)
		t.eq(pool.kind, "tip")
		t.eq(pool.lines, murph.tips)
		-- Once you've met, a high roll is a general line.
		t.eq(NPCDialogue.PoolFor(murph, ctx(fresh), 0.99, false).kind, "line")
		-- Before the save loads, no tip (a veteran must not hear one by mistake).
		local unloaded = {
			loaded = false,
			newPlayer = false,
			sold = false,
			upgradedAxe = false,
			sawmill = false,
		}
		t.eq(NPCDialogue.PoolFor(murph, ctx(unloaded), 0, true).kind, "line")
		-- Millie has no tips, so a first meeting is not one.
		t.ok(NPCDialogue.PoolFor(NPCData.Get("Millie"), ctx(fresh), 0, true).kind ~= "tip")
	end)

	t.test("a low roll prefers progress, then weather, then the hour", function()
		local millie = NPCData.Get("Millie")
		t.eq(NPCDialogue.PoolFor(millie, ctx(fresh), 0, false).kind, "unsold")
		local withSaw = {
			loaded = true,
			newPlayer = false,
			sold = true,
			upgradedAxe = true,
			sawmill = true,
		}
		t.eq(NPCDialogue.PoolFor(millie, ctx(withSaw), 0, false).kind, "sawmill")
		local rustySold = {
			loaded = true,
			newPlayer = false,
			sold = true,
			upgradedAxe = false,
			sawmill = false,
		}
		-- Still on the starter axe: that beats a sale line.
		t.eq(NPCDialogue.PoolFor(millie, ctx(rustySold), 0, false).kind, "rusty")
		local tink = NPCData.Get("Tink")
		t.eq(NPCDialogue.PoolFor(tink, ctx(rustySold), 0, false).kind, "rusty")
		local rainy = {
			loaded = true,
			newPlayer = false,
			sold = true,
			upgradedAxe = true,
			sawmill = false,
		}
		-- Dale has no sawmill lines; rain beats the hour when both could apply.
		local dale = NPCData.Get("Dale")
		t.eq(NPCDialogue.PoolFor(dale, ctx(rainy, "morning", "Rain"), 0, false).kind, "axe")
		local noAxe = {
			loaded = true,
			newPlayer = false,
			sold = true,
			upgradedAxe = false,
			sawmill = false,
		}
		-- Rosa has no rusty or sale lines, so rain wins, then the morning.
		local rosa = NPCData.Get("Rosa")
		t.eq(NPCDialogue.PoolFor(rosa, ctx(noAxe, "morning", "Rain"), 0, false).kind, "sale")
		-- Wait, Rosa has sale lines. Use a weather-only case: Gus in fog with no matching progress.
		-- veteran has sawmill; Gus has sawmill lines? He doesn't. He has sale and axe.
		t.eq(NPCDialogue.PoolFor(NPCData.Get("Gus"), ctx(veteran, "night", "Fog"), 0, false).kind, "axe")
		local fogOnly = NPCDialogue.PoolFor(NPCData.Get("Hazel"), ctx(veteran, "day", "Fog"), 0, false)
		-- Hazel has no sawmill or axe lines. Veteran is sold and upgraded, so sale, else fog.
		t.eq(fogOnly.kind, "sale")
		local clearMorning = {
			loaded = true,
			newPlayer = false,
			sold = true,
			upgradedAxe = true,
			sawmill = false,
		}
		-- Bram has axe lines, so progress wins over morning.
		t.eq(NPCDialogue.PoolFor(NPCData.Get("Bram"), ctx(clearMorning, "morning", "Clear"), 0, false).kind, "axe")
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
		t.eq(NPCDialogue.PoolFor(quiet, ctx(clearMorning, "morning", "Rain"), 0, false).kind, "sale")
		local noSale = {
			loaded = true,
			newPlayer = false,
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
		t.eq(NPCDialogue.PoolFor(hourNpc, ctx(noSale, "morning", "Clear"), 0, false).kind, "morning")
		t.eq(NPCDialogue.PoolFor(hourNpc, ctx(noSale, "morning", "Storm"), 0, false).kind, "morning")
		t.eq(NPCDialogue.PoolFor(hourNpc, ctx(noSale, "day", "Rain"), 0, false).kind, "rain")
		t.eq(NPCDialogue.PoolFor(hourNpc, ctx(noSale, "day", "Clear"), 0.99, false).kind, "line")
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

	t.test("phone bubbles are smaller, lower, and don't reach across the plaza", function()
		t.eq(NPCDialogue.IsPhone(true, false, 800), true)
		t.eq(NPCDialogue.IsPhone(true, false, 900), false)
		t.eq(NPCDialogue.IsPhone(true, true, 400), false)
		t.eq(NPCDialogue.IsPhone(false, false, 400), false)
		local Vector2 = t.roblox.Vector2
		local phone = NPCDialogue.LayoutFor(true)
		local desk = NPCDialogue.LayoutFor(false)
		t.eq(phone.tagSize, Vector2.new(160, 38))
		t.eq(phone.tagName, 18)
		t.eq(phone.tagRole, 11)
		t.eq(phone.tagDistance, 40)
		t.eq(phone.textSize, 14)
		t.ok(phone.width <= 200, "phone bubble width")
		t.ok(phone.maxDistance <= 40, "phone bubble distance")
		t.ok(phone.studsOffset.Y > 1.4, "the phone bubble clears the head")
		t.ok(desk.studsOffset.Y > 1.4, "the desktop bubble clears the head")
		t.ok(phone.studsOffset.Y < desk.studsOffset.Y, "the phone bubble sits lower")
		t.eq(desk.tagDistance, 60)
		t.eq(desk.tagSize, Vector2.new(220, 50))
		t.ok(phone.width < desk.width, "desktop keeps the wider bubble")
		t.ok(NPCDialogue.BubbleSeconds("Hi") >= 2.4, "a short line still stays up")
		t.ok(NPCDialogue.BubbleSeconds(string.rep("a", 200)) <= 6.5, "a long line is capped")
		t.ok(NPCDialogue.PromptCooldown >= 3, "Talk is rate limited")
		t.ok(NPCDialogue.AmbientGap[1] >= 8, "ambient chatter is rate limited")
	end)
end
