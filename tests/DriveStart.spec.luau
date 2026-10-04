--!nocheck
-- Sitting in the driver seat used to yaw the truck toward the camera.
-- VehicleService unanchored the chassis and handed over physics while
-- Heading was still disabled (torque 0 until a deferred step). In that
-- gap the humanoid turns its root to the camera (AutoRotate, shift lock,
-- first person) and the seat weld drags the truck with it.
-- DriveStart arms the parked rotation first, and the client holds that
-- facing until the driver actually throttles or steers.
return function(t)
	local roblox = t.roblox
	local CFrame, Vector3, Instance = roblox.CFrame, roblox.Vector3, roblox.Instance

	local function yawOf(cf)
		local look = cf.LookVector
		return math.deg(math.atan2(-look.X, -look.Z))
	end

	local function yawDelta(a, b)
		local d = (a - b) % 360
		if d > 180 then
			d -= 360
		end
		return math.abs(d)
	end

	local function between(a, b)
		return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
	end

	local function lookYaw(deg)
		return CFrame.Angles(0, math.rad(deg), 0).LookVector
	end

	-- Lune registers a class method once per process. VehicleBays and
	-- VehicleHooks stub the same ones; whichever spec loads first wins,
	-- so these stay compatible with both (Connect, empty overlap, no ray).
	local occupantListeners = {}
	local function stub(class, method, fn)
		pcall(roblox.implementMethod, class, method, fn)
	end
	stub("VehicleSeat", "GetPropertyChangedSignal", function(self, property)
		return {
			Connect = function(_, fn)
				if property == "Occupant" then
					local list = occupantListeners[self]
					if not list then
						list = {}
						occupantListeners[self] = list
					end
					table.insert(list, fn)
				end
				return { Disconnect = function() end }
			end,
		}
	end)
	stub("WorldModel", "GetPartBoundsInBox", function()
		return {}
	end)
	stub("WorldModel", "Raycast", function()
		return nil
	end)

	local seatedOf = {}
	local function event()
		local fns = {}
		local ev = {}
		function ev:Connect(fn)
			table.insert(fns, fn)
			return { Disconnect = function() end }
		end
		function ev:Fire(...)
			for _, fn in ipairs(fns) do
				fn(...)
			end
		end
		return ev
	end
	pcall(roblox.implementProperty, "Humanoid", "Seated", function(self)
		local ev = seatedOf[self]
		if not ev then
			ev = event()
			seatedOf[self] = ev
		end
		return ev
	end)

	local function signal()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end

	local SLOT_AT = Vector3.new(40, 0.1, 30)

	local function world()
		local ws = Instance.new("WorldModel")
		local slot = Instance.new("Part")
		slot.Name = "ParkingSlot"
		slot.Size = Vector3.new(10, 0.2, 60)
		slot.CFrame = CFrame.new(SLOT_AT)
		slot.Position = SLOT_AT
		slot:AddTag("ParkingSlot")
		slot:SetAttribute("Index", 1)
		slot.Parent = ws
		local w = { profile = { truckBed = {}, truckAt = {}, leftLoad = {} } }
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function()
						return w.profile
					end,
				},
				TreeService = { LogDiameter = 0.9 },
				TerrainBuilder = {
					LiftOnto = function(_, y)
						return y
					end,
				},
			},
			services = {
				Players = {
					GetPlayers = function()
						return {}
					end,
					GetPlayerFromCharacter = function(_, character)
						return w.byChar[character]
					end,
				},
				CollectionService = {
					AddTag = function(_, inst, tag)
						inst:AddTag(tag)
					end,
					GetTagged = function(_, tag)
						local out = {}
						for _, d in ipairs(ws:GetDescendants()) do
							if d:HasTag(tag) then
								table.insert(out, d)
							end
						end
						return out
					end,
				},
				RunService = {
					IsStudio = function()
						return false
					end,
					Heartbeat = signal(),
				},
			},
			globals = {
				workspace = ws,
				task = {
					spawn = function() end,
					defer = function() end, -- the old code armed Heading here, too late
					delay = function() end,
				},
				OverlapParams = {
					new = function()
						return {}
					end,
				},
				RaycastParams = {
					new = function()
						return {}
					end,
				},
				Instance = {
					new = function(class)
						if class == "ProximityPrompt" then
							return { Triggered = signal(), SetAttribute = function() end }
						end
						return Instance.new(class)
					end,
				},
			},
		})
		w.byChar = {}
		w.VehicleService = loader:server("VehicleService")
		w.VehicleService.Init(function() end)
		w.player = {
			UserId = 7,
			Name = "Dale",
			DisplayName = "Dale",
			SetAttribute = function() end,
		}
		return w
	end

	-- The bug, logged: parked yaw, then the moment the chassis unanchors,
	-- then the first drive step. Heading must already be holding the
	-- parked rotation when the chassis goes loose. The deferred step is
	-- not allowed to be what arms it (task.defer does nothing here).
	t.test("server: heading is on, with torque, at the parked rotation, before the chassis unanchors", function()
		local w = world()
		local model = w.VehicleService.SpawnTruck(w.player, "Pickup")
		local chassis = model.PrimaryPart
		local heading = chassis:FindFirstChild("Heading")
		local parked = CFrame.new(12, 4, -8) * CFrame.Angles(math.rad(10), math.rad(90), 0)
		model:PivotTo(parked)
		local seatedYaw = yawOf(chassis.CFrame)
		local char = Instance.new("Model")
		char.Name = "Dale"
		local humanoid = Instance.new("Humanoid")
		humanoid.Parent = char
		w.byChar[char] = w.player
		w.player.Character = char
		local seat = model:FindFirstChild("DriverSeat")
		seat.Occupant = humanoid
		local list = occupantListeners[seat]
		t.ok(list and #list > 0, "the seat reports its occupant")
		-- SetNetworkOwner is not on Lune parts. It runs after the unanchor,
		-- so a throw there still leaves the heading in whatever state the
		-- enter path had armed by then.
		pcall(function()
			list[1]()
		end)
		local cameraYaw = 180
		local stepFacing =
			t.shared("DriveStart")
				.Facing(true, t.shared("VehicleLogic").FlatFacing(chassis.CFrame.LookVector), 0, 0, lookYaw(cameraYaw))
		local step = t.shared("VehicleLogic").HeadingCFrame(stepFacing, chassis.CFrame.UpVector)
		print(
			string.format(
				"yaw seated=%.2f afterUnanchor=%.2f afterFirstStep=%.2f camera=%.0f headingEnabled=%s torque=%.1f anchored=%s",
				seatedYaw,
				yawOf(chassis.CFrame),
				yawOf(step),
				cameraYaw,
				tostring(heading.Enabled),
				heading.MaxTorque,
				tostring(chassis.Anchored)
			)
		)
		t.eq(chassis.Anchored, false, "the driver has the truck")
		t.ok(heading.Enabled, "heading holds it through the seat weld")
		t.ok(heading.MaxTorque > 0, "the lock has torque before the deferred resize")
		t.ok(between(heading.CFrame.LookVector, parked.LookVector) < 1, "yaw stays parked, not the camera")
		t.ok(between(heading.CFrame.UpVector, parked.UpVector) < 1, "a 10 degree slope is not snapped level")
		t.ok(yawDelta(yawOf(chassis.CFrame), seatedYaw) < 1, "the chassis itself is not pivoted on enter")
		t.ok(yawDelta(yawOf(step), seatedYaw) < 1, "the first drive step holds the parked yaw")
	end)

	t.test("Seed keeps the parked yaw, pitch and roll, and ignores the camera", function()
		local DriveStart = t.shared("DriveStart")
		local yaws = { 0, 90, 180 }
		local cameras = { 90, 180 }
		for _, yaw in ipairs(yaws) do
			for _, cam in ipairs(cameras) do
				local cf = CFrame.new(3, 2, 1) * CFrame.Angles(0, math.rad(yaw), 0)
				local seed = DriveStart.Seed(cf, lookYaw(cam))
				t.ok(yawDelta(yawOf(seed), yaw) < 1, string.format("yaw %d camera %d", yaw, cam))
				t.ok(between(seed.LookVector, cf.LookVector) < 1)
				t.ok((seed.Position - Vector3.zero).Magnitude < 1e-4, "orientation only")
			end
		end
		-- Nose-down 10 degrees, and a 10 degree roll, at every parked yaw.
		for _, yaw in ipairs(yaws) do
			for _, tilt in ipairs({
				CFrame.Angles(math.rad(10), math.rad(yaw), 0),
				CFrame.Angles(0, math.rad(yaw), math.rad(10)),
			}) do
				local cf = CFrame.new(0, 5, 0) * tilt
				local seed = DriveStart.Seed(cf, lookYaw(if yaw == 0 then 180 else 90))
				t.ok(between(seed.LookVector, cf.LookVector) < 1, "pitch stays")
				t.ok(between(seed.UpVector, cf.UpVector) < 1, "roll stays")
				t.ok(seed.UpVector.Y < 0.995, "not snapped upright")
				t.ok(yawDelta(yawOf(seed), yawOf(cf)) < 1)
			end
		end
	end)

	t.test("Arm sets the parked rotation and torque while the chassis is still anchored", function()
		local DriveStart = t.shared("DriveStart")
		local Handling = t.shared("Handling")
		local parked = CFrame.new(4, 2, -6) * CFrame.Angles(math.rad(10), math.rad(90), math.rad(8))
		local heading = { CFrame = CFrame.identity, MaxTorque = 0, Enabled = false }
		local saw = nil
		-- An empty proxy so every write, including Anchored = false over
		-- a key that already exists, is visible. __newindex does not run
		-- for keys the table already holds.
		local state = { CFrame = parked, AssemblyMass = 25, Anchored = true }
		local chassis = setmetatable({}, {
			__index = state,
			__newindex = function(_, key, value)
				if key == "Anchored" and value == false then
					saw = {
						enabled = heading.Enabled,
						torque = heading.MaxTorque,
						cf = heading.CFrame,
					}
				end
				state[key] = value
			end,
		})
		DriveStart.Arm(chassis, heading, "Pickup")
		t.eq(state.Anchored, true, "Arm does not unanchor")
		t.ok(heading.Enabled)
		t.eq(heading.MaxTorque, 25 * Handling.HoldTorque(Handling.For("Pickup")))
		t.ok(between(heading.CFrame.LookVector, parked.LookVector) < 1)
		t.ok(between(heading.CFrame.UpVector, parked.UpVector) < 1)
		chassis.Anchored = false
		t.ok(saw and saw.enabled and saw.torque > 0, "the lock is on before Anchored goes false")
		t.ok(between(saw.cf.LookVector, parked.LookVector) < 1)
		t.ok(between(saw.cf.UpVector, parked.UpVector) < 1)
	end)

	t.test(
		"no throttle or steer keeps the parked facing; forward is the truck's nose, even with the camera at 180",
		function()
			local DriveStart = t.shared("DriveStart")
			local VehicleLogic = t.shared("VehicleLogic")
			local parked = CFrame.Angles(0, math.rad(35), 0)
			local camera = lookYaw(35 + 180)
			local seed = DriveStart.Seed(parked, camera)
			local facing = VehicleLogic.FlatFacing(seed.LookVector)
			local held, locked = DriveStart.Facing(true, facing, 0, 0, camera.Unit)
			t.eq(locked, true)
			t.ok(between(held, facing) < 1)
			local released, still = DriveStart.Facing(true, facing, 1, 0, camera.Unit)
			t.eq(still, false)
			t.ok(between(released, camera.Unit) < 1, "a real input is allowed to steer")
			local velocity = DriveStart.Velocity(facing, 14)
			t.ok(velocity:Dot(facing) > 13, "throttle drives the nose")
			t.ok(velocity:Dot(camera) < 0, "not the camera, which looks back along the truck")
		end
	)

	t.test("three enter and exit cycles drift less than a degree", function()
		local DriveStart = t.shared("DriveStart")
		local VehicleLogic = t.shared("VehicleLogic")
		-- A slope the way HeadingCFrame builds one: flat yaw, up leaned
		-- forward (nose-down) or to the right (cross-slope). Enter holds
		-- that yaw; exit is holdHeading (HeadingCFrame again).
		local function posed(yawDeg, pitchDeg, rollDeg)
			local flat = CFrame.Angles(0, math.rad(yawDeg), 0)
			local facing = flat.LookVector
			local right = flat.RightVector
			local pitch, roll = math.rad(pitchDeg), math.rad(rollDeg)
			local up = (Vector3.yAxis * math.cos(pitch) + facing * math.sin(pitch)).Unit
			up = (up * math.cos(roll) + right * math.sin(roll)).Unit
			return VehicleLogic.HeadingCFrame(facing, up) + Vector3.new(10, 3, -4)
		end
		local poses = {
			posed(90, 10, 0), -- nose-down
			posed(180, 0, 10), -- cross-slope
			posed(37, 27, 0), -- nose-down near the park limit, off the axes
			posed(0, 0, 15),
		}
		for _, start in ipairs(poses) do
			local origin = yawOf(start)
			local up0 = start.UpVector
			local cf = start
			for _ = 1, 3 do
				local camera = lookYaw(yawOf(cf) + 180)
				local seed = DriveStart.Seed(cf, camera)
				local facing = VehicleLogic.FlatFacing(seed.LookVector)
				local held = DriveStart.Facing(true, facing, 0, 0, camera.Unit)
				local driven = VehicleLogic.HeadingCFrame(held, seed.UpVector) + cf.Position
				-- Exit parks on the current heading (holdHeading), no extra yaw.
				cf = VehicleLogic.HeadingCFrame(
					driven.LookVector,
					VehicleLogic.ClampTilt(driven.UpVector, math.rad(30))
				) + driven.Position
			end
			t.ok(
				yawDelta(yawOf(cf), origin) < 1,
				string.format("yaw drifted %.3f deg from %.1f", yawDelta(yawOf(cf), origin), origin)
			)
			t.ok((cf.Position - start.Position).Magnitude < 1e-3, "exit does not translate the truck")
			t.ok(between(cf.UpVector, up0) < 1, "the slope is still there")
		end
	end)

	t.test("AutoRotate is off while seated and restored on Seated(false), including a new character", function()
		local DriveStart = t.shared("DriveStart")
		local lock = { saved = nil }
		local humanoid = { AutoRotate = true }
		DriveStart.OnSeated(lock, humanoid, true, true)
		t.eq(humanoid.AutoRotate, false)
		t.eq(lock.saved, true)
		DriveStart.OnSeated(lock, humanoid, false, false)
		t.eq(humanoid.AutoRotate, true, "exit restores it")
		t.eq(lock.saved, nil)
		-- It had been turned off before they sat (a tool did). Exit puts it back.
		humanoid.AutoRotate = false
		DriveStart.OnSeated(lock, humanoid, true, true)
		t.eq(humanoid.AutoRotate, false)
		DriveStart.OnSeated(lock, humanoid, false, false)
		t.eq(humanoid.AutoRotate, false, "restored, not forced on")
		-- A respawn starts clean: the next humanoid is not stuck with the old flag.
		humanoid.AutoRotate = false
		DriveStart.OnSeated(lock, humanoid, true, true)
		lock.saved = nil -- watchCharacter clears this when the new body arrives
		local nextHumanoid = { AutoRotate = true }
		DriveStart.OnSeated(lock, nextHumanoid, false, false)
		t.eq(nextHumanoid.AutoRotate, true)

		-- The real client handler: sit, hop out, and Seated(false) again.
		local heartbeat = event()
		local stepped = event()
		local characterAdded = event()
		local char = Instance.new("Model")
		local body = Instance.new("Humanoid")
		body.Name = "Humanoid"
		body.Parent = char
		body.AutoRotate = true
		local player = {
			UserId = 3,
			Character = char,
			CharacterAdded = characterAdded,
			GetAttribute = function()
				return nil
			end,
			GetAttributeChangedSignal = function()
				return signal()
			end,
		}
		local loader = t.loader({
			mocks = {
				HUD = {
					SideButton = function()
						return {
							root = { Visible = false },
							SetText = function() end,
						}
					end,
				},
				UITheme = {},
			},
			services = {
				CollectionService = {
					GetTagged = function()
						return {}
					end,
					HasTag = function(_, inst, tag)
						return inst:HasTag(tag)
					end,
				},
				Players = { LocalPlayer = player },
				RunService = {
					PreSimulation = nil,
					Stepped = stepped,
					Heartbeat = heartbeat,
				},
			},
			globals = {
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
				},
			},
		})
		local VehicleController = loader:load("StarterPlayer/StarterPlayerScripts/VehicleController")
		VehicleController.Start()
		local seat = Instance.new("VehicleSeat")
		body.Seated:Fire(true, seat)
		t.eq(body.AutoRotate, false, "seated in the truck")
		body.Seated:Fire(false, nil)
		t.eq(body.AutoRotate, true, "Seated(false) restores it")
		body.AutoRotate = false
		body.Seated:Fire(true, seat)
		t.eq(body.AutoRotate, false)
		body.Seated:Fire(false, nil)
		t.eq(body.AutoRotate, false, "a humanoid that was not auto-rotating stays that way")
	end)

	-- The planted truck (highest tipResist) leans hardest toward upright.
	-- Sitting still must not start that lean: 3s of the real step loop, no
	-- throttle or steer, on a cross-slope and nose-down.
	t.test("holding for 3s keeps the parked slope; the lean waits for input", function()
		local DriveStart = t.shared("DriveStart")
		local Handling = t.shared("Handling")
		local ItemCatalog = t.shared("ItemCatalog")
		local VehicleLogic = t.shared("VehicleLogic")
		local bestId, bestResist = nil, -1
		for id in pairs(ItemCatalog.Trucks) do
			local resist = Handling.For(id).tipResist
			if resist > bestResist then
				bestId, bestResist = id, resist
			end
		end
		t.ok(bestId, "a truck to sit in")

		local function posed(yawDeg, pitchDeg, rollDeg)
			local flat = CFrame.Angles(0, math.rad(yawDeg), 0)
			local facing = flat.LookVector
			local right = flat.RightVector
			local pitch, roll = math.rad(pitchDeg), math.rad(rollDeg)
			local up = (Vector3.yAxis * math.cos(pitch) + facing * math.sin(pitch)).Unit
			up = (up * math.cos(roll) + right * math.sin(roll)).Unit
			return VehicleLogic.HeadingCFrame(facing, up) + Vector3.new(6, 4, -2)
		end

		local truck = Instance.new("Model")
		truck.Name = "Parked"
		truck:SetAttribute("TruckId", bestId)
		truck:AddTag("Truck")
		local chassis = Instance.new("Part")
		chassis.Name = "Chassis"
		chassis.Size = Vector3.new(8, 2, 20)
		chassis.Parent = truck
		truck.PrimaryPart = chassis
		local drive = Instance.new("LinearVelocity")
		drive.Name = "Drive"
		drive.Parent = chassis
		local heading = Instance.new("AlignOrientation")
		heading.Name = "Heading"
		heading.Parent = chassis
		local seat = Instance.new("VehicleSeat")
		seat.Name = "DriverSeat"
		seat.Parent = truck
		truck.Parent = Instance.new("Folder")

		local function slopeHit(_, origin)
			local cf = chassis.CFrame
			local up = cf.UpVector
			local tHit = (origin - cf.Position):Dot(up) / up.Y
			return {
				Position = origin - Vector3.new(0, tHit, 0),
				Normal = up,
			}
		end

		local preSim = event()
		local char = Instance.new("Model")
		local body = Instance.new("Humanoid")
		body.Name = "Humanoid"
		body.Parent = char
		body.AutoRotate = true
		local player = {
			UserId = 9,
			Character = char,
			CharacterAdded = event(),
			GetAttribute = function()
				return nil
			end,
			GetAttributeChangedSignal = function()
				return signal()
			end,
		}
		local loader = t.loader({
			mocks = {
				HUD = {
					SideButton = function()
						return {
							root = { Visible = false },
							SetText = function() end,
						}
					end,
				},
				UITheme = {},
			},
			services = {
				CollectionService = {
					GetTagged = function()
						return { truck }
					end,
					HasTag = function(_, inst, tag)
						return inst:HasTag(tag)
					end,
				},
				Players = { LocalPlayer = player },
				RunService = {
					PreSimulation = preSim,
					Stepped = event(),
					Heartbeat = event(),
				},
			},
			globals = {
				workspace = { Raycast = slopeHit },
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
				},
				RaycastParams = {
					new = function()
						return {}
					end,
				},
			},
		})
		local VehicleController = loader:load("StarterPlayer/StarterPlayerScripts/VehicleController")
		VehicleController.Start()

		local cases = {
			{ name = "15 degree cross-slope", yaw = 90, pitch = 0, roll = 15 },
			{ name = "28 degree nose-down", yaw = 180, pitch = 28, roll = 0 },
		}
		for _, case in ipairs(cases) do
			local parked = posed(case.yaw, case.pitch, case.roll)
			chassis.CFrame = parked
			chassis.AssemblyLinearVelocity = Vector3.zero
			seat.ThrottleFloat = 0
			seat.SteerFloat = 0
			body.Seated:Fire(true, seat)
			local dt = 1 / 60
			for _ = 1, 180 do
				preSim:Fire(dt)
			end
			local held = heading.CFrame
			t.ok(
				between(held.UpVector, parked.UpVector) < 1,
				string.format(
					"%s (%s tipResist %.2f) eased %.2f deg toward level",
					case.name,
					bestId,
					bestResist,
					between(held.UpVector, parked.UpVector)
				)
			)
			t.ok(yawDelta(yawOf(held), yawOf(parked)) < 1, string.format("%s yaw moved", case.name))
			-- Still the parked facing: no throttle or steer crossed the deadzone.
			local _, locked =
				DriveStart.Facing(true, parked.LookVector, seat.ThrottleFloat, seat.SteerFloat, Vector3.xAxis)
			t.eq(locked, true, case.name .. " had no input")
			body.Seated:Fire(false, nil)
		end
	end)
end
