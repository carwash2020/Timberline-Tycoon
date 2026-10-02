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
				SoundData = { Play = function() end },
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
		t.eq(CutController.WoodGroup, "Wood", "the ray's group: leaves don't collide with Wood")
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
		t.eq({ d2, c2 }, { 6.35, 0.35 })
		local d3 = CutController.Stats(inferno, "oak")
		t.eq(d3, 0.6)
	end)

	t.test("under the v1 loop it starts nothing", function()
		local controller, connected = load(1)
		controller.Start()
		t.eq(connected(), 0, "no signal connected")
	end)
end
