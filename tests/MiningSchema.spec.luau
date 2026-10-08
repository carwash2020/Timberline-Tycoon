--!nocheck
-- MiningSchema: Migrate is idempotent and clamps the section.

return function(t)
	local MiningSchema = t.load("ReplicatedStorage/Shared/Mining/MiningSchema")

	local function cf()
		local list = {}
		for i = 1, 12 do
			list[i] = 0
		end
		return list
	end

	t.test("nil, garbage, and a second pass all land on version 1", function()
		local fromNil = MiningSchema.Migrate(nil)
		t.eq(fromNil.v, 1)
		t.eq(fromNil.pick, "RustyPick")
		t.eq(fromNil.picks.RustyPick, true)
		t.eq(fromNil.bombs, 0)
		t.eq(fromNil.starterGiven, false)
		local junk = MiningSchema.Migrate("nope")
		t.eq(junk.pick, "RustyPick")
		local twice = MiningSchema.Migrate(MiningSchema.Migrate(fromNil))
		t.eq(twice.pick, fromNil.pick)
		t.eq(twice.bombs, fromNil.bombs)
		t.eq(twice.v, 1)
	end)

	t.test("an old shape is clamped", function()
		local old = MiningSchema.Migrate({
			bombs = 500,
			ropes = -4,
			pick = "Nope",
			picks = { RustyPick = true, MadeUp = true, LuxPickaxe = true },
			stash = {
				{ kind = "chunk", ore = "Nope", uid = "x", value = 1, cf = cf() },
				{ kind = "chunk", ore = "Coal", uid = "ok", value = 6.8, cf = cf() },
				{ kind = "ingot", ore = "Coal", uid = "fuel", value = 6, cf = { 1 } },
			},
			lamp = 1,
			hardhat = true,
		})
		t.eq(old.bombs, 99)
		t.eq(old.ropes, 0)
		t.eq(old.pick, "RustyPick")
		t.eq(old.picks.MadeUp, nil)
		t.eq(old.picks.LuxPickaxe, nil)
		t.eq(#old.stash, 1)
		t.eq(old.stash[1].uid, "ok")
		t.eq(old.stash[1].value, 6)
		t.eq(old.lamp, false)
		t.eq(old.hardhat, true)
	end)

	t.test("the equipped pick falls back to the best free one you own", function()
		local saved = MiningSchema.Migrate({
			v = 1,
			picks = { RustyPick = true, IronPick = true },
			pick = "Gone",
			bombs = 0,
			ropes = 0,
			stash = {},
			crafted = {},
		})
		t.eq(saved.pick, "IronPick")
		local lux = MiningSchema.Migrate({
			v = 1,
			picks = { RustyPick = true },
			pick = "LuxPickaxe",
			stash = {},
			crafted = {},
		})
		t.eq(lux.pick, "LuxPickaxe")
	end)
end
