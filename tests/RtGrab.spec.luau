--!nocheck
-- The right trigger (ButtonR2) grabs wood with empty hands, exactly as a
-- mouse click and a resting finger do. This drives DragController's real
-- InputBegan / InputEnded handlers (and its touch action) with fake input:
--   (a) no tool: RT starts a pad grab, releasing RT drops it;
--   (b) a tool in hand: RT never grabs (the swing is Tool.Activated's);
--   (c) the placer up, or a menu holding the pad selection: no grab;
--   (d) the mouse and touch paths still grab and drop.
-- GrabLogic.spec pins the pure rules; NoButtonR2.spec pins the source.
return function(t)
	local roblox = t.roblox
	local Instance, Enum, Vector3, Vector2, CFrame =
		roblox.Instance, roblox.Enum, roblox.Vector3, roblox.Vector2, roblox.CFrame
	local Color3 = roblox.Color3

	local world
	roblox.implementMethod("Workspace", "GetAttributeChangedSignal", function()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end)
	roblox.implementMethod("Model", "GetAttributeChangedSignal", function()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end)
	roblox.implementMethod("Workspace", "Raycast", function()
		return world.hit
	end)
	roblox.implementMethod("Camera", "ViewportPointToRay", function()
		return { Origin = Vector3.new(0, 5, 0), Direction = Vector3.new(0, 0, -1) }
	end)
	roblox.implementMethod("Camera", "ScreenPointToRay", function()
		return { Origin = Vector3.new(0, 5, 0), Direction = Vector3.new(0, 0, -1) }
	end)
	roblox.implementMethod("BasePart", "GetMass", function()
		return 10
	end)
	roblox.implementProperty("Humanoid", "Health", function()
		return 100
	end, function() end)
	roblox.implementProperty("Humanoid", "SeatPart", function()
		return nil
	end, function() end)

	local function noop() end

	local function build(opts)
		opts = opts or {}
		local game = Instance.new("DataModel")
		local workspace = game:GetService("Workspace")
		workspace:SetAttribute("CoreLoopActive", 2)
		local camera = Instance.new("Camera")
		camera.ViewportSize = Vector2.new(1000, 600)
		workspace.CurrentCamera = camera

		local char = Instance.new("Model")
		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.Position = Vector3.new(0, 3, 0)
		hrp.Parent = char
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Position = Vector3.new(0, 5, 0)
		head.Parent = char
		local humanoid = Instance.new("Humanoid")
		humanoid.Health = 100
		humanoid.Parent = char
		if opts.tool then
			local tool = Instance.new("Tool")
			tool.Parent = char
		end

		local wood = Instance.new("Model")
		local log = Instance.new("Part")
		log.Position = Vector3.new(0, 4, -4)
		log.Parent = wood

		-- AssemblyMass has no default off-engine: the piece the ray finds is a
		-- stand-in that reads 10 and passes everything else to the real part.
		local piece = setmetatable({}, {
			__index = function(_, key)
				if key == "AssemblyMass" then
					return 10
				end
				local value = log[key]
				if type(value) == "function" then
					return function(_, ...)
						return value(log, ...)
					end
				end
				return value
			end,
		})
		world = {
			hit = { Instance = piece, Position = Vector3.new(0, 4, -4) },
			grabs = 0,
			releases = 0,
			began = nil,
			ended = nil,
			touchAction = nil,
			heartbeat = nil,
			now = 0,
			placing = opts.placing or false,
			selected = opts.selected,
		}
		local rec = world

		local function slot(field)
			return {
				Connect = function(_, fn)
					rec[field] = fn
					return { Disconnect = noop }
				end,
			}
		end
		local function sig()
			return {
				Connect = function()
					return { Disconnect = noop }
				end,
			}
		end
		local playerGui = Instance.new("Folder")
		local loader = t.loader({
			services = {
				GuiService = setmetatable({}, {
					__index = function(_, k)
						if k == "SelectedObject" then
							return rec.selected
						end
						return nil
					end,
				}),
				CollectionService = {
					GetTagged = function()
						return {}
					end,
					GetInstanceAddedSignal = sig,
					GetInstanceRemovedSignal = sig,
					HasTag = function(_, inst, tag)
						return inst == wood and tag == "Wood"
					end,
				},
				ContextActionService = {
					BindActionAtPriority = function(_, name, fn)
						if name == "DragTouch" then
							rec.touchAction = fn
						end
					end,
					UnbindAction = noop,
				},
				Players = {
					LocalPlayer = {
						UserId = 1,
						Character = char,
						CharacterAdded = sig(),
						GetNetworkPing = function()
							return 0
						end,
					},
					GetPlayers = function()
						return {}
					end,
				},
				ProximityPromptService = { Enabled = true },
				RunService = {
					IsStudio = function()
						return false
					end,
					RenderStepped = sig(),
					Heartbeat = slot("heartbeat"),
					BindToRenderStep = noop,
					UnbindFromRenderStep = noop,
				},
				UserInputService = {
					InputBegan = slot("began"),
					InputEnded = slot("ended"),
					WindowFocusReleased = sig(),
					GetMouseLocation = function()
						return Vector2.new(500, 300)
					end,
					GetFocusedTextBox = function()
						return nil
					end,
					IsGamepadButtonDown = function()
						return false
					end,
				},
			},
			mocks = {
				HUD = {
					Toast = noop,
					NoteGrab = noop,
					BuildOpen = function()
						return false
					end,
				},
				BlueprintPlacer = {
					Active = function()
						return rec.placing
					end,
				},
				Net = {
					Remote = function(name)
						return {
							FireServer = function()
								if name == "Grab" then
									rec.grabs += 1
								elseif name == "Release" then
									rec.releases += 1
								end
							end,
						}
					end,
				},
				UITheme = {
					Layers = { Drag = 4 },
					Size = { Tap = 44, TextButton = 15 },
					Fonts = { Heading = Enum.Font.FredokaOne },
					Colors = { Cream = Color3.new(1, 1, 1), Ink = Color3.new(0, 0, 0) },
					Screen = function(name)
						local gui = Instance.new("ScreenGui")
						gui.Name = name
						return gui
					end,
					Button = function(o)
						local root = Instance.new("Frame")
						root.Name = o.name
						return { root = root, face = { InputBegan = sig(), InputEnded = sig(), Activated = sig() } }
					end,
					list = noop,
					corner = noop,
					stroke = noop,
					Bottom = function()
						return 70
					end,
					PlayerGui = function()
						return playerGui
					end,
					Device = function()
						return "desktop"
					end,
				},
			},
			globals = {
				workspace = workspace,
				RaycastParams = {
					new = function()
						return {}
					end,
				},
				warn = function(...)
					error("DragController warned: " .. table.concat({ ... }, " "))
				end,
				task = { wait = noop, delay = noop, spawn = noop },
				-- the hold's constraints are plain stand-ins (a stand-in part cannot parent real ones)
				Instance = setmetatable({
					new = function(class)
						if class == "Attachment" or class == "AlignPosition" or class == "AlignOrientation" then
							return { Destroy = noop, Disconnect = noop }
						end
						return Instance.new(class)
					end,
				}, { __index = Instance }),
				os = setmetatable({
					clock = function()
						return rec.now
					end,
				}, { __index = os }),
			},
		})
		local DragController = loader:load("StarterPlayer/StarterPlayerScripts/DragController")
		DragController.Start()
		rec.controller = DragController
		return rec
	end

	local function input(userInputType, keyCode)
		return {
			UserInputType = userInputType,
			KeyCode = keyCode or Enum.KeyCode.Unknown,
			Position = Vector3.new(500, 300, 0),
		}
	end
	local function rt()
		return input(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR2)
	end
	local function click()
		return input(Enum.UserInputType.MouseButton1)
	end

	t.test("no tool: RT starts a pad grab and letting go of RT drops it", function()
		local w = build()
		local trigger = rt()
		w.began(trigger, false)
		t.eq(w.grabs, 1, "the grab went to the server")
		t.ok(w.controller.Holding(), "holding")
		w.ended(input(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA))
		t.ok(w.controller.Holding(), "another button's release keeps the hold")
		w.ended(trigger)
		t.eq(w.releases, 1, "the release went to the server")
		t.ok(not w.controller.Holding(), "dropped")
	end)

	t.test("no tool: RT grabs even when the engine marked it handled (a trigger is no click)", function()
		local w = build()
		w.began(rt(), true)
		t.eq(w.grabs, 1)
	end)

	t.test("a tool in hand: RT never grabs (the swing is Tool.Activated's)", function()
		local w = build({ tool = true })
		w.began(rt(), false)
		w.began(rt(), true)
		t.eq(w.grabs, 0)
		t.ok(not w.controller.Holding())
	end)

	t.test("the placer up: RT does not grab", function()
		local w = build({ placing = true })
		w.began(rt(), false)
		t.eq(w.grabs, 0)
		t.ok(not w.controller.Holding())
	end)

	t.test("a menu holding the pad selection: RT does not grab", function()
		local w = build({ selected = Instance.new("TextButton") })
		w.began(rt(), true) -- the menu's press: the engine marks it handled
		t.eq(w.grabs, 0)
		t.ok(not w.controller.Holding())
		w.selected = nil
		w.began(rt(), true)
		t.eq(w.grabs, 1, "with the menu closed the same press grabs")
	end)

	t.test("RT with nothing under the dot grabs nothing", function()
		local w = build()
		w.hit = nil
		w.began(rt(), false)
		t.eq(w.grabs, 0)
	end)

	t.test("the mouse still grabs on click and drops on release; a handled click does not", function()
		local w = build()
		w.began(click(), true)
		t.eq(w.grabs, 0, "a GUI button already took the click")
		w.began(click(), false)
		t.eq(w.grabs, 1)
		t.ok(w.controller.Holding())
		w.ended(rt())
		t.ok(w.controller.Holding(), "RT up does not drop a mouse hold")
		w.ended(click())
		t.eq(w.releases, 1)
		t.ok(not w.controller.Holding())
	end)

	t.test("a mouse hold ignores a trigger press and a pad hold ignores a click", function()
		local w = build()
		w.began(rt(), false)
		w.ended(click())
		t.ok(w.controller.Holding(), "a click's release does not drop a pad hold")
		w.ended(rt())
		t.ok(not w.controller.Holding())
	end)

	t.test("a tool in hand: the mouse click does not grab either", function()
		local w = build({ tool = true })
		w.began(click(), false)
		t.eq(w.grabs, 0)
	end)

	t.test("touch still grabs after a rest and drops when the finger lifts", function()
		local w = build()
		local finger = input(Enum.UserInputType.Touch)
		finger.Position = Vector3.new(500, 200, 0)
		t.eq(w.touchAction("DragTouch", Enum.UserInputState.Begin, finger), Enum.ContextActionResult.Sink)
		t.eq(w.grabs, 0, "not yet: the finger has not rested")
		w.now = 0.5
		w.heartbeat(0.5)
		t.eq(w.grabs, 1)
		t.ok(w.controller.Holding())
		w.touchAction("DragTouch", Enum.UserInputState.End, finger)
		t.eq(w.releases, 1)
		t.ok(not w.controller.Holding())
	end)

	t.test("a tool in hand: a touch does not start a grab", function()
		local w = build({ tool = true })
		local finger = input(Enum.UserInputType.Touch)
		finger.Position = Vector3.new(500, 200, 0)
		t.eq(w.touchAction("DragTouch", Enum.UserInputState.Begin, finger), Enum.ContextActionResult.Pass)
		w.now = 0.5
		w.heartbeat(0.5)
		t.eq(w.grabs, 0)
	end)
end
