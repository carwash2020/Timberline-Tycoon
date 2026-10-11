--!nocheck
-- V1 hardening: the caps on loose slabs, ore chunks and ingots (the wood has
-- its own in WoodService.spec). The oldest go first; a protected one never goes.
return function(t)
	local LooseCaps = t.shared("LooseCaps")
	local GameConfig = t.shared("GameConfig")

	local function e(uid, ownerId, bornAt, protected)
		return { uid = uid, ownerId = ownerId, bornAt = bornAt, protected = protected }
	end

	t.test("nothing goes while both caps hold", function()
		t.eq(LooseCaps.PickEvictions({}, 3, 10), {})
		t.eq(LooseCaps.PickEvictions({ e("a", 1, 1), e("b", 1, 2), e("c", 1, 3) }, 3, 3), {})
	end)

	t.test("a player's own cap: their oldest go, in order, and nobody else's", function()
		local list = {
			e("new", 1, 9),
			e("old", 1, 1),
			e("mid", 1, 5),
			e("other", 2, 0),
		}
		t.eq(LooseCaps.PickEvictions(list, 2, 100), { "old" })
		t.eq(LooseCaps.PickEvictions(list, 1, 100), { "old", "mid" })
		t.eq(
			LooseCaps.PickEvictions(list, 0, 100),
			{ "old", "mid", "new", "other" },
			"owners in id order, oldest first"
		)
	end)

	t.test("equal ages go in uid order, so the same list always gives the same answer", function()
		local list = { e("b", 1, 5), e("a", 1, 5), e("c", 1, 5) }
		t.eq(LooseCaps.PickEvictions(list, 1, 100), { "a", "b" })
	end)

	t.test("the server cap: nobody's go first, then the oldest of anyone's", function()
		local list = {
			e("mine-old", 1, 1),
			e("free-new", 0, 9),
			e("free-old", 0, 5),
			e("mine-new", 2, 8),
		}
		t.eq(LooseCaps.PickEvictions(list, 100, 3), { "free-old" })
		t.eq(LooseCaps.PickEvictions(list, 100, 2), { "free-old", "free-new" })
		t.eq(LooseCaps.PickEvictions(list, 100, 1), { "free-old", "free-new", "mine-old" })
	end)

	t.test("a protected one (held, boxed, on a truck) never goes, and still counts", function()
		local list = {
			e("held", 1, 0, true),
			e("a", 1, 1),
			e("b", 1, 2),
		}
		t.eq(LooseCaps.PickEvictions(list, 2, 100), { "a" }, "the held oldest stays; the next oldest makes room")
		t.eq(LooseCaps.PickEvictions(list, 0, 0), { "a", "b" }, "everything unprotected may go, never the held one")
		local all = { e("x", 0, 1, true), e("y", 0, 2, true) }
		t.eq(LooseCaps.PickEvictions(all, 0, 0), {}, "nothing to take")
	end)

	t.test("a piece the player's cap took is not taken twice by the server's", function()
		local list = { e("a", 1, 1), e("b", 1, 2), e("c", 1, 3) }
		t.eq(LooseCaps.PickEvictions(list, 2, 2), { "a" })
	end)

	t.test("a bad cap removes nothing rather than everything", function()
		local list = { e("a", 1, 1), e("b", 1, 2) }
		for _, bad in ipairs({ 0 / 0, -1, math.huge, "5" }) do
			t.eq(LooseCaps.PickEvictions(list, bad, 100), {}, tostring(bad))
			t.eq(LooseCaps.PickEvictions(list, 100, bad), {}, tostring(bad))
		end
	end)

	t.test("the entries are not changed", function()
		local list = { e("b", 1, 2), e("a", 1, 1) }
		LooseCaps.PickEvictions(list, 0, 0)
		t.eq(list[1].uid, "b")
		t.eq(list[2].uid, "a")
	end)

	t.test("the live caps: a few hundred parts a server, a per-player cap above the per-kind refusals", function()
		local SlabData = t.shared("SlabData")
		local MiningLogic = t.load("ReplicatedStorage/Shared/Mining/MiningLogic")
		t.eq(GameConfig.MaxLooseMaterialsServer, 400)
		t.eq(GameConfig.MaxLooseMaterialsPerPlayer, 64)
		t.ok(
			GameConfig.MaxLooseMaterialsPerPlayer >= SlabData.MaxLoose + MiningLogic.LiveChunks,
			"the per-kind refusals (24 slabs, 40 ore pieces) still hold first; this is the backstop"
		)
		t.ok(
			GameConfig.MaxLooseMaterialsServer < GameConfig.MaxPlayers * GameConfig.MaxLooseMaterialsPerPlayer,
			"a full server of hoarders is capped by the server's number"
		)
	end)
end
