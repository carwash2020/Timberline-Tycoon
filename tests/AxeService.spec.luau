--!nocheck
-- Dropping axes on the server (AxeService.Drop): it never drops the last
-- axe you have to hand, judged from the save and the server's own list of
-- dropped axes, whatever the client sends.
return function(t)
	local CFrame = t.roblox.CFrame

	-- A tool in a container (the character or the Backpack) that can be
	-- destroyed.
	local function container()
		local c = { kids = {} }
		function c:GetChildren()
			return table.clone(self.kids)
		end
		function c:FindFirstChildOfClass(class)
			if class == "Tool" then
				return self.kids[1]
			end
			return nil
		end
		return c
	end

	local function tool(item, where)
		local tl = { item = item, where = where, destroyed = false }
		function tl:IsA(class)
			return class == "Tool"
		end
		function tl:GetAttribute(key)
			if key == "AxeUid" then
				return self.item.uid
			elseif key == "AxeId" then
				return self.item.id
			end
			return nil
		end
		function tl:Destroy()
			self.destroyed = true
			local i = table.find(self.where.kids, self)
			if i then
				table.remove(self.where.kids, i)
			end
		end
		table.insert(where.kids, tl)
		return tl
	end

	-- `axes` are the saved items; the first is in hand, the rest in the
	-- Backpack.
	local function setup(axes)
		local profile = { axes = axes, bestAxeTier = 1, equippedAxe = "" }
		local character = container()
		local backpack = container()
		local hrp = { CFrame = CFrame.new(10, 3, 20) }
		function character:FindFirstChild(name)
			return if name == "HumanoidRootPart" then hrp else nil
		end
		local player = {
			Name = "Tester",
			DisplayName = "Tester",
			UserId = 42,
			Character = character,
			SetAttribute = function() end,
		}
		function player:FindFirstChildOfClass(class)
			return if class == "Backpack" then backpack else nil
		end
		local tools = {}
		for i, item in ipairs(axes) do
			tools[item.uid] = tool(item, if i == 1 then character else backpack)
		end

		local world = {} -- dropped models, in order
		local workspace = {
			Raycast = function()
				return nil
			end,
			FindFirstChild = function()
				return nil
			end,
		}
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
				-- The dropped axe's model (the real art is checked in AxeArt.spec).
				AxeArt = {
					Dropped = function(def)
						local model = { def = def, PrimaryPart = {}, attrs = {} }
						function model:SetAttribute(key, value)
							self.attrs[key] = value
						end
						table.insert(world, model)
						return model
					end,
				},
				Kit = { placeAt = function() end },
			},
			services = { Players = {}, TextChatService = {} },
			globals = {
				workspace = workspace,
				RaycastParams = {
					new = function()
						return {}
					end,
				},
				Instance = {
					new = function(class)
						assert(class == "ProximityPrompt", "only the pick-up prompt is made here")
						return { Triggered = { Connect = function() end } }
					end,
				},
			},
		})
		local AxeService = loader:server("AxeService")
		local toasts = {}
		AxeService.Init(function(_, message)
			table.insert(toasts, message)
		end)
		return {
			AxeService = AxeService,
			player = player,
			character = character,
			backpack = backpack,
			tools = tools,
			world = world,
			toasts = toasts,
			profile = profile,
		}
	end

	-- Puts axe `uid` in hand (from the Backpack), as equipping it does.
	local function hold(s, uid)
		local tl = s.tools[uid]
		local i = table.find(s.backpack.kids, tl)
		table.remove(s.backpack.kids, i)
		table.insert(s.character.kids, tl)
		tl.where = s.character
	end

	t.test("your only axe stays in hand: 'You need an axe to chop!'", function()
		local s = setup({ { uid = "rusty", id = "RustyAxe" } })
		s.AxeService.Drop(s.player, "rusty")
		t.eq(s.toasts, { "You need an axe to chop!" })
		t.eq(s.tools.rusty.destroyed, false)
		t.eq(#s.world, 0, "nothing on the ground")
		t.eq(#s.profile.axes, 1, "still owned")
	end)

	t.test("even when it's better than the starter", function()
		local s = setup({ { uid = "steel", id = "SteelAxe" } })
		s.AxeService.Drop(s.player, "steel")
		t.eq(s.toasts, { "You need an axe to chop!" })
		t.eq(s.tools.steel.destroyed, false)
		t.eq(#s.world, 0)
	end)

	t.test("with another axe in the Backpack, it drops (and stays yours)", function()
		local s = setup({ { uid = "steel", id = "SteelAxe" }, { uid = "rusty", id = "RustyAxe" } })
		s.AxeService.Drop(s.player, "steel")
		t.eq(s.toasts, {})
		t.eq(s.tools.steel.destroyed, true)
		t.eq(#s.world, 1)
		t.eq(s.world[1].attrs.AxeUid, "steel")
		t.eq(s.world[1].attrs.OwnerId, 42)
		t.eq(#s.profile.axes, 2, "a dropped axe is still in the save")
		t.eq(s.AxeService.GetEquippedAxe(s.player), nil, "not in hand any more")
	end)

	t.test("an axe lying on the ground doesn't count as one to hand", function()
		local s = setup({ { uid = "steel", id = "SteelAxe" }, { uid = "rusty", id = "RustyAxe" } })
		s.AxeService.Drop(s.player, "steel")
		hold(s, "rusty")
		s.AxeService.Drop(s.player, "rusty")
		t.eq(s.toasts, { "You need an axe to chop!" })
		t.eq(s.tools.rusty.destroyed, false)
		t.eq(#s.world, 1, "only the first one is down")
	end)

	t.test("a save entry for an axe that no longer exists isn't one to chop with", function()
		local s = setup({ { uid = "rusty", id = "RustyAxe" }, { uid = "gone", id = "NoSuchAxe" } })
		s.AxeService.Drop(s.player, "rusty")
		t.eq(s.toasts, { "You need an axe to chop!" })
		t.eq(s.tools.rusty.destroyed, false)
	end)

	t.test("what the client sends can't get round it", function()
		local s = setup({ { uid = "rusty", id = "RustyAxe" }, { uid = "steel", id = "SteelAxe" } })
		s.AxeService.Drop(s.player, 12)
		s.AxeService.Drop(s.player, nil)
		s.AxeService.Drop(s.player, "someone-elses")
		t.eq(#s.world, 0, "junk and other uids do nothing")
		t.eq(s.toasts, {})
		s.AxeService.Drop(s.player, "rusty")
		t.eq(#s.world, 1)
		s.AxeService.Drop(s.player, "rusty")
		t.eq(#s.world, 1, "the same axe twice: once")
	end)

	t.test("the Lux Axe can't be dropped, even with another axe to hand", function()
		local s = setup({ { uid = "lux", id = "LuxAxe" }, { uid = "rusty", id = "RustyAxe" } })
		s.AxeService.Drop(s.player, "lux")
		t.eq(#s.world, 0)
		t.eq(s.tools.lux.destroyed, false)
		t.eq(#s.profile.axes, 2)
		t.ok(string.find(s.toasts[1], "can't be dropped") ~= nil)
	end)
end
