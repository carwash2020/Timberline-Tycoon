--!nocheck
-- LogicGraph: truth tables, timers, the 200-evaluation cap, loops, and a
-- rebuild that matches.
return function(t)
	local Graph = t.shared("LogicGraph")
	local Wire = t.shared("WireLogic")

	local function piece(uid, id)
		return { uid = uid, blueprintId = id }
	end

	local function has(report, uid)
		return table.find(report.changed, uid) ~= nil
	end

	t.test("AND, OR, XOR and NOT match their truth tables", function()
		local function gate(id, op)
			local placed = {
				piece("a", "Lever"),
				piece("b", "Lever"),
				piece("g", id),
				piece("lamp", "SparkLamp"),
			}
			local wires = {
				{ from = "a", to = "g", toPort = 1 },
				{ from = "b", to = "g", toPort = 2 },
				{ from = "g", to = "lamp" },
			}
			if id == "GateNot" then
				placed = { piece("a", "Lever"), piece("g", id), piece("lamp", "SparkLamp") }
				wires = { { from = "a", to = "g" }, { from = "g", to = "lamp" } }
			end
			local function run(av, bv)
				local g = Graph.Build(placed, wires, {})
				Graph.Set(g, "a", "1", av)
				if id ~= "GateNot" then
					Graph.Set(g, "b", "1", bv)
				end
				return Graph.On(g, "g"), Graph.On(g, "lamp")
			end
			if op == "not" then
				t.eq({ run(false) }, { true, true }, "not 0")
				t.eq({ run(true) }, { false, false }, "not 1")
			else
				local expect = {
					and_ = { false, false, false, true },
					or_ = { false, true, true, true },
					xor = { false, true, true, false },
				}
				local want = expect[op]
				local i = 1
				for _, av in ipairs({ false, true }) do
					for _, bv in ipairs({ false, true }) do
						local out, lamp = run(av, bv)
						t.eq(out, want[i], op .. " " .. tostring(av) .. " " .. tostring(bv))
						t.eq(lamp, out, "lamp follows")
						i += 1
					end
				end
			end
		end
		gate("GateAnd", "and_")
		gate("GateOr", "or_")
		gate("GateXor", "xor")
		gate("GateNot", "not")
	end)

	t.test("several wires into one input are OR, and an open AND input stays off", function()
		local orPlaced = { piece("a", "Lever"), piece("b", "Lever"), piece("g", "GateOr") }
		local orWires = {
			{ from = "a", to = "g", toPort = 1 },
			{ from = "b", to = "g", toPort = 1 },
		}
		local either = Graph.Build(orPlaced, orWires, {})
		Graph.Set(either, "b", "1", true)
		t.eq(Graph.On(either, "g"), true, "one of the two wires is enough")
		Graph.Set(either, "b", "1", false)
		t.eq(Graph.On(either, "g"), false)

		local andPlaced = { piece("a", "Lever"), piece("b", "Lever"), piece("g", "GateAnd") }
		local bothOnOne = Graph.Build(andPlaced, orWires, {})
		Graph.Set(bothOnOne, "a", "1", true)
		Graph.Set(bothOnOne, "b", "1", true)
		t.eq(Graph.On(bothOnOne, "g"), false, "input 2 has no wire, so AND stays off")
	end)

	t.test("a button stays on for one second, a lever holds", function()
		local g = Graph.Build({ piece("b", "Button"), piece("lamp", "SparkLamp") }, { { from = "b", to = "lamp" } }, {})
		local report = Graph.Set(g, "b", "1", true)
		t.eq(Graph.On(g, "b"), true)
		t.eq(Graph.On(g, "lamp"), true)
		t.ok(has(report, "lamp"))
		Graph.Tick(g, 0.9)
		t.eq(Graph.On(g, "b"), true, "still inside the second")
		Graph.Tick(g, 0.1)
		t.eq(Graph.On(g, "b"), false)
		t.eq(Graph.On(g, "lamp"), false)

		local lever = Graph.Build(
			{ piece("L", "Lever"), piece("lamp", "SparkLamp") },
			{ { from = "L", to = "lamp" } },
			{}
		)
		Graph.Set(lever, "L", "1", true)
		Graph.Tick(lever, 3)
		t.eq(Graph.On(lever, "L"), true, "a lever does not time out")
	end)

	t.test("Delay waits out its setting, and a 0.1 s tick is the step", function()
		local placed = { piece("L", "Lever"), piece("D", "Delay"), piece("lamp", "SparkLamp") }
		local wires = { { from = "L", to = "D" }, { from = "D", to = "lamp" } }
		local g = Graph.Build(placed, wires, { D = { delay = 0.5 } })
		Graph.Set(g, "L", "1", true)
		t.eq(Graph.On(g, "D"), false, "not yet")
		Graph.Tick(g, 0.4)
		t.eq(Graph.On(g, "D"), false, "0.4 s is short of 0.5")
		Graph.Tick(g, 0.1)
		t.eq(Graph.On(g, "D"), true)
		t.eq(Graph.On(g, "lamp"), true)
		-- A fraction under a step waits for the next step.
		local g2 = Graph.Build(placed, wires, { D = { delay = 0.2 } })
		Graph.Set(g2, "L", "1", true)
		Graph.Tick(g2, 0.05)
		t.eq(Graph.On(g2, "D"), false)
		Graph.Tick(g2, 0.05)
		t.eq(Graph.On(g2, "D"), false, "0.1 s has elapsed; a 0.2 s delay needs another step")
		Graph.Tick(g2, 0.1)
		t.eq(Graph.On(g2, "D"), true)
	end)

	t.test("Sustain holds on after the input drops, for the time you set", function()
		local placed = { piece("L", "Lever"), piece("S", "Sustain") }
		local g = Graph.Build(placed, { { from = "L", to = "S" } }, { S = { hold = 0.3 } })
		Graph.Set(g, "L", "1", true)
		t.eq(Graph.On(g, "S"), true)
		Graph.Set(g, "L", "1", false)
		t.eq(Graph.On(g, "S"), true, "still holding")
		Graph.Tick(g, 0.2)
		t.eq(Graph.On(g, "S"), true)
		Graph.Tick(g, 0.1)
		t.eq(Graph.On(g, "S"), false)
	end)

	t.test("a Clock blinks once per period, starting off", function()
		local g = Graph.Build({ piece("C", "Clock"), piece("lamp", "SparkLamp") }, {
			{ from = "C", to = "lamp" },
		}, { C = { period = 1 } })
		t.eq(Graph.On(g, "C"), false)
		Graph.Tick(g, 0.4)
		t.eq(Graph.On(g, "C"), false)
		Graph.Tick(g, 0.1)
		t.eq(Graph.On(g, "C"), true, "on at half the period")
		t.eq(Graph.On(g, "lamp"), true)
		Graph.Tick(g, 0.5)
		t.eq(Graph.On(g, "C"), false, "off again at the full period")
		Graph.Tick(g, 0.5)
		t.eq(Graph.On(g, "C"), true, "the next cycle")
	end)

	t.test("an oscillating circuit stops at 200 evaluations and is Overloaded", function()
		local placed = { piece("N", "GateNot") }
		local g = Graph.Build(placed, { { from = "N", to = "N" } }, {})
		t.eq(Graph.Overloaded(g, "N"), true)
		t.eq(Graph.Evals(g), Graph.Cap)
		t.eq(Graph.Cap, 200)
		-- A ring a player can actually save (a piece cannot wire to itself).
		local ring = {
			piece("a", "GateNot"),
			piece("b", "GateNot"),
			piece("c", "GateNot"),
		}
		local wires = { { from = "a", to = "b" }, { from = "b", to = "c" }, { from = "c", to = "a" } }
		local loop = Graph.Build(ring, wires, {})
		t.eq(Graph.Overloaded(loop, "a"), true)
		t.eq(Graph.Evals(loop), Graph.Cap)
		-- Cutting the loop (rebuilding without the return wire) is stable.
		local calm = Graph.Build(ring, { { from = "a", to = "b" }, { from = "b", to = "c" } }, {})
		t.eq(Graph.Overloaded(calm, "a"), false)
		t.ok(Graph.Evals(calm) < Graph.Cap)
	end)

	t.test("rebuilding after a load gives the same latch and gate state", function()
		local placed = {
			piece("L", "Lever"),
			piece("B", "Button"),
			piece("g", "GateAnd"),
			piece("lamp", "SparkLamp"),
			piece("C", "Clock"),
		}
		local wires = {
			{ from = "L", to = "g", toPort = 1 },
			{ from = "B", to = "g", toPort = 2 },
			{ from = "g", to = "lamp" },
		}
		local settings = { C = { period = 2 } }
		local function picture(buttonOn)
			local g = Graph.Build(placed, wires, settings)
			Graph.Set(g, "L", "1", true)
			if buttonOn then
				Graph.Set(g, "B", "1", true)
			end
			return {
				Graph.On(g, "g"),
				Graph.On(g, "lamp"),
				Graph.On(g, "L"),
				Graph.On(g, "C"),
			}
		end
		t.eq(picture(false), picture(false))
		t.eq(picture(true), { true, true, true, false })
		t.eq(picture(false), { false, false, true, false })
		-- The setting is part of the rebuild.
		local slow = Graph.Build({ piece("D", "Delay") }, {}, { D = { delay = 4 } })
		local fast = Graph.Build({ piece("D", "Delay") }, {}, { D = { delay = 4 } })
		t.eq(Graph.On(slow, "D"), Graph.On(fast, "D"))
		t.eq(Wire.ClampSetting("Delay", "delay", 4), 4)
	end)

	t.test("settings outside the range are refused, and in-range values snap to the step", function()
		t.eq(Wire.ClampSetting("Delay", "delay", 0.1), 0.1)
		t.eq(Wire.ClampSetting("Delay", "delay", 10), 10)
		t.eq(Wire.ClampSetting("Delay", "delay", 0.05), nil)
		t.eq(Wire.ClampSetting("Delay", "delay", 10.1), nil)
		t.eq(Wire.ClampSetting("Delay", "hold", 1), nil, "delay has no hold key")
		t.eq(Wire.ClampSetting("Clock", "period", 0.5), 0.5)
		t.eq(Wire.ClampSetting("Clock", "period", 30), 30)
		t.eq(Wire.ClampSetting("Clock", "period", 0.4), nil)
		t.eq(Wire.ClampSetting("Clock", "period", 1.3), 1.5)
		t.eq(Wire.ClampSetting("Sustain", "hold", 2.5), 2.5)
		t.eq(Wire.DefaultSetting("Delay"), "delay")
	end)
end
