--!nocheck
-- Lane F: sandstone slabs are worth nothing and are capped loose.
return function(t)
	local SlabData = t.shared("SlabData")

	t.test("a slab is a 4 x 2 x 2 part with its owner and uid, worth $0", function()
		local slab = SlabData.Make(7, "s1")
		t.eq(slab.Size, t.roblox.Vector3.new(4, 2, 2))
		t.eq(slab:GetAttribute("OwnerId"), 7)
		t.eq(slab:GetAttribute("Uid"), "s1")
		t.eq(SlabData.IsSlab(slab), true)
		t.eq(SlabData.SellValue(slab), 0, "never cash")
		t.eq(SlabData.IsSlab(t.roblox.Instance.new("Part")), false)
		t.eq(SlabData.IsSlab(nil), false)
	end)

	t.test("at most 24 loose a player, and slabs for units", function()
		t.eq(SlabData.CanSpawn(23), true)
		t.eq(SlabData.CanSpawn(24), false)
		t.eq(SlabData.CanSpawn(0 / 0), false)
		t.eq(SlabData.SlabsFor(4), 4)
		t.eq(SlabData.SlabsFor(0), 0)
		t.eq(SlabData.SlabsFor(-1), 0)
	end)
end
