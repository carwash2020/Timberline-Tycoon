--!nocheck
-- Who may grab or open a shop box, and when an unpaid box has left the store.
return function(t)
	local BoxLogic = t.shared("BoxLogic")
	local GameConfig = t.shared("GameConfig")
	local Vector3, CFrame = t.roblox.Vector3, t.roblox.CFrame

	local function grab(over)
		local f = { userId = 1, now = 100, heldBy = 0 }
		for k, v in pairs(over or {}) do
			f[k] = v
		end
		return f
	end

	t.test("an unpaid box can be taken, a claim expires, and the caps refuse the next one", function()
		t.eq(BoxLogic.BoxClaimSec, 8)
		t.eq(BoxLogic.ClaimUntil(100), 108)
		t.eq({ BoxLogic.CanGrab(grab({})) }, { true })
		t.eq({ BoxLogic.CanGrab(grab({ claimUserId = 2, claimUntil = 101 })) }, { false, "claim" })
		t.eq({ BoxLogic.CanGrab(grab({ claimUserId = 2, claimUntil = 100 })) }, { true })
		t.eq({ BoxLogic.CanGrab(grab({ heldBy = 2 })) }, { false, "held" })
		t.eq({ BoxLogic.CanGrab(grab({ paid = true, buyerId = 1 })) }, { true })
		t.eq({ BoxLogic.CanGrab(grab({ paid = true, buyerId = 2 })) }, { false, "owned" })
		t.eq({ BoxLogic.CanGrab(grab({ taking = true, unpaidByPlayer = 3, unpaidOnServer = 0 })) }, { false, "cap" })
		t.eq({ BoxLogic.CanGrab(grab({ taking = true, unpaidByPlayer = 0, unpaidOnServer = 30 })) }, { false, "cap" })
		t.eq({ BoxLogic.CanGrab(grab({ taking = true, unpaidByPlayer = 2, unpaidOnServer = 29 })) }, { true })
		t.eq({ BoxLogic.CanGrab(grab({ taking = false, unpaidByPlayer = 3, unpaidOnServer = 30 })) }, { true })
	end)

	t.test("the cap counts the unpaid boxes in your hands, not stale ones", function()
		local function box(over)
			local b = { paid = false, opened = false, onShelf = false, heldBy = 0 }
			for k, v in pairs(over or {}) do
				b[k] = v
			end
			return b
		end
		t.eq({ BoxLogic.CountUnpaid({}, 1) }, { 0, 0 })
		-- Three loose boxes someone dropped, one on a shelf, a paid one, an opened one.
		local floor =
			{ box(), box(), box(), box({ onShelf = true }), box({ paid = true, heldBy = 1 }), box({ opened = true }) }
		t.eq({ BoxLogic.CountUnpaid(floor, 1) }, { 0, 3 }, "dropped boxes are loose, not carried")
		table.insert(floor, box({ heldBy = 1 }))
		t.eq({ BoxLogic.CountUnpaid(floor, 1) }, { 1, 4 }, "one in hand")
		t.eq({ BoxLogic.CountUnpaid(floor, 2) }, { 0, 4 }, "another player's box is not yours")
		t.eq({ BoxLogic.CountUnpaid(floor, 0) }, { 0, 4 }, "nobody is not a holder")
		t.eq({ BoxLogic.CanGrab(grab({ taking = true, unpaidByPlayer = 1, unpaidOnServer = 4 })) }, { true })
	end)

	t.test("a box let go over its shelf spot is put back; one let go elsewhere is not", function()
		local home = Vector3.new(10, 4, 20)
		t.eq(BoxLogic.PutBack(home, home), true)
		t.eq(BoxLogic.PutBack(home + Vector3.new(BoxLogic.PutBackRadius, 1, 0), home), true)
		t.eq(BoxLogic.PutBack(home + Vector3.new(BoxLogic.PutBackRadius + 0.1, 0, 0), home), false)
		t.eq(BoxLogic.PutBack(home + Vector3.new(0, BoxLogic.PutBackHeight + 0.1, 0), home), false, "too high")
		t.eq(BoxLogic.PutBack(home + Vector3.new(0, -BoxLogic.PutBackHeight - 0.1, 0), home), false, "too low")
		t.eq(BoxLogic.PutBack(Vector3.new(0, 1, 0), home), false, "across the shop")
	end)

	t.test("only the buyer, close enough, with the matching box, may open it", function()
		local function open(over)
			local f = { userId = 1, buyerId = 1, paid = true, distance = 12, uid = "a", promptUid = "a" }
			for k, v in pairs(over or {}) do
				f[k] = v
			end
			return f
		end
		t.eq({ BoxLogic.CanOpen(open({})) }, { true })
		t.eq({ BoxLogic.CanOpen(open({ distance = 12.01 })) }, { false, "far" })
		t.eq({ BoxLogic.CanOpen(open({ userId = 2 })) }, { false, "owner" })
		t.eq({ BoxLogic.CanOpen(open({ paid = false })) }, { false, "unpaid" })
		t.eq({ BoxLogic.CanOpen(open({ promptUid = "b" })) }, { false, "uid" })
		t.eq({ BoxLogic.CanOpen(open({ opened = true })) }, { false, "opened" })
		t.eq(BoxLogic.OpenMessage("owner"), "That box isn't yours.")
	end)

	t.test("the store volume: one stud inside the door stays, past the pad leaves", function()
		local floor = CFrame.new()
		local foot = Vector3.new(18, 1, 14)
		local pad = GameConfig.StoreDespawnPad
		local function at(x, y, z)
			return BoxLogic.InsideVolume(Vector3.new(x, y, z), floor, foot)
		end
		t.eq(at(0, 1, -foot.Z / 2 + 1), true, "one stud inside the door")
		t.eq(at(0, 1, -(foot.Z / 2 + pad) - 0.01), false, "beyond the pad")
		t.eq(at(0, 0, 0), true)
		t.eq(at(0, GameConfig.StoreDespawnHeight, 0), true)
		t.eq(at(0, GameConfig.StoreDespawnHeight + 0.1, 0), false)
		t.eq(at(0, -0.1, 0), false)
		t.eq(BoxLogic.OutsideStreak(false, 0), 1)
		t.eq(BoxLogic.ShouldReturn(1), false)
		t.eq(BoxLogic.OutsideStreak(false, 1), 2)
		t.eq(BoxLogic.ShouldReturn(2), true)
		t.eq(BoxLogic.OutsideStreak(true, 2), 0)
		t.eq(BoxLogic.DespawnHz, 2)
	end)

	t.test("the box part cap, the pay tap and the lid faces", function()
		t.eq(BoxLogic.BoxPartCap, 6)
		t.ok(BoxLogic.PayTapPx >= 44)
		local faces = BoxLogic.LargestFaces(Vector3.new(2, 1.2, 1.6))
		t.eq(faces[1].Name, "Top")
		t.eq(faces[2].Name, "Bottom")
	end)
end
