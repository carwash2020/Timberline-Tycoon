--!nocheck
-- Clearance: shape distances and the spatial hash agree with a brute-force scan.
return function(t)
	local Vector2 = t.roblox.Vector2
	local Clearance = t.load("ReplicatedStorage/Shared/World/Clearance")
	local near = function(a, b)
		return math.abs(a - b) < 1e-6
	end

	t.test("two discs: the gap between their edges, negative when they overlap", function()
		t.ok(near(Clearance.Distance(Clearance.Disc(0, 0, 2), Clearance.Disc(10, 0, 3)), 5))
		t.ok(near(Clearance.Distance(Clearance.Disc(0, 0, 2), Clearance.Disc(3, 0, 2)), -1))
	end)

	t.test("a disc and a rectangle: 0 inside or touching, else the edge gap", function()
		local box = Clearance.Rect(0, 0, 10, 10)
		t.ok(near(Clearance.Distance(Clearance.Disc(5, 5, 1), box), 0), "inside")
		t.ok(near(Clearance.Distance(Clearance.Disc(13, 5, 1), box), 2), "beside")
		t.ok(near(Clearance.Distance(box, Clearance.Disc(13, 13, 1)), math.sqrt(18) - 1), "off a corner")
		t.ok(near(Clearance.Distance(Clearance.Disc(11, 5, 1), box), 0), "touching")
	end)

	t.test("two rectangles: overlap, containment, crossing and a gap", function()
		local a = Clearance.Rect(0, 0, 10, 10)
		t.eq(Clearance.Distance(a, Clearance.Rect(5, 5, 15, 15)), 0)
		t.eq(Clearance.Distance(a, Clearance.Rect(2, 2, 3, 3)), 0)
		t.eq(Clearance.Distance(Clearance.Rect(-5, 4, 15, 6), a), 0, "a bar crossing it")
		t.ok(near(Clearance.Distance(a, Clearance.Rect(14, 0, 20, 10)), 4))
		t.ok(Clearance.Closer(a, Clearance.Rect(14, 0, 20, 10), 5))
		t.ok(not Clearance.Closer(a, Clearance.Rect(14, 0, 20, 10), 4))
	end)

	t.test("Grow pushes a shape out", function()
		t.ok(near(Clearance.Distance(Clearance.Grow(Clearance.Disc(0, 0, 1), 2), Clearance.Disc(5, 0, 1)), 1))
		local grown = Clearance.Grow(Clearance.Rect(0, 0, 4, 4), 2)
		t.eq(grown.x0, -2)
		t.eq(grown.z1, 6)
	end)

	t.test("the grid finds exactly what a brute-force scan finds", function()
		local grid = Clearance.NewGrid()
		local seed = 5
		local rng = {
			NextNumber = function(_, lo, hi)
				seed = (seed * 1103515245 + 12345) % 2147483648
				return lo + (hi - lo) * seed / 2147483648
			end,
		}
		local shapes = {}
		for i = 1, 400 do
			local shape = if i % 3 == 0
				then Clearance.Rect(rng:NextNumber(-300, 300), rng:NextNumber(-300, 300), 0, 0)
				else Clearance.Disc(rng:NextNumber(-300, 300), rng:NextNumber(-300, 300), rng:NextNumber(1, 6))
			if shape.pts then
				local x, z = shape.x0, shape.z0
				shape = Clearance.Rect(x, z, x + rng:NextNumber(2, 20), z + rng:NextNumber(2, 20))
			end
			shapes[i] = shape
			Clearance.Add(grid, "s" .. i, if i % 3 == 0 then "box" else "disc", shape)
		end
		local gap = 8
		local want = 0
		for i = 1, #shapes do
			for j = i + 1, #shapes do
				if Clearance.Closer(shapes[i], shapes[j], gap) then
					want += 1
				end
			end
		end
		local got = #Clearance.Hits(grid, "disc", "disc", gap) + #Clearance.Hits(grid, "box", "box", gap)
		local mixed = #Clearance.Hits(grid, "disc", "box", gap)
		local wantMixed = 0
		for i = 1, #shapes do
			for j = 1, #shapes do
				if i % 3 ~= 0 and j % 3 == 0 and Clearance.Closer(shapes[i], shapes[j], gap) then
					wantMixed += 1
				end
			end
		end
		t.eq(mixed, wantMixed)
		t.ok(got <= want and got + mixed >= want, "the same-kind and mixed pairs add up to the brute-force total")
		t.eq(got + mixed, want)
	end)

	t.test("sources register footprints and Build walks them in name order", function()
		Clearance.Sources = {}
		Clearance.Register("b", function(grid)
			Clearance.Add(grid, "b1", "tree", Clearance.Disc(0, 0, 1))
		end)
		Clearance.Register("a", function(grid)
			Clearance.Add(grid, "a1", "rock", Clearance.Disc(2, 0, 1))
		end)
		local grid = Clearance.Build()
		t.eq(grid.all[1].id, "a1")
		local hits = Clearance.Hits(grid, "tree", "rock", 2)
		t.eq(#hits, 1)
		t.ok(near(hits[1].gap, 0))
		Clearance.Sources = {}
	end)
end
