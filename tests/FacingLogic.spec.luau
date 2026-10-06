--!nocheck
-- Facing: models are built front -Z, so a walker must move along its own
-- look vector and a figure must face the thing it is told to.

return function(t)
	local V3 = t.roblox.Vector3
	local CF = t.roblox.CFrame
	local FacingLogic = t.shared("FacingLogic")
	local NPCData = t.shared("NPCData")

	local function look(yaw)
		return CF.Angles(0, yaw, 0).LookVector
	end

	t.test("Face points the model's front (-Z) at the target", function()
		local from = V3.new(5, 3, -2)
		local targets = { V3.new(5, 0, -20), V3.new(30, 9, -2), V3.new(5, 0, 40), V3.new(-9, 0, -2), V3.new(20, 0, 17) }
		for _, to in ipairs(targets) do
			local want = V3.new(to.X - from.X, 0, to.Z - from.Z).Unit
			local got = look(FacingLogic.Face(from, to))
			t.ok((got - want).Magnitude < 1e-4, "faces " .. tostring(to) .. ", got " .. tostring(got))
			t.ok((FacingLogic.Direction(FacingLogic.Face(from, to)) - want).Magnitude < 1e-4, "Direction agrees")
		end
	end)

	t.test("yaw 0 looks along -Z and a zero vector keeps it", function()
		t.ok((look(0) - V3.new(0, 0, -1)).Magnitude < 1e-6)
		t.eq(FacingLogic.YawOf(0, 0), 0)
		t.eq(NPCData.YawOf(1, 0), FacingLogic.YawOf(1, 0))
	end)

	t.test("CFrameFacing looks at the target and stays upright", function()
		local cf = FacingLogic.CFrameFacing(V3.new(1, 2, 3), V3.new(11, 50, 3))
		t.ok((cf.LookVector - V3.new(1, 0, 0)).Magnitude < 1e-4)
		t.ok((cf.UpVector - V3.new(0, 1, 0)).Magnitude < 1e-4)
	end)

	t.test("every walker moves along its look vector, never backwards", function()
		local checked = 0
		for _, npc in ipairs(NPCData.All()) do
			if npc.route then
				local speed = npc.speed or 4
				local cycle = NPCData.CycleTime(npc.route, speed)
				local time = 0
				while time < cycle do
					local x0, z0, yaw, moving = NPCData.RouteState(npc.route, speed, time)
					if moving then
						local x1, z1 = NPCData.RouteState(npc.route, speed, time + 0.05)
						local d = V3.new(x1 - x0, 0, z1 - z0)
						if d.Magnitude > 1e-3 then
							t.ok(look(yaw):Dot(d.Unit) > 0.99, npc.id .. " walks along its look at t=" .. time)
							checked += 1
						end
					end
					time += 0.25
				end
			end
		end
		t.ok(checked > 50, "sampled the walkers")
	end)

	t.test("standing NPCs turn to face the player through the same helper", function()
		local pos, player = V3.new(0, 0, 0), V3.new(7, 0, -7)
		local yaw = NPCData.FaceYaw(0, pos, player, NPCData.FaceRange)
		t.eq(yaw, FacingLogic.Face(pos, player))
	end)
end
