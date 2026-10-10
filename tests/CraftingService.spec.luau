--!nocheck
-- CraftingService: the bench's 12-stud reach, ore that has to be in reach
-- of the bench, and a stranger's closer log.

return function(t)
	local Instance = t.roblox.Instance
	local CFrame = t.roblox.CFrame
	local Vector3 = t.roblox.Vector3

	local function signal()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end
	pcall(t.roblox.implementProperty, "Tool", "Activated", signal)
	pcall(t.roblox.implementProperty, "Tool", "Equipped", signal)
	pcall(t.roblox.implementProperty, "Tool", "Unequipped", signal)
	-- Lune's ProximityPrompt has no Triggered signal, and only the first spec
	-- to add one wins. Share the per-prompt signals other specs fire through
	-- (_G.__promptTriggered), so the result doesn't depend on spec order.
	local triggered = _G.__promptTriggered or setmetatable({}, { __mode = "k" })
	_G.__promptTriggered = triggered
	pcall(t.roblox.implementProperty, "ProximityPrompt", "Triggered", function(self)
		local s = triggered[self]
		if not s then
			local list = {}
			s = { list = list }
			function s:Connect(fn)
				table.insert(list, fn)
				return { Disconnect = function() end }
			end
			function s:Fire(...)
				for _, fn in ipairs(list) do
					fn(...)
				end
			end
			triggered[self] = s
		end
		return s
	end)

	local function place(part, pos)
		part.CFrame = CFrame.new(pos)
		part.Position = pos
	end

	local function setup()
		local world = Instance.new("Folder")
		world.Name = "Workspace"
		local profile = {
			cash = 0,
			pendingCash = 0,
			gear = {},
			passes = {},
			mining = nil,
		}
		local player = {
			UserId = 7,
			Name = "Tester",
			attrs = {},
			SetAttribute = function(self, key, value)
				self.attrs[key] = value
			end,
			GetAttribute = function(self, key)
				return self.attrs[key]
			end,
		}
		local backpack = Instance.new("Folder")
		player.FindFirstChildOfClass = function(_, class)
			if class == "Backpack" then
				return backpack
			end
			return nil
		end
		local function stand(pos)
			local character = Instance.new("Model")
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Size = Vector3.new(2, 2, 1)
			place(root, pos)
			root.Parent = character
			character.PrimaryPart = root
			player.Character = character
			return root
		end
		local function walk(inst, tag, into)
			if inst.HasTag and inst:HasTag(tag) then
				table.insert(into, inst)
			end
			for _, child in ipairs(inst:GetChildren()) do
				walk(child, tag, into)
			end
		end
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				WoodService = {
					FromModel = function()
						return nil
					end,
					Remove = function() end,
				},
			},
			services = {
				Workspace = world,
				Players = {
					GetPlayerByUserId = function()
						return nil
					end,
					GetPlayers = function()
						return {}
					end,
				},
				CollectionService = {
					GetTagged = function(_, tag)
						local found = {}
						walk(world, tag, found)
						return found
					end,
					AddTag = function(_, inst, tag)
						inst:AddTag(tag)
					end,
				},
			},
		})
		local Crafting = loader:server("CraftingService")
		local folder = Instance.new("Folder")
		folder.Name = "Mining"
		folder.Parent = world
		local bench = Instance.new("Model")
		bench.Name = "CraftBench"
		local top = Instance.new("Part")
		top.Name = "Top"
		top.Size = Vector3.new(4, 0.3, 2)
		place(top, Vector3.zero)
		top.Parent = bench
		bench.PrimaryPart = top
		bench.Parent = folder
		return {
			Crafting = Crafting,
			profile = profile,
			player = player,
			folder = folder,
			stand = stand,
		}
	end

	local function piece(parent, name, ore, ownerId, at)
		local model = Instance.new("Model")
		model.Name = name
		local part = Instance.new("Part")
		part.Size = Vector3.new(1, 1, 1)
		place(part, at)
		part.Parent = model
		model.PrimaryPart = part
		model:SetAttribute("Ore", ore)
		model:SetAttribute("OwnerId", ownerId)
		model.Parent = parent
		return model
	end

	t.test("craft requires the bench, and ore out of reach of the bench is ignored", function()
		local world = setup()
		world.stand(Vector3.new(0, 0, 40))
		local farIngots = piece(world.folder, "Ingot", "Iron", world.player.UserId, Vector3.zero)
		t.eq(world.Crafting.Craft(world.player, "RopeLadder"), false)
		t.eq(farIngots.Parent ~= nil, true)

		local near = setup()
		near.stand(Vector3.new(0, 0, 4))
		local out = piece(near.folder, "Ingot", "Iron", near.player.UserId, Vector3.new(0, 0, 30))
		local out2 = piece(near.folder, "Ingot", "Iron", near.player.UserId, Vector3.new(1, 0, 30))
		t.eq(near.Crafting.Craft(near.player, "RopeLadder"), false)
		t.eq(out.Parent ~= nil, true)
		t.eq(out2.Parent ~= nil, true)
		t.eq(near.profile.mining.ropes, 0)
	end)

	t.test("a stranger's closer log does not block a craft of your own", function()
		local world = setup()
		local root = world.stand(Vector3.new(0, 0, 4))
		piece(world.folder, "Ingot", "Iron", world.player.UserId, Vector3.new(1, 0, 0))
		piece(world.folder, "Ingot", "Iron", world.player.UserId, Vector3.new(-1, 0, 0))
		local stranger = Instance.new("Model")
		stranger.Name = "Wood_stranger"
		local sPart = Instance.new("Part")
		sPart.Size = Vector3.new(1, 4, 1)
		place(sPart, root.Position + Vector3.new(0, 0, -2))
		sPart.Parent = stranger
		stranger.PrimaryPart = sPart
		stranger:SetAttribute("Owner", 99)
		stranger:SetAttribute("Volume", 8)
		stranger:AddTag("Wood")
		stranger.Parent = world.folder
		local own = Instance.new("Model")
		own.Name = "Wood_own"
		local oPart = Instance.new("Part")
		oPart.Size = Vector3.new(1, 4, 1)
		place(oPart, root.Position + Vector3.new(0, 0, -8))
		oPart.Parent = own
		own.PrimaryPart = oPart
		own:SetAttribute("Owner", world.player.UserId)
		own:SetAttribute("Volume", 6)
		own:AddTag("Wood")
		own.Parent = world.folder
		t.eq(world.Crafting.Craft(world.player, "RopeLadder"), true)
		t.eq(stranger.Parent ~= nil, true)
		t.eq(own.Parent, nil)
		t.eq(world.profile.mining.ropes, 1)
	end)

	t.test("furniture: the bench grants one placeable piece and takes the ingots in the same block", function()
		local world = setup()
		world.stand(Vector3.new(0, 0, 4))
		local granted = {}
		world.Crafting.Hooks.canGrant = function(_, id)
			return id == "GoldChest", nil
		end
		world.Crafting.Hooks.grant = function(player, id, source)
			table.insert(granted, { player = player, id = id, source = source })
			return true, nil
		end
		local gold1 = piece(world.folder, "Ingot", "Gold", world.player.UserId, Vector3.new(1, 0, 0))
		local gold2 = piece(world.folder, "Ingot", "Gold", world.player.UserId, Vector3.new(-1, 0, 0))
		local iron1 = piece(world.folder, "Ingot", "Iron", world.player.UserId, Vector3.new(0, 0, 1))
		local iron2 = piece(world.folder, "Ingot", "Iron", world.player.UserId, Vector3.new(0, 0, -1))
		t.eq(world.Crafting.Craft(world.player, "GoldChest"), true)
		t.eq(#granted, 1)
		t.eq({ granted[1].id, granted[1].source }, { "GoldChest", "craft" })
		for _, ingot in ipairs({ gold1, gold2, iron1, iron2 }) do
			t.eq(ingot.Parent, nil, "every ingot was taken")
		end
		t.eq(world.profile.mining.crafted.GoldChest, 1)
	end)

	t.test("furniture: a grant that cannot happen takes nothing", function()
		local world = setup()
		world.stand(Vector3.new(0, 0, 4))
		local ingots = {
			piece(world.folder, "Ingot", "Gold", world.player.UserId, Vector3.new(1, 0, 0)),
			piece(world.folder, "Ingot", "Gold", world.player.UserId, Vector3.new(-1, 0, 0)),
			piece(world.folder, "Ingot", "Iron", world.player.UserId, Vector3.new(0, 0, 1)),
			piece(world.folder, "Ingot", "Iron", world.player.UserId, Vector3.new(0, 0, -1)),
		}
		t.eq(world.Crafting.Craft(world.player, "GoldChest"), false, "no grant hook bound: refused")
		world.Crafting.Hooks.canGrant = function()
			return false, "full"
		end
		world.Crafting.Hooks.grant = function()
			error("must not be called")
		end
		t.eq(world.Crafting.Craft(world.player, "GoldChest"), false, "a full stock: refused")
		for _, ingot in ipairs(ingots) do
			t.ok(ingot.Parent ~= nil, "the ingots are still there")
		end
		t.eq(world.profile.mining.crafted.GoldChest, nil)
	end)
end
