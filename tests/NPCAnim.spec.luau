--!nocheck
-- NPCAnim: the blocky rig's walk, work, and talk poses. A chop winds up
-- and strikes, a saw slides both arms, a sweep changes direction, a carry
-- holds the left arm, a walk swings opposite limbs, and talking is still
-- when the weight is zero.

return function(t)
	local NPCAnim = t.shared("NPCAnim")

	t.test("a chop winds up behind, then strikes forward", function()
		local windPitch = NPCAnim.Chop(0.35)
		local strikePitch = NPCAnim.Chop(0.56)
		local donePitch = NPCAnim.Chop(1)
		t.ok(windPitch < -1, "arm back on the wind-up: " .. windPitch)
		t.ok(strikePitch > 0.8, "arm forward on the strike: " .. strikePitch)
		t.ok(strikePitch > windPitch, "the strike is in front of the wind-up")
		t.ok(math.abs(donePitch) < 0.05, "recovers")
		t.ok(NPCAnim.Length("chop") > 1, "a chop takes a moment")
		t.eq(NPCAnim.Length("carry"), 0)
	end)

	t.test("sawing holds both arms forward and slides them apart", function()
		local aL, aR = NPCAnim.Saw(0)
		t.ok(aL > 0.8 and aR > 0.8, "both arms forward")
		t.ok(math.abs(aL - aR) < 1e-6, "together at the start")
		local bL, bR = NPCAnim.Saw(math.pi / 2 / 8.5)
		t.ok(bL > bR, "they slide opposite ways")
		t.ok(NPCAnim.Length("saw") > NPCAnim.Length("chop"), "a few strokes")
	end)

	t.test("a sweep crosses and comes back", function()
		local _, yaw0 = NPCAnim.Sweep(0)
		local _, yawRight = NPCAnim.Sweep(math.pi / 2 / 3.6)
		local _, yawLeft = NPCAnim.Sweep(3 * math.pi / 2 / 3.6)
		t.ok(math.abs(yaw0) < 1e-6, "starts centred")
		t.ok(yawRight > 0.5, "one way: " .. yawRight)
		t.ok(yawLeft < -0.5, "and back: " .. yawLeft)
	end)

	t.test("a basket is held up, a cane stays low, a mug is not a carry", function()
		local basket = NPCAnim.Carry("basket")
		local cane = NPCAnim.Carry("cane")
		t.ok(basket > cane + 0.4, "the basket is cradled higher than the cane")
		t.eq(NPCAnim.Holds("basket"), true)
		t.eq(NPCAnim.Holds("sapling"), true)
		t.eq(NPCAnim.Holds("cane"), true)
		t.eq(NPCAnim.Holds("mug"), false)
		t.eq(NPCAnim.Holds(nil), false)
	end)

	t.test("walking swings opposite arms and legs", function()
		local leftHip, rightHip, leftArm, rightArm, bob = NPCAnim.Walk(math.pi / 2, 1)
		t.ok(leftHip > 0 and rightHip < 0, "legs oppose")
		t.ok(leftArm < 0 and rightArm > 0, "arms oppose the legs on their side")
		t.ok(math.abs(leftHip + rightHip) < 1e-6, "even stride")
		t.ok(bob > 0, "a step bobs")
		local still = NPCAnim.Walk(math.pi / 2, 0)
		t.eq(still, 0)
	end)

	t.test("talking is a gesture only while the weight is up", function()
		local stillArm, stillNod = NPCAnim.Talk(1, 0)
		t.eq(stillArm, 0)
		t.eq(stillNod, 0)
		local arm = NPCAnim.Talk(0, 1)
		t.ok(arm > 0.4 and arm < 0.9, "a raised hand: " .. arm)
	end)

	t.test("a sample blends a walk, a carry, and a chop without NaNs", function()
		local pose = NPCAnim.Sample({
			phase = 1,
			walk = 1,
			carry = "basket",
			work = "chop",
			workU = 0.5,
			workTime = 0.5,
			workWeight = 1,
			talkTime = 0.2,
			talkWeight = 1,
			breath = 0.5,
		})
		t.ok(pose.leftPitch > 0.5, "the basket stays up while walking")
		t.ok(pose.rightPitch > 0, "the chop is on the other arm")
		for key, value in pairs(pose) do
			t.ok(value == value, key .. " is NaN")
		end
		local quiet = NPCAnim.Sample({
			phase = 0,
			walk = 0,
			carry = nil,
			work = nil,
			workU = 0,
			workTime = 0,
			workWeight = 0,
			talkTime = 0,
			talkWeight = 0,
			breath = 0,
		})
		t.eq(quiet.leftHip, 0)
		t.eq(quiet.rightPitch, 0)
		t.eq(quiet.neckPitch, 0)
	end)
end
