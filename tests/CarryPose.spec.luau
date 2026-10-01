--!nocheck
-- CarryPose (StarterPlayerScripts) against fake players and rigs: anyone
-- carrying logs within range (you included) has their arm joints' Transform
-- set to the carry pose every frame, over whatever the Animator wrote; the
-- arms go back (Transform = identity) the moment the logs are loaded, sold
-- or dropped, and on sitting, dying, leaving range or the character going;
-- a player who leaves takes every connection with them.
return function(t)
	local roblox = t.roblox
	local CFrame, Vector3, Enum = roblox.CFrame, roblox.Vector3, roblox.Enum
	local CarryLayout = t.shared("CarryLayout")

	local function near(a, b)
		return (a.Position - b.Position).Magnitude < 1e-6
			and (a.RightVector - b.RightVector).Magnitude < 1e-6
			and (a.UpVector - b.UpVector).Magnitude < 1e-6
	end

	local function signal()
		local entries = {}
		local s = {}
		function s:Connect(fn)
			local entry = { fn = fn, on = true }
			table.insert(entries, entry)
			return {
				Disconnect = function()
					entry.on = false
				end,
			}
		end
		function s:Fire(...)
			for _, e in ipairs(entries) do
				if e.on then
					e.fn(...)
				end
			end
		end
		function s:Live()
			local n = 0
			for _, e in ipairs(entries) do
				if e.on then
					n += 1
				end
			end
			return n
		end
		return s
	end

	local function node(fields, children, class)
		fields.FindFirstChild = function(_, name)
			return children[name]
		end
		fields.IsA = function(_, c)
			return c == class
		end
		return fields
	end

	local function motor(name, c0)
		return node({ Name = name, C0 = c0, Transform = CFrame.identity }, {}, "Motor6D")
	end

	local R6_RIGHT = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
	local R6_LEFT = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)

	-- A character standing at `pos`: its joints by name, its Humanoid and
	-- root part.
	local function character(rig, pos)
		local joints, children = {}, {}
		if rig == "R15" then
			for _, j in ipairs({
				{ "RightUpperArm", "RightShoulder", CFrame.new(1, 0.563, 0) },
				{ "LeftUpperArm", "LeftShoulder", CFrame.new(-1, 0.563, 0) },
				{ "RightLowerArm", "RightElbow", CFrame.new(0, -0.334, 0) },
				{ "LeftLowerArm", "LeftElbow", CFrame.new(0, -0.334, 0) },
			}) do
				local m = motor(j[2], j[3])
				joints[j[2]] = m
				children[j[1]] = node({ Name = j[1] }, { [j[2]] = m }, "BasePart")
			end
		else
			joints["Right Shoulder"] = motor("Right Shoulder", R6_RIGHT)
			joints["Left Shoulder"] = motor("Left Shoulder", R6_LEFT)
			children.Torso = node({ Name = "Torso" }, joints, "BasePart")
		end
		local root = node({ Name = "HumanoidRootPart", Position = pos }, {}, "BasePart")
		children.HumanoidRootPart = root
		local humanoid = {
			RigType = if rig == "R15" then Enum.HumanoidRigType.R15 else Enum.HumanoidRigType.R6,
			Health = 100,
			Sit = false,
			SeatPart = nil,
		}
		local char = node({ Name = "Character" }, children, "Model")
		char.FindFirstChildOfClass = function(_, class)
			return if class == "Humanoid" then humanoid else nil
		end
		return { model = char, joints = joints, humanoid = humanoid, root = root }
	end

	local function newPlayer(name, char, carried)
		local attrs = { CarriedLogs = carried }
		local changed = {}
		local p = {
			Name = name,
			Character = if char then char.model else nil,
			CharacterRemoving = signal(),
		}
		function p:GetAttribute(key)
			return attrs[key]
		end
		function p:GetAttributeChangedSignal(key)
			changed[key] = changed[key] or signal()
			return changed[key]
		end
		p.set = function(key, value)
			attrs[key] = value
			if changed[key] then
				changed[key]:Fire()
			end
		end
		p.live = function()
			local n = p.CharacterRemoving:Live()
			for _, s in pairs(changed) do
				n += s:Live()
			end
			return n
		end
		return p
	end

	-- CarryPose started with `you` and `others` in the game; `step(dt)` runs
	-- one PreSimulation.
	local function start(you, others)
		local players = { you }
		for _, o in ipairs(others or {}) do
			table.insert(players, o)
		end
		local stepFn
		local Players = {
			LocalPlayer = you,
			PlayerAdded = signal(),
			PlayerRemoving = signal(),
			GetPlayers = function()
				return players
			end,
		}
		local loader = t.loader({
			services = {
				Players = Players,
				RunService = {
					PreSimulation = {
						Connect = function(_, fn)
							stepFn = fn
						end,
					},
				},
			},
			globals = {
				workspace = { CurrentCamera = { CFrame = CFrame.new(0, 20, 30) } },
			},
		})
		local CarryPose = loader:load("StarterPlayer/StarterPlayerScripts/CarryPose")
		CarryPose.Start()
		assert(stepFn, "CarryPose didn't connect PreSimulation")
		return {
			Players = Players,
			step = function(dt)
				stepFn(dt or 1 / 60)
			end,
		}
	end

	local RAISE = CFrame.Angles(CarryLayout.ShoulderRaise, 0, 0)
	local BEND = CFrame.Angles(CarryLayout.ElbowBend, 0, 0)
	local ANIMATED = CFrame.Angles(0.4, 0, 0.1) -- something the Animator wrote this frame

	local function posedR15(c)
		return near(c.joints.RightShoulder.Transform, RAISE)
			and near(c.joints.LeftShoulder.Transform, RAISE)
			and near(c.joints.RightElbow.Transform, BEND)
			and near(c.joints.LeftElbow.Transform, BEND)
	end
	local function posedR6(c)
		return near(c.joints["Right Shoulder"].Transform, CFrame.Angles(0, 0, CarryLayout.R6ShoulderRaise))
			and near(c.joints["Left Shoulder"].Transform, CFrame.Angles(0, 0, -CarryLayout.R6ShoulderRaise))
	end
	local function all(c, cf)
		for _, j in pairs(c.joints) do
			if not near(j.Transform, cf) then
				return false
			end
		end
		return true
	end
	local function animate(c)
		for _, j in pairs(c.joints) do
			j.Transform = ANIMATED
		end
	end

	t.test("you, R15, carrying: arms up and elbows bent, rewritten every frame over the Animator", function()
		local me = character("R15", Vector3.zero)
		local world = start(newPlayer("You", me, 1))
		world.step()
		t.ok(posedR15(me), "posed on the first frame")
		for _ = 1, 3 do
			animate(me) -- the Animator writes before PreSimulation each frame
			world.step()
			t.ok(posedR15(me), "the pose wins every frame")
		end
	end)

	t.test("loading, selling or dropping lowers the arms at once and leaves them to the Animator", function()
		local me = character("R15", Vector3.zero)
		local you = newPlayer("You", me, 2)
		local world = start(you)
		world.step()
		t.ok(posedR15(me))
		you.set("CarriedLogs", 0)
		t.ok(all(me, CFrame.identity), "back to identity without waiting for a frame")
		animate(me)
		world.step(1)
		t.ok(all(me, ANIMATED), "no more writes")
		you.set("CarriedLogs", 1) -- picked up again
		world.step()
		t.ok(posedR15(me), "posed from the next frame")
	end)

	t.test("another player on R6, in range: posed about the joint's Z; out of range: let go", function()
		local me = character("R15", Vector3.zero)
		local them = character("R6", Vector3.new(100, 0, 0))
		local other = newPlayer("Them", them, 1)
		local world = start(newPlayer("You", me, 0), { other })
		world.step()
		t.ok(posedR6(them), "both R6 arms raised")
		t.ok(all(me, CFrame.identity), "you carry nothing: untouched")
		them.root.Position = Vector3.new(160, 0, 0)
		world.step(0.3)
		t.ok(all(them, CFrame.identity), "out of range: arms back")
		animate(them)
		world.step(0.3)
		t.ok(all(them, ANIMATED), "and left alone")
		them.root.Position = Vector3.new(140, 0, 0)
		world.step(0.3)
		t.ok(posedR6(them), "back in range")
	end)

	t.test("no pose while seated; sitting down mid-carry lets go on the next frame", function()
		local me = character("R15", Vector3.zero)
		me.humanoid.Sit = true
		local world = start(newPlayer("You", me, 1))
		world.step()
		t.ok(all(me, CFrame.identity), "seated: not posed")
		me.humanoid.Sit = false
		world.step(0.3)
		t.ok(posedR15(me), "standing: posed")
		me.humanoid.SeatPart = {} -- into the driver's seat
		world.step()
		t.ok(all(me, CFrame.identity), "let go at once")
	end)

	t.test("dying lets go", function()
		local me = character("R6", Vector3.zero)
		local world = start(newPlayer("You", me, 1))
		world.step()
		t.ok(posedR6(me))
		me.humanoid.Health = 0
		world.step()
		t.ok(all(me, CFrame.identity))
	end)

	t.test("the character going restores it; a player leaving disconnects everything", function()
		local me = character("R15", Vector3.zero)
		local them = character("R15", Vector3.new(10, 0, 0))
		local other = newPlayer("Them", them, 1)
		local world = start(newPlayer("You", me, 0), { other })
		world.step()
		t.ok(posedR15(them))
		t.ok(other.live() > 0, "listening to them")
		other.CharacterRemoving:Fire(them.model)
		t.ok(all(them, CFrame.identity), "CharacterRemoving: arms back")
		world.step(0.3)
		t.ok(posedR15(them), "still their character, still carrying: posed again on the next check")
		world.Players.PlayerRemoving:Fire(other)
		t.eq(other.live(), 0, "no connections left behind")
		t.ok(all(them, CFrame.identity), "let go")
		animate(them)
		other.set("CarriedLogs", 2)
		world.step(1)
		t.ok(all(them, ANIMATED), "never touched again")
	end)

	t.test("an AnimationConstraint in a joint's place is posed through its Transform", function()
		local me = character("R15", Vector3.zero)
		local constraint = node({
			Name = "RightShoulder",
			Transform = CFrame.identity,
			Attachment0 = { CFrame = CFrame.new(1, 0.563, 0) },
		}, {}, "AnimationConstraint")
		me.model:FindFirstChild("RightUpperArm").FindFirstChild = function(_, name)
			return if name == "RightShoulder" then constraint else nil
		end
		local world = start(newPlayer("You", me, 1))
		world.step()
		t.ok(near(constraint.Transform, RAISE), "the constraint's arm rises")
		t.ok(near(me.joints.LeftShoulder.Transform, RAISE), "the Motor6Ds still do")
		me.humanoid.Health = 0
		world.step()
		t.ok(near(constraint.Transform, CFrame.identity), "and lets go")
	end)

	t.test("a player who joins later, and arms that stream in late, are posed", function()
		local me = character("R15", Vector3.zero)
		local world = start(newPlayer("You", me, 0))
		local newcomer = newPlayer("New", nil, 2)
		world.Players.PlayerAdded:Fire(newcomer)
		world.step(1)
		local them = character("R15", Vector3.new(0, 0, 50))
		newcomer.Character = them.model
		world.step(0.1)
		world.step(0.2)
		t.ok(posedR15(them), "picked up on the next check")
	end)
end
