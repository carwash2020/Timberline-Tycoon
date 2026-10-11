--!nocheck
-- Lane R: the quarry's slab nodes.
return function(t)
	local QuarryLogic = t.load("ReplicatedStorage/Shared/Regions/QuarryLogic")
	local SlabData = t.shared("SlabData")

	local function facts(over)
		local f = { known = true, distance = 4, loose = 0, stage = 4 }
		for k, v in pairs(over or {}) do
			f[k] = v
		end
		return f
	end

	t.test("a ready node in reach gives a slab, then is empty until the timer runs out", function()
		local state = QuarryLogic.New()
		t.eq(QuarryLogic.Check(state, "slab-1", 100, facts()).ok, true)
		QuarryLogic.Take(state, "slab-1", 100)
		t.eq(QuarryLogic.Check(state, "slab-1", 101, facts()).ok, false)
		t.eq(QuarryLogic.Wait(state, "slab-1", 130), 30)
		t.eq(QuarryLogic.Check(state, "slab-1", 159.9, facts()).ok, false)
		t.eq(QuarryLogic.Check(state, "slab-1", 160, facts()).ok, true, "60 seconds")
		t.eq(QuarryLogic.RespawnSec, 60)
	end)

	t.test("nodes are independent", function()
		local state = QuarryLogic.New()
		QuarryLogic.Take(state, "slab-1", 0)
		t.eq(QuarryLogic.Check(state, "slab-2", 1, facts()).ok, true)
	end)

	t.test("at most 24 loose slabs a player", function()
		local state = QuarryLogic.New()
		t.eq(QuarryLogic.Check(state, "slab-1", 0, facts({ loose = 23 })).ok, true)
		local v = QuarryLogic.Check(state, "slab-1", 0, facts({ loose = SlabData.MaxLoose }))
		t.eq(v.ok, false)
		t.ok(v.reason ~= nil)
	end)

	t.test("it needs the reach, a known node and Stage 4", function()
		local state = QuarryLogic.New()
		t.eq(QuarryLogic.Check(state, "slab-1", 0, facts({ distance = QuarryLogic.Reach + 1 })).ok, false)
		t.eq(QuarryLogic.Check(state, "slab-1", 0, facts({ distance = 0 / 0 })).ok, false)
		t.eq(QuarryLogic.Check(state, "nope", 0, facts({ known = false })).ok, false)
		t.eq(QuarryLogic.Check(state, "slab-1", 0, facts({ stage = 3 })).ok, false)
		t.eq(QuarryLogic.Check(state, "slab-1", 0, facts({ stage = 8 })).ok, true)
	end)

	t.test("a refund gives the node back at once", function()
		local state = QuarryLogic.New()
		QuarryLogic.Take(state, "slab-1", 5)
		QuarryLogic.Refund(state, "slab-1")
		t.eq(QuarryLogic.Ready(state, "slab-1", 5), true)
	end)
end
