--!nocheck
-- TreeIndex (Shared/TreeIndex): the grid CanopyFade's 10 Hz look asks which
-- trees stand near its lines of sight. Pins that it answers exactly what a
-- scan of every tree with CanopyLogic.NearSightline answers, that the work
-- per look is the cells round the line and not the forest, and that learning
-- new trees is budgeted per call.
return function(t)
	local Vector3 = t.roblox.Vector3
	local TreeIndex = t.load("ReplicatedStorage/Shared/TreeIndex")
	local CanopyLogic = t.load("ReplicatedStorage/Shared/CanopyLogic")

	-- A fixed pseudo-random stream (no math.random: the spec must not vary).
	local function stream(seed)
		local state = seed
		return function()
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
	end

	local function forest(n, seed)
		local rand = stream(seed)
		local trees = {}
		for i = 1, n do
			trees[i] = { id = i, home = Vector3.new(rand() * 2200 - 1100, 0, rand() * 2200 - 1100) }
		end
		return trees
	end
	local function homeOf(tree)
		return tree.home
	end
	local function ids(list)
		local out = {}
		for _, tr in ipairs(list) do
			table.insert(out, tr.id)
		end
		table.sort(out)
		return out
	end

	t.test("Near is exactly the trees a full scan with NearSightline finds", function()
		local trees = forest(1500, 7)
		local index = TreeIndex.new()
		TreeIndex.Sync(index, trees, homeOf, math.huge)
		local rand = stream(99)
		for _ = 1, 200 do
			local eye = Vector3.new(rand() * 2200 - 1100, 20, rand() * 2200 - 1100)
			local target = eye + Vector3.new(rand() * 60 - 30, -15, rand() * 60 - 30)
			local want = {}
			for _, tr in ipairs(trees) do
				if CanopyLogic.NearSightline(tr.home, eye, target) then
					table.insert(want, tr)
				end
			end
			local got = TreeIndex.Near(index, eye, target, CanopyLogic.Reach)
			t.eq(ids(got), ids(want))
		end
		-- A line longer than the cell cap falls back to the full scan, same answer.
		local a, b = Vector3.new(-1000, 0, -900), Vector3.new(1000, 0, 900)
		local want = {}
		for _, tr in ipairs(trees) do
			if CanopyLogic.NearSightline(tr.home, a, b) then
				table.insert(want, tr)
			end
		end
		t.eq(ids((TreeIndex.Near(index, a, b, CanopyLogic.Reach))), ids(want))
	end)

	t.test("a look visits the cells round the line, a small part of 1,500 trees", function()
		local trees = forest(1500, 3)
		local index = TreeIndex.new()
		TreeIndex.Sync(index, trees, homeOf, math.huge)
		local most = 0
		local rand = stream(5)
		for _ = 1, 100 do
			local eye = Vector3.new(rand() * 2000 - 1000, 20, rand() * 2000 - 1000)
			local _, looked = TreeIndex.Near(index, eye, eye + Vector3.new(20, -10, 20), CanopyLogic.Reach)
			most = math.max(most, looked)
		end
		print(string.format("canopy look: at most %d of %d trees visited (a scan visits all)", most, #trees))
		t.ok(most < 150, "visited " .. most)
	end)

	t.test("Sync learns at most `budget` new trees a call, known trees cost no homeOf call", function()
		local trees = forest(600, 11)
		local index = TreeIndex.new()
		local calls = 0
		local function counting(tree)
			calls += 1
			return tree.home
		end
		local rounds = 0
		while index.count < #trees do
			calls = 0
			local asked = TreeIndex.Sync(index, trees, counting, 150)
			t.ok(asked <= 150 and calls <= 150, "bounded per call: " .. calls)
			rounds += 1
			t.ok(rounds <= 10)
		end
		t.eq(rounds, 4)
		calls = 0
		TreeIndex.Sync(index, trees, counting, 150)
		t.eq(calls, 0, "nothing new: no homeOf calls")
	end)

	t.test("trees that leave are forgotten, ones not placed yet are retried, non-trees asked once", function()
		local a = { id = 1, home = Vector3.new(0, 0, 0) }
		local b = { id = 2, home = Vector3.new(10, 0, 0) }
		local late = { id = 3, home = nil }
		local junk = { id = 4 }
		local asks = { late = 0, junk = 0 }
		local function of(tree)
			if tree == junk then
				asks.junk += 1
				return false
			elseif tree == late then
				asks.late += 1
				return tree.home
			end
			return tree.home
		end
		local index = TreeIndex.new()
		TreeIndex.Sync(index, { a, b, late, junk }, of, 100)
		TreeIndex.Sync(index, { a, b, late, junk }, of, 100)
		t.eq(asks.junk, 1, "a non-tree is asked once")
		t.eq(asks.late, 2, "a tree with no home yet is asked again")
		t.eq(ids((TreeIndex.Near(index, Vector3.new(0, 0, 0), Vector3.new(5, 0, 0), 24))), { 1, 2 })
		late.home = Vector3.new(3, 0, 3)
		TreeIndex.Sync(index, { a, b, late, junk }, of, 100)
		t.eq(ids((TreeIndex.Near(index, Vector3.new(0, 0, 0), Vector3.new(5, 0, 0), 24))), { 1, 2, 3 })
		TreeIndex.Sync(index, { a, late }, of, 100)
		t.eq(ids((TreeIndex.Near(index, Vector3.new(0, 0, 0), Vector3.new(5, 0, 0), 24))), { 1, 3 })
		t.eq(index.count, 2)
		TreeIndex.Sync(index, { a, late, junk }, of, 100)
		t.eq(asks.junk, 2, "a non-tree that left and came back is asked afresh")
	end)

	t.test("its distance is CanopyLogic's", function()
		local rand = stream(21)
		for _ = 1, 300 do
			local p = Vector3.new(rand() * 100, 0, rand() * 100)
			local a = Vector3.new(rand() * 100, 5, rand() * 100)
			local b = Vector3.new(rand() * 100, 9, rand() * 100)
			local tree = { id = 1, home = p }
			local index = TreeIndex.new()
			TreeIndex.Sync(index, { tree }, homeOf, 10)
			local reach = rand() * 40
			local near = #TreeIndex.Near(index, a, b, reach) == 1
			t.eq(near, CanopyLogic.DistanceXZ(p, a, b) <= reach)
		end
	end)
end
