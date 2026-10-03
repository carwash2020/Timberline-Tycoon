--!nocheck
-- ChopController's swing against fakes of the character, the axe and a
-- tree: a swing turns you to face the tree before the slash plays (when
-- it's more than 15 degrees off), holding to chop turns you again on every
-- swing, and sitting (or climbing) never turns you. The server is still
-- asked to chop either way.
return function(t)
	local roblox = t.roblox
	local CFrame, Vector3, Enum = roblox.CFrame, roblox.Vector3, roblox.Enum

	local function signal()
		local fns = {}
		return {
			Connect = function(_, fn)
				table.insert(fns, fn)
				return {
					Disconnect = function() end,
				}
			end,
			Fire = function(_, ...)
				for _, fn in ipairs(fns) do
					fn(...)
				end
			end,
		}
	end

	-- A world with one oak at `treeAt` (its base) and the character's root
	-- part at `rootCf`. Returns handles to drive and inspect it.
	local function setup(rootCf, treeAt, loop)
		local clock = 100
		local heartbeat = nil
		local fired = {} -- { remote, uid, look } per FireServer, look = the root's then
		local slashes = {} -- the root's LookVector when each slash started

		-- The root part: CFrame is settable, Position follows it.
		local hrpState = { CFrame = rootCf, Anchored = false }
		local hrp = setmetatable({}, {
			__index = function(_, key)
				if key == "Position" then
					return hrpState.CFrame.Position
				end
				return hrpState[key]
			end,
			__newindex = function(_, key, value)
				hrpState[key] = value
			end,
		})
		local humanoid = {
			Sit = false,
			SeatPart = nil,
			PlatformStand = false,
			Health = 100,
			state = Enum.HumanoidStateType.Running,
			GetState = function(self)
				return self.state
			end,
		}
		local tool = {
			Name = "RustyAxe",
			Activated = signal(),
			Deactivated = signal(),
			Unequipped = signal(),
			IsA = function(_, class)
				return class == "Tool"
			end,
			GetAttribute = function(_, key)
				return if key == "AxeId" then "RustyAxe" else nil
			end,
		}
		local char = {
			ChildAdded = signal(),
			GetChildren = function()
				return { tool }
			end,
			FindFirstChild = function(_, name)
				return if name == "HumanoidRootPart" then hrp else nil
			end,
			FindFirstChildOfClass = function(_, class)
				if class == "Tool" then
					return tool
				elseif class == "Humanoid" then
					return humanoid
				end
				return nil
			end,
		}
		local treeAttrs = { HP = 10, WoodId = "oak", TrunkRadius = 1, Uid = "tree-1" }
		local tree = {
			Name = "Oak",
			IsA = function(_, class)
				return class == "Model"
			end,
			GetAttribute = function(_, key)
				return treeAttrs[key]
			end,
			GetPivot = function()
				return CFrame.new(treeAt)
			end,
		}
		local player = { UserId = 1, Character = char, CharacterAdded = signal() }

		-- Instances the controller makes (the outline, the "toolanim" value):
		-- a parented "toolanim" is the slash starting.
		local function fakeInstance(className)
			local fields = { ClassName = className }
			return setmetatable({}, {
				__index = fields,
				__newindex = function(_, key, value)
					fields[key] = value
					if key == "Parent" and value == tool and fields.Name == "toolanim" then
						table.insert(slashes, hrpState.CFrame.LookVector)
					end
				end,
			})
		end

		local loader = t.loader({
			services = {
				CollectionService = {
					GetTagged = function(_, tag)
						return if tag == "Tree" then { tree } else {}
					end,
					GetInstanceAddedSignal = function()
						return signal()
					end,
					GetInstanceRemovedSignal = function()
						return signal()
					end,
					HasTag = function()
						return false
					end,
				},
				Debris = { AddItem = function() end },
				Players = { LocalPlayer = player },
				RunService = {
					Heartbeat = {
						Connect = function(_, fn)
							heartbeat = fn
						end,
					},
				},
				UserInputService = {
					InputBegan = signal(),
					-- A gamepad: no pointer, so the swing takes the nearest tree.
					GetLastInputType = function()
						return Enum.UserInputType.Gamepad1
					end,
				},
			},
			mocks = {
				HUD = { Toast = function() end },
				SoundData = {
					Play = function() end,
					SwingFor = function()
						return "Swing"
					end,
				},
				Net = {
					Remote = function(name)
						return {
							FireServer = function(_, uid)
								table.insert(fired, { remote = name, uid = uid, look = hrpState.CFrame.LookVector })
							end,
						}
					end,
				},
			},
			globals = {
				Instance = { new = fakeInstance },
				RaycastParams = {
					new = function()
						return {}
					end,
				},
				os = {
					clock = function()
						return clock
					end,
				},
				task = {
					defer = function(fn, ...)
						fn(...)
					end,
				},
				workspace = {
					CurrentCamera = nil,
					GetPropertyChangedSignal = function()
						return signal()
					end,
					-- Which core loop runs (Shared/CoreLoop): v1 unless a test says.
					GetAttribute = function(_, name)
						return if name == "CoreLoopActive" then loop or 1 else nil
					end,
				},
			},
		})
		local ChopController = loader:load("StarterPlayer/StarterPlayerScripts/ChopController")
		ChopController.Start()
		if (loop or 1) ~= 2 then
			assert(heartbeat, "ChopController didn't connect Heartbeat")
		end

		return {
			hrp = hrp,
			humanoid = humanoid,
			fired = fired,
			slashes = slashes,
			press = function()
				tool.Activated:Fire()
			end,
			release = function()
				tool.Deactivated:Fire()
			end,
			wait = function(seconds)
				clock += seconds
				heartbeat(seconds)
			end,
		}
	end

	local function near(a, b)
		return (a - b).Magnitude < 1e-6
	end
	local function flatTo(from, to)
		return Vector3.new(to.X - from.X, 0, to.Z - from.Z).Unit
	end

	local ROOT = Vector3.new(0, 3, 0)
	local FACING_NORTH = CFrame.new(ROOT) -- looks along -Z
	local EAST_TREE = Vector3.new(4, 0, 0) -- 90 degrees to the right, 3 studs from the bark

	t.test("a tree to your side: you turn to it before the slash, and stay put", function()
		local w = setup(FACING_NORTH, EAST_TREE)
		w.press()
		t.eq(#w.fired, 1, "the server is asked to chop")
		t.eq(w.fired[1].remote, "ChopTree")
		t.eq(w.fired[1].uid, "tree-1")
		t.eq(#w.slashes, 1, "the slash plays")
		local toTree = flatTo(ROOT, EAST_TREE)
		t.ok(near(w.slashes[1], toTree), "already facing the tree when the slash starts")
		t.ok(near(w.fired[1].look, toTree), "and when the chop is sent")
		t.ok(near(w.hrp.CFrame.Position, ROOT), "turned on the spot")
		t.ok(near(w.hrp.CFrame.UpVector, Vector3.yAxis), "upright")
	end)

	t.test("a tree nearly straight ahead: no turn", function()
		local ahead = ROOT + Vector3.new(math.sin(math.rad(10)) * 4, -3, -math.cos(math.rad(10)) * 4)
		local w = setup(FACING_NORTH, ahead)
		w.press()
		t.eq(#w.fired, 1)
		t.eq(w.hrp.CFrame, FACING_NORTH, "left exactly as it was")
	end)

	t.test("hold to chop: every swing turns you back to the tree", function()
		local w = setup(FACING_NORTH, EAST_TREE)
		w.press()
		t.eq(#w.slashes, 1)
		-- Turned away between swings (the camera, a bump), still holding.
		w.hrp.CFrame = CFrame.new(ROOT) * CFrame.Angles(0, math.rad(120), 0)
		w.wait(0.3)
		t.eq(#w.slashes, 1, "not before the cooldown")
		w.wait(0.6)
		t.eq(#w.slashes, 2, "the held swing")
		t.ok(near(w.slashes[2], flatTo(ROOT, EAST_TREE)), "facing the tree again")
		w.release()
		w.hrp.CFrame = FACING_NORTH
		w.wait(1)
		t.eq(#w.slashes, 2, "let go: no more swings")
		t.eq(w.hrp.CFrame, FACING_NORTH, "and no more turning")
	end)

	t.test("sitting, climbing, knocked over or dead: the swing goes ahead without a turn", function()
		local cases = {
			function(h)
				h.Sit = true
			end,
			function(h)
				h.SeatPart = {}
			end,
			function(h)
				h.PlatformStand = true
			end,
			function(h)
				h.Health = 0
			end,
			function(h)
				h.state = Enum.HumanoidStateType.Climbing
			end,
		}
		for i, apply in ipairs(cases) do
			local w = setup(FACING_NORTH, EAST_TREE)
			apply(w.humanoid)
			w.press()
			t.eq(#w.fired, 1, "case " .. i .. " still chops")
			t.eq(w.hrp.CFrame, FACING_NORTH, "case " .. i .. " doesn't turn")
		end
	end)

	t.test("under the v2 loop it never swings (CutController does)", function()
		local w = setup(FACING_NORTH, EAST_TREE, 2)
		w.press()
		t.eq(#w.fired, 0, "no ChopTree")
		t.eq(#w.slashes, 0, "no slash")
	end)
end
