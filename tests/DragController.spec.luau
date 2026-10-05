--!nocheck
-- DragController (V2_PLAN.md §4a) starting up: under the v1 loop it binds,
-- connects and builds nothing (the live game is untouched); under v2 it
-- takes touches only through a low-priority action (under the touch
-- thumbstick's), binds the hold's keys only while holding, and builds its
-- touch buttons hidden. Its input maths is GrabLogic's (GrabLogic.spec).
return function(t)
	local roblox = t.roblox
	local Instance, Enum, Color3 = roblox.Instance, roblox.Enum, roblox.Color3

	local function setup(loop)
		local game = Instance.new("DataModel")
		local workspace = game:GetService("Workspace")
		workspace:SetAttribute("CoreLoopActive", loop)
		local rec = { binds = {}, connections = 0, made = {}, renderSteps = {}, waited = 0 }
		local function sig()
			return {
				Connect = function()
					rec.connections += 1
					return { Disconnect = function() end }
				end,
			}
		end
		local function noop() end
		local playerGui = Instance.new("Folder")
		local loader = t.loader({
			services = {
				CollectionService = {
					GetTagged = function()
						return {}
					end,
					GetInstanceAddedSignal = sig,
					GetInstanceRemovedSignal = sig,
					HasTag = function()
						return false
					end,
				},
				ContextActionService = {
					BindActionAtPriority = function(_, name, _fn, touchButton, priority, ...)
						table.insert(
							rec.binds,
							{ name = name, touchButton = touchButton, priority = priority, inputs = { ... } }
						)
					end,
					UnbindAction = noop,
				},
				Players = {
					LocalPlayer = {
						UserId = 1,
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
					Heartbeat = sig(),
					BindToRenderStep = function(_, name)
						table.insert(rec.renderSteps, name)
					end,
					UnbindFromRenderStep = noop,
				},
				UserInputService = { InputBegan = sig(), InputEnded = sig() },
			},
			mocks = {
				HUD = { Toast = noop, NoteGrab = noop },
				Net = {
					Remote = function()
						return { FireServer = noop }
					end,
				},
				UITheme = {
					Size = { Tap = 44, TextButton = 15 },
					Fonts = { Heading = Enum.Font.FredokaOne },
					Colors = { Cream = Color3.new(1, 1, 1), Ink = Color3.new(0, 0, 0) },
					Screen = function(name)
						local gui = Instance.new("ScreenGui")
						gui.Name = name
						return gui
					end,
					Button = function(opts)
						local root = Instance.new("Frame")
						root.Name = opts.name
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
				task = {
					wait = function()
						rec.waited += 0.25
						return 0.25
					end,
					delay = noop,
				},
				Instance = setmetatable({
					new = function(class)
						table.insert(rec.made, class)
						return Instance.new(class)
					end,
				}, { __index = Instance }),
			},
		})
		local DragController = loader:load("StarterPlayer/StarterPlayerScripts/DragController")
		DragController.Start()
		rec.workspace = workspace
		rec.playerGui = playerGui
		return rec
	end

	t.test("under the v1 loop it does nothing at all", function()
		local rec = setup(1)
		t.eq(rec.binds, {}, "no actions bound")
		t.eq(rec.connections, 0, "no input, render or tag signals")
		t.eq(rec.made, {}, "nothing built")
		t.eq(#rec.playerGui:GetChildren(), 0)
		t.eq(rec.waited, 0, "and it didn't wait: the loop was known")
	end)

	t.test("no word from the server about the loop: it waits a while, then stays off", function()
		local rec = setup(nil)
		t.ok(rec.waited >= 60, "waited " .. rec.waited)
		t.eq(rec.binds, {})
		t.eq(rec.connections, 0)
	end)

	t.test("under v2: touches through a low-priority action, the hold's keys only while holding", function()
		local rec = setup(2)
		t.eq(#rec.binds, 1, "one action until something is held")
		local touch = rec.binds[1]
		t.eq(touch.name, "DragTouch")
		t.eq(touch.touchButton, false, "no on-screen button of Roblox's own")
		t.eq(touch.priority, Enum.ContextActionPriority.Low.Value, "under the thumbstick's action")
		t.eq(touch.inputs, { Enum.UserInputType.Touch })
		t.eq(rec.renderSteps, {}, "no per-frame work until something is held")
		t.ok(rec.connections > 0)
		t.ok(rec.workspace:FindFirstChild("GrabBalls") ~= nil, "a folder for everyone's grip balls")
	end)

	t.test("under v2: the touch row (- + Turn Tip) is built hidden, and the gamepad's dot", function()
		local rec = setup(2)
		local gui = rec.playerGui:FindFirstChild("DragControls")
		t.ok(gui ~= nil)
		local row = gui:FindFirstChild("Row")
		t.eq(row.Visible, false)
		local names = {}
		for _, child in ipairs(row:GetChildren()) do
			names[child.LayoutOrder] = child.Name
		end
		t.eq(names, { "Nearer", "Further", "Turn", "Tip" })
		local reticle = rec.playerGui:FindFirstChild("DragReticle")
		t.ok(reticle and reticle.IgnoreGuiInset, "the dot sits at the true centre, where the gamepad's ray goes")
		t.eq(reticle:FindFirstChild("Dot").Visible, false)
	end)
end
