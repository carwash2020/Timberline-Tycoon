--!nocheck
-- TalkLock: who an NPC faces while it talks, and when it lets go. Pure rules:
-- the most recent talker wins, yaw only, a smooth turn, a held walker stays
-- where it stands, and nothing outlives the conversation.
return function(t)
	local V3 = t.roblox.Vector3
	local TalkLock = t.shared("TalkLock")
	local DialogueFlow = t.shared("DialogueFlow")
	local FacingLogic = t.shared("FacingLogic")
	local NPCData = t.shared("NPCData")

	local function ids(list)
		local out = {}
		for _, talker in ipairs(list) do
			table.insert(out, talker.userId)
		end
		return out
	end

	t.test("a talk starts as the most recent, a repeat press moves them to the end, End removes", function()
		local list = TalkLock.Begin({}, 1, 10)
		list = TalkLock.Begin(list, 2, 11)
		t.eq(ids(list), { 1, 2 })
		local again = TalkLock.Begin(list, 1, 12)
		t.eq(ids(again), { 2, 1 })
		t.eq(ids(list), { 1, 2 }, "the list passed in is not changed")
		t.eq(ids(TalkLock.End(again, 2)), { 1 })
		t.eq(ids(TalkLock.End(again, 99)), { 2, 1 }, "an unknown player changes nothing")
		t.eq(TalkLock.Held({}), false)
		t.eq(TalkLock.Held(list), true)
	end)

	t.test("a crowd cannot grow the list without bound", function()
		local list = {}
		for i = 1, TalkLock.MaxTalkers + 5 do
			list = TalkLock.Begin(list, i, i)
		end
		t.eq(#list, TalkLock.MaxTalkers)
		t.eq(list[#list].userId, TalkLock.MaxTalkers + 5, "the newest stays")
		t.eq(list[1].userId, 6, "the oldest went")
	end)

	t.test("two players: face the most recent; the nearer on a tie; nobody means nil", function()
		local list = TalkLock.Begin(TalkLock.Begin({}, 1, 10), 2, 11)
		t.eq(TalkLock.Target(list, { [1] = 3, [2] = 9 }), 2, "the later talker, though farther")
		local tie = { { userId = 5, since = 10 }, { userId = 6, since = 10 } }
		t.eq(TalkLock.Target(tie, { [5] = 9, [6] = 4 }), 6, "the nearer of two at the same moment")
		t.eq(TalkLock.Target(tie, { [5] = 4, [6] = 9 }), 5)
		t.eq(TalkLock.Target(tie, nil), 5, "no distances: the lower id, never a flip between runs")
		t.eq(TalkLock.Target(tie, { [5] = 4, [6] = 4 }), 5)
		t.eq(TalkLock.Target({}, nil), nil)
		-- The most recent leaves: back to the other one, and only then to nobody.
		local left = TalkLock.End(list, 2)
		t.eq(TalkLock.Target(left, nil), 1)
		t.eq(TalkLock.Target(TalkLock.End(left, 1), nil), nil)
	end)

	t.test("everyone who stays within reach, alive and not too long keeps the lock", function()
		local list = TalkLock.Begin(TalkLock.Begin({}, 1, 0), 2, 1)
		local kept, released = TalkLock.Prune(list, { [1] = { distance = 5 }, [2] = { distance = 20 } }, 5)
		t.eq(ids(kept), { 1, 2 })
		t.eq(released, {})
		-- Past the box's own walk-away distance but inside the slack: still held.
		local edge = DialogueFlow.CloseDistance + TalkLock.CloseSlack
		kept = TalkLock.Prune(list, { [1] = { distance = edge }, [2] = { distance = 5 } }, 5)
		t.eq(ids(kept), { 1, 2 }, "exactly at the line is not past it")
		kept, released = TalkLock.Prune(list, { [1] = { distance = edge + 0.1 }, [2] = { distance = 5 } }, 5)
		t.eq(ids(kept), { 2 }, "walked out of range")
		t.eq(released, { 1 })
	end)

	t.test("a player who left, died or has no character is let go", function()
		local list = TalkLock.Begin(TalkLock.Begin({}, 1, 0), 2, 1)
		local kept, released = TalkLock.Prune(list, { [2] = { distance = 4 } }, 2)
		t.eq(ids(kept), { 2 }, "player 1 left the game")
		t.eq(released, { 1 })
		kept, released =
			TalkLock.Prune(list, { [1] = { distance = 4, down = true }, [2] = { distance = nil, down = true } }, 2)
		t.eq(kept, {}, "dead, or no character")
		t.eq(released, { 1, 2 })
		kept = TalkLock.Prune(list, { [1] = { distance = nil }, [2] = { distance = 4 } }, 2)
		t.eq(ids(kept), { 1, 2 }, "an unknown distance alone is not a reason to let go")
	end)

	t.test("the NPC going or lying down ends every talk; so does a box left up far too long", function()
		local list = TalkLock.Begin(TalkLock.Begin({}, 1, 0), 2, 1)
		local facts = { [1] = { distance = 3 }, [2] = { distance = 3 } }
		local kept, released = TalkLock.Prune(list, facts, 2, true, false)
		t.eq(kept, {}, "removed")
		t.eq(released, { 1, 2 })
		kept = TalkLock.Prune(list, facts, 2, false, true)
		t.eq(kept, {}, "asleep")
		local limit = DialogueFlow.MaxOpenSeconds + TalkLock.TimeoutSlack
		kept = TalkLock.Prune(list, facts, limit, false, false)
		t.eq(ids(kept), { 1, 2 }, "exactly at the limit still holds")
		kept = TalkLock.Prune(list, facts, limit + 0.5, false, false)
		t.eq(ids(kept), { 2 }, "player 1 timed out, player 2 began a second later")
		kept = TalkLock.Prune(list, facts, limit + 2, false, false)
		t.eq(kept, {}, "then player 2")
	end)

	t.test("the yaw faces the partner about Y only, any distance, and keeps its heading on top of them", function()
		local from = V3.new(10, 3, 10)
		local targets = {
			V3.new(10, 3, -30),
			V3.new(60, 40, 10),
			V3.new(10, -5, 90),
			V3.new(-4, 3, 10),
			V3.new(200, 3, 190),
		}
		for _, to in ipairs(targets) do
			local yaw = TalkLock.Yaw(0.7, from, to)
			local want = V3.new(to.X - from.X, 0, to.Z - from.Z).Unit
			t.ok((FacingLogic.Direction(yaw) - want).Magnitude < 1e-4, "faces " .. tostring(to))
		end
		t.eq(TalkLock.Yaw(1.25, from, V3.new(10.2, 9, 10.1)), 1.25, "on their toes: no spin")
		t.eq(TalkLock.Yaw(1.25, from, from), 1.25)
	end)

	t.test("the turn is smooth: no faster than the NPCs' turn rate, the short way round, then still", function()
		local from, to = V3.new(0, 0, 0), V3.new(0, 0, 10) -- the partner is behind (+Z): yaw pi
		local dt = 1 / 30
		local yaw = 0
		local last = yaw
		local steps = 0
		while math.abs(math.abs(yaw) - math.pi) > 1e-9 and steps < 200 do
			yaw = TalkLock.Turn(yaw, from, to, dt)
			t.ok(math.abs(yaw - last) <= NPCData.TurnRate * dt + 1e-9, "a bounded step")
			last = yaw
			steps += 1
		end
		t.ok(steps > 1, "it turned over several frames, not in one")
		t.ok(math.abs(math.abs(yaw) - math.pi) < 1e-9, "and arrived")
		t.ok(math.abs(TalkLock.Turn(yaw, from, to, dt) - yaw) < 1e-9, "then it stays")
		-- The short way round across the wrap: 3.0 toward 3.2 goes up through pi, not back through 0.
		local across = TalkLock.Turn(3.0, from, V3.new(-math.sin(3.2), 0, -math.cos(3.2)), dt)
		t.ok(across > 3.0, "short way")
		t.eq(TalkLock.Turn(0.4, from, to, 0), 0.4, "no time, no turn")
		t.eq(TalkLock.Turn(0.4, from, to, -1), 0.4, "negative time never turns it backwards")
	end)

	t.test("Want: the partner at any distance, else the nearest player in range, else home", function()
		local pos = V3.new(0, 0, 0)
		local far = V3.new(0, 0, -80) -- well past FaceRange, straight ahead of yaw 0
		t.eq(TalkLock.Want(1.1, pos, far, nil), 0, "partner far away: still faced")
		t.eq(TalkLock.Want(1.1, pos, nil, far), 1.1, "a stranger that far gets no turn")
		local near = V3.new(8, 0, 0)
		t.eq(TalkLock.Want(1.1, pos, nil, near), FacingLogic.Face(pos, near), "the usual turn within range")
		t.eq(TalkLock.Want(1.1, pos, far, near), 0, "the partner beats a nearer stranger")
		t.eq(TalkLock.Want(1.1, pos, nil, nil), 1.1, "nobody: home")
	end)

	t.test("a held walker stays where it stands, a free one follows the clock", function()
		local x, z = TalkLock.HoldAt(true, 5, 6, 50, 60)
		t.eq({ x, z }, { 5, 6 })
		x, z = TalkLock.HoldAt(false, 5, 6, 50, 60)
		t.eq({ x, z }, { 50, 60 })
		x, z = TalkLock.HoldAt(true, nil, nil, 50, 60)
		t.eq({ x, z }, { 50, 60 }, "never placed yet: nothing to hold")
	end)

	t.test("a talk begins only within the prompt's reach plus slack", function()
		t.eq(TalkLock.BeginReach(), NPCData.TalkDistance + TalkLock.BeginSlack)
		t.ok(
			TalkLock.BeginReach() < DialogueFlow.CloseDistance,
			"a press far out cannot start a talk the box would close"
		)
	end)
end
