--!nocheck
-- LoadQueue: the deferred build queue. What nobody needs in the first minute
-- is built after the first player can play, tier by tier, nearest the
-- players first, a time slice at a time, and a step that fails never stops
-- the rest.
return function(t)
	local LoadQueue = t.shared("LoadQueue")

	local function step(name, tier, x, z)
		return {
			name = name,
			tier = tier,
			at = if x then { x = x, z = z or 0 } else nil,
			run = function() end,
		}
	end

	local function names(list)
		local out = {}
		for _, s in ipairs(list) do
			table.insert(out, s.name)
		end
		return out
	end

	t.test("order: lower tier first, then nearest the focus, then first added", function()
		local steps = {
			step("far decor", 2, 900, 0),
			step("sky", 3, 10, 0),
			step("near decor", 2, 100, 0),
			step("npc far", 1, 500, 0),
			step("npc near", 1, 50, 0),
			step("no position", 2),
		}
		t.eq(
			names(LoadQueue.Order(steps, { { x = 0, z = 0 } })),
			{ "npc near", "npc far", "no position", "near decor", "far decor", "sky" }
		)
	end)

	t.test("order follows the player: standing by the volcano pulls its steps forward", function()
		local steps = {
			step("sawmill decor", 2, 0, 0),
			step("volcano crater", 2, 1000, 1000),
			step("hills boulders", 2, -600, 100),
		}
		t.eq(
			names(LoadQueue.Order(steps, { { x = 0, z = 0 } })),
			{ "sawmill decor", "hills boulders", "volcano crater" }
		)
		t.eq(
			names(LoadQueue.Order(steps, { { x = 980, z = 990 } })),
			{ "volcano crater", "sawmill decor", "hills boulders" }
		)
		-- Two players: each step is judged by its nearest player.
		t.eq(
			names(LoadQueue.Order(steps, { { x = 980, z = 990 }, { x = -560, z = 100 } })),
			{ "volcano crater", "hills boulders", "sawmill decor" }
		)
	end)

	t.test("with nobody to follow it is nearest the origin (the town), and ties keep their order", function()
		local steps = { step("b", 2, 10, 0), step("a", 2, 10, 0), step("c", 2, 5, 0) }
		t.eq(names(LoadQueue.Order(steps, nil)), { "c", "b", "a" })
		t.eq(names(LoadQueue.Order(steps, {})), { "c", "b", "a" })
	end)

	t.test("Cells groups a scattered list by square, rows then columns, keeping each cell's order", function()
		local items = {
			{ id = "a", x = 10, z = 10 },
			{ id = "b", x = 450, z = 20 },
			{ id = "c", x = 30, z = 30 },
			{ id = "d", x = 20, z = 450 },
			{ id = "e", x = -10, z = 5 },
		}
		local cells = LoadQueue.Cells(items, function(item)
			return { x = item.x, z = item.z }
		end, 400)
		t.eq(#cells, 4)
		local ids = {}
		for _, cell in ipairs(cells) do
			local row = {}
			for _, item in ipairs(cell.items) do
				table.insert(row, item.id)
			end
			table.insert(ids, table.concat(row))
		end
		-- Cells sort by z cell, then x cell: (-1,0) e; (0,0) a c; (1,0) b; (0,1) d.
		t.eq(ids, { "e", "ac", "b", "d" })
		-- `at` is the cell's centre of mass.
		t.eq(cells[2].at, { x = 20, z = 20 })
	end)

	t.test("the queue runs every step once, by priority, yielding a frame between steps", function()
		local waits = 0
		local ran = {}
		local queue = LoadQueue.new({
			wait = function()
				waits += 1
			end,
			spawn = function(fn)
				fn()
			end,
			log = function() end,
		})
		for _, spec in ipairs({
			{ "sky", 3, 0, 0 },
			{ "npc", 1, 0, 0 },
			{ "boulders", 2, 0, 0 },
		}) do
			queue.Add({
				name = spec[1],
				tier = spec[2],
				at = { x = spec[3], z = spec[4] },
				run = function()
					table.insert(ran, spec[1])
				end,
			})
		end
		t.eq(queue.Pending(), 3)
		t.eq(ran, {}, "nothing runs before Start")
		queue.Start()
		t.eq(ran, { "npc", "boulders", "sky" })
		t.eq(queue.Pending(), 0)
		t.eq(queue.Running(), false)
		t.ok(waits >= 3, "a frame between steps")
		local stats = queue.Stats()
		t.eq(stats.ran, 3)
		t.eq(stats.failed, 0)
		t.eq(stats.order, { "npc", "boulders", "sky" })
	end)

	t.test("a step that errors is logged and counted and the rest still run", function()
		local lines = {}
		local ran = {}
		local queue = LoadQueue.new({
			wait = function() end,
			spawn = function(fn)
				fn()
			end,
			log = function(line)
				table.insert(lines, line)
			end,
		})
		queue.Add({
			name = "bad",
			tier = 1,
			run = function()
				error("a bad seed")
			end,
		})
		queue.Add({
			name = "good",
			tier = 2,
			run = function()
				table.insert(ran, "good")
			end,
		})
		queue.Start()
		t.eq(ran, { "good" })
		t.eq(queue.Stats().failed, 1)
		t.eq(queue.Stats().ran, 2)
		t.ok(string.find(lines[1], "[Load] deferred bad FAILED", 1, true), lines[1])
		t.ok(string.find(lines[1], "a bad seed", 1, true))
		t.ok(string.find(lines[2], "[Load] deferred good took", 1, true), lines[2])
	end)

	t.test("every step logs one [Load] line with its name", function()
		local lines = {}
		local queue = LoadQueue.new({
			wait = function() end,
			spawn = function(fn)
				fn()
			end,
			log = function(line)
				table.insert(lines, line)
			end,
		})
		queue.Add(step("NPC Millie", 1))
		queue.Add(step("5. The scenery 1/9 (4)", 2))
		queue.Start()
		t.eq(#lines, 2)
		for _, line in ipairs(lines) do
			t.ok(string.find(line, "^%[Load%] deferred "), line)
		end
	end)

	t.test("the slice a step gets yields only when its budget is spent", function()
		local now = 0
		local waits = 0
		local queue = LoadQueue.new({
			budget = 0.01,
			clock = function()
				return now
			end,
			wait = function()
				waits += 1
			end,
			spawn = function(fn)
				fn()
			end,
			log = function() end,
		})
		local yielded = 0
		queue.Add({
			name = "long",
			run = function(slice)
				for _ = 1, 100 do
					now += 0.001 -- 1 ms of work
					if slice() then
						yielded += 1
					end
				end
			end,
		})
		queue.Start()
		t.ok(yielded >= 8 and yielded <= 11, "yielded " .. yielded .. " times in 100 ms of work")
		t.ok(waits >= yielded, "each yield is a real wait")
	end)

	t.test("steps added while it runs are picked up, and added after it went idle restart it", function()
		local ran = {}
		local idle = 0
		local queue = LoadQueue.new({
			wait = function() end,
			spawn = function(fn)
				fn()
			end,
			log = function() end,
		})
		queue.OnIdle(function()
			idle += 1
		end)
		queue.Start()
		t.eq(queue.Running(), false, "nothing to do: not running")
		queue.Add({
			name = "first",
			run = function()
				table.insert(ran, "first")
				-- A step may queue more (the planners queue their cells).
				queue.Add({
					name = "cell",
					run = function()
						table.insert(ran, "cell")
					end,
				})
			end,
		})
		t.eq(ran, { "first", "cell" })
		t.eq(idle, 1)
		queue.Add({
			name = "later",
			run = function()
				table.insert(ran, "later")
			end,
		})
		t.eq(ran, { "first", "cell", "later" }, "added after idle: the runner started again")
		t.eq(idle, 2)
	end)

	t.test("the focus is asked before every pick", function()
		local at = { x = 0, z = 0 }
		local order = {}
		local queue = LoadQueue.new({
			wait = function() end,
			spawn = function(fn)
				fn()
			end,
			log = function() end,
			focus = function()
				return { at }
			end,
		})
		local function add(name, x)
			queue.Add({
				name = name,
				at = { x = x, z = 0 },
				run = function()
					table.insert(order, name)
					if name == "first" then
						at = { x = 1000, z = 0 } -- the player runs east while it builds
					end
				end,
			})
		end
		add("first", 0)
		add("west", -300)
		add("east", 900)
		queue.Start()
		t.eq(order, { "first", "east", "west" })
	end)
end
