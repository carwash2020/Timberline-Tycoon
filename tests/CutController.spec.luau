--!nocheck
-- CutController (V2_PLAN.md M1.3): the v2 axe's pure parts. What a ray
-- hit means (sections of standing trees and loose pieces; never leaves,
-- bark details, cut faces or notches; not a stub, a sapling, a dormant or
-- dead tree), where a swing lands (knee to chest by the root part on a
-- trunk, where you pointed on a log), the axe's v2 numbers per wood, and
-- that under the v1 loop it starts nothing.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

	local function load(loop)
		local connected = 0
		local sig = {
			Connect = function()
				connected += 1
				return { Disconnect = function() end }
			end,
		}
		local workspace = {
			GetAttribute = function(_, name)
				return if name == "CoreLoopActive" then loop else nil
			end,
			GetPropertyChangedSignal = function()
				return sig
			end,
		}
		local params = {
			new = function()
				return {}
			end,
		}
		local loader = t.loader({
			services = {
				Debris = { AddItem = function() end },
				Players = { LocalPlayer = { UserId = 1, CharacterAdded = sig } },
				RunService = { Heartbeat = sig },
				UserInputService = { InputBegan = sig },
			},
			mocks = {
				HUD = { Toast = function() end },
				Quality = {
					Tier = function()
						return "high"
					end,
				},
				SoundData = {
					Play = function() end,
					SwingFor = function()
						return "Swing"
					end,
				},
				Net = {
					Remote = function()
						return { FireServer = function() end }
					end,
				},
			},
			globals = {
				workspace = workspace,
				RaycastParams = params,
				OverlapParams = params,
				task = {
					wait = function()
						return 0.25
					end,
				},
			},
		})
		return loader:load("StarterPlayer/StarterPlayerScripts/CutController"), function()
			return connected
		end
	end

	local CutController = load(2)
	local SectionLogic = t.shared("SectionLogic")
	local ItemCatalog = t.shared("ItemCatalog")

	local function tree(tag, attrs)
		local model = Instance.new("Model")
		model:AddTag(tag)
		for k, v in pairs(attrs or {}) do
			model:SetAttribute(k, v)
		end
		local section = Instance.new("Part")
		section.Name = "Section"
		section:SetAttribute("Section", 1)
		section.Size = Vector3.new(2, 4.5, 2)
		section.CFrame = CFrame.new(0, 2.25, 0)
		section.Parent = model
		local leaves = Instance.new("Part")
		leaves.Name = "Leaves"
		leaves:SetAttribute("Section", 1)
		leaves.Parent = model
		local notch = Instance.new("Part")
		notch.Name = "Notch"
		notch:SetAttribute("Section", 1)
		notch.Parent = model
		local clue = Instance.new("Model")
		clue.Name = "BarkClue"
		clue.Parent = model
		local cluePart = Instance.new("Part")
		cluePart.Name = "Eye"
		cluePart:SetAttribute("Section", 1)
		cluePart.Parent = clue
		return model, section, leaves, notch, cluePart
	end

	t.test("leaves are skipped: only a Section is a target, on a standing tree or a loose piece", function()
		local model, section, leaves, notch, clue = tree("Tree", { WoodId = "oak" })
		local part, m, kind = CutController.TargetOf(section)
		t.ok(part == section and m == model)
		t.eq(kind, "tree")
		t.eq(CutController.TargetOf(leaves), nil, "leaves")
		t.eq(CutController.TargetOf(notch), nil, "a notch")
		t.eq(CutController.TargetOf(clue), nil, "a bark clue")
		t.eq(CutController.TargetOf(nil), nil)
		local piece, logSection = tree("Wood", { WoodId = "oak" })
		local p2, m2, k2 = CutController.TargetOf(logSection)
		t.ok(p2 == logSection and m2 == piece)
		t.eq(k2, "wood")
		local stray = Instance.new("Part")
		stray.Name = "Section"
		stray:SetAttribute("Section", 1)
		t.eq(CutController.TargetOf(stray), nil, "a section of nothing")
		t.eq(CutController.WoodGroup, "Wood", "nearest-section search; the pointer ray does not use it")
	end)

	t.test("a stub, a sapling, a dormant or a dead tree is no target; a node is mined", function()
		for _, attr in ipairs({ "Felled", "Sapling", "Dormant", "Dead" }) do
			local _, section = tree("Tree", { WoodId = "oak", [attr] = true })
			t.eq(CutController.TargetOf(section), nil, attr)
		end
		local node = Instance.new("Model")
		node:AddTag("Node")
		local crystal = Instance.new("Part")
		crystal.Parent = node
		local _, m, kind = CutController.TargetOf(crystal)
		t.ok(m == node)
		t.eq(kind, "node")
	end)

	t.test("a crown click cuts the in-reach trunk, and a far crown says so", function()
		local model, section, leaves = tree("Tree", { WoodId = "oak" })
		local high = Instance.new("Part")
		high.Name = "Section"
		high:SetAttribute("Section", 2)
		high.Size = Vector3.new(1.2, 8, 1.2)
		high.CFrame = CFrame.new(0, 16, 0)
		high.Parent = model
		leaves:SetAttribute("Section", 2)
		local rusty = ItemCatalog.GetAxe("RustyAxe")
		local root = Vector3.new(3, 3, 0)
		local near = CutController.PickSection(model, "tree", rusty, root, Vector3.new(0, 12, 0), Vector3.yAxis)
		t.ok(near ~= nil)
		t.ok(near.part == section, "the trunk you can reach, not the leaf's high branch")
		t.eq(near.problem, nil)
		local far =
			CutController.PickSection(model, "tree", rusty, Vector3.new(40, 3, 0), Vector3.new(0, 12, 0), Vector3.yAxis)
		t.ok(far ~= nil)
		t.eq(far.problem, "far", "out of reach says so, instead of a silent miss")
		t.ok(far.part == section)
	end)

	t.test("auto-target: a trunk is cut between knee and chest by the root part, on the side facing you", function()
		local _, section = tree("Tree", { WoodId = "oak" })
		local root = Vector3.new(4, 3, 0)
		local hit, normal = CutController.Aim(section, root, nil, nil)
		t.ok(math.abs(hit.Y - 3) < 1e-5, "the root part's height with no pointer")
		t.ok(normal.X > 0.99, "toward you")
		local low = CutController.Aim(section, root, Vector3.new(1, 0.1, 0), Vector3.xAxis)
		t.ok(math.abs(low.Y - (3 + SectionLogic.KneeAbove)) < 1e-5, "no lower than the knee")
		local high = CutController.Aim(section, root, Vector3.new(1, 4.4, 0), Vector3.xAxis)
		t.ok(math.abs(high.Y - (3 + SectionLogic.ChestAbove)) < 1e-5, "no higher than the chest")
		-- Standing higher (on a slope): the cut follows you up the trunk.
		local up = CutController.Aim(section, Vector3.new(4, 3.9, 0), nil, nil)
		t.ok(up.Y > hit.Y, "it follows the root part")
	end)

	t.test("the axe's v2 numbers: damage, cooldown and reach, a specialist's per wood", function()
		local rusty = ItemCatalog.GetAxe("RustyAxe")
		local damage, cooldown, range = CutController.Stats(rusty, "oak")
		t.eq({ damage, cooldown, range }, { 0.2, 0.65, 4.8 })
		local inferno = ItemCatalog.GetAxe("InfernoAxe")
		local d2, c2 = CutController.Stats(inferno, "emberwood")
		t.eq({ d2, c2 }, { 7.5, 0.4 })
		local d3 = CutController.Stats(inferno, "oak")
		t.eq(d3, 4.6)
	end)

	t.test("where a swing aims: the finger on touch, the cursor on a mouse, nothing on a gamepad", function()
		local Vector2 = roblox.Vector2
		t.eq(CutController.PointerKind("Touch"), "touch")
		t.eq(CutController.PointerKind("Gamepad1"), "gamepad")
		t.eq(CutController.PointerKind("Gamepad2"), "gamepad")
		t.eq(CutController.PointerKind("MouseButton1"), "mouse")
		t.eq(CutController.PointerKind("Keyboard"), "mouse")
		local tap, mouse = Vector2.new(12, 34), Vector2.new(56, 78)
		local point, space = CutController.PointerPoint("touch", tap, mouse)
		t.eq({ point.X, point.Y, space }, { 12, 34, "screen" }, "a stored finger is screen pixels")
		point, space = CutController.PointerPoint("touch", nil, mouse)
		t.eq({ point.X, point.Y, space }, { 56, 78, "viewport" }, "no finger yet: the mouse location, never no ray")
		point, space = CutController.PointerPoint("mouse", tap, mouse)
		t.eq({ point.X, point.Y, space }, { 56, 78, "viewport" })
		point, space = CutController.PointerPoint("gamepad", tap, mouse)
		t.eq(point, nil, "a pad has no pointer")
		t.eq(space, "viewport")
		local screen = Vector2.new(800, 400)
		t.eq(CutController.TouchAims(true, Vector2.new(500, 200), screen), false, "a button already took it")
		t.eq(CutController.TouchAims(false, Vector2.new(100, 300), screen), false, "the thumbstick walks")
		t.eq(CutController.TouchAims(false, Vector2.new(500, 200), screen), true, "a tap in the world")
	end)

	t.test("under the v1 loop it starts nothing", function()
		local controller, connected = load(1)
		controller.Start()
		t.eq(connected(), 0, "no signal connected")
	end)

	-- The HUD's v2 hints: pointing at loose wood (put the axe away to drag
	-- it) and at wood too hard for the axe.
	t.test("what the axe points at, for the hint: loose wood, and wood too hard for it", function()
		local HintLogic = t.shared("HintLogic")
		local FieldGuide = t.shared("FieldGuide")
		local rusty = ItemCatalog.GetAxe("RustyAxe")
		local part = Instance.new("Part")
		part.Size = Vector3.new(2, 9, 2)
		local function seen(kind, woodId, problem)
			return { part = part, model = Instance.new("Model"), kind = kind, woodId = woodId, problem = problem }
		end
		t.eq({ CutController.PointingFacts(nil, rusty) }, { false, false }, "nothing")
		t.eq({ CutController.PointingFacts(seen("node"), rusty) }, { false, false }, "a crystal node")
		t.eq({ CutController.PointingFacts(seen("tree", "oak"), rusty) }, { false, false }, "an oak the hatchet cuts")
		t.eq({ CutController.PointingFacts(seen("wood", "oak"), rusty) }, { true, false }, "a loose oak log")
		t.eq({ CutController.PointingFacts(seen("tree", "frostwood", "hard"), rusty) }, { false, true }, "can't cut it")
		-- A thick lumenwood trunk with the hatchet: far past the useful pace.
		part.Size = Vector3.new(4, 9, 4)
		local hits = FieldGuide.CutHits(rusty, "lumenwood", 4, 4)
		t.ok(HintLogic.TooHard(hits), "lumenwood takes " .. hits .. " hits")
		t.eq({ CutController.PointingFacts(seen("tree", "lumenwood"), rusty) }, { false, true }, "too many hits")
	end)

	-- A live v2 client: tapping a tree fires Chop (not the idle v1 ChopTree),
	-- aimed with the right camera ray. GetPartBoundsInRadius is empty unless
	-- a case fills it, so a missing ray cannot be saved by the nearest tree.
	local function signal()
		local fns = {}
		return {
			Connect = function(_, fn)
				table.insert(fns, fn)
				return { Disconnect = function() end }
			end,
			Fire = function(_, ...)
				for _, fn in ipairs(fns) do
					fn(...)
				end
			end,
		}
	end

	local function swingWorld()
		local Vector2, Vector3, CFrame = roblox.Vector2, roblox.Vector3, roblox.CFrame
		local fires, rays, delayed = {}, {}, {}
		local inputName = "Touch"
		local mouse = Vector2.new(120, 80)
		local radiusParts = {}
		local time = { now = 1000 }
		local touchTap = signal()
		local inputBegan = signal()
		local activated = signal()

		local model = Instance.new("Model")
		model:AddTag("Tree")
		model:SetAttribute("WoodId", "oak")
		local section = Instance.new("Part")
		section.Name = "Section"
		section:SetAttribute("Section", 1)
		section.Size = Vector3.new(2, 4.5, 2)
		section.CFrame = CFrame.new(0, 2.25, 0)
		section.Parent = model
		local leaves = Instance.new("Part")
		leaves.Name = "Leaves"
		leaves:SetAttribute("Section", 1)
		leaves.Parent = model
		local hrp = Instance.new("Part")
		hrp.Name = "HumanoidRootPart"
		hrp.CFrame = CFrame.new(3, 3, 0)
		hrp.Position = Vector3.new(3, 3, 0)
		local tool = {
			Activated = activated,
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
				return if class == "Tool" then tool else nil
			end,
		}
		local hitInstance: any = section
		local camera = {
			ViewportSize = Vector2.new(844, 390),
			ScreenPointToRay = function(_, x, y)
				table.insert(rays, { method = "screen", x = x, y = y })
				return { Origin = Vector3.new(0, 8, 8), Direction = Vector3.new(0, -1, -1).Unit }
			end,
			ViewportPointToRay = function(_, x, y)
				table.insert(rays, { method = "viewport", x = x, y = y })
				return { Origin = Vector3.new(0, 8, 8), Direction = Vector3.new(0, -1, -1).Unit }
			end,
		}
		local function fakeInstance(className)
			local fields = { ClassName = className }
			return setmetatable({}, {
				__index = fields,
				__newindex = function(_, key, value)
					fields[key] = value
				end,
			})
		end
		local loader = t.loader({
			services = {
				Debris = { AddItem = function() end },
				Players = { LocalPlayer = { UserId = 1, Character = char, CharacterAdded = signal() } },
				RunService = { Heartbeat = signal() },
				UserInputService = {
					InputBegan = inputBegan,
					TouchTapInWorld = touchTap,
					GetLastInputType = function()
						return { Name = inputName }
					end,
					GetMouseLocation = function()
						return mouse
					end,
				},
			},
			mocks = {
				HUD = {
					Toast = function() end,
					SetPointing = function() end,
				},
				Quality = {
					Tier = function()
						return "high"
					end,
				},
				SoundData = {
					Play = function() end,
					SwingFor = function()
						return "Swing"
					end,
				},
				Net = {
					Remote = function(name)
						return {
							FireServer = function(_, ...)
								table.insert(fires, { name = name, args = { ... } })
							end,
						}
					end,
				},
			},
			globals = {
				workspace = {
					CurrentCamera = camera,
					GetAttribute = function(_, name)
						return if name == "CoreLoopActive" then 2 else nil
					end,
					GetPropertyChangedSignal = function()
						return signal()
					end,
					Raycast = function(_, _, params)
						if hitInstance == nil then
							return nil
						end
						-- Group Wood does not collide with Leaves: a Wood-group
						-- pointer ray misses a crown and hits nothing here.
						if params and params.CollisionGroup == "Wood" and hitInstance.Name == "Leaves" then
							return nil
						end
						return { Instance = hitInstance, Position = Vector3.new(1, 3, 0), Normal = Vector3.xAxis }
					end,
					GetPartBoundsInRadius = function()
						return radiusParts
					end,
				},
				RaycastParams = {
					new = function()
						return {}
					end,
				},
				OverlapParams = {
					new = function()
						return {}
					end,
				},
				Instance = { new = fakeInstance },
				task = {
					wait = function()
						return 0.25
					end,
					delay = function(_, fn)
						table.insert(delayed, fn)
					end,
					defer = function(fn, ...)
						fn(...)
					end,
				},
				os = setmetatable({
					clock = function()
						return time.now
					end,
				}, { __index = os }),
			},
		})
		local controller = loader:load("StarterPlayer/StarterPlayerScripts/CutController")
		controller.Start()
		local function flush()
			local pending = delayed
			delayed = {}
			for _, fn in ipairs(pending) do
				fn()
			end
		end
		return {
			fires = fires,
			rays = rays,
			section = section,
			leaves = leaves,
			press = function(inputType, keyCode, processed)
				inputBegan:Fire({
					UserInputType = inputType,
					KeyCode = keyCode,
					Position = roblox.Vector3.zero,
				}, processed == true)
			end,
			tap = function(pos, processed)
				touchTap:Fire(pos, processed == true)
			end,
			finger = function(pos)
				inputBegan:Fire({
					UserInputType = roblox.Enum.UserInputType.Touch,
					Position = roblox.Vector3.new(pos.X, pos.Y, 0),
				})
			end,
			activate = function()
				activated:Fire()
			end,
			flush = flush,
			input = function(name)
				inputName = name
			end,
			mouse = function(point)
				mouse = point
			end,
			radius = function(parts)
				radiusParts = parts
			end,
			hit = function(inst)
				hitInstance = inst
			end,
			advance = function(dt)
				time.now += dt
			end,
		}
	end

	t.test("a tap in the world fires Chop along a screen ray; a button or the thumbstick does not", function()
		local Vector2 = roblox.Vector2
		local w = swingWorld()
		w.tap(Vector2.new(500, 100), true)
		t.eq(#w.fires, 0, "a button")
		w.tap(Vector2.new(80, 300), false)
		t.eq(#w.fires, 0, "the thumbstick")
		w.tap(Vector2.new(500, 100), false)
		t.eq(#w.fires, 1)
		t.eq(w.fires[1].name, "Chop", "the live v2 remote, not ChopTree")
		t.ok(w.fires[1].args[1] == w.section, "the section the ray hit")
		t.eq(w.rays[1], { method = "screen", x = 500, y = 100 })
	end)

	t.test("touch Activated with no stored tap still swings, through the mouse-location ray", function()
		local w = swingWorld()
		w.radius({})
		w.mouse(roblox.Vector2.new(120, 80))
		w.activate()
		t.eq(#w.fires, 0, "it waits a frame for the tap")
		w.flush()
		t.eq(#w.fires, 1)
		t.eq(w.fires[1].name, "Chop")
		t.eq(w.rays[1], { method = "viewport", x = 120, y = 80 })
	end)

	t.test("a world tap and the tool's Activated are one swing, and a thumbstick activate is none", function()
		local Vector2 = roblox.Vector2
		local w = swingWorld()
		w.tap(Vector2.new(500, 100), false)
		w.activate()
		w.flush()
		t.eq(#w.fires, 1, "Activated does not swing the tap again")
		w.advance(1)
		w.finger(Vector2.new(80, 300))
		w.activate()
		w.flush()
		t.eq(#w.fires, 1, "activating from the thumbstick doesn't chop")
	end)

	t.test("a mouse click fires Chop through ViewportPointToRay", function()
		local w = swingWorld()
		w.input("MouseButton1")
		w.mouse(roblox.Vector2.new(40, 50))
		w.activate()
		t.eq(#w.fires, 1)
		t.eq(w.fires[1].name, "Chop")
		t.eq(w.rays[1], { method = "viewport", x = 40, y = 50 })
	end)

	t.test("a gamepad trigger fires Chop at the nearest section, with no pointer ray", function()
		local w = swingWorld()
		w.input("Gamepad1")
		w.hit(nil)
		w.radius({ w.section })
		w.activate()
		t.eq(#w.fires, 1)
		t.eq(w.fires[1].name, "Chop")
		t.ok(w.fires[1].args[1] == w.section)
		t.eq(#w.rays, 0, "no pointer")
	end)

	t.test("clicking the crown fires Chop at the trunk; a Wood-group ray would miss", function()
		local Enum = roblox.Enum
		local w = swingWorld()
		w.input("MouseButton1")
		w.hit(w.leaves)
		w.press(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, false)
		t.eq(#w.fires, 1)
		t.eq(w.fires[1].name, "Chop")
		t.ok(w.fires[1].args[1] == w.section, "the trunk, not the leaves")
		w.advance(1)
		w.section.CFrame = CFrame.new(40, 2.25, 0)
		w.press(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, false)
		t.eq(#w.fires, 1, "a crown you can't reach does not fire")
	end)

	t.test("a mouse button and the tool's Activated are one swing; a button's click is none", function()
		local Enum = roblox.Enum
		local w = swingWorld()
		w.input("MouseButton1")
		w.press(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, false)
		w.activate()
		t.eq(#w.fires, 1, "Activated does not swing the click again")
		w.advance(1)
		w.press(Enum.UserInputType.MouseButton1, Enum.KeyCode.Unknown, true)
		t.eq(#w.fires, 1, "a Gui button already took it")
	end)

	t.test("ButtonR2 fires Chop at the nearest section without Activated", function()
		local Enum = roblox.Enum
		local w = swingWorld()
		w.input("Gamepad1")
		w.hit(nil)
		w.radius({ w.section })
		w.press(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR2, false)
		t.eq(#w.fires, 1)
		t.eq(w.fires[1].name, "Chop")
		t.ok(w.fires[1].args[1] == w.section)
		t.eq(#w.rays, 0, "no pointer")
	end)
end
