--!nocheck
-- The wiring rules: which pieces connect, how far, how many, and what a
-- lamp or door does with its switches. Also the save sanitiser.
return function(t)
	local WireLogic = t.shared("WireLogic")

	local function item(uid, id, x, z, fill)
		return { uid = uid, blueprintId = id, x = x, z = z, fill = fill }
	end

	local function plot()
		return {
			item("sw", "SparkSwitch", 0, 0),
			item("lamp", "SparkLamp", 6, 0),
			item("door", "Door", 0, 10),
			item("far", "SparkLamp", 40, 0),
			item("bench", "Bench", 2, 2),
		}
	end

	t.test("roles: a switch, a lamp, a door, and nothing else", function()
		t.eq(WireLogic.Role("SparkSwitch"), "switch")
		t.eq(WireLogic.Role("SparkLamp"), "lamp")
		t.eq(WireLogic.Role("Door"), "door")
		t.eq(WireLogic.Role("Bench"), nil)
		t.eq(WireLogic.IsTarget("lamp"), true)
		t.eq(WireLogic.IsTarget("door"), true)
		t.eq(WireLogic.IsTarget("switch"), false)
		t.eq(WireLogic.IsTarget(nil), false)
	end)

	t.test("Check joins a switch to a lamp or a door and says why not otherwise", function()
		local p = plot()
		t.eq({ WireLogic.Check({}, p, "sw", "lamp") }, { true, nil })
		t.eq({ WireLogic.Check({}, p, "sw", "door") }, { true, nil })
		t.eq({ WireLogic.Check({}, p, "lamp", "sw") }, { false, "from" })
		t.eq({ WireLogic.Check({}, p, "sw", "bench") }, { false, "to" })
		t.eq({ WireLogic.Check({}, p, "sw", "sw") }, { false, "bad" })
		t.eq({ WireLogic.Check({}, p, "sw", "nope") }, { false, "missing" })
		t.eq({ WireLogic.Check({}, p, "sw", "far") }, { false, "span" })
		t.eq({ WireLogic.Check({ { from = "sw", to = "lamp" } }, p, "sw", "lamp") }, { false, "dup" })
		p[3].fill = { units = 2 }
		t.eq({ WireLogic.Check({}, p, "sw", "door") }, { false, "unfinished" })
	end)

	t.test("a switch feeds six things at most and a plot holds MaxWires", function()
		local p = { item("sw", "SparkSwitch", 0, 0) }
		local wires = {}
		for i = 1, WireLogic.MaxPerSwitch do
			table.insert(p, item("l" .. i, "SparkLamp", i, 0))
			table.insert(wires, { from = "sw", to = "l" .. i })
		end
		table.insert(p, item("extra", "SparkLamp", 2, 4))
		t.eq({ WireLogic.Check(wires, p, "sw", "extra") }, { false, "limit" })

		-- Doors are not logic pieces, so this fills the wire cap without the item cap.
		local big, bigWires = {}, {}
		local switches = math.ceil(WireLogic.MaxWires / WireLogic.MaxPerSwitch)
		for i = 1, switches do
			table.insert(big, item("s" .. i, "SparkSwitch", 0, 0))
		end
		local source = 1
		for n = 1, WireLogic.MaxWires do
			table.insert(big, item("d" .. n, "Door", 1, 0))
			table.insert(bigWires, { from = "s" .. source, to = "d" .. n })
			if n % WireLogic.MaxPerSwitch == 0 then
				source += 1
			end
		end
		table.insert(big, item("s0", "SparkSwitch", 0, 0))
		t.eq({ WireLogic.Check(bigWires, big, "s0", "d1") }, { false, "full" })
	end)

	t.test("a plot holds MaxItems logic pieces; a Door does not count", function()
		local p = {}
		for i = 1, WireLogic.MaxItems do
			table.insert(p, item("s" .. i, "SparkSwitch", 0, 0))
		end
		table.insert(p, item("door", "Door", 1, 0))
		t.eq(WireLogic.LogicCount(p), WireLogic.MaxItems)
		t.eq({ WireLogic.Check({}, p, "s1", "door") }, { true, nil }, "at the cap, wiring still works")
		table.insert(p, item("over", "SparkLamp", 2, 0))
		t.eq({ WireLogic.Check({}, p, "s1", "door") }, { false, "items" })
		t.eq(WireLogic.CanPlace(p, "Button"), false)
		t.eq(WireLogic.CanPlace(p, "Door"), true)
	end)

	t.test("Live drops wires to pieces that are gone or the wrong way round", function()
		local p = plot()
		local wires = {
			{ from = "sw", to = "lamp" },
			{ from = "sw", to = "gone" },
			{ from = "lamp", to = "sw" },
			{ from = "sw", to = "bench" },
		}
		t.eq(WireLogic.Live(wires, p), { { from = "sw", to = "lamp" } })
		t.eq(WireLogic.Live(nil, p), {})
	end)

	t.test("Candidates are the free targets in reach, nearest first", function()
		local p = plot()
		t.eq(WireLogic.Candidates({}, p, "sw"), { "lamp", "door" })
		t.eq(WireLogic.Candidates({ { from = "sw", to = "lamp" } }, p, "sw"), { "door" })
		t.eq(WireLogic.Candidates({}, p, "lamp"), {})
		t.eq(WireLogic.Candidates({}, p, "nope"), {})
	end)

	t.test("Without cuts every wire on a piece, at either end", function()
		local wires = { { from = "a", to = "b" }, { from = "a", to = "c" }, { from = "d", to = "c" } }
		local rest, cut = WireLogic.Without(wires, "c")
		t.eq(cut, 2)
		t.eq(rest, { { from = "a", to = "b" } })
		local same, none = WireLogic.Without(wires, "z")
		t.eq(none, 0)
		t.eq(#same, 3)
	end)

	t.test("a wired target follows any switch that is on, an unwired lamp stays lit", function()
		local wires = { { from = "s1", to = "lamp" }, { from = "s2", to = "lamp" } }
		t.eq({ WireLogic.Power(wires, "lamp", {}) }, { true, false })
		t.eq({ WireLogic.Power(wires, "lamp", { s2 = true }) }, { true, true })
		t.eq({ WireLogic.Power(wires, "other", { s2 = true }) }, { false, false })
		t.eq(WireLogic.LampLit(true, false), false)
		t.eq(WireLogic.LampLit(true, true), true)
		t.eq(WireLogic.LampLit(false, false), true)
	end)

	t.test("InReach is a sphere of Reach studs and refuses NaN", function()
		local sw = item("sw", "SparkSwitch", 10, 0)
		t.eq(WireLogic.InReach(10 + WireLogic.Reach, 0, 0, sw), true)
		t.eq(WireLogic.InReach(10 + WireLogic.Reach + 1, 0, 0, sw), false)
		t.eq(WireLogic.InReach(10, WireLogic.Reach + 1, 0, sw), false)
		t.eq(WireLogic.InReach(0 / 0, 0, 0, sw), false)
		t.eq(WireLogic.InReach(math.huge, 0, 0, sw), false)
	end)

	t.test("Clean keeps well formed, unique, non-looping pairs and caps the list", function()
		local messy = {
			{ from = "a", to = "b" },
			{ from = "a", to = "b" },
			{ from = "a", to = "a" },
			{ from = "", to = "b" },
			{ from = 1, to = "b" },
			"junk",
			{ from = "c", to = "d", extra = true },
		}
		t.eq(WireLogic.Clean(messy), { { from = "a", to = "b" }, { from = "c", to = "d" } })
		t.eq(WireLogic.Clean(nil), {})
		t.eq(WireLogic.Clean(7), {})
		local many = {}
		for i = 1, WireLogic.MaxWires + 20 do
			table.insert(many, { from = "s" .. i, to = "t" .. i })
		end
		t.eq(#WireLogic.Clean(many), WireLogic.MaxWires)
	end)

	t.test("every refusal has a plain message", function()
		for _, key in ipairs({
			"bad",
			"missing",
			"from",
			"to",
			"unfinished",
			"dup",
			"span",
			"reach",
			"full",
			"limit",
			"none",
		}) do
			t.ok(WireLogic.Message(key), key)
		end
		t.eq(WireLogic.Message("nonsense"), nil)
	end)

	t.test("saved switch positions: cleaned, toggled, and pruned to switches still placed", function()
		t.eq(WireLogic.CleanSwitches({ "a", "a", "", 4, "b", {} }), { "a", "b" })
		t.eq(WireLogic.CleanSwitches("on"), {})
		t.eq(WireLogic.CleanSwitches(nil), {})
		local many = {}
		for i = 1, WireLogic.MaxSwitches + 20 do
			table.insert(many, "s" .. i)
		end
		t.eq(#WireLogic.CleanSwitches(many), WireLogic.MaxSwitches)
		t.eq(WireLogic.IsOn({ "a" }, "a"), true)
		t.eq(WireLogic.IsOn({ "a" }, "b"), false)
		t.eq(WireLogic.IsOn(nil, "a"), false)
		local list = WireLogic.SetOn({}, "a", true)
		t.eq(list, { "a" })
		t.eq(WireLogic.SetOn(list, "a", true), { "a" }, "no repeat")
		t.eq(WireLogic.SetOn(list, "b", true), { "a", "b" })
		t.eq(WireLogic.SetOn({ "a", "b" }, "a", false), { "b" })
		t.eq(list, { "a" }, "the old list is left alone")
		local placed = { item("a", "SparkSwitch", 0, 0), item("lamp", "SparkLamp", 4, 0) }
		t.eq(WireLogic.LiveSwitches({ "a", "gone", "lamp" }, placed), { "a" }, "gone and not-a-switch drop out")
	end)
end
