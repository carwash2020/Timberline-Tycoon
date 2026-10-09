--!nocheck
-- What a hand-in may take: your own loose planks in reach, not in a truck
-- bed, not in someone else's hands.
return function(t)
	local H = t.shared("HandInLogic")

	local function c(uid, over)
		local base = {
			uid = uid,
			woodId = "frostwood",
			kind = "plank",
			volume = 10,
			figure = nil,
			owner = 7,
			welded = false,
			held = false,
			distance = 5,
		}
		for k, v in pairs(over or {}) do
			base[k] = v
		end
		return base
	end

	t.test("only your own loose planks in reach count", function()
		local list = {
			c("a"),
			c("b", { owner = 8 }),
			c("c", { welded = true }),
			c("d", { held = true }),
			c("e", { distance = H.Reach + 1 }),
			c("f", { kind = "log" }),
			c("g", { volume = 0 / 0 }),
			c("h", { woodId = "emberwood", volume = 4 }),
		}
		local planks = H.Planks(list, 7)
		t.eq(planks.frostwood, 10)
		t.eq(planks.emberwood, 4)
		t.eq(H.Planks(list, 0).frostwood, nil, "owner 0 is nobody")
	end)

	t.test("planks are picked smallest first until the need is met", function()
		local list =
			{ c("big", { volume = 50 }), c("s1", { volume = 5 }), c("s2", { volume = 8 }), c("mid", { volume = 20 }) }
		t.eq(table.concat(H.PickPlanks(list, 7, "frostwood", 12), ","), "s1,s2")
		t.eq(table.concat(H.PickPlanks(list, 7, "frostwood", 13), ","), "s1,s2")
		t.eq(table.concat(H.PickPlanks(list, 7, "frostwood", 14), ","), "s1,s2,mid")
		t.eq(#H.PickPlanks(list, 7, "emberwood", 5), 0)
	end)

	t.test("a relic takes one figured piece, log or plank, the smallest", function()
		local list = {
			c("p", { figure = "curly", volume = 9 }),
			c("l", { figure = "birdseye", kind = "log", volume = 6 }),
			c("plain", { volume = 1 }),
			c("theirs", { figure = "curly", owner = 9, volume = 1 }),
		}
		t.eq(H.Figured(list, 7, "frostwood"), 2)
		t.eq(H.PickFigured(list, 7, "frostwood"), "l")
		t.eq(H.PickFigured(list, 7, "emberwood"), nil)
	end)
end
