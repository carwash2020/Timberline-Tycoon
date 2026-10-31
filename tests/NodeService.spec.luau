--!nocheck
-- T414e: the node's look changed to rock and ore veins; what you aim at, hit and get paid for did not.
return function(t)
	local Vector3 = t.roblox.Vector3
	local ItemCatalog = t.shared("ItemCatalog")
	local GameConfig = t.shared("GameConfig")

	local delays = {}
	local function setup()
		delays = {}
		local profile = { materials = {} }
		local char = { HumanoidRootPart = { Position = Vector3.new(0, 3, 0) } }
		local player = {
			Character = char,
			attrs = {},
		}
		function char:FindFirstChild(name)
			return self[name]
		end
		function player:SetAttribute(name, value)
			self.attrs[name] = value
		end
		local toasts = {}
		local loader = t.loader({
			services = { Players = {}, Workspace = {} },
			globals = {
				task = {
					delay = function(sec, fn)
						table.insert(delays, { sec = sec, fn = fn })
					end,
				},
			},
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
			},
		})
		local NodeService = loader:server("NodeService")
		NodeService.Init(function(_, message)
			table.insert(toasts, message)
		end)
		local folder = t.roblox.Instance.new("Folder")
		return { service = NodeService, player = player, profile = profile, toasts = toasts, folder = folder }
	end

	t.test("a node keeps its tag, attributes, hit box and Atomic streaming", function()
		local s = setup()
		local material = ItemCatalog.Materials.SkyShard
		local model = s.service.Spawn("SkyShard", Vector3.new(0, 0, 4), s.folder)
		t.eq(model.Name, "Node_SkyShard")
		t.ok(model:HasTag("Node"), "tagged Node: the client aims at it like a tree")
		t.eq(model.ModelStreamingMode, t.roblox.Enum.ModelStreamingMode.Atomic)
		t.eq(model:GetAttribute("Material"), "SkyShard")
		t.eq(model:GetAttribute("MaxHP"), material.node.hits)
		t.eq(model:GetAttribute("HP"), material.node.hits)
		t.ok(model:GetAttribute("Uid") ~= nil)
		t.eq(model:GetAttribute("BarOffset"), 3.5)
		local part = model.PrimaryPart
		t.eq(part.Name, "Crystal", "the part the client aims at")
		t.eq(part.Transparency, 1)
		t.eq(part.CanCollide, true, "you bump into it")
		t.eq(part.CFrame.Position, Vector3.new(0, 2.25, 4), "its centre is where the range check measured before")
		local look = model:FindFirstChild("Look")
		t.ok(look ~= nil and #look:GetChildren() >= 8, "the rock and its veins")
		for _, d in ipairs(model:GetDescendants()) do
			t.ok(not d:IsA("Light"), "no light")
		end
	end)

	t.test("mining pays what it paid: hits swings, then yield, then it grows back after respawnSec", function()
		local s = setup()
		local material = ItemCatalog.Materials.SkyShard
		t.eq(material.node.hits, 12)
		t.eq(material.node.yield, 1)
		t.eq(material.node.respawnSec, 600)
		local model = s.service.Spawn("SkyShard", Vector3.new(0, 0, 4), s.folder)
		local uid = model:GetAttribute("Uid")
		for swing = 1, material.node.hits - 1 do
			t.eq(s.service.Hit(s.player, uid), "hit")
			t.eq(model:GetAttribute("HP"), material.node.hits - swing)
		end
		t.eq(s.profile.materials.SkyShard, nil, "nothing paid before it breaks")
		t.eq(s.service.Hit(s.player, uid), "mined")
		t.eq(s.profile.materials.SkyShard, material.node.yield)
		t.eq(s.player.attrs.Materials ~= nil, true, "the Materials attribute is mirrored")
		t.eq(#s.toasts, 1)
		t.eq(model.PrimaryPart.CanCollide, false, "gone while mined")
		t.eq(model:FindFirstChild("Look"), nil, "its look leaves with it")
		t.eq(s.service.Hit(s.player, uid), nil, "a mined node cannot be hit")
		t.eq(#delays, 1)
		t.eq(delays[1].sec, material.node.respawnSec)
		delays[1].fn()
		t.eq(model:GetAttribute("HP"), material.node.hits, "grown back")
		t.eq(model.PrimaryPart.CanCollide, true)
		t.ok(model:FindFirstChild("Look") ~= nil, "with its rock")
		t.eq(s.service.Hit(s.player, uid), "hit")
	end)

	t.test("a swing from too far is refused and costs nothing", function()
		local s = setup()
		local model = s.service.Spawn("SkyShard", Vector3.new(0, 0, 4), s.folder)
		s.player.Character.HumanoidRootPart.Position =
			Vector3.new(0, 3, 4 + GameConfig.ChopRange + GameConfig.RangeTolerance + 5)
		t.eq(s.service.Hit(s.player, model:GetAttribute("Uid")), "far")
		t.eq(model:GetAttribute("HP"), model:GetAttribute("MaxHP"))
	end)
end
