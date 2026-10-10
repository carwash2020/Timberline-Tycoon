--!nocheck
-- GrabLogic (V2_PLAN.md §4a): who may grab which piece of loose wood, the
-- drag's pull (light wood lifts, a whole pine trunk only drags), the hold
-- distance, where a grab may land, when a hold ends, and DragController's
-- input maths (the target point, rotation steps, keys and buttons, touch
-- tap-and-hold, the confirm wait, the axe hint).
return function(t)
	local GrabLogic = t.shared("GrabLogic")
	local GameConfig = t.shared("GameConfig")
	local HintLogic = t.shared("HintLogic")
	local Vector3, Vector2, CFrame = t.roblox.Vector3, t.roblox.Vector2, t.roblox.CFrame

	local ME, OTHER, THIRD = 1, 2, 3
	local NOW = 1000

	-- A grab by ME of a piece, with `over` changing the facts.
	local function facts(over)
		local f = { userId = ME, ownerId = 0, createdAt = NOW - 1, now = NOW, heldBy = 0 }
		for k, v in pairs(over or {}) do
			f[k] = v
		end
		return f
	end

	local function near(a, b, eps)
		return (a - b).Magnitude < (eps or 1e-4)
	end

	t.test("the permission matrix", function()
		local fresh = NOW - 10 -- cut free 10 s ago: inside the cutter's 45 s
		local old = NOW - GameConfig.PickupGraceSec - 1
		local cases = {
			-- { what, facts, ok, reason }
			{ "unowned wood", {}, true },
			{ "your own fresh cut", { ownerId = ME, createdAt = fresh }, true },
			{ "someone else's wood while they're here", { ownerId = OTHER, createdAt = old }, false, "owned" },
			{
				"someone else's (not known to have left)",
				{ ownerId = OTHER, createdAt = old, ownerHere = nil },
				false,
				"owned",
			},
			{
				"someone else's fresh cut, and they've left",
				{ ownerId = OTHER, createdAt = fresh, ownerHere = false },
				false,
				"grace",
			},
			{
				"someone else's, they've left, after the grace",
				{ ownerId = OTHER, createdAt = old, ownerHere = false },
				true,
			},
			{ "an Elder's piece, at once", { ownerId = OTHER, createdAt = fresh, elder = true }, true },
			{ "held by someone else", { heldBy = OTHER }, false, "held" },
			{ "held by you (a new grip)", { ownerId = ME, heldBy = ME }, true },
			{ "dead wood, even your own", { ownerId = ME, dead = true }, false, "dead" },
			{ "being sold, even your own", { ownerId = ME, selling = true }, false, "selling" },
			{ "a shop's display item", { shopItem = true }, true },
			{ "a display item someone holds", { shopItem = true, heldBy = OTHER }, false, "held" },
			{ "on someone else's truck bed", { ownerId = OTHER, createdAt = old, bedOwnerId = OTHER }, false, "bed" },
			{ "unowned, on someone else's bed", { bedOwnerId = THIRD }, false, "bed" },
			{ "someone else's wood on your own bed", { ownerId = OTHER, createdAt = old, bedOwnerId = ME }, true },
			{
				"someone else's fresh cut on your own bed",
				{ ownerId = OTHER, createdAt = fresh, bedOwnerId = ME },
				true,
			},
			{ "a plot that says no", { plotAllows = false }, false, "plot" },
			{ "a plot that says yes", { plotAllows = true }, true },
		}
		for _, case in ipairs(cases) do
			local ok, reason = GrabLogic.CanGrab(facts(case[2]))
			t.eq(ok, case[3], case[1])
			t.eq(reason, case[4], case[1])
		end
	end)

	t.test("someone else's wood is theirs while they're here, an Elder's anyone's", function()
		local f = facts({ ownerId = OTHER, createdAt = NOW - 3600, ownerHere = true })
		t.eq({ GrabLogic.CanGrab(f) }, { false, "owned" })
		t.eq(GrabLogic.Message("owned", f, "Pal2"), "That's Pal2's wood.")
		t.eq(GrabLogic.Message("owned", f), "That's someone else's wood.")
		t.ok(GrabLogic.OwnedByOther(f))
		t.ok(not GrabLogic.OwnedByOther(facts({ ownerId = ME })), "yours")
		t.ok(not GrabLogic.OwnedByOther(facts({ ownerId = 0 })), "nobody's")
		t.ok(not GrabLogic.OwnedByOther(facts({ ownerId = OTHER, elder = true })), "an Elder's")
		t.ok(GrabLogic.CanGrab(facts({ ownerId = OTHER, elder = true, ownerHere = true })))
		f.ownerHere = false
		t.ok(GrabLogic.CanGrab(f), "once they've left (and the grace is over), anyone's")
	end)

	t.test("an owner who has left: the grace is PickupGraceSec (45 s) from being cut free, to the second", function()
		t.eq(GameConfig.PickupGraceSec, 45)
		local f = facts({ ownerId = OTHER, createdAt = NOW - 44.5, ownerHere = false })
		t.ok(not GrabLogic.CanGrab(f))
		t.eq(GrabLogic.GraceLeft(f), 0.5)
		t.eq(GrabLogic.Message("grace", f), "Someone else just cut that. It's free to take in 1 second.")
		f.createdAt = NOW - 45
		t.ok(GrabLogic.CanGrab(f), "at 45 s it's anyone's")
		t.eq(GrabLogic.GraceLeft(facts({ ownerId = OTHER, createdAt = NOW - 10 })), 35)
		t.eq(
			GrabLogic.Message("grace", facts({ ownerId = OTHER, createdAt = NOW - 10 })),
			"Someone else just cut that. It's free to take in 35 seconds."
		)
		t.eq(GrabLogic.GraceLeft(facts({ ownerId = ME, createdAt = NOW })), 0, "never for the owner")
	end)

	t.test("unowned wood becomes the grabber's; moving anyone else's never changes who's paid", function()
		t.eq(GrabLogic.NewOwner(facts({ ownerId = 0 })), ME)
		t.eq(GrabLogic.NewOwner(facts({ ownerId = OTHER, createdAt = 0 })), OTHER)
		t.eq(GrabLogic.NewOwner(facts({ ownerId = OTHER, elder = true })), OTHER)
		t.eq(GrabLogic.NewOwner(facts({ ownerId = 0, shopItem = true })), 0, "a display item belongs to the shop")
	end)

	t.test("refusals read clearly; a dead or selling piece says nothing", function()
		t.eq(GrabLogic.Message("held"), "Someone else is holding that.")
		t.eq(GrabLogic.Message("bed", nil, "Dale"), "That's on Dale's truck.")
		t.eq(GrabLogic.Message("far"), "Too far away. Walk closer to grab it.")
		t.ok(GrabLogic.Message("plot") ~= nil)
		t.eq(GrabLogic.Message("dead"), nil)
		t.eq(GrabLogic.Message("selling"), nil)
		t.eq(GrabLogic.Message(nil), nil)
	end)

	t.test(
		"an anchored piece still gets a pull: the mass comes from its parts when the assembly reports none",
		function()
			-- A shelf box is anchored until the server frees it; the client sizes the pull
			-- at the grab, so an assembly mass of 0 must not mean no force (the first grab
			-- did nothing and the second, on the freed box, worked).
			t.eq(GrabLogic.Force(0), 0)
			t.eq(GrabLogic.PullMass(0, { 8, 4, 0 }), 12)
			t.eq(GrabLogic.Force(GrabLogic.PullMass(0, { 8, 4, 0 })), 4000, "a 12-mass box is lifted at full pull")
			t.ok(GrabLogic.CanLift(GrabLogic.PullMass(0, { 10 })), "and can be lifted")
			t.eq(GrabLogic.PullMass(20, { 8, 4 }), 20, "a real assembly mass wins when it is larger")
			t.eq(GrabLogic.PullMass(5, { 8, 4 }), 12, "the parts win when they are larger")
			t.eq(GrabLogic.PullMass(0, {}), 0, "nothing to pull")
			t.eq(GrabLogic.PullMass(0 / 0, { -3, math.huge, 2 }), 2, "nonsense is ignored")
		end
	)

	t.test("the pull: mass x DragForcePerMass, capped at DragForceCap; nonsense pulls nothing", function()
		t.eq(GameConfig.DragForcePerMass, 400)
		t.eq(GameConfig.DragForceCap, 4000)
		t.eq(GrabLogic.Force(1), 400)
		t.eq(GrabLogic.Force(10), 4000)
		t.eq(GrabLogic.Force(100), 4000, "capped")
		t.eq(GrabLogic.Force(0), 0)
		t.eq(GrabLogic.Force(-5), 0)
		t.eq(GrabLogic.Force(0 / 0), 0)
		t.eq(GrabLogic.Force(math.huge), 0)
		t.eq(GrabLogic.Force(2, 500, 800), 800, "Tune's numbers when given")
		t.eq(GrabLogic.Torque(2000), 2000 * GrabLogic.TorqueArm)
		t.eq(GrabLogic.Torque(0 / 0), 0)
	end)

	t.test("an oak trunk lifts; a whole pine trunk only drags (V2_PLAN §2f: about 20 mass lifts)", function()
		local density = GameConfig.WoodDensity
		local oakTrunk = density * 2.0 * 2.0 * 9 -- §3a: 2.0 thick, 9 long
		local pineTrunk = density * 2.6 * 2.6 * 46 -- 2.6 thick, 46 long
		t.ok(GrabLogic.CanLift(oakTrunk), "oak trunk, mass " .. oakTrunk)
		t.ok(not GrabLogic.CanLift(pineTrunk), "pine trunk, mass " .. pineTrunk)
		t.ok(GrabLogic.CanLift(20) and not GrabLogic.CanLift(21), "the lift limit is about 20 mass")
		t.ok(GrabLogic.CanLift(0.5), "a limb flies")
	end)

	t.test(
		"a held shop box is carried: lifted whole, pulled at its centre, turned hard enough to stay level",
		function()
			-- A big shelf box (BoxSize.Max 3.1 x 4.6 x 3.6) weighs more than the wood cap lifts.
			local mass = 3.1 * 4.6 * 3.6 * 0.7
			local radius = math.sqrt(3.1 ^ 2 + 4.6 ^ 2 + 3.6 ^ 2) / 2
			t.ok(not GrabLogic.CanLift(mass), "the wood pull alone cannot lift it (the cause of the spin)")
			local wood = GrabLogic.HoldForce(mass, false)
			t.eq(wood, GrabLogic.Force(mass), "wood keeps the capped pull")
			local force = GrabLogic.HoldForce(mass, true)
			t.ok(force > mass * GrabLogic.Gravity, "a box's pull beats its weight")
			t.eq(force, mass * GrabLogic.Gravity * GrabLogic.BoxLiftMargin)
			t.eq(GrabLogic.HoldForce(1, true), 400, "a light box keeps the wood pull")
			t.eq(GrabLogic.HoldForce(0 / 0, true), 0)
			t.eq(GrabLogic.HoldTorque(force, false, radius), GrabLogic.Torque(force), "wood's torque is unchanged")
			local torque = GrabLogic.HoldTorque(force, true, radius)
			t.ok(torque >= force * radius, "a box's turn outweighs the pull at its far corner")
			t.ok(torque > GrabLogic.Torque(force))
			t.eq(GrabLogic.HoldTorque(0, true, radius), 0)
			t.eq(GrabLogic.HoldTorque(force, true, nil), GrabLogic.Torque(force), "no radius: the wood torque")
			t.ok(GrabLogic.PullsAtCentre(true) and not GrabLogic.PullsAtCentre(false))
		end
	)

	t.test("a box is held upright: only its turn about the world's up is kept", function()
		local tilted = CFrame.Angles(0.4, 1.0, 0.3)
		local up = GrabLogic.Upright(tilted)
		t.ok(math.abs(up.UpVector.Y - 1) < 1e-5, "level")
		local want = Vector3.new(tilted.LookVector.X, 0, tilted.LookVector.Z).Unit
		t.ok((up.LookVector - want).Magnitude < 1e-5, "same way round")
		local flat = CFrame.Angles(0, 2, 0)
		t.ok((GrabLogic.Upright(flat).LookVector - flat.LookVector).Magnitude < 1e-5, "an upright box is unchanged")
		local onFace = CFrame.Angles(math.rad(90), 0, 0) -- looking straight up or down
		t.ok(math.abs(GrabLogic.Upright(onFace).UpVector.Y - 1) < 1e-5, "even on its face it comes out level")
	end)

	t.test("the hold distance stays HoldMin..HoldMax studs from you", function()
		t.eq({ GameConfig.HoldMin, GameConfig.HoldMax }, { 3, 30 })
		t.eq(GrabLogic.ClampHold(1), 3)
		t.eq(GrabLogic.ClampHold(8), 8)
		t.eq(GrabLogic.ClampHold(60), 30)
		t.eq(GrabLogic.ClampHold(0 / 0), 3)
		t.eq(GrabLogic.ClampHold(10, 4, 6), 6, "Tune's limits when given")
		local head = Vector3.new(0, 5, 0)
		t.eq(GrabLogic.StartHold(Vector3.new(0, 5, -7), head), 7)
		t.eq(GrabLogic.StartHold(Vector3.new(0, 5, -1), head), 3, "grabbed at your feet: held at the least")
		t.eq(GrabLogic.StepHold(13.5, 1), 14.5)
		t.eq(GrabLogic.StepHold(29.5, 1), 30)
		t.eq(GrabLogic.StepHold(5, -1), 4)
	end)

	t.test("a grab lands on its part, or within the margin of it (the piece moved meanwhile)", function()
		local cf = CFrame.new(10, 2, 0) * CFrame.Angles(0, math.rad(90), 0)
		local size = Vector3.new(2, 9, 2)
		local inside = cf:PointToWorldSpace(Vector3.new(0.5, 3, -0.5))
		t.ok(near(GrabLogic.ClampToBox(cf, size, inside, 2), inside), "inside: where it was grabbed")
		local justOff = cf:PointToWorldSpace(Vector3.new(1.8, 0, 0))
		t.ok(
			near(GrabLogic.ClampToBox(cf, size, justOff, 2), cf:PointToWorldSpace(Vector3.new(1, 0, 0))),
			"onto the face"
		)
		t.eq(GrabLogic.ClampToBox(cf, size, cf:PointToWorldSpace(Vector3.new(4, 0, 0)), 2), nil, "3 studs off: no")
		t.eq(GrabLogic.ClampToBox(cf, size, Vector3.new(0 / 0, 0, 0), 2), nil)
	end)

	t.test("a hold ends past ReleaseDistance, on death, sitting down or taking a tool out", function()
		local ok = { distance = 10, alive = true, seated = false, toolOut = false }
		t.eq(GrabLogic.ReleaseReason(ok), nil)
		local function with(k, v)
			local s = table.clone(ok)
			s[k] = v
			return GrabLogic.ReleaseReason(s)
		end
		t.eq(with("alive", false), "died")
		t.eq(with("seated", true), "seated")
		t.eq(with("toolOut", true), "tool")
		t.eq(GameConfig.ReleaseDistance, 40)
		t.eq(with("distance", 40), nil)
		t.eq(with("distance", 40.5), "far")
		t.eq(with("distance", 0 / 0), "far")
		-- The server allows its range tolerance on top.
		t.ok(not GrabLogic.TooFar(40 + GameConfig.RangeTolerance))
		t.ok(GrabLogic.TooFar(40 + GameConfig.RangeTolerance + 0.1))
		t.ok(GrabLogic.TooFar(0 / 0))
	end)

	t.test("the target: along the camera ray, the hold distance from your head, in front", function()
		local head = Vector3.new(0, 5, 0)
		-- First person: straight out of your eyes.
		t.ok(near(GrabLogic.Target(head, Vector3.new(0, 0, -1), head, 6), Vector3.new(0, 5, -6)))
		-- Third person: the camera 12 behind and 4 up, looking past your head.
		local cam = Vector3.new(0, 9, 12)
		local dir = (Vector3.new(0, 3, -6) - cam).Unit
		local target = GrabLogic.Target(cam, dir, head, 8)
		t.ok(math.abs((target - head).Magnitude - 8) < 1e-4, "8 from the head")
		t.ok(target.Z < head.Z, "in front of you, not behind")
		local onRay = cam + dir * (target - cam):Dot(dir)
		t.ok(near(onRay, target), "on the ray")
		-- Looking far off to the side: the point 8 from the head nearest the ray.
		local away = GrabLogic.Target(cam, Vector3.new(1, 0, 0), head, 8)
		t.ok(math.abs((away - head).Magnitude - 8) < 1e-4)
		t.ok(near(GrabLogic.Target(head, Vector3.zero, head, 5), Vector3.new(0, 5, -5)), "no direction: ahead")
	end)

	t.test("turns are 15 degree steps: yaw about up, tip about the camera's right", function()
		local look = Vector3.new(0, 0, -1)
		local yawed = GrabLogic.Turn(CFrame.identity, { kind = "yaw", steps = 6 }, look)
		t.ok(near(yawed.LookVector, Vector3.new(-1, 0, 0)), "6 steps left: a quarter turn")
		local tipped = GrabLogic.Turn(CFrame.identity, { kind = "pitch", steps = -6 }, look)
		t.ok(near(tipped.UpVector, Vector3.new(0, 0, -1)), "tipped away from you")
		local spun = CFrame.identity
		for _ = 1, 24 do
			spun = GrabLogic.Turn(spun, { kind = "yaw", steps = 1 }, look)
		end
		t.ok(near(spun.LookVector, Vector3.new(0, 0, -1)) and near(spun.UpVector, Vector3.new(0, 1, 0)), "24 = round")
		t.ok(
			near(GrabLogic.Turn(CFrame.new(5, 5, 5), { kind = "yaw", steps = 0 }, look).Position, Vector3.zero),
			"a rotation"
		)
		local straightDown = GrabLogic.Turn(CFrame.identity, { kind = "pitch", steps = 6 }, Vector3.new(0, -1, 0))
		t.ok(not near(straightDown.UpVector, Vector3.new(0, 1, 0)), "looking straight down still tips about something")
	end)

	t.test("keys: Q/E and Shift+A/D turn, Shift+W/S tip, plain WASD still walks", function()
		t.eq(GrabLogic.KeyAction("Q", false), { kind = "yaw", steps = 1 })
		t.eq(GrabLogic.KeyAction("E", false), { kind = "yaw", steps = -1 })
		for _, key in ipairs({ "W", "A", "S", "D" }) do
			t.eq(GrabLogic.KeyAction(key, false), nil, key .. " walks")
		end
		t.eq(GrabLogic.KeyAction("A", true), { kind = "yaw", steps = 1 })
		t.eq(GrabLogic.KeyAction("D", true), { kind = "yaw", steps = -1 })
		t.eq(GrabLogic.KeyAction("W", true), { kind = "pitch", steps = -1 })
		t.eq(GrabLogic.KeyAction("S", true), { kind = "pitch", steps = 1 })
		t.eq(GrabLogic.KeyAction("R", true), nil)
	end)

	t.test("gamepad: D-pad or RB/LB push and pull, D-pad left/right turn", function()
		t.eq({ GrabLogic.PadAction("DPadUp") }, { nil, 1 })
		t.eq({ GrabLogic.PadAction("DPadDown") }, { nil, -1 })
		t.eq({ GrabLogic.PadAction("ButtonR1") }, { nil, 1 })
		t.eq({ GrabLogic.PadAction("ButtonL1") }, { nil, -1 })
		t.eq({ GrabLogic.PadAction("DPadLeft") }, { { kind = "yaw", steps = 1 } })
		t.eq({ GrabLogic.PadAction("DPadRight") }, { { kind = "yaw", steps = -1 } })
		t.eq({ GrabLogic.PadAction("ButtonA") }, {})
	end)

	t.test("touch: a finger resting 0.25 s grabs; one that moves is the camera's", function()
		local start = Vector2.new(400, 200)
		t.eq(GrabLogic.TouchHoldSec, 0.25)
		t.eq(GrabLogic.TouchHold(10, start, 10.1, start), "wait")
		t.eq(GrabLogic.TouchHold(10, start, 10.25, start + Vector2.new(5, 5)), "grab", "a wobble is still resting")
		t.eq(GrabLogic.TouchHold(10, start, 10.1, start + Vector2.new(20, 0)), "cancel")
		-- Never in the thumbstick's corner.
		local screen = Vector2.new(1000, 600)
		t.ok(GrabLogic.InThumbstickZone(Vector2.new(100, 500), screen))
		t.ok(not GrabLogic.InThumbstickZone(Vector2.new(100, 100), screen), "the top-left is free")
		t.ok(not GrabLogic.InThumbstickZone(Vector2.new(600, 500), screen), "the middle is free")
	end)

	t.test("the client waits half a second for the server, plus the round trip, at most 2 s", function()
		t.eq(GrabLogic.ConfirmSec(nil), 0.5)
		t.eq(GrabLogic.ConfirmSec(0), 0.5)
		t.ok(math.abs(GrabLogic.ConfirmSec(0.2) - 0.9) < 1e-9, "200 ms lag")
		t.eq(GrabLogic.ConfirmSec(5), 2)
		t.eq(GrabLogic.ConfirmSec(0 / 0), 0.5)
	end)

	t.test("the axe hint fits the hint line on every device", function()
		for _, device in ipairs(HintLogic.Devices) do
			local line = GrabLogic.AxeHint(device)
			t.ok(#line <= HintLogic.MaxLength, line)
			t.ok(string.find(line, "axe away", 1, true) ~= nil, line)
		end
		t.eq(GrabLogic.AxeHint("desktop"), "Put your axe away (press 1) to drag")
	end)

	t.test("a shop box: unpaid until someone has it, then only the buyer, and the cap", function()
		local BoxLogic = t.shared("BoxLogic")
		local function box(over)
			local f = facts({ shopBox = true, ownerId = 0 })
			for k, v in pairs(over or {}) do
				f[k] = v
			end
			return f
		end
		local open = box({})
		t.eq({ GrabLogic.CanGrab(open) }, { true })
		t.eq(GrabLogic.NewOwner(open), 0, "grabbing a box does not make it yours")
		local claimed = box({ claimUserId = OTHER, claimUntil = NOW + 1 })
		t.eq({ GrabLogic.CanGrab(claimed) }, { false, "claim" })
		local expired = box({ claimUserId = OTHER, claimUntil = NOW })
		t.eq({ GrabLogic.CanGrab(expired) }, { true }, "the claim ends on its clock")
		local mine = box({ paid = true, buyerId = ME })
		t.eq({ GrabLogic.CanGrab(mine) }, { true })
		local theirs = box({ paid = true, buyerId = OTHER })
		t.eq({ GrabLogic.CanGrab(theirs) }, { false, "owned" })
		local fourth = box({ taking = true, unpaidByPlayer = BoxLogic.MaxUnpaidPerPlayer, unpaidOnServer = 0 })
		t.eq({ GrabLogic.CanGrab(fourth) }, { false, "cap" })
		local full = box({ taking = true, unpaidByPlayer = 0, unpaidOnServer = BoxLogic.MaxUnpaidPerServer })
		t.eq({ GrabLogic.CanGrab(full) }, { false, "cap" })
		local holding = box({ taking = false, unpaidByPlayer = 5, unpaidOnServer = 40 })
		t.eq({ GrabLogic.CanGrab(holding) }, { true }, "a box already off the shelf is not a new take")
		t.eq(GrabLogic.Message("cap", fourth), "You can only carry 3 unpaid boxes.")
		t.eq(GrabLogic.Message("cap", full), "The shop is full of loose boxes. Put one back and try again.")
	end)

	t.test("T5: only the pad owner or someone the plot allows can press", function()
		t.eq(GrabLogic.CanPressPad({ userId = ME, ownerId = ME, plotAllows = false }), true)
		t.eq(GrabLogic.CanPressPad({ userId = ME, ownerId = ME }), true)
		t.eq(GrabLogic.CanPressPad({ userId = OTHER, ownerId = ME, plotAllows = true }), true)
		t.eq(GrabLogic.CanPressPad({ userId = OTHER, ownerId = ME, plotAllows = false }), false)
		t.eq(GrabLogic.CanPressPad({ userId = OTHER, ownerId = ME }), false)
	end)

	t.test("PadPressAccepted: a handled R2 still grabs, a handled click does not, the placer owns R2", function()
		-- processed, trigger, selecting, placing
		t.eq(GrabLogic.PadPressAccepted(false, true, false, false), true)
		t.eq(GrabLogic.PadPressAccepted(true, true, false, false), true, "a bound action marked it handled")
		t.eq(GrabLogic.PadPressAccepted(true, true, true, false), false, "a menu has the pad selection")
		t.eq(GrabLogic.PadPressAccepted(true, false, false, false), false, "a handled mouse click is a button's")
		t.eq(GrabLogic.PadPressAccepted(false, false, false, false), true)
		t.eq(GrabLogic.PadPressAccepted(true, true, false, true), false, "placing: R2 is Place, not Grab")
		t.eq(GrabLogic.PadPressAccepted(false, true, false, true), false)
		t.eq(GrabLogic.PadPressAccepted(false, false, false, true), true, "the mouse still grabs")
	end)

	t.test("LT + the LEFT stick turns a carried piece: dead zone, rescaled throw, yaw and tip", function()
		local yaw, pitch = GrabLogic.StickTurn(0.1, -0.1, 0.016)
		t.eq({ yaw, pitch }, { 0, 0 }, "inside the dead zone nothing moves")
		local full = GrabLogic.StickTurn(1, 0, 0.016)
		t.ok(full < 0, "stick right turns it clockwise from above")
		t.ok(math.abs(full - -GrabLogic.StickTurnSpeed * 0.016) < 1e-9, "full throw is the full speed")
		local _, up = GrabLogic.StickTurn(0, 1, 0.016)
		t.ok(up < 0, "stick up tips it")
		local half = GrabLogic.StickTurn(0.6, 0, 0.016)
		t.ok(math.abs(half) < math.abs(full) and half < 0, "a gentler throw is slower")
		local huge = GrabLogic.StickTurn(1, 0, 5)
		t.ok(math.abs(huge) <= GrabLogic.StickTurnSpeed * 0.1 + 1e-9, "a long frame can't spin it")
		t.eq({ GrabLogic.StickTurn(0 / 0, 0 / 0, 0.016) }, { 0, 0 })
		local turned = GrabLogic.Rotate(CFrame.new(), math.rad(90), 0, Vector3.new(0, 0, -1))
		t.ok((turned.LookVector - Vector3.new(-1, 0, 0)).Magnitude < 1e-6, "a quarter turn left of -Z is -X")
	end)

	t.test("a stick flick fires once per push and rearms when the stick comes back", function()
		local flick, armed = GrabLogic.StickFlick(0, 0.9, true)
		t.eq({ flick, armed }, { 1, false })
		flick, armed = GrabLogic.StickFlick(0.9, 1, false)
		t.eq({ flick, armed }, { 0, false }, "held over: nothing more")
		flick, armed = GrabLogic.StickFlick(1, 0.1, false)
		t.eq({ flick, armed }, { 0, true }, "back to centre rearms")
		flick, armed = GrabLogic.StickFlick(0.1, -0.8, true)
		t.eq({ flick, armed }, { -1, false })
		t.eq({ GrabLogic.StickFlick(0, 0.5, true) }, { 0, true }, "not far enough")
	end)
	t.test(
		"while LT locks a piece the left stick turns it and does not walk; the lock cannot outlive its reasons",
		function()
			t.eq(GrabLogic.StickWalks(false), true, "no lock: the left stick walks as always")
			t.eq(GrabLogic.StickWalks(true), false, "locked: it turns the piece, never the character")
			local function facts(over)
				local f = {
					holding = true,
					triggerDown = true,
					alive = true,
					seated = false,
					toolOut = false,
					panelOpen = false,
					typing = false,
					focused = nil,
				}
				for k, v in pairs(over or {}) do
					f[k] = v
				end
				return f
			end
			t.eq(GrabLogic.LockStays(facts()), true)
			t.eq(GrabLogic.LockStays(facts({ triggerDown = false })), false, "LT up: released at once")
			t.eq(GrabLogic.LockStays(facts({ holding = false })), false, "dropped or placed")
			t.eq(GrabLogic.LockStays(facts({ alive = false })), false, "death")
			t.eq(GrabLogic.LockStays(facts({ seated = true })), false, "sat in a truck")
			t.eq(GrabLogic.LockStays(facts({ toolOut = true })), false, "a tool taken out")
			t.eq(GrabLogic.LockStays(facts({ panelOpen = true })), false, "a menu has the pad")
			t.eq(GrabLogic.LockStays(facts({ typing = true })), false, "typing in chat")
			t.eq(GrabLogic.LockStays(facts({ focused = false })), false, "the window lost focus")
			t.eq(GrabLogic.LockStays(facts({ focused = true })), true)
		end
	)

	t.test("DragController holds a shop box with the box rules (centre pull, upright, sized torque)", function()
		local fs = require("@lune/fs")
		local drag = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DragController.luau")
		t.ok(string.find(drag, "GrabLogic.HoldForce(", 1, true), "the pull is the hold force")
		t.ok(string.find(drag, "GrabLogic.HoldTorque(", 1, true), "the turn is the hold torque")
		t.ok(string.find(drag, "GrabLogic.PullsAtCentre(isBox)", 1, true), "boxes pull at the centre of mass")
		t.ok(string.find(drag, "GrabLogic.Upright(part.CFrame)", 1, true), "boxes are held upright")
		t.eq(string.find(drag, "GrabLogic.Torque(force)", 1, true), nil, "no bare wood torque left")
	end)

	t.test("the controllers turn with the LEFT stick (Thumbstick1) and leave the camera's right stick alone", function()
		local fs = require("@lune/fs")
		local Enum = t.roblox.Enum
		local dir = "src/StarterPlayer/StarterPlayerScripts/"
		local drag = fs.readFile(dir .. "DragController.luau")
		local placer = fs.readFile(dir .. "BlueprintPlacer.luau")
			.. fs.readFile(dir .. "PlaceControls.luau")
			.. fs.readFile("src/ReplicatedStorage/Shared/PlaceControlsLogic.luau")
		for name, src in pairs({ DragController = drag, BlueprintPlacer = placer }) do
			t.eq(string.find(src, "Enum.KeyCode.Thumbstick2", 1, true), nil, name .. " never binds the right stick")
			t.ok(string.find(src, "Thumbstick1", 1, true), name .. " binds the left stick")
			t.ok(string.find(src, "GrabLogic.StickWalks(", 1, true), name .. " asks whether the stick walks")
			t.ok(string.find(src, "GrabLogic.LockStays(", 1, true), name .. " ends the lock on its own")
			t.ok(
				string.find(src, "Move(Vector3.zero, false)", 1, true),
				name .. " holds the humanoid still while locked"
			)
			t.ok(
				string.find(src, "IsGamepadButtonDown(", 1, true),
				name .. " polls LT, so a missed release can't stick"
			)
			t.ok(string.find(src, "WindowFocusReleased", 1, true), name .. " lets go when the window loses focus")
		end
		-- The stick action sinks only while locked and passes otherwise.
		local onStick = string.match(drag, "onStick = function.-\nend\n")
		t.ok(onStick and string.find(onStick, "Enum.ContextActionResult.Pass", 1, true))
		t.ok(onStick and string.find(onStick, "Enum.ContextActionResult.Sink", 1, true))
		-- Released with the hold, on a drop, a placement or a tool away.
		local unbind = string.match(drag, "local function unbindHold%(%).-\nend\n")
		t.ok(unbind and string.find(unbind, "locked = false", 1, true), "the drop clears the lock")
		t.ok(unbind and string.find(unbind, 'UnbindAction("DragStick")', 1, true), "and gives the stick back")
		local stop = string.match(placer, "function BlueprintPlacer.Stop%(%).-\nend\n")
		t.ok(stop and string.find(stop, "PlaceControls.Unbind()", 1, true), "stopping unbinds the placer's stick sink")
		t.ok(string.find(placer, "UnbindAction(name)", 1, true), "and PlaceControls unbinds each action")
		-- The hint says it the right way round.
		local HintLogic = t.shared("HintLogic")
		t.ok(string.find(HintLogic.PickV2("console", "holding"), "left stick", 1, true))
		t.eq(string.find(HintLogic.PickV2("console", "holding"), "right stick", 1, true), nil)
		-- The build line is short (40 chars) and names no stick at all.
		t.eq(string.find(HintLogic.Pick("console", "build"), "right stick", 1, true), nil)
		-- InputKit's maps name the left stick, once per context.
		local InputKit = t.shared("InputKit")
		for _, context in ipairs({ "placer", "drag" }) do
			local sticks = 0
			for _, bind in ipairs(InputKit.Target[context]) do
				t.ok(bind.gamepad ~= Enum.KeyCode.Thumbstick2, context .. " binds no right stick")
				if bind.gamepad == Enum.KeyCode.Thumbstick1 then
					sticks += 1
				end
			end
			t.eq(sticks, 1, context .. " lists the left stick once")
			t.ok(InputKit.KeysUnique(InputKit.Target[context], false), context .. " keeps every key unique")
		end
	end)
end
