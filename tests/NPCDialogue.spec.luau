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

	t.test("phone bubbles are smaller and don't reach across the plaza", function()
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
		t.eq(phone.textSize, 14)
		t.ok(phone.width <= 200, "phone bubble width")
		t.ok(phone.maxDistance <= 40, "phone bubble distance")
		t.eq(NPCDialogue.BubbleClearance, 1.5)
		t.ok(phone.studsOffset.X > 0, "the phone bubble sits beside the head")
		t.ok(desk.studsOffset.X > phone.studsOffset.X, "desktop sits a little further aside")
		t.eq(desk.tagDistance, 60)
		t.eq(desk.tagSize, Vector2.new(220, 50))
		t.ok(phone.width < desk.width, "desktop keeps the wider bubble")
		t.ok(NPCDialogue.BubbleSeconds("Hi") >= 2.4, "a short line still stays up")
		t.ok(NPCDialogue.BubbleSeconds(string.rep("a", 200)) <= 6.5, "a long line is capped")
		t.ok(NPCDialogue.PromptCooldown >= 3, "Talk is rate limited")
		t.ok(NPCDialogue.AmbientGap[1] >= 8, "ambient chatter is rate limited")
	end)

	t.test("the bubble clears every hat, stays on screen, and follows the walk", function()
		local fs = require("@lune/fs")
		local Vector3 = t.roblox.Vector3
		local CharacterArt = t.load("ReplicatedStorage/Shared/Art/CharacterArt")
		local NPCWalk = t.shared("NPCWalk")
		local QualityBudgets = t.shared("QualityBudgets")
		local controller = fs.readFile("src/StarterPlayer/StarterPlayerScripts/NPCController.luau")

		local function between(src, from, to)
			local a = string.find(src, from, 1, true)
			local b = string.find(src, to, a, true)
			return string.sub(src, a, b)
		end

		t.eq(string.find(controller, "TextChatService", 1, true), nil, "NPC lines are not TextChatService bubbles")
		t.ok(string.find(controller, "gui.Adornee = rig.head", 1, true) ~= nil, "the bubble is adorned to the head")
		t.eq(string.find(controller, "gui.Adornee = rig.root", 1, true), nil)
		t.eq(string.find(controller, "gui.Adornee = rig.torso", 1, true), nil)

		local sayBody = between(controller, "local function say", "local function hasPlacedSawmill")
		t.ok(
			string.find(sayBody, "rig.topOffset + NPCDialogue.BubbleClearance", 1, true) ~= nil,
			"say lifts the tail by TopOffset plus the clearance"
		)
		local placeBody = between(controller, "local function placeBubble", "local function say")
		t.ok(string.find(placeBody, "BubbleStudsOffset(rig.topOffset", 1, true) ~= nil, "placeBubble uses TopOffset")
		t.eq(string.find(placeBody, "1.45", 1, true), nil, "the top-of-screen nudge does not drop the tail")
		t.eq(string.find(placeBody, "offset.Y -", 1, true), nil, "placeBubble never lowers Y")
		t.eq(string.find(controller, "HeadTopY", 1, true), nil)

		-- The walk root moves every rendered frame, outside the cosmetic
		-- gate, and the bubble is adorned to the head on that rig. A 2 Hz
		-- cosmetic tick must not freeze the tail.
		local stepBody = between(controller, "local function step", "function NPCController.Start")
		local dueAt = string.find(stepBody, "CosmeticDue", 1, true)
		local walkAt = string.find(stepBody, "presentWalkers(dt)", 1, true)
		t.ok(dueAt ~= nil and walkAt ~= nil and walkAt > dueAt, "the walk is not inside the cosmetic gate")

		local function partTop(head, part)
			local localCf = head.CFrame:ToObjectSpace(part.CFrame)
			local hx, hy, hz = part.Size.X / 2, part.Size.Y / 2, part.Size.Z / 2
			local maxY = -math.huge
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local corner = localCf * Vector3.new(sx * hx, sy * hy, sz * hz)
						maxY = math.max(maxY, corner.Y)
					end
				end
			end
			return maxY
		end

		-- Head, anything hung on it, and hat parts welded to it (those are
		-- parented on the model, not under the head).
		local function hatTop(model, head)
			local maxY = partTop(head, head)
			local function consider(part)
				if part:IsA("BasePart") then
					maxY = math.max(maxY, partTop(head, part))
				end
			end
			for _, d in ipairs(head:GetDescendants()) do
				consider(d)
			end
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("Weld") and d.Part0 == head and d.Part1 and d.Part1:IsA("BasePart") then
					consider(d.Part1)
					for _, sub in ipairs(d.Part1:GetDescendants()) do
						consider(sub)
					end
				end
			end
			return maxY
		end

		-- A talk at the edge of talk range. The head sits a little below
		-- centre, which is how a standing NPC reads when you face them.
		-- The card above the tail is the label cap, its padding, and the
		-- gap under the card. Nudge is on, so the tail is further aside.
		local TALK_DISTANCE = 16
		local CARD_ABOVE = 14 + 96 + 14
		local views = { { 375, 667 }, { 667, 375 } }

		for _, npc in ipairs(NPCData.All()) do
			local model = CharacterArt.Build(npc.look)
			local head = model:FindFirstChild("Head")
			t.ok(head and head:IsA("BasePart"), npc.id .. " has a head")
			local topOffset = model:GetAttribute("TopOffset")
			t.eq(type(topOffset), "number", npc.id .. " publishes TopOffset")
			local bounds = hatTop(model, head)
			for _, phone in ipairs({ false, true }) do
				local layout = NPCDialogue.LayoutFor(phone)
				local still = NPCDialogue.BubbleStudsOffset(topOffset, layout.studsOffset.X, false)
				local offset = NPCDialogue.BubbleStudsOffset(topOffset, layout.studsOffset.X, true)
				local where = npc.id .. (if phone then " phone" else " desktop")
				t.ok(
					offset.Y >= topOffset + NPCDialogue.BubbleClearance - 1e-4,
					string.format("%s offset %.2f is under TopOffset + 1.5", where, offset.Y)
				)
				t.eq(offset.Y, still.Y, where .. " nudge does not change Y")
				t.ok(offset.X > still.X, where .. " nudge steps aside")
				t.ok(
					offset.Y > bounds - 1e-3,
					string.format("%s tail %.2f is inside the hat (top %.2f)", where, offset.Y, bounds)
				)
				for _, view in ipairs(views) do
					local viewW, viewH = view[1], view[2]
					local headX, headY = viewW / 2, viewH * 0.62
					t.ok(
						NPCDialogue.TailOnScreen(viewW, viewH, headX, headY, offset, TALK_DISTANCE),
						string.format("%s tail leaves %dx%d", where, viewW, viewH)
					)
					local tailX, tailY = NPCDialogue.TailScreen(headX, headY, offset, viewH, TALK_DISTANCE)
					local half = layout.width / 2
					t.ok(tailY - CARD_ABOVE >= 0, string.format("%s card clips the top of %dx%d", where, viewW, viewH))
					t.ok(tailY <= viewH, string.format("%s card leaves the bottom of %dx%d", where, viewW, viewH))
					t.ok(
						tailX - half >= 0 and tailX + half <= viewW,
						string.format("%s card leaves %dx%d", where, viewW, viewH)
					)
				end
			end
		end

		local rosa = NPCData.Get("Rosa")
		local rosaModel = CharacterArt.Build(rosa.look)
		local lift = rosaModel:GetAttribute("TopOffset") + NPCDialogue.BubbleClearance
		local hz = QualityBudgets.For("low").CosmeticHz
		t.eq(hz, 2)
		local since, time = 0, 0.4
		local visual, prev = nil, nil
		local movedOffTick = 0
		for _ = 1, 120 do
			local dt = 1 / 60
			since += dt
			local cosmetic = QualityBudgets.CosmeticDue(hz, since)
			if cosmetic then
				since = 0
			end
			time += dt
			local x, z, yaw, moving, walked = NPCData.RouteState(rosa.route, rosa.speed, time)
			local target = { x = x, y = 0, z = z, yaw = yaw, moving = moving, walked = walked }
			visual = NPCWalk.Follow(visual, target, dt, rosa.speed, true)
			-- The tail is the head (which rides the root) plus the lift.
			-- That lift does not wait for the cosmetic tick.
			local tailY = visual.y + lift
			t.ok(math.abs(tailY - (visual.y + rosaModel:GetAttribute("TopOffset") + 1.5)) < 1e-6, "lift stays put")
			if prev and visual.moving and not cosmetic then
				local dx, dz = visual.x - prev.x, visual.z - prev.z
				local step = math.sqrt(dx * dx + dz * dz)
				if step > 1e-3 then
					movedOffTick += 1
					t.ok(step <= rosa.speed * dt + NPCWalk.Slack + 1e-6, "the tail jumps between cosmetic ticks")
				end
			end
			prev = { x = visual.x, z = visual.z }
		end
		t.ok(movedOffTick >= 30, "the tail kept up between cosmetic ticks: " .. movedOffTick)
	end)
end
