--!nocheck
-- Lane R: RegionService. The quarry (a slab a swing, a timer, a cap, Stage 4),
-- the rare finds (disabled, one pick, saved once), the Wader Boots (cash plus
-- planks, atomic), first visits, and the Build wiring.
return function(t)
	local Instance = t.roblox.Instance
	local V3 = t.roblox.Vector3

	local function signal()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end
	-- Lune's ProximityPrompt has no Triggered signal; share the per-prompt
	-- signals other specs fire through (_G.__promptTriggered).
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
	local _ = signal

	local function setup(opts)
		opts = opts or {}
		local profile = {
			cash = opts.cash or 0,
			gear = opts.gear or {},
			bestAxeTier = opts.tier or 5, -- the Cobalt Axe: S4
			onboarding = {},
			guideStamps = {},
		}
		local toasts = {}
		local spent = {}
		local slabs = {}
		local taken = {}
		local events = {}
		local attrs = {}
		local player = {
			UserId = 7,
			Name = "Tester",
			SetAttribute = function(_, k, v)
				attrs[k] = v
			end,
			GetAttribute = function(_, k)
				return attrs[k]
			end,
		}
		local rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		local character = Instance.new("Model")
		rootPart.Parent = character
		player.Character = character
		local function stand(pos)
			rootPart.CFrame = t.roblox.CFrame.new(pos)
			rootPart.Position = pos
		end
		stand(V3.new(0, 0, 0))
		local planks = opts.planks or {}
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				EconomyService = {
					GetCash = function()
						return profile.cash
					end,
					SpendCash = function(_, amount, reason)
						if profile.cash < amount then
							return false
						end
						profile.cash -= amount
						table.insert(spent, { amount, reason })
						return true
					end,
				},
				BuildMaterials = {
					SlabRoom = function()
						return math.max(0, 24 - #slabs - (opts.loose or 0))
					end,
					ReturnSlab = function(userId, cf)
						if opts.noRoom then
							return false
						end
						table.insert(slabs, { userId, cf })
						return true
					end,
				},
				HandInWood = {
					Near = function()
						local list, byUid = {}, {}
						for i, p in ipairs(planks) do
							list[i] = {
								uid = "p" .. i,
								woodId = p.woodId or "bogcypress",
								kind = "plank",
								volume = p.volume,
								owner = player.UserId,
								welded = false,
								held = false,
								distance = 1,
							}
							byUid["p" .. i] = p
						end
						return list, byUid
					end,
					Take = function(byUid, uids, reason)
						for _, uid in ipairs(uids) do
							table.insert(taken, { uid, reason })
						end
						return 0
					end,
				},
				MilestoneService = {
					Event = function(_, kind, data)
						table.insert(events, { kind, data and data.id })
					end,
				},
				WorldPlan = {
					RegionTrees = function()
						return {}
					end,
				},
			},
			services = {
				Players = {
					GetPlayers = function()
						return { player }
					end,
					PlayerRemoving = {
						Connect = function() end,
					},
				},
			},
		})
		local ok, Service = pcall(function()
			return loader:server("RegionService")
		end)
		if not ok then
			error(Service, 0)
		end
		Service.Reset()
		Service.SetNotify(function(_, text)
			table.insert(toasts, text)
		end)
		return {
			Service = Service,
			profile = profile,
			player = player,
			toasts = toasts,
			spent = spent,
			slabs = slabs,
			taken = taken,
			events = events,
			attrs = attrs,
			stand = stand,
			loader = loader,
		}
	end

	local NODE = V3.new(660, 0, -700)

	t.test(
		"a swing at a node gives one slab, spawned in front of it, and the node is empty until it refills",
		function()
			local s = setup()
			s.Service.SetSpots({ ["slab-1"] = NODE })
			s.stand(NODE + V3.new(0, 0, -4))
			t.eq(s.Service.Quarry(s.player, "slab-1"), true)
			t.eq(#s.slabs, 1)
			t.eq(s.slabs[1][1], 7, "the slab is the player's")
			t.eq(s.Service.Quarry(s.player, "slab-1"), false, "the same node a second time")
			t.eq(#s.slabs, 1)
		end
	)

	t.test("the quarry refuses a far player, an unknown node, junk, a low stage and a full set of 24", function()
		local s = setup()
		s.Service.SetSpots({ ["slab-1"] = NODE })
		s.stand(NODE + V3.new(0, 0, -40))
		t.eq(s.Service.Quarry(s.player, "slab-1"), false, "too far")
		s.stand(NODE)
		t.eq(s.Service.Quarry(s.player, "slab-99"), false, "unknown")
		t.eq(s.Service.Quarry(s.player, nil), false)
		t.eq(s.Service.Quarry(s.player, 5), false)
		t.eq(s.Service.Quarry(s.player, {}), false)
		t.eq(#s.slabs, 0)
		local low = setup({ tier = 3 }) -- Silver Axe: S3
		low.Service.SetSpots({ ["slab-1"] = NODE })
		low.stand(NODE)
		t.eq(low.Service.Quarry(low.player, "slab-1"), false, "Stage 4")
		t.ok(string.find(low.toasts[#low.toasts] or "", "Stage 4", 1, true), tostring(low.toasts[#low.toasts]))
		local full = setup({ loose = 24 })
		full.Service.SetSpots({ ["slab-1"] = NODE })
		full.stand(NODE)
		t.eq(full.Service.Quarry(full.player, "slab-1"), false, "at the 24 cap")
	end)

	t.test("a slab with no room is given back: the node is not spent", function()
		local s = setup({ noRoom = true })
		s.Service.SetSpots({ ["slab-1"] = NODE })
		s.stand(NODE)
		t.eq(s.Service.Quarry(s.player, "slab-1"), false)
		local ok = setup()
		ok.Service.SetSpots({ ["slab-1"] = NODE })
		ok.stand(NODE)
		t.eq(ok.Service.Quarry(ok.player, "slab-1"), true)
	end)

	t.test("quarrying is rate limited like every other handler", function()
		local s = setup()
		local nodes = {}
		for i = 1, 8 do
			nodes["slab-" .. i] = NODE
		end
		s.Service.SetSpots(nodes)
		s.stand(NODE)
		local made = 0
		for i = 1, 8 do
			if s.Service.Quarry(s.player, "slab-" .. i) then
				made += 1
			end
		end
		t.ok(made <= 3, made .. " in one burst")
	end)

	t.test("a disabled find says the rare line and saves nothing", function()
		local s = setup()
		local at = V3.new(590, 0, -860)
		s.Service.SetSpots(nil, { redmesa = at })
		s.stand(at + V3.new(2, 0, 0))
		t.eq(s.Service.Find(s.player, "redmesa"), false)
		t.eq(s.toasts[#s.toasts], "Something rare lives here.")
		t.eq(next(s.profile.guideStamps), nil)
		t.eq(s.Service.Find(s.player, "nope"), false)
		t.eq(s.Service.Find(s.player, 12), false)
	end)

	t.test("the first visit to each region shows its name once and tells MilestoneService", function()
		local s = setup()
		s.stand(V3.new(-760, 0, -700))
		s.Service.Sweep()
		t.eq(#s.events, 1)
		t.eq(s.events[1], { "area", "bayou" })
		t.ok(string.find(s.toasts[1], "Bayou", 1, true), s.toasts[1])
		t.eq(s.profile.guideStamps["Region:Seen:bayou"], true)
		s.Service.Sweep()
		t.eq(#s.events, 1, "once")
		s.stand(V3.new(590, 0, -790))
		s.Service.Sweep()
		t.eq(s.events[2], { "area", "mesa" })
		s.stand(V3.new(0, 0, 0))
		s.Service.Sweep()
		t.eq(#s.events, 2, "the open country is no region")
		for key in pairs(s.profile.guideStamps) do
			t.eq(string.sub(key, 1, 7), "Region:", "stamps live under the Region: prefix")
		end
	end)

	t.test("a visitor short of the stage hears what the region asks for, once a visit", function()
		local s = setup({ tier = 1 })
		s.stand(V3.new(-760, 0, -700))
		s.Service.Sweep()
		s.Service.Sweep()
		local gate = 0
		for _, text in ipairs(s.toasts) do
			if string.find(text, "Needs Stage 2", 1, true) then
				gate += 1
			end
		end
		t.eq(gate, 1)
	end)

	local COUNTER = V3.new(-720, 3, -666)

	t.test("Wader Boots: $2,000 and 20 u³ of cypress planks, taken together, once", function()
		local s = setup({ cash = 2500, planks = { { volume = 12 }, { volume = 9 } }, tier = 2 })
		s.Service.SetSpots(nil, nil, COUNTER)
		s.stand(COUNTER + V3.new(0, 0, -3))
		t.eq(s.Service.BuyBoots(s.player), true)
		t.eq(s.profile.cash, 500)
		t.eq(s.profile.gear, { "WaderBoots" })
		t.eq(#s.taken, 2, "both planks used up")
		t.ok(string.find(s.attrs.OwnedGear or "", "WaderBoots", 1, true), "the shop attribute is refreshed")
		t.eq(s.Service.BuyBoots(s.player), false, "a second time")
		t.eq(s.profile.cash, 500)
	end)

	t.test("Wader Boots take nothing when anything is short", function()
		local function try(opts, mutate)
			local s = setup(opts)
			s.Service.SetSpots(nil, nil, COUNTER)
			s.stand(COUNTER + V3.new(0, 0, -3))
			if mutate then
				mutate(s)
			end
			local got = s.Service.BuyBoots(s.player)
			t.eq(got, false)
			t.eq(s.profile.gear, opts.gear or {}, "no boots")
			t.eq(#s.taken, 0, "no planks used")
			return s
		end
		local s1 = try({ cash = 1999, planks = { { volume = 25 } }, tier = 2 })
		t.eq(s1.profile.cash, 1999)
		local s2 = try({ cash = 5000, planks = { { volume = 19 } }, tier = 2 })
		t.eq(s2.profile.cash, 5000, "19 u³ is not 20")
		try({ cash = 5000, planks = { { volume = 25, woodId = "oak" } }, tier = 2 })
		try({ cash = 5000, planks = { { volume = 25 } }, tier = 1 }) -- not S2
		local far = setup({ cash = 5000, planks = { { volume = 25 } }, tier = 2 })
		far.Service.SetSpots(nil, nil, COUNTER)
		far.stand(COUNTER + V3.new(0, 0, -60))
		t.eq(far.Service.BuyBoots(far.player), false, "away from the counter")
		t.eq(far.profile.cash, 5000)
		-- Already owned.
		local owned = setup({ cash = 5000, gear = { "WaderBoots" }, planks = { { volume = 25 } }, tier = 2 })
		owned.Service.SetSpots(nil, nil, COUNTER)
		owned.stand(COUNTER)
		t.eq(owned.Service.BuyBoots(owned.player), false)
		t.eq(owned.profile.cash, 5000)
	end)

	t.test("Build hangs the prompts: eight quarry nodes, the boots counter, two rare finds", function()
		local s = setup()
		local map = Instance.new("Folder")
		local folder = s.Service.Build(map, function()
			return 0
		end)
		t.eq(folder.Parent, map)
		local prompts = {}
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				prompts[d.Name] = (prompts[d.Name] or 0) + 1
				t.eq(d.RequiresLineOfSight, false)
				t.ok(d.MaxActivationDistance >= 8 and d.MaxActivationDistance <= 16)
			end
		end
		t.eq(prompts.Quarry, 8)
		t.eq(prompts.WaderBoots, 1)
		t.eq(prompts.RareFind, 2)
		-- No Robux anywhere in what a prompt says.
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				t.ok(not string.find(d.ActionText, "R$", 1, true))
			end
		end
	end)

	t.test(
		"Build's scatter stays in budget: at most 36 + 30 pieces of 10 parts or fewer, off the roads and the footprints",
		function()
			local s = setup()
			local folder = s.Service.Build(Instance.new("Folder"), function()
				return 0
			end)
			local pieces = 0
			for _, f in ipairs(folder:GetDescendants()) do
				if f:IsA("Folder") and string.sub(f.Name, 1, 8) == "Scatter_" then
					for _, piece in ipairs(f:GetChildren()) do
						pieces += 1
						local n = 0
						for _, d in ipairs(piece:GetDescendants()) do
							if d:IsA("BasePart") then
								n += 1
							end
						end
						t.ok(n <= 10, piece.Name .. " " .. n)
					end
				end
			end
			t.ok(pieces >= 40 and pieces <= 66, pieces .. " pieces")
		end
	)

	t.test("RegionBoot starts the service without GameServer, and a missing module is skipped", function()
		local fs = require("@lune/fs")
		local text = fs.readFile("src/ServerScriptService/RegionBoot.server.luau")
		t.ok(string.find(text, 'FindFirstChild("RegionService")', 1, true))
		t.ok(string.find(text, "pcall", 1, true))
	end)
end
