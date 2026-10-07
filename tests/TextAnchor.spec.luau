--!nocheck
-- TextAnchor: text over a head never sits in a wall. The height clamp under a
-- ceiling, the sideways rule, the wall hide with its hysteresis, and the
-- wiring in NPCController / PromptUI (rays at a low rate, nothing "always on
-- top" over a person).
return function(t)
	local fs = require("@lune/fs")
	local TextAnchor = t.shared("TextAnchor")
	local NPCDialogue = t.shared("NPCDialogue")
	local NPCData = t.shared("NPCData")
	local CharacterArt = t.load("ReplicatedStorage/Shared/Art/CharacterArt")

	t.test("under open sky the tail keeps its usual lift", function()
		local lift, fits = TextAnchor.Lift(3, NPCDialogue.BubbleClearance, nil, 2)
		t.eq(lift, 4.5)
		t.eq(fits, true)
	end)

	t.test("a high ceiling changes nothing; a low one brings the tail down so the card fits", function()
		-- Head centre to roof 12 studs, a 2 stud card: plenty.
		local lift, fits = TextAnchor.Lift(3, 1.5, 12, 2)
		t.eq(lift, 4.5)
		t.eq(fits, true)
		-- Roof 6.5 up: the card's top (lift + 2) must stay 0.35 under it.
		local low, lowFits = TextAnchor.Lift(3, 1.5, 6.5, 2)
		t.eq(lowFits, true)
		t.ok(low < 4.5, "lowered: " .. low)
		t.ok(low + 2 <= 6.5 - TextAnchor.Margin + 1e-9, "the top of the card is under the roof")
		t.ok(low >= 3 + TextAnchor.MinClearance, "never into the hat")
	end)

	t.test("with no room above the hat at all, it does not fit (a bubble hides, never clips)", function()
		local lift, fits = TextAnchor.Lift(3, 1.5, 4.5, 2)
		t.eq(fits, false)
		t.eq(lift, 3 + TextAnchor.MinClearance, "a name tag still sits just above the hat")
		local tight, tightFits = TextAnchor.Lift(3, 1.5, 3.1, 0.5)
		t.eq(tightFits, false, "a roof on the hat")
		t.ok(tight >= 3, "and the lift never goes below the hat")
	end)

	t.test("the lift is monotonic: a lower roof never raises the tail", function()
		local last = math.huge
		for headroom = 14, 3, -0.5 do
			local lift = TextAnchor.Lift(3, 1.5, headroom, 1.5)
			t.ok(lift <= last + 1e-9, "headroom " .. headroom)
			t.ok(lift >= 3 + TextAnchor.MinClearance - 1e-9)
			last = lift
		end
	end)

	t.test("a card is taller in studs the farther the camera is", function()
		local near = TextAnchor.CardStuds(100, 8, 1080)
		local far = TextAnchor.CardStuds(100, 30, 1080)
		t.ok(far > near * 3, "pixels grow with distance: " .. near .. " vs " .. far)
		t.ok(math.abs(TextAnchor.CardStuds(1080, 10, 1080) - 2 * 10 * math.tan(math.rad(35))) < 1e-6)
		t.ok(TextAnchor.CardStuds(100, 0, 0) > 0, "no division by nothing")
	end)

	t.test("a card's estimated height grows with its text, to four lines", function()
		local one = TextAnchor.CardPx(10, 230, 16)
		local many = TextAnchor.CardPx(400, 230, 16)
		t.ok(many > one)
		t.eq(many, TextAnchor.CardPx(4000, 230, 16), "the label stops at four lines")
		t.ok(one >= 16 + 14 + 18)
	end)

	t.test("every NPC fits a bubble under a 14-stud roof, and none can have its hat in the card", function()
		for _, npc in ipairs(NPCData.All()) do
			local model = CharacterArt.Build(npc.look)
			local top = model:GetAttribute("TopOffset")
			local lift, fits = TextAnchor.Lift(top, NPCDialogue.BubbleClearance, 14, 2)
			t.ok(fits, npc.id .. " fits under open-ish roofs")
			t.ok(lift >= top + TextAnchor.MinClearance, npc.id .. " clears the hat")
		end
	end)

	t.test("a wall beside the bubble puts it straight above the head", function()
		t.eq(TextAnchor.Side(1.6, false), 1.6)
		t.eq(TextAnchor.Side(1.6, true), 0)
	end)

	t.test("a wall hides text at once; it returns after two clear checks, not one", function()
		local hidden, clear = false, 0
		hidden, clear = TextAnchor.NextHidden(hidden, false, clear)
		t.eq(hidden, false)
		hidden, clear = TextAnchor.NextHidden(hidden, true, clear)
		t.eq(hidden, true, "at once")
		t.eq(clear, 0)
		hidden, clear = TextAnchor.NextHidden(hidden, false, clear)
		t.eq(hidden, true, "one clear check is a flicker")
		hidden, clear = TextAnchor.NextHidden(hidden, false, clear)
		t.eq(hidden, false, "two are not")
		hidden, clear = TextAnchor.NextHidden(hidden, true, clear)
		hidden, clear = TextAnchor.NextHidden(hidden, false, clear)
		hidden, clear = TextAnchor.NextHidden(hidden, true, clear)
		t.eq(hidden, true, "a wall in between resets the count")
		t.eq(TextAnchor.CheckSeconds, 0.25, "four checks a second")
	end)

	t.test("nothing over a person is drawn on top of the scene", function()
		t.eq(TextAnchor.OnTop(true), false, "over a head: the walls hide it")
		t.eq(TextAnchor.OnTop(false), true, "on a counter's middle: it stays visible")
		local prompt = fs.readFile("src/StarterPlayer/StarterPlayerScripts/PromptUI.luau")
		t.ok(string.find(prompt, "TextAnchor.OnTop(studs ~= nil)", 1, true) ~= nil)
		t.eq(string.find(prompt, "AlwaysOnTop = true", 1, true), nil, "no prompt is on top by decree")
		t.ok(string.find(prompt, "TextAnchor.NextHidden(", 1, true) ~= nil, "a wall hides a head's card")
		t.ok(string.find(prompt, "TextAnchor.Lift(0, PromptUI.HeadLift", 1, true) ~= nil, "and a low roof lowers it")
		local npcs = fs.readFile("src/StarterPlayer/StarterPlayerScripts/NPCController.luau")
		t.eq(string.find(npcs, "AlwaysOnTop = true", 1, true), nil, "bubbles are never on top")
		t.ok(string.find(npcs, "gui.AlwaysOnTop = false", 1, true) ~= nil)
	end)

	t.test("NPCController checks walls and ceilings at a low rate and applies the clamp", function()
		local npcs = fs.readFile("src/StarterPlayer/StarterPlayerScripts/NPCController.luau")
		t.ok(string.find(npcs, "rig.textAt = now + TextAnchor.CheckSeconds", 1, true) ~= nil, "4 Hz")
		t.ok(string.find(npcs, "if now >= rig.textAt and", 1, true) ~= nil, "gated by the clock")
		t.ok(string.find(npcs, "RespectCanCollide = true", 1, true) ~= nil, "leaves and awnings are not walls")
		t.ok(string.find(npcs, "TextAnchor.NextHidden(rig.hidden, blocked, rig.clear)", 1, true) ~= nil)
		t.ok(string.find(npcs, "TextAnchor.Lift(rig.topOffset, NPCDialogue.BubbleClearance", 1, true) ~= nil)
		t.ok(string.find(npcs, "TextAnchor.Side(", 1, true) ~= nil)
		t.ok(string.find(npcs, "gui.Enabled = not rig.hidden and not rig.crowded", 1, true) ~= nil)
		t.ok(string.find(npcs, "tag.Enabled = rig.bubble == nil and not rig.hidden", 1, true) ~= nil)
		-- No second place turns the name tag on behind checkText's back.
		t.eq(string.find(npcs, "rig.tag.Enabled", 1, true), nil)
	end)
end
