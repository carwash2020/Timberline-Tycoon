--!nocheck
-- DialogueFlow: the dialogue box's rules (paging, advancing, closing, size)
-- and DialogueUI's wiring to them. A press continues; the last press closes;
-- walking away, the speaker going or another panel closes; nothing is
-- granted by pressing.
return function(t)
	local fs = require("@lune/fs")
	local DialogueFlow = t.shared("DialogueFlow")
	local NPCData = t.shared("NPCData")

	local function convo(lines, maxChars)
		return DialogueFlow.New("Millie", "Millie", "Sawyer", DialogueFlow.Pages(lines, maxChars or 100))
	end

	t.test("a conversation pages through in order and the last press closes it", function()
		local state = convo({ "Morning!", "Mind the saw.", "Mind the sap." })
		t.eq(#state.pages, 3)
		t.eq(DialogueFlow.Current(state), "Morning!")
		t.eq(DialogueFlow.IsLast(state), false)
		t.eq(DialogueFlow.PromptWord(state), "Continue")
		t.eq(DialogueFlow.Counter(state), "1/3")
		local second, done = DialogueFlow.Advance(state)
		t.eq(done, false)
		t.eq(DialogueFlow.Current(second), "Mind the saw.")
		t.eq(DialogueFlow.Current(state), "Morning!", "the state passed in is not changed")
		local third, done3 = DialogueFlow.Advance(second)
		t.eq(done3, false)
		t.eq(DialogueFlow.Current(third), "Mind the sap.")
		t.eq(DialogueFlow.IsLast(third), true)
		t.eq(DialogueFlow.PromptWord(third), "Close")
		local _, over = DialogueFlow.Advance(third)
		t.eq(over, true, "the press on the last line ends it")
	end)

	t.test("a single line is one press: it closes at once", function()
		local state = convo({ "Hello there." })
		t.eq(DialogueFlow.IsLast(state), true)
		t.eq(DialogueFlow.PromptWord(state), "Close")
		t.eq(DialogueFlow.Counter(state), nil, "no 1/1")
		local _, over = DialogueFlow.Advance(state)
		t.eq(over, true)
	end)

	t.test("nothing to say opens nothing; blanks, junk and repeats are dropped", function()
		t.eq(DialogueFlow.New("Millie", "Millie", nil, DialogueFlow.Pages({}, 100)), nil)
		t.eq(DialogueFlow.New("Millie", "Millie", nil, DialogueFlow.Pages({ "", "   " }, 100)), nil)
		local pages = DialogueFlow.Pages({ "Hi.", 5, false, "Hi.", "  Hi.  ", "Bye." }, 100)
		t.eq(pages, { "Hi.", "Bye." })
		t.eq(#DialogueFlow.Pages({ "a", "b", "c", "d", "e", "f", "g", "h" }, 100), DialogueFlow.MaxPages)
		local state = DialogueFlow.New(nil, nil, "", { "x" })
		t.eq(state.speaker, "")
		t.eq(state.name, "...")
		t.eq(state.role, nil)
	end)

	t.test("a long line splits at a sentence, else a space, and every page fits", function()
		local text = "I'm Murph. Chop a tree, haul the wood, sell it at the mill. Follow the amber arrow."
		local pages = DialogueFlow.Split(text, 40)
		t.ok(#pages >= 2, "it was split")
		for _, page in ipairs(pages) do
			t.ok(#page <= 40, "'" .. page .. "' fits")
			t.ok(page == page:match("^%s*(.-)%s*$"), "no stray spaces")
		end
		t.eq(table.concat(pages, " "), text, "nothing is lost or reworded")
		t.eq(pages[1], "I'm Murph. Chop a tree, haul the wood,", "a short first sentence fills the page")
		t.eq(
			DialogueFlow.Split("Hello there friend. This is the second part.", 25),
			{ "Hello there friend.", "This is the second part." },
			"a sentence end near the limit is where it breaks"
		)
		-- No sentence to break at: a space, never mid-word.
		local words = DialogueFlow.Split("one two three four five six seven eight nine ten", 18)
		for _, page in ipairs(words) do
			t.ok(#page <= 18)
		end
		t.eq(table.concat(words, " "), "one two three four five six seven eight nine ten")
		t.eq(DialogueFlow.Split("short", 40), { "short" })
		t.eq(DialogueFlow.Split("", 40), {})
		-- One endless word is cut rather than looping.
		local hard = DialogueFlow.Split(string.rep("x", 50), 20)
		t.eq(table.concat(hard), string.rep("x", 50))
	end)

	t.test("every real line fits in three lines of the smallest box, split if not", function()
		local width = DialogueFlow.Width(0)
		t.eq(width, 1, "never wider than a screen that is not there")
		local phone = DialogueFlow.Width(667)
		local per = DialogueFlow.PageChars(phone, 17)
		t.ok(per >= 60, "a phone page holds a real sentence: " .. per)
		for _, npc in ipairs(NPCData.All()) do
			local lines = {}
			for _, group in ipairs({ npc.greetings, npc.lines, npc.tips or {} }) do
				for _, line in ipairs(group) do
					table.insert(lines, line)
				end
			end
			for _, group in pairs(npc.react or {}) do
				for _, line in ipairs(group) do
					table.insert(lines, line)
				end
			end
			for _, line in ipairs(lines) do
				for _, page in ipairs(DialogueFlow.Split(line, per)) do
					t.ok(#page <= per, npc.id .. ": " .. page)
				end
			end
		end
	end)

	t.test("the box is 40% of the screen, kept readable and never a banner", function()
		t.eq(DialogueFlow.WidthFraction, 0.4)
		t.eq(DialogueFlow.Width(1920), DialogueFlow.MaxWidth, "a monitor or a TV caps")
		t.eq(DialogueFlow.Width(1000), 400)
		t.eq(DialogueFlow.Width(667), DialogueFlow.MinWidth, "a phone floors at readable")
		t.ok(DialogueFlow.Width(320) <= 320, "and never off a tiny screen")
		t.ok(DialogueFlow.CharsPerLine(300, 17) >= 12)
		t.eq(DialogueFlow.MaxTextLines, 3)
	end)

	t.test("it closes when you walk off, the speaker goes, you go down, or another panel opens", function()
		local far = DialogueFlow.CloseDistance
		t.ok(far > 12, "a step back from a Talk prompt (12 studs) does not close it")
		t.eq(DialogueFlow.ShouldClose({ distance = 5 }), nil)
		t.eq(DialogueFlow.ShouldClose({ distance = far }), nil, "exactly at the limit stays")
		t.eq(DialogueFlow.ShouldClose({ distance = far + 0.1 }), "far")
		t.eq(DialogueFlow.ShouldClose({ distance = nil }), nil, "an unknown position never closes it")
		t.eq(DialogueFlow.ShouldClose({ distance = 3, gone = true }), "gone")
		t.eq(DialogueFlow.ShouldClose({ distance = 3, asleep = true }), "asleep")
		t.eq(DialogueFlow.ShouldClose({ distance = 3, playerDown = true }), "down")
		t.eq(DialogueFlow.ShouldClose({ distance = 3, panelOpen = true }), "panel")
		t.eq(DialogueFlow.ShouldClose({ openFor = DialogueFlow.MaxOpenSeconds + 1 }), "timeout")
		t.eq(DialogueFlow.ShouldClose({ openFor = 5 }), nil)
		t.eq(DialogueFlow.ShouldClose({}), nil)
	end)

	t.test("the prompt shows E on a keyboard, X on a gamepad, TAP on a phone", function()
		t.eq(DialogueFlow.Key("desktop"), "E")
		t.eq(DialogueFlow.Key("console"), "X")
		t.eq(DialogueFlow.Key("phone"), "TAP")
		t.eq(DialogueFlow.Key("anything else"), "E")
	end)

	t.test("keepers, the Hermit and Old Hank speak from the server; everyone else is built here", function()
		t.eq(DialogueFlow.ServerSpoken("ToolShed", "Tink"), true)
		t.eq(DialogueFlow.ServerSpoken(nil, "Hermit"), true)
		t.eq(DialogueFlow.ServerSpoken(nil, "OldHank"), true)
		t.eq(DialogueFlow.ServerSpoken(nil, "Millie"), false)
		for _, npc in ipairs(NPCData.All()) do
			local expected = npc.shop ~= nil or npc.id == "Hermit" or npc.id == "OldHank"
			t.eq(DialogueFlow.ServerSpoken(npc.shop, npc.id), expected, npc.id)
		end
		for _, id in ipairs({ "Tink", "Hazel", "Dale" }) do
			t.ok(NPCData.Get(id).shop ~= nil, id .. " keeps a shop")
		end
		t.eq(NPCData.ForShop("ToolShed").id, "Tink")
		t.eq(NPCData.ForShop("HearthAndHome").id, "Hazel")
		t.eq(NPCData.ForShop("Dealership").id, "Dale")
		t.eq(NPCData.ForShop("Nowhere"), nil)
		t.eq(NPCData.ForShop(nil), nil)
	end)

	t.test("a keeper's hello is their greeting, the shop's line and a line of their own", function()
		local dale = NPCData.Get("Dale")
		local greeting, line = DialogueFlow.KeeperExtras(dale.greetings, dale.lines, 0, 0)
		t.eq(greeting, dale.greetings[1])
		t.eq(line, dale.lines[1])
		greeting, line = DialogueFlow.KeeperExtras(dale.greetings, dale.lines, 0.999, 0.999)
		t.eq(greeting, dale.greetings[#dale.greetings], "the top of the roll is the last entry")
		t.eq(line, dale.lines[#dale.lines])
		greeting, line = DialogueFlow.KeeperExtras(dale.greetings, dale.lines, 1, -1)
		t.ok(greeting ~= nil and line ~= nil, "a roll outside [0, 1) never indexes past the list")
		t.eq({ DialogueFlow.KeeperExtras({}, nil, 0.5, 0.5) }, {}, "no words, no extras")
		for _, id in ipairs({ "Tink", "Hazel", "Dale" }) do
			local keeper = NPCData.Get(id)
			t.ok(#keeper.greetings > 0 and #keeper.lines > 0, id .. " has words to say")
		end
	end)

	t.test("a server payload is paged intro, text, more; an offer is its text alone", function()
		local lines = DialogueFlow.ServerLines({
			text = "Trucks are on the board.",
			intro = "Hey hey!",
			more = { "Take the corners slow." },
		})
		t.eq(lines, { "Hey hey!", "Trucks are on the board.", "Take the corners slow." })
		local state = DialogueFlow.New("Dale", "Dale", "Truck dealer", DialogueFlow.Pages(lines, 100))
		t.eq(#state.pages, 3, "a press for each")
		t.eq(DialogueFlow.ServerLines({ text = "Pay $5?", choice = true, intro = "Hi", more = { "x" } }), { "Pay $5?" })
		t.eq(DialogueFlow.ServerLines({ text = "Just this." }), { "Just this." })
		t.eq(
			DialogueFlow.ServerLines({ text = "T", intro = 5, more = { 1, "ok", false } }),
			{ "T", "ok" },
			"only text is trusted"
		)
		t.eq(DialogueFlow.ServerLines({ intro = "no text" }), {})
		t.eq(DialogueFlow.ServerLines(nil), {})
	end)

	t.test("DialogueUI: a press continues, the last closes, Yes and No still go to the server", function()
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DialogueUI.luau")
		t.ok(string.find(ui, "DialogueFlow.Advance(current)", 1, true) ~= nil, "paging is DialogueFlow's")
		t.ok(string.find(ui, "DialogueFlow.ShouldClose({", 1, true) ~= nil, "closing is DialogueFlow's")
		t.ok(string.find(ui, "DialogueFlow.IgnoreSeconds", 1, true) ~= nil, "the opening press is not a continue")
		-- The keys: E and X advance (Yes on an offer); B and Esc close (No on an offer).
		t.ok(string.find(ui, "Enum.KeyCode.ButtonX or key == Enum.KeyCode.E", 1, true) ~= nil)
		t.ok(string.find(ui, "Enum.KeyCode.ButtonB or key == Enum.KeyCode.Escape", 1, true) ~= nil)
		t.ok(string.find(ui, "BindActionAtPriority", 1, true) ~= nil, "X and E are the box's while it is up")
		-- A click or tap on the box, and the Continue button, are the same press.
		t.ok(string.find(ui, "nextBtn.Activated:Connect(advance)", 1, true) ~= nil, "tap Continue")
		t.ok(string.find(ui, "column.Activated:Connect(advance)", 1, true) ~= nil, "click or tap the box")
		-- Only an offer sends anything to the server, and only Yes or No.
		local sends = 0
		for _ in string.gmatch(ui, ':FireServer%("pick"') do
			sends += 1
		end
		t.eq(sends, 1, "one send: the offer's pick")
		t.eq(string.find(ui, 'FireServer("open"', 1, true), nil, "the box never opens a conversation on the server")
		-- The glyph by device.
		t.ok(string.find(ui, "UITheme.Glyph(Enum.KeyCode.ButtonX", 1, true) ~= nil, "the pad's X glyph")
		t.ok(string.find(ui, "DialogueFlow.Key(device)", 1, true) ~= nil)
		-- Other prompts are off while it is up, and come back after a beat.
		t.ok(string.find(ui, 'PromptSwitch.Hold("dialogue")', 1, true) ~= nil)
		t.ok(string.find(ui, "DialogueFlow.ReenableDelay", 1, true) ~= nil)
		-- Toasts hold (NoticePolicy) and the gamepad's focus is given back.
		t.ok(string.find(ui, 'player:SetAttribute("TalkOpen", true)', 1, true) ~= nil)
		t.ok(string.find(ui, 'player:SetAttribute("TalkOpen", false)', 1, true) ~= nil)
		t.ok(string.find(ui, "GamepadNav.Focus(nextBtn, column)", 1, true) ~= nil, "focus to the box")
		t.ok(string.find(ui, "GamepadNav.Restore(column)", 1, true) ~= nil, "and handed back")
		local hud = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HUD.luau")
		t.ok(string.find(hud, 'player:GetAttribute("TalkOpen") == true', 1, true) ~= nil, "HUD holds toasts")
		t.ok(string.find(hud, "flowQuiet(), talkHeld()", 1, true) ~= nil)
		t.eq(string.find(ui, "WalkSpeed", 1, true), nil, "walking is never locked")
	end)

	t.test("NPCController opens the box for a Talk press, and nothing floats over any NPC's head", function()
		local controller = fs.readFile("src/StarterPlayer/StarterPlayerScripts/NPCController.luau")
		local from = string.find(controller, "local function onTalk", 1, true)
		local to = string.find(controller, "-- Binding to models as they stream in", 1, true)
		local body = string.sub(controller, from, to)
		t.ok(string.find(body, "DialogueUI.Talk({", 1, true) ~= nil, "a Talk press is the dialogue box")
		t.eq(string.find(body, "say(rig", 1, true), nil, "and no bubble")
		t.ok(string.find(body, "DialogueFlow.ServerSpoken(npc.shop, npc.id)", 1, true) ~= nil, "keepers: the server's")
		t.ok(string.find(body, "PlotSalesmanData.Id", 1, true) ~= nil, "Old Hank's picker is his talk")
		-- The floating speech bubbles are gone: the wave hello, Murph's first tip
		-- and the chatter. No billboard text but the name tag.
		t.eq(string.find(controller, "SpeechBubble", 1, true), nil, "no speech bubble gui")
		t.eq(string.find(controller, "autoSay", 1, true), nil, "no automatic lines")
		t.eq(string.find(controller, 'Instance.new("BillboardGui")', 1, true), nil, "no billboard built here")
		t.eq(string.find(controller, "AutoBubbles", 1, true), nil)
		-- The talking gesture plays while the box is open for them.
		t.ok(string.find(controller, "DialogueUI.IsTalkingTo(rig.model)", 1, true) ~= nil)
		-- Murph's Talk press is the same box, with his tutorial line.
		local quest = fs.readFile("src/StarterPlayer/StarterPlayerScripts/QuestUI.luau")
		t.ok(string.find(quest, "DialogueUI.Talk({", 1, true) ~= nil)
		t.ok(string.find(quest, 'id = "Murph"', 1, true) ~= nil)
		-- His onboarding tips used to be a bubble on the first hello: now the
		-- first talk on step one opens them in the box ahead of the step line.
		t.ok(string.find(quest, "murph.tips", 1, true) ~= nil, "the tips reach the player by talking to him")
	end)

	t.test("the server's lines name their speaker for the box", function()
		local service = fs.readFile("src/ServerScriptService/DialogueService.luau")
		t.ok(string.find(service, "NPCData.ForShop(shop)", 1, true) ~= nil)
		t.ok(string.find(service, "speaker = if keeper then keeper.id else nil", 1, true) ~= nil)
		local server = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		t.ok(string.find(server, 'speaker = "Hermit"', 1, true) ~= nil)
	end)
end
