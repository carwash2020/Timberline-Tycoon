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
		for i = 1, 100 do
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

	t.test("InputKit.WireBinds: RT picks, X cuts, B leaves, and no key is used twice", function()
		local by = {}
		for _, bind in ipairs(InputKit.WireBinds) do
			by[bind.action] = bind
		end
		t.eq(by.Pick.gamepad, Enum.KeyCode.ButtonR2)
		t.eq(by.Cut.gamepad, Enum.KeyCode.ButtonX)
		t.eq(by.Done.gamepad, Enum.KeyCode.ButtonB)
		t.eq(by.Done.gamepad, InputKit.Actions.Cancel.gamepad, "B is the same Cancel everywhere")
		t.ok(InputKit.WireSafe(InputKit.WireBinds))
		t.ok(not InputKit.WireSafe({
			{ action = "A", gamepad = Enum.KeyCode.ButtonR2 },
			{ action = "B", gamepad = Enum.KeyCode.ButtonR2 },
		}))
		t.ok(not InputKit.WireSafe({
			{ action = "A", gamepad = Enum.KeyCode.ButtonR2, keyboard = Enum.KeyCode.X },
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
		t.ok(string.find(tool, "ProximityPromptService.Enabled", 1, true), "world prompts off while wiring")
		local plot = fs.readFile("src/StarterPlayer/StarterPlayerScripts/PlotUI.luau")
		t.ok(string.find(plot, "WireTool.SetBuilding(on)", 1, true), "build mode drives the tool")
		t.ok(string.find(plot, 'text = "WIRE"', 1, true), "a WIRE button on the build bar")
	end)
end
