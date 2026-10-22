--!nocheck
-- The wiring tool's rules: what a tap does, the lines drawn (and their
-- budget), the gamepad's aim, the touch pick, and its keys.
return function(t)
	local Logic = t.shared("WireToolLogic")
	local InputKit = t.shared("InputKit")
	local Enum = t.roblox.Enum

	local function piece(uid, id, x, z, y)
		return { uid = uid, blueprintId = id, x = x, y = y, z = z }
	end
	local pieces = {
		piece("sw", "SparkSwitch", 0, 0),
		piece("sw2", "SparkSwitch", 0, 10),
		piece("lamp", "SparkLamp", 6, 0),
		piece("door", "Door", 12, 0),
		piece("bench", "Bench", 20, 0),
	}

	t.test("tapping a switch picks it, again drops it, ground or a bench clears the pick", function()
		t.eq({ Logic.Tap(nil, "sw", pieces) }, { "sw" })
		t.eq({ Logic.Tap("sw", "sw", pieces) }, {})
		t.eq({ Logic.Tap("sw", "sw2", pieces) }, { "sw2" }, "another switch swaps the pick")
		t.eq({ Logic.Tap("sw", nil, pieces) }, {})
		t.eq({ Logic.Tap("sw", "bench", pieces) }, {})
		t.eq({ Logic.Tap("sw", "nothing", pieces) }, {})
	end)

	t.test("a lamp or door tapped with a switch picked links, and the switch stays picked", function()
		local pick, action = Logic.Tap("sw", "lamp", pieces)
		t.eq(pick, "sw")
		t.eq(action, { op = "link", from = "sw", to = "lamp" })
		local pick2, action2 = Logic.Tap("sw", "door", pieces)
		t.eq(pick2, "sw")
		t.eq(action2, { op = "link", from = "sw", to = "door" })
	end)

	t.test("a lamp tapped with nothing picked is just picked, for CUT", function()
		t.eq({ Logic.Tap(nil, "lamp", pieces) }, { "lamp" })
		t.eq({ Logic.Tap("lamp", "door", pieces) }, { "door" }, "a target picked: no wire made")
		t.eq(Logic.Cut("lamp", pieces), { op = "cut", uid = "lamp" })
		t.eq(Logic.Cut("sw", pieces), { op = "cut", uid = "sw" })
		t.eq(Logic.Cut(nil, pieces), nil)
		t.eq(Logic.Cut("bench", pieces), nil)
		t.eq(Logic.Cut("gone", pieces), nil)
	end)

	t.test("the Wire remote's arguments are the existing protocol", function()
		t.eq(Logic.Args({ op = "link", from = "sw", to = "lamp" }), { "sw", 1, "lamp", 1 })
		t.eq(Logic.Args({ op = "cut", uid = "sw" }), { "cut", "sw" })
		local WireLogic = t.shared("WireLogic")
		t.eq(Logic.Args({ op = "link", from = "a", to = "b" })[2], WireLogic.Port)
	end)

	t.test("the help line says what to do next, for each pick", function()
		t.ok(string.find(Logic.Help(nil, pieces), "Wall Switch", 1, true))
		t.ok(string.find(Logic.Help("sw", pieces), "Spark Lamp or a Door", 1, true))
		t.ok(string.find(Logic.Help("lamp", pieces), "CUT", 1, true))
	end)

	t.test("lines run from each switch to what it feeds, skipping what is gone", function()
		local wires = { sw = "lamp,door,ghost", sw2 = "lamp", lamp = "door", ghost = "lamp" }
		local lines = Logic.Segments(pieces, wires)
		t.eq(#lines, 3, "a lamp is not a source and ghosts are skipped")
		local first = lines[1]
		t.eq({ first.from, first.to }, { "sw", "lamp" })
		t.eq({ first.ax, first.az, first.bx, first.bz }, { 0, 0, 6, 0 })
		t.eq(first.ay, Logic.Height.switch)
		t.eq(first.by, Logic.Height.lamp)
		t.eq(Logic.Segments(pieces, {}), {})
	end)

	t.test("lines are budgeted: never more than MaxLines parts", function()
		local many = { piece("s", "SparkSwitch", 0, 0) }
		local targets = {}
		for i = 1, Logic.MaxLines + 20 do
			table.insert(many, piece("l" .. i, "SparkLamp", i % 10, i))
			table.insert(targets, "l" .. i)
		end
		local lines = Logic.Segments(many, { s = table.concat(targets, ",") })
		t.eq(#lines, Logic.MaxLines)
		t.eq(Logic.MaxLines, t.shared("WireLogic").MaxWires)
	end)

	t.test("Parse reads the attribute text and nothing else", function()
		t.eq(Logic.Parse("a,b,,c"), { "a", "b", "c" })
		t.eq(Logic.Parse(""), {})
		t.eq(Logic.Parse(nil), {})
		t.eq(Logic.Parse(7), {})
		t.eq(Logic.WireList({ sw = "a,b", sw2 = "a" }), {
			{ from = "sw", to = "a" },
			{ from = "sw", to = "b" },
			{ from = "sw2", to = "a" },
		})
	end)

	t.test("gamepad aim picks the wireable piece nearest the crosshair, within reach and angle", function()
		-- Standing at x = -10 looking along +x at the switch's tie height.
		t.eq(Logic.Aim(pieces, -10, 3.4, 0, 1, 0, 0), "sw")
		t.eq(Logic.Aim(pieces, -10, 3.4, 0, -1, 0, 0), nil, "looking away")
		t.eq(Logic.Aim(pieces, -10, 3.4, 0, 0, 0, 1), nil, "looking sideways")
		t.eq(Logic.Aim(pieces, -200, 3.4, 0, 1, 0, 0), nil, "too far")
		t.eq(Logic.Aim(pieces, -10, 3.4, 0, 0, 0, 0), nil, "no direction")
		t.eq(Logic.Aim({ piece("bench", "Bench", 0, 0) }, -10, 3.4, 0, 1, 0, 0), nil, "a bench cannot be wired")
		t.eq(Logic.Aim(pieces, 12, 4, -10, 0, 0, 1), "door", "the door is dead ahead from there")
	end)

	t.test("a touch pick takes the nearest wireable piece within the tap size", function()
		local points = { sw = { 100, 100 }, lamp = { 130, 100 }, bench = { 101, 101 }, door = { 400, 400 } }
		t.eq(Logic.NearestOnScreen(pieces, points, 102, 100), "sw")
		t.eq(Logic.NearestOnScreen(pieces, points, 125, 100), "lamp")
		t.eq(Logic.NearestOnScreen(pieces, points, 101, 101), "sw", "a bench never wins")
		t.eq(Logic.NearestOnScreen(pieces, points, 250, 250), nil, "empty ground")
		t.ok(Logic.TapPx >= InputKit.MinTouchPx, "the pick radius is a touch target")
	end)

	t.test("InputKit.WireBinds: RB picks, X cuts, B leaves, and no key is used twice", function()
		local by = {}
		for _, bind in ipairs(InputKit.WireBinds) do
			by[bind.action] = bind
		end
		t.eq(by.Pick.gamepad, Enum.KeyCode.ButtonR1, "RB picks: the right trigger is never bound")
		t.eq(by.Cut.gamepad, Enum.KeyCode.ButtonX)
		t.eq(by.BuyWire.gamepad, Enum.KeyCode.ButtonR3, "pressing the right stick buys the missing wire")
		t.ok(by.BuyWire.gamepad ~= Enum.KeyCode.ButtonR2 and by.BuyWire.gamepad ~= Enum.KeyCode.ButtonL2, "no trigger")
		t.ok(by.BuyWire.gamepad ~= Enum.KeyCode.ButtonY, "Y stays the HUD's Recall: buying never takes it")
		-- No other context binds the buy key, so nothing else fires with it.
		for context, binds in pairs(InputKit.Target) do
			for _, bind in ipairs(binds) do
				t.ok(bind.gamepad ~= by.BuyWire.gamepad, context .. " " .. bind.action .. " shares the buy key")
			end
		end
		t.eq(by.Done.gamepad, Enum.KeyCode.ButtonB)
		t.eq(by.Done.gamepad, InputKit.Actions.Cancel.gamepad, "B is the same Cancel everywhere")
		t.ok(InputKit.WireSafe(InputKit.WireBinds))
		t.ok(not InputKit.WireSafe({
			{ action = "A", gamepad = Enum.KeyCode.ButtonR1 },
			{ action = "B", gamepad = Enum.KeyCode.ButtonR1 },
		}))
		t.ok(not InputKit.WireSafe({
			{ action = "A", gamepad = Enum.KeyCode.ButtonR1, keyboard = Enum.KeyCode.X },
			{ action = "B", gamepad = Enum.KeyCode.ButtonB, keyboard = Enum.KeyCode.X },
		}))
	end)

	t.test("the client wires the tool into BUILD mode, the Wire remote and the module list", function()
		local fs = require("@lune/fs")
		local tool = fs.readFile("src/StarterPlayer/StarterPlayerScripts/WireTool.luau")
		t.ok(string.find(tool, 'Net.Remote("Wire")', 1, true), "fires the existing Wire remote")
		t.ok(string.find(tool, "InputKit.WireBinds", 1, true), "keys come from InputKit")
		t.ok(string.find(tool, "TouchTapInWorld", 1, true), "phone tap")
		t.ok(string.find(tool, "MouseButton1", 1, true), "PC click")
		t.ok(string.find(tool, 'PromptSwitch.Hold("wire")', 1, true), "world prompts off while wiring")
		t.ok(string.find(tool, 'PromptSwitch.Release("wire")', 1, true), "and back after")
		local plot = fs.readFile("src/StarterPlayer/StarterPlayerScripts/PlotUI.luau")
		t.ok(string.find(plot, "WireTool.SetBuilding(on)", 1, true), "build mode still shows the lines")
		t.eq(string.find(plot, 'text = "WIRE"', 1, true), nil, "no WIRE button on the hammer's bar (T420)")
		t.ok(string.find(tool, "WireSpool", 1, true), "the wire spool in hand starts the tool")
		t.ok(string.find(tool, "LogicPanelUI.Start", 1, true), "the settings panel starts with the tool")
	end)

	t.test("the first wiring session teaches three steps, then stays done", function()
		t.eq(Logic.Lesson(1), "Pick an output")
		t.eq(Logic.Lesson(2), "Pick an input")
		t.eq(Logic.Lesson(3), "Done: flip it")
		t.eq(Logic.Lesson(4), nil)
		t.eq(Logic.Advance(1, "source"), 2)
		t.eq(Logic.Advance(2, "link"), 3)
		t.eq(Logic.Advance(3, "done"), 4)
		t.eq(Logic.Advance(4, "source"), 4)
		t.eq(Logic.Advance(1, "done"), 1, "leaving early does not skip the lesson")
	end)

	t.test("a gate's second wire lands on the free input, then further wires share port 1", function()
		local wires = { { from = "sw", to = "gate" } }
		t.eq(Logic.NextIn(wires, "gate", "GateAnd"), 2)
		t.eq(Logic.NextIn({}, "gate", "GateAnd"), 1)
		local both = { { from = "sw", to = "gate" }, { from = "sw2", to = "gate", toPort = 2 } }
		t.eq(Logic.NextIn(both, "gate", "GateAnd"), 1)
		t.eq(Logic.NextIn({}, "lamp", "SparkLamp"), 1)
	end)

	local WireSupply = t.shared("WireSupply")

	t.test(
		"stretching a wire: nothing picked, then a length to the aim, then the pieces, all priced from the box",
		function()
			local sw, lamp, far = pieces[1], pieces[3], piece("far", "SparkLamp", 200, 0)
			t.eq(Logic.Stretch(10, nil, nil, nil).state, "start")
			local aiming = Logic.Stretch(10, sw, nil, 7.4)
			t.eq(aiming.state, "aim")
			t.eq(aiming.units, 8)
			local ok = Logic.Stretch(10, sw, lamp, nil)
			t.eq(ok.state, "ok")
			t.eq(ok.length, 6)
			t.eq(ok.units, 6)
			t.eq(ok.left, 4, "what the box would hold after")
			local short = Logic.Stretch(4, sw, lamp, nil)
			t.eq(short.state, "short")
			t.eq(short.short, 2)
			t.eq(short.buyCost, 2 * WireSupply.UnitPrice())
			local tooLong = Logic.Stretch(999, sw, far, nil)
			t.eq(tooLong.state, "far")
			t.eq(tooLong.short, 0)
			t.eq(Logic.Stretch(10, sw, sw, nil).state, "aim", "an end on itself is not an end")
			t.eq(Logic.Stretch(10, lamp, sw, nil).state, "start", "a wire starts at an output, not a lamp")
			t.eq(Logic.Stretch(10, sw, nil, WireSupply.MaxLength + 5).state, "far", "aiming past the longest wire")
		end
	)

	t.test("every stretch says its state in words, and the line colour follows the state", function()
		local sw, lamp = pieces[1], pieces[3]
		for _, r in ipairs({
			Logic.Stretch(10, nil, nil, nil),
			Logic.Stretch(10, sw, nil, 3),
			Logic.Stretch(10, sw, lamp, nil),
			Logic.Stretch(1, sw, lamp, nil),
			Logic.Stretch(10, sw, piece("far", "SparkLamp", 200, 0), nil),
		}) do
			t.ok(type(r.text) == "string" and r.text ~= "", r.state .. " has words")
		end
		t.eq(Logic.LineTone("ok"), "ok")
		t.eq(Logic.LineTone("aim"), "ok")
		t.eq(Logic.LineTone("short"), "warn")
		t.eq(Logic.LineTone("far"), "bad")
	end)

	t.test("the box line says how much wire is left, and when to buy", function()
		t.ok(string.find(Logic.BoxLine(14), "14", 1, true))
		t.ok(string.find(string.lower(Logic.BoxLine(0)), "empty", 1, true))
	end)

	t.test(
		"the buy button offers a pack: the smallest that covers the shortfall, else the smallest, never past the box",
		function()
			local sw, lamp = pieces[1], pieces[3]
			local short = Logic.BuyPlan(4, Logic.Stretch(4, sw, lamp, nil))
			t.eq(short.amount, 32, "2 short: the 32 pack")
			t.eq(short.cost, 32 * WireSupply.UnitPrice())
			t.ok(string.find(short.text, "32", 1, true) and string.find(short.text, "$", 1, true), short.text)
			local topUp = Logic.BuyPlan(30, Logic.Stretch(30, sw, lamp, nil))
			t.eq(topUp.amount, 32, "nothing missing: a top-up of the smallest pack")
			local nearlyFull =
				Logic.BuyPlan(WireSupply.MaxStock - 20, Logic.Stretch(WireSupply.MaxStock - 20, sw, lamp, nil))
			t.eq(nearlyFull.amount, 0, "no pack fits")
			local fits = Logic.BuyPlan(WireSupply.MaxStock - 32, Logic.Stretch(WireSupply.MaxStock - 32, sw, lamp, nil))
			t.eq(fits.amount, 32)
			local full = Logic.BuyPlan(WireSupply.MaxStock, Logic.Stretch(WireSupply.MaxStock, sw, lamp, nil))
			t.eq(full.amount, 0)
			t.ok(string.find(string.lower(full.text), "full", 1, true))
		end
	)

	t.test(
		"Lesson(step) returns the lesson, and nil once all three are seen (the file has no stray block in it)",
		function()
			t.eq(Logic.Lesson(1), "Pick an output")
			t.eq(Logic.Lesson(2), "Pick an input")
			t.eq(Logic.Lesson(3), "Done: flip it")
			t.eq(Logic.Lesson(4), nil)
			local fs = require("@lune/fs")
			local source = fs.readFile("src/ReplicatedStorage/Shared/WireToolLogic.luau")
			local _, count = string.gsub(source, "function WireToolLogic.Stretch%(", "")
			t.eq(count, 1, "one Stretch")
			local from = string.find(source, "function WireToolLogic.Lesson", 1, true)
			local to = string.find(source, "function WireToolLogic.Advance", 1, true)
			t.ok(to - from < 250, "Lesson is three lines long")
		end
	)

	t.test("a run's corners: a fifth bend is refused, and a stretch measures along them", function()
		local sw, lamp = pieces[1], pieces[3] -- 6 studs apart
		local bends = {}
		for i = 1, 4 do
			local added = Logic.AddBend(bends, i, 5)
			t.ok(added ~= nil, "bend " .. i)
			bends = added
		end
		t.eq({ Logic.AddBend(bends, 9, 9) }, { nil, "bends" }, "the fifth is refused")
		t.eq(({ Logic.AddBend({}, 0 / 0, 1) })[2], "badvia")
		local straight = Logic.Stretch(100, sw, lamp, nil, {})
		local bent = Logic.Stretch(100, sw, lamp, nil, { { x = 0, z = 20 }, { x = 6, z = 20 } })
		t.eq(straight.length, 6)
		t.eq(bent.length, 46, "20 up, 6 across, 20 back")
		t.eq(bent.bends, 2)
		t.eq(
			Logic.Stretch(100, sw, lamp, nil, { { x = 0, z = 30 }, { x = 6, z = 30 } }).state,
			"far",
			"66 studs along the path"
		)
	end)

	t.test("bends travel in the Wire args and the Wires attribute, and are drawn as legs", function()
		local args = Logic.Args({ op = "link", from = "sw", to = "lamp", via = { { x = 1, z = 2 } } })
		t.eq(#args, 5)
		t.eq(args[5], { { x = 1, z = 2 } })
		t.eq(#Logic.Args({ op = "link", from = "sw", to = "lamp" }), 4, "no corners: the old four")
		local WireLogic = t.shared("WireLogic")
		local text =
			Logic.Encode({ from = "sw", to = "lamp", toPort = 2, via = { { x = 1, z = 2 }, { x = -3.5, z = 4 } } })
		t.eq(text, "lamp@2~1.00:2.00~-3.50:4.00")
		local token = Logic.ParseToken(text)
		t.eq(token.uid, "lamp")
		t.eq(token.port, 2)
		t.eq(token.via, { { x = 1, z = 2 }, { x = -3.5, z = 4 } })
		t.eq(Logic.Parse(text .. ",door"), { "lamp", "door" })
		local legs = Logic.Segments(pieces, { sw = "lamp~3.00:5.00" })
		t.eq(#legs, 2, "one bend, two legs")
		t.eq({ legs[1].bx, legs[1].bz }, { 3, 5 })
		t.eq({ legs[2].ax, legs[2].az }, { 3, 5 })
		t.ok(WireLogic.Role("SparkSwitch") ~= nil)
	end)
end
