--!nocheck
-- The blasting charge, the pure part (WORLD_DESIGN §11, §15).
return function(t)
	local BlastLogic = t.shared("BlastLogic")
	local GameConfig = t.shared("GameConfig")

	local function p(x, y, z)
		return { x = x, y = y, z = z }
	end

	t.test("a charge costs the locked price and the fuse is 5 seconds", function()
		t.eq(BlastLogic.Price(), 220)
		t.eq(BlastLogic.Price(), GameConfig.DynamitePrice)
		t.eq(BlastLogic.Price(), GameConfig.BlastingChargePrice)
		t.eq(BlastLogic.FuseSec, 5)
		t.eq(GameConfig.BoulderRespawnSec, 1200)
	end)

	t.test("the first respawn waits the full time, a blocked one waits 10 seconds", function()
		t.eq(BlastLogic.Delay(0), GameConfig.BoulderRespawnSec)
		t.eq(BlastLogic.Delay(1), 10)
		t.eq(BlastLogic.Delay(7), 10)
	end)

	t.test("a person or a truck part inside the boulder's box blocks it, padded by a couple of studs", function()
		local centre, size = p(0, 4, 0), p(8, 8, 8)
		t.ok(BlastLogic.Blocked(centre, size, { p(0, 3, 0) }), "standing in it")
		t.ok(BlastLogic.Blocked(centre, size, { p(5.5, 3, 0) }), "in the pad")
		t.ok(not BlastLogic.Blocked(centre, size, { p(7, 3, 0) }), "beside it")
		t.ok(not BlastLogic.Blocked(centre, size, { p(0, 12, 0) }), "far overhead")
		t.ok(not BlastLogic.Blocked(centre, size, {}), "nobody")
		t.ok(BlastLogic.Blocked(centre, size, { p(40, 3, 40), p(-1, 4, 1) }), "any one of them")
	end)

	t.test("setting a charge needs the player at the boulder", function()
		t.ok(BlastLogic.InRange(0))
		t.ok(BlastLogic.InRange(BlastLogic.PlaceRange))
		t.ok(not BlastLogic.InRange(BlastLogic.PlaceRange + 1))
		t.ok(BlastLogic.PlaceRange >= BlastLogic.PromptRange)
	end)

	t.test("the texts say 'blasting charge' and the price, and avoid the source game's word", function()
		t.eq(BlastLogic.ActionText(), "Set a blasting charge ($220)")
		t.eq(BlastLogic.ShortText(), "A blasting charge costs $220.")
		for _, text in ipairs({
			BlastLogic.ActionText(),
			BlastLogic.ShortText(),
			BlastLogic.FuseText(),
			BlastLogic.BusyText(),
		}) do
			t.ok(string.find(string.lower(text), "dynamite", 1, true) == nil, text)
		end
		t.ok(string.find(BlastLogic.FuseText(), "5 seconds", 1, true) ~= nil)
	end)
end
