--!nocheck
-- The Sky Forge's end game on the server, against mocks: tempering (exact
-- cost, one family, grades in order, Lux refused, nothing random, no
-- Robux), relics (once, wood and shards used, paid), the weekly order (paid
-- once, resets Monday 00:00 UTC), and range.
return function(t)
	local Vector3 = t.roblox.Vector3
	local MON = 1791158400 -- Monday 2026-10-05 00:00:00 UTC

	local function setup(opts)
		opts = opts or {}
		local profile = {
			cash = opts.cash or 500000,
			materials = { SkyShard = opts.shards or 100 },
			axes = opts.axes or { { uid = "u1", id = "SteelAxe" }, { uid = "lux", id = "LuxAxe" } },
			temper = opts.temper or {},
			relics = opts.relics or {},
			forgeOrder = opts.forgeOrder or { week = -1, delivered = {}, claimed = false },
			forgeWood = {},
		}
		local anvil = { Position = Vector3.new(0, 3, 0), Parent = true }
		function anvil:IsA(class)
			return class == "BasePart"
		end
		function anvil:FindFirstChild(name)
			return name == "SkyForgePoint" -- its prompt is already there
		end
		local root = { Position = Vector3.new(opts.distance or 5, 3, 0) }
		function root:IsA(class)
			return class == "BasePart"
		end
		local char = {}
		function char:FindFirstChild(name)
			return if name == "HumanoidRootPart" then root else nil
		end
		local attrs = {}
		local player = { UserId = 7, Name = "Ann", Character = char }
		function player:SetAttribute(k, v)
			attrs[k] = v
		end
		local w = { toasts = {}, taken = {}, spent = {}, paid = {}, forged = 0, pieces = opts.pieces or {} }
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				AxeService = {
					OwnedCounts = function()
						return {}, 0
					end,
				},
				AetherService = {
					Forge = function()
						w.forged += 1
					end,
				},
				HandInWood = {
					Near = function()
						local byUid = {}
						for _, c in ipairs(w.pieces) do
							byUid[c.uid] = c
						end
						return w.pieces, byUid
					end,
					Take = function(_, uids)
						for _, uid in ipairs(uids) do
							table.insert(w.taken, uid)
							for i, c in ipairs(w.pieces) do
								if c.uid == uid then
									table.remove(w.pieces, i)
									break
								end
							end
						end
						return 0
					end,
				},
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
				EconomyService = {
					SpendCash = function(_, amount)
						if profile.cash < amount then
							return false
						end
						profile.cash -= amount
						table.insert(w.spent, amount)
						return true
					end,
					AddCash = function(_, amount)
						profile.cash += amount
						table.insert(w.paid, amount)
						return amount, 0
					end,
				},
			},
			-- The map watchers wait for the world: not run here.
			globals = {
				task = { spawn = opts.spawn or function() end },
				workspace = opts.workspace or {
					FindFirstChild = opts.findFirstChild or function()
						return nil -- no plots here: the trophy step is skipped
					end,
				},
			},
			services = {
				CollectionService = {
					GetTagged = function()
						return { anvil }
					end,
					GetInstanceAddedSignal = function()
						return { Connect = function() end }
					end,
				},
				Players = {
					PlayerAdded = { Connect = function() end },
					GetPlayers = function()
						return {}
					end,
				},
			},
		})
		local S = loader:server("SkyForgeService")
		S._reset()
		S.Clock = function()
			return opts.now or (MON + 3600)
		end
		w.S, w.profile, w.player, w.attrs = S, profile, player, attrs
		-- notify: set through V1Init's ctx without binding remotes.
		S.V1Init({
			notify = function(_, text)
				table.insert(w.toasts, text)
			end,
		})
		S.Clock = function()
			return opts.now or (MON + 3600)
		end
		return w
	end

	local function piece(uid, woodId, volume, figure, kind)
		return {
			uid = uid,
			woodId = woodId,
			kind = kind or "plank",
			volume = volume,
			figure = figure,
			owner = 7,
			welded = false,
			held = false,
			distance = 3,
		}
	end

	t.test("the owner's plot is found where PlotService builds it: TimberlineMap/Plots", function()
		local asked = {}
		local plot = {
			IsA = function(_, kind)
				return kind == "Model"
			end,
			GetAttribute = function(_, key)
				return if key == "OwnerId" then 7 else nil
			end,
			FindFirstChild = function(_, name)
				table.insert(asked, name)
				return nil
			end,
		}
		local plots = {
			GetChildren = function()
				return { plot }
			end,
		}
		local map = {
			FindFirstChild = function(_, name)
				return if name == "Plots" then plots else nil
			end,
		}
		local w = setup({
			findFirstChild = function(_, name)
				return if name == "TimberlineMap" then map else nil -- (there is no Workspace/Plots)
			end,
		})
		w.S.BuildTrophies(w.player)
		t.ok(table.find(asked, "SignPost") ~= nil, "the trophy step reached the plot (it looked for the sign post)")
	end)

	-- Server audit leftover (11 October 2026): V1Init listened to every
	-- instance added anywhere under TimberlineMap (the forest plants ~1,400
	-- trees there) to catch the court's TemperSpot. Now it walks the map once
	-- and listens only to TownScenes, where MapBuilder puts the court.
	t.test("the map is walked once and only the town scenes are listened to, and the court's anvil is found", function()
		local function inst(class, name, parent)
			local i = { ClassName = class, Name = name, Parent = parent, kids = {} }
			function i:IsA(c)
				return c == class or (c == "BasePart" and class == "Part")
			end
			function i:FindFirstChild(n)
				return if n == "SkyForgePoint" then self.point else nil
			end
			function i:GetDescendants()
				return self.kids
			end
			return i
		end
		local listens = {}
		local function listener(name)
			return {
				Connect = function(_, fn)
					table.insert(listens, { on = name, fn = fn })
				end,
			}
		end
		local map = inst("Folder", "TimberlineMap")
		local oak = inst("Model", "Tree")
		local scenes = inst("Folder", "TownScenes", map)
		map.kids = { oak, scenes }
		map.DescendantAdded = listener("map")
		scenes.DescendantAdded = listener("scenes")
		map.WaitForChild = function(_, name)
			return if name == "TownScenes" then scenes else nil
		end
		local walks = { map = 0, scenes = 0 }
		local mapKids, sceneKids = map.GetDescendants, scenes.GetDescendants
		map.GetDescendants = function(self)
			walks.map += 1
			return mapKids(self)
		end
		scenes.GetDescendants = function(self)
			walks.scenes += 1
			return sceneKids(self)
		end
		local w
		w = setup({
			spawn = function(fn)
				fn()
			end,
			workspace = {
				FindFirstChild = function()
					return nil
				end,
				WaitForChild = function(_, name)
					return if name == "TimberlineMap" then map else nil
				end,
			},
		})
		t.eq(walks.map, 1, "the map is walked once")
		t.eq(#listens, 1)
		t.eq(listens[1].on, "scenes", "and only the town scenes are listened to")
		-- The court lands later: its anvil's TemperSpot is found.
		local anvil = t.roblox.Instance.new("Part")
		anvil.Name = "Anvil"
		anvil.Position = Vector3.new(500, 3, 0) -- far from the tagged anvil the setup stands at
		anvil.Parent = t.roblox.Instance.new("Folder")
		local spot = t.roblox.Instance.new("Attachment")
		spot.Name = "TemperSpot"
		spot.Parent = anvil
		local point = t.roblox.Instance.new("Attachment")
		point.Name = "SkyForgePoint" -- its prompt is already there (Lune has no ProximityPrompt events)
		point.Parent = anvil
		listens[1].fn(spot)
		w.player.Character.FindFirstChild = function(_, name)
			return if name == "HumanoidRootPart"
				then {
					Position = Vector3.new(502, 3, 0),
					IsA = function()
						return true
					end,
				}
				else nil
		end
		t.ok(w.S.AnvilNear(w.player) ~= nil)
	end)

	t.test("TemperSpot is made only by the court, which is placed in TownScenes", function()
		local fs = require("@lune/fs")
		local hits = 0
		for _, path in ipairs({
			"src/ReplicatedStorage/Shared/Art/BuildingArt.luau",
			"src/ReplicatedStorage/Shared/Art/PropArt.luau",
			"src/ServerScriptService/PlotService.luau",
			"src/ServerScriptService/MapBuilder.server.luau",
		}) do
			local source = fs.readFile(path)
			for _ in string.gmatch(source, "TemperSpot") do
				hits += 1
			end
		end
		t.eq(hits, 1, "one TemperSpot in the builders: the court's anvil")
		local map = fs.readFile("src/ServerScriptService/MapBuilder.server.luau")
		t.ok(string.find(map, 'folder.Name = "TownScenes"', 1, true), "the court's home folder")
		t.ok(string.find(map, "BuildingArt.SkyForgeCourt()", 1, true))
	end)

	t.test("tempering charges the exact cost and stamps the grade; nothing else moves", function()
		local w = setup({ shards = 20, pieces = { piece("g1", "phantomwood", 20), piece("g2", "phantomwood", 15) } })
		w.S.Temper(w.player, "u1", "Keen")
		t.eq(w.profile.temper.u1.prefix, "Keen")
		t.eq(w.profile.temper.u1.tier, 1)
		t.eq(w.spent[1], 20000, "grade I cash")
		t.eq(w.profile.materials.SkyShard, 14, "6 shards")
		t.eq(#w.taken, 2, "30 u³ of Gloamwood planks used up")
		t.ok(string.find(w.toasts[#w.toasts], "Keen I", 1, true) ~= nil, w.toasts[#w.toasts])
	end)

	t.test("grades go in order; a new family replaces the old at I; III is the top", function()
		local w = setup({
			temper = { u1 = { prefix = "Keen", tier = 2 } },
			pieces = { piece("l1", "lumenwood", 200) },
		})
		w.S.Temper(w.player, "u1", "Keen")
		t.eq(w.profile.temper.u1.tier, 3)
		t.eq(w.spent[1], 120000)
		w.S.Temper(w.player, "u1", "Keen")
		t.eq(w.profile.temper.u1.tier, 3, "no IV")
		t.eq(#w.spent, 1, "nothing charged for a refusal")
		w.pieces[1] = piece("g", "phantomwood", 30)
		w.S.Temper(w.player, "u1", "Heavy")
		t.eq(w.profile.temper.u1.prefix, "Heavy", "retemper replaces")
		t.eq(w.profile.temper.u1.tier, 1)
	end)

	t.test("refusals: short of cash, shards or planks, the Lux Axe, an axe you don't own, out of range", function()
		local w = setup({ cash = 100, pieces = { piece("g", "phantomwood", 30) } })
		t.eq(w.S.Temper(w.player, "u1", "Keen"), "Not enough cash.")
		local w2 = setup({ shards = 2, pieces = { piece("g", "phantomwood", 30) } })
		t.eq(w2.S.Temper(w2.player, "u1", "Keen"), "4 more Sky Shards needed.")
		local w3 = setup({ pieces = { piece("g", "phantomwood", 10) } })
		t.ok(string.find(w3.S.Temper(w3.player, "u1", "Keen"), "Gloamwood", 1, true) ~= nil)
		local w4 = setup({ pieces = { piece("g", "phantomwood", 30) } })
		t.eq(w4.S.Temper(w4.player, "lux", "Keen"), "That axe can't be tempered.")
		t.eq(w4.S.Temper(w4.player, "nope", "Keen"), nil, "not your axe")
		t.eq(w4.S.Temper(w4.player, "u1", "Swift"), nil, "not a temper")
		local far = setup({ distance = 60, pieces = { piece("g", "phantomwood", 30) } })
		t.eq(far.S.Temper(far.player, "u1", "Keen"), nil)
		for _, x in ipairs({ w, w2, w3, w4, far }) do
			t.eq(#x.spent, 0, "nothing charged")
			t.eq(x.profile.temper.u1, nil)
		end
	end)

	t.test("relics: one figured piece and shards, paid once, the attribute lists it", function()
		local w = setup({ shards = 10, pieces = { piece("f", "frostwood", 8, "curly", "log") } })
		w.S.Relic(w.player, "FrostRelic")
		t.eq(w.profile.relics.FrostRelic, true)
		t.eq(w.paid[1], 22500)
		t.eq(w.profile.materials.SkyShard, 6)
		t.eq(w.taken[1], "f")
		t.eq(w.attrs.Relics, "FrostRelic")
		w.pieces[1] = piece("f2", "frostwood", 8, "curly")
		w.S.Relic(w.player, "FrostRelic")
		t.eq(#w.paid, 1, "never twice")
		t.eq(#w.taken, 1)
		t.eq(w.S.Relic(w.player, "SunRelic"), nil)
		local plain = setup({ pieces = { piece("p", "emberwood", 8) } })
		t.ok(string.find(plain.S.Relic(plain.player, "EmberRelic"), "figured", 1, true) ~= nil)
		t.eq(#plain.paid, 0)
	end)

	t.test("weekly order: delivered planks add up, pay $18,000 + 4 shards once, reset Monday", function()
		local w = setup({ shards = 0, pieces = {} })
		local ForgeOrderLogic = t.shared("ForgeOrderLogic")
		local week = ForgeOrderLogic.WeekId(MON + 3600)
		local order = ForgeOrderLogic.OrderFor(week)
		local n = 0
		for id, need in pairs(order) do
			n += 1
			table.insert(w.pieces, piece("p" .. n, id, need))
		end
		w.S.Order(w.player)
		t.eq(w.paid[1], 18000)
		t.eq(w.profile.materials.SkyShard, 4)
		t.eq(w.profile.forgeOrder.claimed, true)
		w.S.Order(w.player)
		t.eq(#w.paid, 1, "once a week")
		local nextWeek = setup({ now = MON + 7 * 86400, forgeOrder = w.profile.forgeOrder })
		t.eq(nextWeek.S.View(nextWeek.player).order.claimed, false, "a new order on Monday")
	end)

	t.test("the view shows exact costs, results and refusals; Lux is not listed", function()
		local w = setup({ shards = 3 })
		local view = w.S.View(w.player)
		t.eq(#view.axes, 1, "the Lux Axe is not offered")
		local keen = view.axes[1].options[1]
		t.eq(keen.prefix, "Keen")
		t.eq(keen.tier, 1)
		t.eq(keen.effect, "Swings 8% faster")
		t.eq(keen.cost, "$20,000 + 6 Sky Shards + 30 Gloamwood planks")
		t.eq(keen.refusal, "3 more Sky Shards needed.")
		t.eq(#view.relics, 4)
		t.eq(view.shards, 3)
		t.ok(view.order.endsIn > 0 and view.order.endsIn <= 7 * 86400)
		-- Player text never says "u³" (repo rule).
		local function scan(v, path)
			if type(v) == "string" then
				t.ok(string.find(v, "u³", 1, true) == nil, path .. ": " .. v)
			elseif type(v) == "table" then
				for k, x in pairs(v) do
					scan(x, path .. "." .. tostring(k))
				end
			end
		end
		scan(view, "view")
		local poor = setup({ shards = 100, pieces = {} })
		scan(poor.S.View(poor.player), "short of planks")
	end)

	t.test("the Starfall row forges through AetherService, in range only", function()
		local w = setup()
		w.S.Act(w.player, "starfall")
		t.eq(w.forged, 1)
		local far = setup({ distance = 80 })
		far.S.Act(far.player, "starfall")
		t.eq(far.forged, 0)
		w.S.Act(w.player, "bogus")
		t.eq(w.forged, 1)
	end)
end
