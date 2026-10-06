--!nocheck
-- HeadLook: the neck yaw and pitch that point a head at the player, and
-- the front of every NPC's head (part-built and mesh) being on -Z.

return function(t)
	local V3, CF = t.roblox.Vector3, t.roblox.CFrame
	local HeadLook = t.shared("HeadLook")
	local NPCData = t.shared("NPCData")
	local CharacterArt = t.load("ReplicatedStorage/Shared/Art/CharacterArt")
	local TownModels = t.load("ReplicatedStorage/Shared/Art/TownModels")
	local NPCMeshes = t.load("ReplicatedStorage/Shared/Art/NPCMeshes")

	local function close(a, b, eps)
		return (a - b).Magnitude < (eps or 1e-4)
	end

	-- Roblox's Motor6D: Part1 = Part0 * C0 * Transform * C1:Inverse().
	local function headAfter(m, transform)
		local neck = m:FindFirstChild("Neck", true)
		return neck.Part0.CFrame * neck.C0 * transform * neck.C1:Inverse()
	end

	t.test("straight ahead is no turn; right of the face turns right (yaw < 0)", function()
		local pivot = CF.new(0, 5, 0)
		local yaw, pitch, ok = HeadLook.Aim(pivot, V3.new(0, 5, -10))
		t.ok(ok and math.abs(yaw) < 1e-9 and math.abs(pitch) < 1e-9)
		local ryaw = HeadLook.Aim(pivot, V3.new(10, 5, -10))
		t.ok(math.abs(ryaw + math.rad(45)) < 1e-6, "target to the right: " .. ryaw)
		local lyaw = HeadLook.Aim(pivot, V3.new(-10, 5, -10))
		t.ok(math.abs(lyaw - math.rad(45)) < 1e-6, "target to the left: " .. lyaw)
	end)

	t.test("yaw and pitch are clamped to 70 and 35 degrees", function()
		local yaw, pitch = HeadLook.Aim(CF.new(0, 0, 0), V3.new(10, 100, 1))
		t.ok(math.abs(yaw + math.rad(70)) < 1e-9, "yaw " .. yaw)
		t.ok(math.abs(pitch - math.rad(35)) < 1e-9, "pitch " .. pitch)
		local _, down = HeadLook.Aim(CF.new(0, 0, 0), V3.new(0, -100, -3))
		t.ok(math.abs(down + math.rad(35)) < 1e-9)
	end)

	t.test("a target behind the figure is out of reach: look ahead", function()
		local yaw, pitch, ok = HeadLook.Aim(CF.new(0, 0, 0), V3.new(1, 0, 20))
		t.ok(not ok and yaw == 0 and pitch == 0)
		local _, _, none = HeadLook.Aim(CF.new(0, 0, 0), V3.new(0, 9, 0))
		t.ok(not none, "straight above has no direction")
	end)

	t.test("the pivot's own turn is accounted for (world vs local space)", function()
		local pivot = CF.new(10, 0, 10) * CF.Angles(0, math.pi / 2, 0) -- front is now -X
		local yaw = HeadLook.Aim(pivot, V3.new(-20, 0, 10))
		t.ok(math.abs(yaw) < 1e-6, "dead ahead of a figure facing -X: " .. yaw)
		local right = HeadLook.Aim(pivot, V3.new(-20, 0, 20)) -- +Z of a figure facing -X is its left
		t.ok(right > 0.3, "turns left: " .. right)
	end)

	t.test("a restFront facing +Z (a flipped head) sees a -Z target as behind it", function()
		local _, _, ok = HeadLook.Aim(CF.new(0, 0, 0), V3.new(0, 0, -10), nil, V3.new(0, 0, 1))
		t.ok(not ok, "a head built backwards cannot face the player; this is what the mesh turn fixes")
		local yaw, _, ok2 = HeadLook.Aim(CF.new(0, 0, 0), V3.new(0, 0, 10), nil, V3.new(0, 0, 1))
		t.ok(ok2 and math.abs(yaw) < 1e-9)
	end)

	t.test("Approach eases toward the goal without overshoot", function()
		local v = 0
		for _ = 1, 10 do
			local n = HeadLook.Approach(v, 1, 1 / 30)
			t.ok(n > v and n < 1)
			v = n
		end
		t.ok(math.abs(HeadLook.Approach(0.5, 1, 0) - 0.5) < 1e-12)
	end)

	t.test("every NPC's face is on the head's -Z side", function()
		local checked = 0
		for _, npc in ipairs(NPCData.All()) do
			local m = CharacterArt.Build(npc.look)
			local head = m.Head
			for _, name in ipairs({ "Nose", "Mouth" }) do
				local part = head:FindFirstChild(name)
				t.ok(part, npc.id .. " has a " .. name)
				local rel = head.CFrame:PointToObjectSpace(part.CFrame.Position)
				t.ok(rel.Z < -0.3, npc.id .. " " .. name .. " is at z " .. rel.Z .. ", not on the -Z side")
			end
			local eyes = 0
			for _, d in ipairs(head:GetChildren()) do
				if d.Name == "Eye" then
					eyes += 1
					t.ok(head.CFrame:PointToObjectSpace(d.CFrame.Position).Z < -0.3, npc.id .. " eye on -Z")
				end
			end
			t.eq(eyes, 2)
			t.ok(close(head.CFrame.LookVector, V3.new(0, 0, -1)), npc.id .. " head front -Z at rest")
			checked += 1
		end
		t.ok(checked >= 13, "every NPC was checked: " .. checked)
	end)

	t.test("the named NPCs exist and are covered", function()
		for _, id in ipairs({ "Murph", "OldHank", "OldTolly", "CapnMoss", "Gus", "Rosa", "Pip", "Bram", "Hermit" }) do
			t.ok(NPCData.Get(id), id)
		end
	end)

	t.test("after the neck turns, every NPC's face points at the player", function()
		local players = { V3.new(0, 0, -12), V3.new(9, 3, -9), V3.new(-9, 2, -7), V3.new(11, 0, 4), V3.new(-4, 1, 9) }
		for _, npc in ipairs(NPCData.All()) do
			local m = CharacterArt.Build(npc.look)
			local neck = m:FindFirstChild("Neck", true)
			local pivot = neck.Part0.CFrame * neck.C0
			for _, p in ipairs(players) do
				local target = pivot.Position + p
				local yaw, pitch, ok = HeadLook.Aim(pivot, target)
				if ok then
					local head = headAfter(m, HeadLook.Transform(yaw, pitch))
					local want = (target - head.Position).Unit
					local flatWant = V3.new(want.X, 0, want.Z).Unit
					local flatGot = V3.new(head.LookVector.X, 0, head.LookVector.Z).Unit
					local clamped = math.abs(yaw) >= HeadLook.MaxYaw - 1e-9
					if not clamped then
						t.ok(
							(flatWant - flatGot).Magnitude < 1e-3,
							npc.id .. " face " .. tostring(flatGot) .. " vs player " .. tostring(flatWant)
						)
					else
						t.ok(flatWant:Dot(flatGot) > 0.3, npc.id .. " turns toward the player at its limit")
					end
				end
			end
		end
	end)

	t.test("the mesh NPCs get their face onto -Z (a half turn from the authored +Z)", function()
		t.ok(math.abs(TownModels.NpcMeshYaw - math.pi) < 1e-9)
		t.ok(math.abs(NPCMeshes.FrontTurn() - math.pi) < 1e-9)
		local face = CF.Angles(0, NPCMeshes.FrontTurn(), 0):VectorToWorldSpace(V3.new(0, 0, 1))
		t.ok(close(face, V3.new(0, 0, -1), 1e-5), "authored +Z face ends up on -Z: " .. tostring(face))
	end)
end
