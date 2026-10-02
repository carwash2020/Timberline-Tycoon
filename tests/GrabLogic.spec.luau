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
			{ "someone else's fresh cut", { ownerId = OTHER, createdAt = fresh }, false, "grace" },
			{ "someone else's, after the grace", { ownerId = OTHER, createdAt = old }, true },
			{ "an Elder's piece, at once", { ownerId = OTHER, createdAt = fresh, elder = true }, true },
			{ "held by someone else", { heldBy = OTHER }, false, "held" },
			{ "held by you (a new grip)", { ownerId = ME, heldBy = ME }, true },
			{ "dead wood, even your own", { ownerId = ME, dead = true }, false, "dead" },
			{ "being sold, even your own", { ownerId = ME, selling = true }, false, "selling" },
			{ "a shop's display item", { shopItem = true }, true },
			{ "a display item someone holds", { shopItem = true, heldBy = OTHER }, false, "held" },
			{ "on someone else's truck bed", { ownerId = OTHER, createdAt = old, bedOwnerId = OTHER }, false, "bed" },
			{ "unowned, on someone else's bed", { bedOwnerId = THIRD }, false, "bed" },
			{ "on your own bed", { ownerId = OTHER, createdAt = old, bedOwnerId = ME }, true },
			{ "a plot that says no", { plotAllows = false }, false, "plot" },
			{ "a plot that says yes", { plotAllows = true }, true },
		}
		for _, case in ipairs(cases) do
			local ok, reason = GrabLogic.CanGrab(facts(case[2]))
			t.eq(ok, case[3], case[1])
			t.eq(reason, case[4], case[1])
		end
	end)

	t.test("the grace is PickupGraceSec (45 s) from being cut free, to the second", function()
		t.eq(GameConfig.PickupGraceSec, 45)
		local f = facts({ ownerId = OTHER, createdAt = NOW - 44.5 })
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

	t.test("the hold distance stays HoldMin..HoldMax studs from you", function()
		t.eq({ GameConfig.HoldMin, GameConfig.HoldMax }, { 3, 14 })
		t.eq(GrabLogic.ClampHold(1), 3)
		t.eq(GrabLogic.ClampHold(8), 8)
		t.eq(GrabLogic.ClampHold(40), 14)
		t.eq(GrabLogic.ClampHold(0 / 0), 3)
		t.eq(GrabLogic.ClampHold(10, 4, 6), 6, "Tune's limits when given")
		local head = Vector3.new(0, 5, 0)
		t.eq(GrabLogic.StartHold(Vector3.new(0, 5, -7), head), 7)
		t.eq(GrabLogic.StartHold(Vector3.new(0, 5, -1), head), 3, "grabbed at your feet: held at the least")
		t.eq(GrabLogic.StepHold(13.5, 1), 14)
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
		t.eq(GameConfig.ReleaseDistance, 20)
		t.eq(with("distance", 20), nil)
		t.eq(with("distance", 20.5), "far")
		t.eq(with("distance", 0 / 0), "far")
		-- The server allows its range tolerance on top.
		t.ok(not GrabLogic.TooFar(20 + GameConfig.RangeTolerance))
		t.ok(GrabLogic.TooFar(20 + GameConfig.RangeTolerance + 0.1))
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

	t.test("gamepad: D-pad up/down push and pull, left/right turn, LB/RB tip", function()
		t.eq({ GrabLogic.PadAction("DPadUp") }, { nil, 1 })
		t.eq({ GrabLogic.PadAction("DPadDown") }, { nil, -1 })
		t.eq({ GrabLogic.PadAction("DPadLeft") }, { { kind = "yaw", steps = 1 } })
		t.eq({ GrabLogic.PadAction("DPadRight") }, { { kind = "yaw", steps = -1 } })
		t.eq({ GrabLogic.PadAction("ButtonL1") }, { { kind = "pitch", steps = 1 } })
		t.eq({ GrabLogic.PadAction("ButtonR1") }, { { kind = "pitch", steps = -1 } })
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
end
