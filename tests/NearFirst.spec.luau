--!nocheck
-- NearFirst: build what is nearest the players first (the forest planter, the
-- terrain writer, the mesh swaps). Pure: the focus is injected.
return function(t)
	local NearFirst = t.shared("NearFirst")

	local function at(x, z)
		return { x = x, z = z }
	end
	local function posOf(item)
		return item
	end

	t.test("Distance2: the nearest of the players, or the fallback when there are none", function()
		t.eq(NearFirst.Distance2(3, 4, { at(0, 0), at(3, 0) }, at(100, 100)), 16, "nearest is (3,0): 4 away")
		t.eq(NearFirst.Distance2(3, 4, {}, at(0, 0)), 25, "no players: the spawn")
		t.eq(NearFirst.Distance2(3, 4, nil, at(3, 4)), 0)
	end)

	t.test("Order: nearest first, ties in the order given, the input untouched", function()
		local items = { at(50, 0), at(10, 0), at(-10, 0), at(30, 0), at(0, 10) }
		local ordered = NearFirst.Order(items, posOf, { at(0, 0) }, at(0, 0))
		t.eq(ordered[1], items[2], "(10,0) is the first of the three tied at 10")
		t.eq(ordered[2], items[3])
		t.eq(ordered[3], items[5])
		t.eq(ordered[4], items[4])
		t.eq(ordered[5], items[1])
		t.eq(items[1].x, 50, "the input list is as it was")
	end)

	t.test("Order: the nearest of several players counts, and a tier beats distance", function()
		local items = { at(0, 0), at(100, 100), at(90, 100), at(500, 0) }
		local ordered = NearFirst.Order(items, posOf, { at(95, 100), at(500, 10) }, at(0, 0))
		-- (95,100) is 5 from both (100,100) and (90,100): the earlier given first.
		t.eq(ordered[1], items[2])
		t.eq(ordered[2], items[3])
		t.eq(ordered[3], items[4], "500,0 is 10 from the second player")
		local tiered = NearFirst.Order(items, posOf, { at(0, 0) }, at(0, 0), function(item)
			return if item.x == 500 then 0 else 1
		end)
		t.eq(tiered[1], items[4], "tier 0 first, however far")
	end)

	t.test("Queue: the nearest of what is in it comes out first", function()
		local focus = { at(0, 0) }
		local q = NearFirst.Queue(posOf, {
			focus = function()
				return focus
			end,
		})
		q.Add({ at(30, 0), at(5, 0), at(500, 0) })
		t.eq(q.Remaining(), 3)
		t.eq(q.Next().x, 5)
		t.eq(q.Next().x, 30)
		-- A later batch (the planner hands them over as it goes): a near one beats the far one waiting.
		q.Add({ at(2, 0), at(9000, 0) })
		t.eq(q.Next().x, 2)
		t.eq(q.Next().x, 500)
		t.eq(q.Next().x, 9000)
		t.eq(q.Next(), nil)
		t.eq(q.Remaining(), 0)
	end)

	t.test("Queue: ties come out in the order they were added", function()
		local q = NearFirst.Queue(posOf)
		local a, b, c = at(10, 0), at(0, 10), at(-10, 0)
		q.Add({ a, b })
		q.Add({ c })
		t.ok(q.Next() == a)
		t.ok(q.Next() == b)
		t.ok(q.Next() == c)
	end)

	t.test("Queue: a player who runs off pulls the far trees forward, and a small step does not re-sort", function()
		local focus = { at(0, 0) }
		local q = NearFirst.Queue(posOf, {
			focus = function()
				return focus
			end,
			resortDistance = 40,
		})
		local items = {}
		for i = 1, 200 do
			table.insert(items, at(i * 10, 0)) -- a line out to 2000 studs
		end
		q.Add(items)
		t.eq(q.Next().x, 10)
		local sorts = q.Resorts()
		focus = { at(5, 0) } -- 5 studs: not enough to matter
		t.eq(q.Next().x, 20)
		t.eq(q.Resorts(), sorts, "no re-sort for a small step")
		focus = { at(1500, 0) } -- the player ran to the far end
		t.eq(q.Next().x, 1500, "the trees where the player is now go first")
		t.ok(q.Resorts() > sorts)
		t.eq(q.Next().x, 1490)
	end)

	t.test("Queue: with nobody in, the fallback (the spawn) decides", function()
		local q = NearFirst.Queue(posOf, {
			fallback = at(100, 0),
			focus = function()
				return {}
			end,
		})
		q.Add({ at(0, 0), at(90, 0), at(200, 0) })
		t.eq(q.Next().x, 90)
	end)

	t.test("Moved: a different number of points, or one past the distance", function()
		t.eq(NearFirst.Moved({ at(0, 0) }, nil, 40), true)
		t.eq(NearFirst.Moved({ at(0, 0) }, { at(10, 0) }, 40), false)
		t.eq(NearFirst.Moved({ at(0, 0) }, { at(41, 0) }, 40), true)
		t.eq(NearFirst.Moved({ at(0, 0), at(1, 1) }, { at(0, 0) }, 40), true)
		t.eq(NearFirst.Moved({}, {}, 40), false)
	end)
end
