--!nocheck
-- The counter queue: three boxes, one offer at a time, no keeps the rest.
return function(t)
	local CounterLogic = t.shared("CounterLogic")
	local GameConfig = t.shared("GameConfig")
	local Vector3, CFrame = t.roblox.Vector3, t.roblox.CFrame

	t.test("the pay zone is the counter top, half a stud under it to six over it", function()
		local cf = CFrame.new()
		local size = Vector3.new(8, 2, 4)
		local top = size.Y / 2
		t.eq(CounterLogic.InZone(Vector3.new(0, top + 1, 0), cf, size), true)
		t.eq(CounterLogic.InZone(Vector3.new(0, top - 0.51, 0), cf, size), false)
		t.eq(CounterLogic.InZone(Vector3.new(0, top + 6, 0), cf, size), true)
		t.eq(CounterLogic.InZone(Vector3.new(0, top + 6.01, 0), cf, size), false)
		t.eq(CounterLogic.InZone(Vector3.new(size.X / 2, top + 1, 0), cf, size), true)
		t.eq(CounterLogic.InZone(Vector3.new(size.X / 2 + 0.01, top + 1, 0), cf, size), false)
	end)

	t.test("four boxes in the zone queue as three, and no keeps the order", function()
		t.eq(GameConfig.CounterMaxItems, 3)
		local items = {
			{ uid = "a", inZone = true },
			{ uid = "b", inZone = true },
			{ uid = "c", inZone = true },
			{ uid = "d", inZone = true },
			{ uid = "e", inZone = false },
		}
		local queue = CounterLogic.Queue(items)
		t.eq(queue, { "a", "b", "c" })
		t.eq(CounterLogic.Offer(queue), "a")
		t.eq(CounterLogic.Decline(queue), { "b", "c" })
	end)

	t.test("a box that left the counter is missing, even when the wallet is short", function()
		t.eq(CounterLogic.Line({ boxUid = "a", inZone = false, cash = 0, price = 160 }), "missing")
		t.eq(CounterLogic.Line({ boxUid = "a", inZone = true, cash = 100, price = 160 }), "broke")
		t.eq(CounterLogic.Line({ boxUid = "a", inZone = true, cash = 200, price = 160 }), "offer")
		t.eq(CounterLogic.Line({ greeting = true }), "greet")
		t.eq(CounterLogic.Line({ declined = true, boxUid = "a", inZone = true }), "declined")
		t.eq(CounterLogic.Line({ paid = true, boxUid = "a", inZone = true }), "thanks")
		t.eq(CounterLogic.Line({}), "missing")
	end)
end
