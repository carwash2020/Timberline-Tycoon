--!nocheck
-- The hammer and the rolled plans on the server (BlueprintService): the
-- hammer comes with every spawn, a plan is one saved item and one Tool, using
-- it consumes it and teaches the book, dropping and picking up keep it yours,
-- and nothing the client sends gets round those rules.
return function(t)
	local Vector3, CFrame = t.roblox.Vector3, t.roblox.CFrame

	-- Just enough of Instance for tools, models and the pick-up prompt.
	local function fakeInstance()
		local made = {}
		local Instance = {}
		local methods = {}
		function methods:SetAttribute(key, value)
			self._attrs[key] = value
		end
		function methods:GetAttribute(key)
			return self._attrs[key]
		end
		function methods:GetChildren()
			return table.clone(self._kids)
		end
		function methods:FindFirstChildOfClass(class)
			for _, child in ipairs(self._kids) do
				if child.ClassName == class then
					return child
				end
			end
			return nil
		end
		function methods:IsA(class)
			return class == self.ClassName
		end
		function methods:Destroy()
			self.destroyed = true
			self.Parent = nil
		end
		function Instance.new(class)
			local props = { ClassName = class, _kids = {}, _attrs = {}, Name = class }
			local inst = {}
			setmetatable(inst, {
				__index = function(_, key)
					if props[key] ~= nil then
						return props[key]
					end
					if key == "Triggered" then
						local signal = { handlers = {} }
						function signal:Connect(fn)
							table.insert(self.handlers, fn)
						end
						props[key] = signal
						return signal
					end
					return methods[key]
				end,
				__newindex = function(_, key, value)
					if key == "Parent" then
						local old = props.Parent
						if old then
							local list = old._kids
							local at = table.find(list, inst)
							if at then
								table.remove(list, at)
							end
						end
						props.Parent = value
						if value then
							table.insert(value._kids, inst)
						end
						return
					end
					props[key] = value
				end,
			})
			table.insert(made, inst)
			return inst
		end
		return Instance, made
	end

	local function setup(options)
		options = options or {}
		local Instance, made = fakeInstance()
		local profile = options.profile
			or {
				hammer = true,
				blueprintBook = {},
				blueprintItems = {},
				furnitureBlueprints = {},
			}
		local character = Instance.new("Model")
		local backpack = Instance.new("Backpack")
		local root = { Position = Vector3.new(10, 3, 20), CFrame = CFrame.new(10, 3, 20) }
		function character:FindFirstChild(name)
			return if name == "HumanoidRootPart" then root else nil
		end
		local attrs = {}
		local player = {
			Name = "Tester",
			DisplayName = "Tester",
			UserId = 42,
			Character = character,
			SetAttribute = function(_, key, value)
				attrs[key] = value
			end,
			FindFirstChildOfClass = function(_, class)
				return if class == "Backpack" then backpack else nil
			end,
		}
		local other = {
			Name = "Other",
			DisplayName = "Other",
			UserId = 43,
			Character = {
				FindFirstChild = function(_, name)
					return if name == "HumanoidRootPart" then { Position = Vector3.new(11, 3, 21) } else nil
				end,
				GetChildren = function()
					return {}
				end,
			},
			SetAttribute = function() end,
			FindFirstChildOfClass = function()
				return nil
			end,
		}
		local allowed = true
		local worldModels = {}
		local function artModel()
			local model = Instance.new("Model")
			model.PrimaryPart = Instance.new("Part")
			function model:GetPivot()
				return CFrame.new(10, 0, 17)
			end
			return model
		end
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile elseif p == other then options.otherProfile else nil
					end,
				},
				RateLimiter = {
					Allow = function()
						return allowed
					end,
				},
				BlueprintArt = {
					Held = function()
						return artModel()
					end,
					Dropped = function(id)
						local model = artModel()
						model.art = id
						table.insert(worldModels, model)
						return model
					end,
					Grip = function()
						return CFrame.identity
					end,
				},
				HammerArt = {
					Held = function()
						return artModel()
					end,
					Grip = function()
						return CFrame.identity
					end,
				},
				Kit = { placeAt = function() end },
			},
			globals = {
				Instance = Instance,
				workspace = {
					_kids = {},
					Raycast = function()
						return nil
					end,
					FindFirstChild = function()
						return nil
					end,
				},
				RaycastParams = {
					new = function()
						return {}
					end,
				},
			},
		})
		local Service = loader:server("BlueprintService")
		local toasts = {}
		local remotes = {}
		for _, name in ipairs({ "UseBlueprint", "DropBlueprint" }) do
			remotes[name] = { OnServerEvent = {
				Connect = function(self, fn)
					self.fn = fn
				end,
			} }
		end
		Service.Init(function(who, message)
			table.insert(toasts, { to = who, text = message })
		end, remotes)
		local function toolsIn(container)
			local out = {}
			for _, child in ipairs(container._kids) do
				if child.ClassName == "Tool" then
					table.insert(out, child)
				end
			end
			return out
		end
		-- Equip a Tool the way Roblox does: from the Backpack to the character.
		local function equip(tool)
			tool.Parent = character
		end
		return {
			Service = Service,
			player = player,
			other = other,
			profile = profile,
			character = character,
			backpack = backpack,
			attrs = attrs,
			toasts = toasts,
			remotes = remotes,
			world = worldModels,
			made = made,
			loader = loader,
			toolsIn = toolsIn,
			equip = equip,
			rate = function(on)
				allowed = on
			end,
		}
	end

	local function names(tools)
		local out = {}
		for _, tool in ipairs(tools) do
			table.insert(out, tool.Name)
		end
		return out
	end

	t.test("every spawn hands over the Hammer, once, and nothing else for a player with no plans", function()
		local s = setup()
		s.Service.GiveLoadout(s.player, s.character)
		t.eq(names(s.toolsIn(s.backpack)), { "Hammer" })
		local hammer = s.toolsIn(s.backpack)[1]
		t.eq(hammer:GetAttribute("Hammer"), true)
		t.eq(hammer.CanBeDropped, false)
		t.eq(hammer.RequiresHandle, true)
		-- A second hand-over (a slot swap, a join retry) adds no second hammer.
		s.Service.GiveLoadout(s.player, s.character)
		t.eq(#s.toolsIn(s.backpack), 1)
	end)

	t.test("a hammer in hand is not given again either", function()
		local s = setup()
		s.Service.GiveLoadout(s.player, s.character)
		s.equip(s.toolsIn(s.backpack)[1])
		s.Service.GiveLoadout(s.player, s.character)
		t.eq(#s.toolsIn(s.backpack), 0)
		t.eq(#s.toolsIn(s.character), 1)
	end)

	t.test("no hammer flag, no hammer", function()
		local s = setup({ profile = { hammer = false, blueprintBook = {}, blueprintItems = {} } })
		s.Service.GiveLoadout(s.player, s.character)
		t.eq(#s.toolsIn(s.backpack), 0)
	end)

	t.test("the Blueprints attribute carries the book, plus anything bought under the old rules", function()
		local s = setup({
			profile = {
				hammer = true,
				blueprintBook = { "Wall", "Shed" },
				blueprintItems = {},
				furnitureBlueprints = { Table = true, Nope = true },
			},
		})
		s.Service.GiveLoadout(s.player, s.character)
		t.eq(s.attrs.Blueprints, "Shed,Table,Wall")
	end)

	t.test("saved plans come back as Tools, after the hammer, named for the building", function()
		local s = setup({
			profile = {
				hammer = true,
				blueprintBook = {},
				blueprintItems = { { uid = "a", id = "Shed" }, { uid = "b", id = "Mailbox" } },
			},
		})
		s.Service.GiveLoadout(s.player, s.character)
		t.eq(names(s.toolsIn(s.backpack)), { "Hammer", "Small Shed Blueprint", "Mailbox Blueprint" })
		local plan = s.toolsIn(s.backpack)[2]
		t.eq(plan:GetAttribute("BlueprintId"), "Shed")
		t.eq(plan:GetAttribute("BlueprintUid"), "a")
	end)

	t.test("Grant adds one saved item and one Tool; a repeat, a known plan or a bad id is refused", function()
		local s = setup()
		s.Service.GiveLoadout(s.player, s.character)
		local item, why = s.Service.Grant(s.player, "Shed")
		t.ok(item ~= nil and why == nil)
		t.eq(#s.profile.blueprintItems, 1)
		t.eq(s.profile.blueprintItems[1].id, "Shed")
		t.eq(item.uid, s.profile.blueprintItems[1].uid)
		t.eq(#s.toolsIn(s.backpack), 2)
		local again, reason = s.Service.Grant(s.player, "Shed")
		t.eq(again, nil)
		t.eq(reason, "held")
		local bad, badReason = s.Service.Grant(s.player, "Nope")
		t.eq(bad, nil)
		t.eq(badReason, "unknown")
		local machine, machineReason = s.Service.Grant(s.player, "SawmillRickety")
		t.eq(machine, nil)
		t.eq(machineReason, "unknown")
		s.profile.blueprintBook = { "Mailbox" }
		local known, knownReason = s.Service.Grant(s.player, "Mailbox")
		t.eq(known, nil)
		t.eq(knownReason, "known")
		t.eq(#s.profile.blueprintItems, 1)
	end)

	t.test("a plan from the legacy set counts as known", function()
		local s = setup()
		s.profile.furnitureBlueprints = { Table = true }
		local item, why = s.Service.Grant(s.player, "Table")
		t.eq(item, nil)
		t.eq(why, "known")
	end)

	t.test("a full pack takes no more", function()
		local s = setup()
		local Book = s.loader:shared("BlueprintBook")
		for i = 1, Book.MaxItems do
			table.insert(s.profile.blueprintItems, { uid = "x" .. i, id = "Shed" })
		end
		local item, why = s.Service.Grant(s.player, "Mailbox")
		t.eq(item, nil)
		t.eq(why, "full")
	end)

	t.test("using the plan in your hand consumes it and teaches the book, for good", function()
		local s = setup()
		s.Service.GiveLoadout(s.player, s.character)
		local item = s.Service.Grant(s.player, "Shed")
		local plan = s.toolsIn(s.backpack)[2]
		s.equip(plan)
		s.remotes.UseBlueprint.OnServerEvent.fn(s.player, item.uid)
		t.eq(s.profile.blueprintBook, { "Shed" })
		t.eq(s.profile.blueprintItems, {})
		t.eq(plan.destroyed, true, "the physical item is gone")
		t.eq(s.attrs.Blueprints, "Shed")
		t.eq(s.toasts[#s.toasts].text, "You learned the Small Shed. It's in your hammer's list for good.")
	end)

	t.test("a plan in the Backpack (not in hand) cannot be used", function()
		local s = setup()
		local item = s.Service.Grant(s.player, "Shed")
		s.Service.Use(s.player, item.uid)
		t.eq(s.profile.blueprintBook, {})
		t.eq(#s.profile.blueprintItems, 1)
	end)

	t.test("a plan is used once: the same uid again does nothing", function()
		local s = setup()
		local item = s.Service.Grant(s.player, "Shed")
		s.equip(s.toolsIn(s.backpack)[1])
		s.Service.Use(s.player, item.uid)
		s.Service.Use(s.player, item.uid)
		t.eq(s.profile.blueprintBook, { "Shed" })
		t.eq(#s.toasts, 1, "only the first use says anything")
	end)

	t.test("using a plan for a building you know keeps the item", function()
		local s = setup()
		local item = s.Service.Grant(s.player, "Shed")
		s.profile.blueprintBook = { "Shed" }
		local plan = s.toolsIn(s.backpack)[1]
		s.equip(plan)
		s.Service.Use(s.player, item.uid)
		t.eq(#s.profile.blueprintItems, 1)
		t.eq(plan.destroyed, nil)
		t.ok(string.find(s.toasts[1].text, "already know", 1, true))
	end)

	t.test("what the client sends cannot get round it", function()
		local s = setup()
		local item = s.Service.Grant(s.player, "Shed")
		s.equip(s.toolsIn(s.backpack)[1])
		for _, junk in ipairs({ 12, true, {}, "someone-elses", "" }) do
			s.Service.Use(s.player, junk)
		end
		s.Service.Use(s.player, nil)
		t.eq(s.profile.blueprintBook, {})
		t.eq(#s.profile.blueprintItems, 1)
		s.rate(false)
		s.Service.Use(s.player, item.uid)
		t.eq(s.profile.blueprintBook, {}, "over its rate limit it does nothing")
		s.rate(true)
		s.Service.Use(s.player, item.uid)
		t.eq(s.profile.blueprintBook, { "Shed" })
	end)

	t.test("someone else's plan cannot be used or dropped by uid", function()
		local s = setup({ otherProfile = { hammer = true, blueprintBook = {}, blueprintItems = {} } })
		local item = s.Service.Grant(s.player, "Shed")
		s.equip(s.toolsIn(s.backpack)[1])
		s.Service.Use(s.other, item.uid)
		s.Service.Drop(s.other, item.uid)
		t.eq(#s.world, 0)
		t.eq(s.profile.blueprintBook, {})
	end)

	t.test("dropping lays the plan on the ground, still yours and still saved", function()
		local s = setup()
		local item = s.Service.Grant(s.player, "Shed")
		local tool = s.toolsIn(s.backpack)[1]
		s.remotes.DropBlueprint.OnServerEvent.fn(s.player, item.uid)
		t.eq(tool.destroyed, true)
		t.eq(#s.world, 1)
		t.eq(s.world[1]:GetAttribute("BlueprintUid"), item.uid)
		t.eq(s.world[1]:GetAttribute("OwnerId"), 42)
		t.eq(#s.profile.blueprintItems, 1)
		t.eq(s.Service.DroppedCount(s.player), 1)
		-- A plan on the ground is not in your hand, so it cannot be used.
		s.Service.Use(s.player, item.uid)
		t.eq(s.profile.blueprintBook, {})
		-- And it is not handed to you again by a respawn.
		s.Service.GiveLoadout(s.player, s.character)
		for _, tool2 in ipairs(s.toolsIn(s.backpack)) do
			t.ok(tool2:GetAttribute("BlueprintUid") ~= item.uid)
		end
	end)

	t.test("only the owner picks a dropped plan up, and it comes back as a Tool", function()
		local s = setup({ otherProfile = { hammer = true, blueprintBook = {}, blueprintItems = {} } })
		local item = s.Service.Grant(s.player, "Shed")
		s.Service.Drop(s.player, item.uid)
		local prompt
		for _, inst in ipairs(s.made) do
			if inst.ClassName == "ProximityPrompt" then
				prompt = inst
			end
		end
		t.ok(prompt ~= nil, "a Pick up prompt")
		t.eq(prompt.ActionText, "Pick up")
		prompt.Triggered.handlers[1](s.other)
		t.eq(s.Service.DroppedCount(s.player), 1, "someone else cannot take it")
		t.eq(s.toasts[#s.toasts].to, s.other)
		prompt.Triggered.handlers[1](s.player)
		t.eq(s.Service.DroppedCount(s.player), 0)
		t.eq(#s.toolsIn(s.backpack), 1)
		t.eq(s.toolsIn(s.backpack)[1]:GetAttribute("BlueprintUid"), item.uid)
		t.eq(#s.profile.blueprintItems, 1, "never duplicated")
	end)

	t.test("a plan too far away cannot be picked up", function()
		local s = setup()
		local item = s.Service.Grant(s.player, "Shed")
		s.Service.Drop(s.player, item.uid)
		local prompt
		for _, inst in ipairs(s.made) do
			if inst.ClassName == "ProximityPrompt" then
				prompt = inst
			end
		end
		s.player.Character.FindFirstChild = function()
			return { Position = Vector3.new(500, 3, 500) }
		end
		prompt.Triggered.handlers[1](s.player)
		t.eq(s.Service.DroppedCount(s.player), 1)
	end)

	t.test("at most ten lie around at once", function()
		local s = setup()
		local Book = s.loader:shared("BlueprintBook")
		local ids = {}
		for _, bp in ipairs(s.loader:shared("PlotData").Blueprints) do
			if #ids < s.Service.MaxDropped + 1 then
				table.insert(ids, bp.id)
			end
		end
		for _, id in ipairs(ids) do
			s.Service.Grant(s.player, id)
		end
		local uids = {}
		for _, item in ipairs(s.profile.blueprintItems) do
			table.insert(uids, item.uid)
		end
		for _, uid in ipairs(uids) do
			s.Service.Drop(s.player, uid)
		end
		t.eq(s.Service.DroppedCount(s.player), s.Service.MaxDropped)
		t.ok(Book.MaxItems >= #ids)
		t.ok(string.find(s.toasts[#s.toasts].text, "lying around", 1, true))
	end)

	t.test("leaving takes the world plans away; they stay in the save", function()
		local s = setup()
		local item = s.Service.Grant(s.player, "Shed")
		s.Service.Drop(s.player, item.uid)
		s.Service.PlayerRemoving(s.player)
		t.eq(s.Service.DroppedCount(s.player), 0)
		t.eq(s.world[1].destroyed, true)
		t.eq(#s.profile.blueprintItems, 1)
	end)

	t.test("a plan found in the world can be taken by anyone, once, and joins their pack", function()
		local s = setup()
		local model = s.Service.Spawn(Vector3.new(0, 0, 0), "Mailbox")
		t.ok(model ~= nil)
		t.eq(s.Service.Spawn(Vector3.new(0, 0, 0), "Nope"), nil)
		t.eq(s.Service.Spawn(Vector3.new(0, 0, 0), "SawmillRickety"), nil, "a machine is not a plan")
		local prompt
		for _, inst in ipairs(s.made) do
			if inst.ClassName == "ProximityPrompt" then
				prompt = inst
			end
		end
		prompt.Triggered.handlers[1](s.player)
		t.eq(#s.profile.blueprintItems, 1)
		t.eq(s.profile.blueprintItems[1].id, "Mailbox")
		t.eq(model.destroyed, true)
		-- A second tap on the same prompt finds it gone.
		prompt.Triggered.handlers[1](s.player)
		t.eq(#s.profile.blueprintItems, 1)
	end)

	t.test("a world plan for a building you know stays where it is", function()
		local s = setup()
		s.profile.blueprintBook = { "Mailbox" }
		local model = s.Service.Spawn(Vector3.new(0, 0, 0), "Mailbox")
		local prompt
		for _, inst in ipairs(s.made) do
			if inst.ClassName == "ProximityPrompt" then
				prompt = inst
			end
		end
		prompt.Triggered.handlers[1](s.player)
		t.eq(#s.profile.blueprintItems, 0)
		t.eq(model.destroyed, nil)
		t.ok(string.find(s.toasts[#s.toasts].text, "already know", 1, true))
	end)

	t.test("nothing in BlueprintService touches cash", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/ServerScriptService/BlueprintService.luau")
		t.eq(string.find(src, "EconomyService", 1, true), nil)
		t.eq(string.find(src, ".cash", 1, true), nil)
	end)
end
