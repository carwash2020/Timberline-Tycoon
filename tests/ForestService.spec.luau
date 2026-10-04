--!nocheck
-- The Living Forest on the server (ForestService), with TreeService, the
-- profiles, the remotes, the clock and the dice faked.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame

	local function setup()
		local base = t.loader()
		local Schema = base:server("ProfileSchema")
		local Util = base:shared("Util")
		local TreeArt = base:load("ReplicatedStorage/Shared/Art/TreeArt")
		local Kit = base:load("ReplicatedStorage/Shared/Art/Kit")
		local TreeLogic = base:shared("TreeLogic")
		local WoodData = base:shared("WoodData")

		local s = {
			profiles = {},
			byId = {},
			fxAll = {},
			fxOne = {},
			toasts = {},
			quest = {},
			daily = {},
			reveals = {},
			paid = {},
			delays = {},
			now = 1000,
			serverNow = 0, -- the day and night clock
			rolls = {}, -- queued dice; 0.5 once they run out (no figure, no lucky seed)
			allow = true,
		}

		-- Fake world: the workspace (attributes and the map folder).
		local workspace = roblox.Instance.new("Model")
		workspace.Name = "Workspace"
		local map = roblox.Instance.new("Folder")
		map.Name = "TimberlineMap"
		map.Parent = workspace
		s.workspace = workspace
		s.map = map
		-- A Lune Model rejects new methods, so the clock is a table that
		-- forwards attributes and the map folder to the Model. nightLeft
		-- reads WorldTime.Hour(), which asks GetServerTimeNow.
		local clockWorkspace = {
			GetServerTimeNow = function()
				return s.serverNow
			end,
			GetAttribute = function(_, name)
				return workspace:GetAttribute(name)
			end,
			SetAttribute = function(_, name, value)
				workspace:SetAttribute(name, value)
			end,
			FindFirstChild = function(_, name, recursive)
				return workspace:FindFirstChild(name, recursive)
			end,
		}

		-- Fake TreeService: records like the real one's.
		local trees, logs = {}, {}
		local counter = 0
		local TreeService = {}
		function TreeService.AllTrees()
			return trees
		end
		function TreeService.GetTree(uid)
			return trees[uid]
		end
		function TreeService.GetLog(uid)
			return logs[uid]
		end
		function TreeService.Decorate(uid, build)
			local rec = trees[uid]
			if rec then
				build(rec.model, rec)
			end
		end
		function TreeService.Forget() end
		function TreeService.Remove(uid)
			trees[uid] = nil
		end
		function TreeService.RegrowsIn(uid)
			local rec = trees[uid]
			return if rec and rec.felled then rec.regrowsIn else nil
		end
		function TreeService.Regrow(uid, planterId)
			local rec = trees[uid]
			if not rec or not rec.felled then
				return
			end
			rec.felled, rec.alive, rec.stump = false, true, nil
			rec.planterId = planterId
			rec.damageBy = {}
			rec.model:SetAttribute("PlanterId", planterId)
			if TreeService.OnRegrown then
				TreeService.OnRegrown(rec)
			end
		end
		function TreeService.SpawnTree(woodId, cf, opts)
			opts = opts or {}
			local def = WoodData.Get(woodId)
			local size = opts.size or TreeLogic.Sizes[2]
			counter += 1
			local uid = "tree" .. counter
			local model = TreeArt.Build(def, opts.seed or counter, size.scale)
			Kit.placeAt(model, CFrame.new(cf.Position))
			model:SetAttribute("Uid", uid)
			trees[uid] = {
				uid = uid,
				model = model,
				def = def,
				size = size,
				maxHp = TreeLogic.MaxHP(def.treeHP, size),
				hp = TreeLogic.MaxHP(def.treeHP, size),
				alive = true,
				base = cf.Position,
				parts = {},
				effects = {},
				felled = false,
				dormant = false,
				stump = nil,
				seed = opts.seed or counter,
				planterId = opts.planterId,
				damageBy = {},
				temporary = opts.temporary == true,
				growth = 0,
			}
			return model
		end
		s.trees, s.logs, s.TreeService = trees, logs, TreeService

		local Players = {
			GetPlayerByUserId = function(_, id)
				return s.byId[id]
			end,
			GetPlayers = function()
				local list = {}
				for _, p in pairs(s.byId) do
					table.insert(list, p)
				end
				return list
			end,
		}

		local fakeTask = {
			delay = function(seconds, fn, ...)
				table.insert(s.delays, { seconds = seconds, fn = fn, args = table.pack(...) })
			end,
			spawn = function(fn, ...)
				fn(...)
			end,
			wait = function()
				return 0
			end,
		}

		local loader = t.loader({
			mocks = {
				TreeService = TreeService,
				ProfileService = {
					GetProfile = function(p)
						return s.profiles[p]
					end,
				},
				EconomyService = {
					AddCash = function(p, amount, reason)
						local n = math.floor(amount)
						s.profiles[p].cash += n
						table.insert(s.paid, { player = p, amount = n, reason = reason })
						return n, 0
					end,
				},
				QuestService = {
					Event = function(p, event)
						table.insert(s.quest, { p, event })
					end,
				},
				DailyService = {
					Event = function(p, event, n)
						table.insert(s.daily, { p, event, n })
					end,
				},
				FieldGuideService = {
					RevealFigures = function(p, figures)
						table.insert(s.reveals, { p, figures })
					end,
				},
				RateLimiter = {
					Allow = function()
						return s.allow
					end,
				},
			},
			services = { Players = Players },
			globals = { workspace = clockWorkspace, task = fakeTask },
		})
		s.Forest = loader:server("ForestService")
		s.ForestData = loader:shared("ForestData")
		s.ForestLogic = loader:shared("ForestLogic")
		s.GameConfig = loader:shared("GameConfig")
		s.WorldTime = loader:shared("WorldTime")
		-- Noon, so a grove that only wakes at night stays asleep until a
		-- test sets the clock. Hour 0 would be midnight.
		s.serverNow = s.WorldTime.SecondsFromMidnight(12)
		s.WoodData = WoodData
		s.TreeLogic = TreeLogic

		function s.player(userId, name, pos)
			local root = { Position = pos or Vector3.new(0, 0, 0) }
			local p = {
				UserId = userId,
				Name = name,
				DisplayName = name,
				attrs = {},
				Character = {
					FindFirstChild = function(_, child)
						return if child == "HumanoidRootPart" then root else nil
					end,
				},
			}
			function p:SetAttribute(key, value)
				self.attrs[key] = value
			end
			function p:GetAttribute(key)
				return self.attrs[key]
			end
			p.root = root
			s.profiles[p] = Util.deepCopy(Schema.Template)
			-- Past Murph's tutorial, which keeps seeds until its plant step
			-- (tested on its own below).
			s.profiles[p].tutorialDone = true
			s.byId[userId] = p
			return p
		end

		function s.tree(woodId, pos, opts)
			local model = TreeService.SpawnTree(woodId, CFrame.new(pos or Vector3.new(0, 0, 0)), opts)
			return trees[model:GetAttribute("Uid")]
		end

		-- Fells a tree the way TreeService does: down, a stump, its logs,
		-- then the OnFelled hook.
		local logCounter = 0
		function s.fell(p, rec)
			rec.alive, rec.felled = false, true
			rec.growth += 1
			local stump = TreeArt.Stump(rec.def, rec.seed, rec.size.scale)
			Kit.placeAt(stump, CFrame.new(rec.base))
			rec.stump = stump
			local uids = {}
			for _ = 1, TreeLogic.LogCount(rec.def.logsPerTree, rec.size) do
				logCounter += 1
				local uid = "log" .. logCounter
				logs[uid] = {
					model = TreeArt.Log(rec.def, 3, 1.2),
					def = rec.def,
					ownerId = p.UserId,
					fellTime = os.time(),
					state = "world",
					despawnToken = 0,
					value = rec.def.pricePerLog,
					tags = {},
				}
				table.insert(uids, uid)
			end
			TreeService.OnFelled(p, rec, uids, Vector3.xAxis)
			return uids
		end

		function s.start()
			s.Forest.Init({
				WorldFX = {
					FireAllClients = function(_, kind, payload)
						table.insert(s.fxAll, { kind = kind, payload = payload })
					end,
					FireClient = function(_, p, kind, payload)
						table.insert(s.fxOne, { player = p, kind = kind, payload = payload })
					end,
				},
			}, function(p, message)
				table.insert(s.toasts, { player = p, message = message })
			end, {
				clock = function()
					return s.now
				end,
				serverTime = function()
					return s.serverNow
				end,
				random = function()
					return if #s.rolls > 0 then table.remove(s.rolls, 1) else 0.5
				end,
				manual = true,
			})
		end

		function s.runDelays()
			local due = s.delays
			s.delays = {}
			for _, d in ipairs(due) do
				d.fn(table.unpack(d.args, 1, d.args.n))
			end
		end

		function s.fxKinds(list)
			local kinds = {}
			for _, e in ipairs(list or s.fxAll) do
				table.insert(kinds, e.kind)
			end
			return kinds
		end

		function s.lastToast(p)
			for i = #s.toasts, 1, -1 do
				if s.toasts[i].player == p then
					return s.toasts[i].message
				end
			end
			return nil
		end

		function s.attr(name)
			return workspace:GetAttribute(name)
		end
		return s
	end

	local function find(model, name)
		return model:FindFirstChild(name, true)
	end

	t.test("Init: standing trees get their hidden figures, and the bloom starts at rest", function()
		local s = setup()
		local rec = s.tree("oak")
		s.rolls = { 0.01, 0.95, 0.9 } -- under 6%; a burl
		s.start()
		t.eq(s.attr("SkyrootBloom"), false)
		t.eq(s.attr("ElderUid"), "")
		local clue = rec.model:FindFirstChild("BarkClue")
		t.ok(clue ~= nil, "the burl shows on the bark")
		t.eq(clue:GetAttribute("Figure"), "burl")
		t.ok(s.TreeService.OnFelled ~= nil and s.TreeService.OnRegrown ~= nil, "hooks set")
	end)

	t.test("felling a figured tree: figured logs, seeds to the feller, the grove thins a little", function()
		local s = setup()
		local rec = s.tree("oak")
		s.rolls = { 0.01, 0.95, 0.9 }
		s.start()
		local a = s.player(1, "Ada")
		local uids = s.fell(a, rec)
		t.eq(#uids, 3)
		for _, uid in ipairs(uids) do
			local log = s.logs[uid]
			t.eq(log.value, 3 * 4, "a burl oak log sells for x4")
			t.eq(log.tags.figure, "burl")
			t.eq(log.model:GetAttribute("Figure"), "burl")
			t.ok(find(log.model, "FigureBand") ~= nil, "a coloured band on the log")
			t.ok(log.fellTime >= os.time() - 1, "the feller keeps the usual pickup grace")
		end
		t.eq(rec.model:FindFirstChild("BarkClue"), nil, "the clue goes with the tree")
		t.eq(s.profiles[a].heartseeds, nil, "felling grants no seeds")
	end)

	t.test("plain trees: plain logs; a large tree and a lucky roll add seeds", function()
		local s = setup()
		local rec = s.tree("pine", nil, { size = s.TreeLogic.Sizes[3] })
		s.start()
		local a = s.player(1, "Ada")
		s.rolls = { 0.1 } -- the seed roll: lucky
		local uids = s.fell(a, rec)
		t.eq(s.logs[uids[1]].value, 7)
		t.eq(s.logs[uids[1]].tags.figure, nil)
		t.eq(s.profiles[a].heartseeds, nil)
	end)

	t.test("felling grants no seeds and there is nothing to plant", function()
		local s = setup()
		local rec = s.tree("oak")
		s.start()
		local a = s.player(1, "Ada")
		s.fell(a, rec)
		t.eq(s.profiles[a].heartseeds, nil)
		t.eq(a.attrs.Seeds, nil)
		t.eq(s.plant, nil, "nothing to plant is connected")
		t.eq(rec.planterId, nil)
	end)

	t.test("lightning strikes the nearest standing tree; felled in time it's Stormgrain", function()
		local s = setup()
		local near = s.tree("oak", Vector3.new(30, 0, 0))
		local other = s.tree("oak", Vector3.new(50, 0, 0))
		s.tree("oak", Vector3.new(200, 0, 0))
		s.start()
		t.eq(s.Forest.Strike(Vector3.new(0, 0, 0)), near.uid)
		t.ok(near.model:FindFirstChild("StormGlow") ~= nil, "it glows")
		t.eq(s.fxKinds(), { "Struck" })
		t.eq(s.fxAll[1].payload.seconds, 120)
		t.eq(s.Forest.Strike(Vector3.new(0, 0, 0)), other.uid, "a struck tree isn't struck twice")
		t.eq(s.Forest.Strike(Vector3.new(-100, 0, 0)), nil, "nothing within 60 studs")
		local a = s.player(1, "Ada")
		local uids = s.fell(a, near)
		t.eq(s.logs[uids[1]].tags.figure, "stormgrain")
		t.eq(s.logs[uids[1]].value, 9)
		t.eq(s.profiles[a].heartseeds, nil)
		-- The other one's glow fades after two minutes: then it's plain wood.
		s.now += 121
		s.Forest.Tick(1)
		t.eq(other.model:FindFirstChild("StormGlow"), nil)
		local later = s.fell(a, other)
		t.eq(s.logs[later[1]].tags.figure, nil)
	end)

	local function elderSetup()
		local s = setup()
		s.start()
		-- Varied dice for the spot search.
		for i = 1, 400 do
			table.insert(s.rolls, (i * 0.6180339887) % 1)
		end
		local uid = s.Forest.WakeElder("hills")
		s.rolls = {}
		return s, uid
	end

	t.test("an Elder wakes: a giant, always figured, announced, marked", function()
		local s, uid = elderSetup()
		t.ok(uid ~= nil, "found a spot in the hills")
		local rec = s.trees[uid]
		t.eq(rec.size.name, "elder")
		t.eq(rec.size.scale, 1.7)
		t.ok(rec.temporary, "Elders never regrow")
		t.ok(rec.def.id == "pine" or rec.def.id == "maple")
		local clue = rec.model:FindFirstChild("BarkClue")
		local figure = clue and clue:GetAttribute("Figure")
		t.ok(figure == "quilted" or figure == "burl", "always quilted or burl")
		t.eq(s.attr("ElderUid"), uid)
		t.eq(s.attr("ElderBiome"), "hills")
		t.ok(typeof(s.attr("ElderPos")) == "Vector3")
		t.ok(s.map.ForestMarks:FindFirstChild("ElderAura") ~= nil)
		t.eq(s.fxKinds(), { "Elder" })
		t.eq(s.Forest.WakeElder("starter"), nil, "one at a time")
	end)

	t.test("felling an Elder together: helpers share 10% and 2 seeds, its logs are free to grab", function()
		local s, uid = elderSetup()
		local rec = s.trees[uid]
		local a = s.player(1, "Ada")
		local b = s.player(2, "Bo")
		local c = s.player(3, "Cy")
		rec.damageBy = { [1] = rec.maxHp * 0.6, [2] = rec.maxHp * 0.3, [3] = rec.maxHp * 0.05 }
		local figure = rec.model.BarkClue:GetAttribute("Figure")
		local uids = s.fell(a, rec)
		t.eq(#uids, 3 * rec.def.logsPerTree)
		for _, logUid in ipairs(uids) do
			local log = s.logs[logUid]
			t.eq(log.tags.figure, figure)
			t.ok(os.time() - log.fellTime >= s.GameConfig.PickupGraceSec, "anyone can grab it now")
		end
		local value = #uids * s.ForestLogic.LogValue(rec.def.pricePerLog, figure)
		local bonus = s.ForestLogic.HelperBonus(value)
		t.eq(s.profiles[a].cash, bonus)
		t.eq(s.profiles[b].cash, bonus)
		t.eq(s.profiles[c].cash, 0, "5% isn't helping")
		t.eq(s.profiles[a].forest.elders, 1)
		t.eq(s.profiles[b].forest.elders, 1)
		t.eq(s.profiles[a].heartseeds, nil, "helpers are paid in cash, not seeds")
		t.eq(s.attr("ElderUid"), "")
		t.eq(s.map.ForestMarks:FindFirstChild("ElderAura"), nil)
		local kinds = s.fxKinds()
		t.eq(kinds[#kinds], "ElderFallen")
	end)

	t.test("an Elder nobody fells fades after 15 minutes", function()
		local s, uid = elderSetup()
		s.now += 14 * 60
		s.Forest.Tick(0)
		t.ok(s.trees[uid] ~= nil, "still there at 14 minutes")
		s.now += 61
		s.Forest.Tick(0)
		t.eq(s.trees[uid], nil, "gone")
		t.eq(s.attr("ElderUid"), "")
		local kinds = s.fxKinds()
		t.eq(kinds[#kinds], "ElderFaded")
	end)

	t.test("the Skyroot blooms for 8 minutes, then rests 30, on the clock", function()
		local s = setup()
		s.start()
		t.eq(s.attr("SkyrootBloom"), false)
		s.Forest.Tick(0)
		t.eq(s.attr("SkyrootBloom"), false, "it starts in the rest")
		s.now += 30 * 60
		s.Forest.Tick(0)
		t.eq(s.attr("SkyrootBloom"), true)
		t.ok(math.abs(s.ForestLogic.FigureChance("Healthy", false, true) - 0.12) < 1e-9)
		s.now += 8 * 60
		s.Forest.Tick(0)
		t.eq(s.attr("SkyrootBloom"), false)
		s.now += 60
		s.Forest.Tick(0)
		t.eq(s.attr("SkyrootBloom"), false, "still resting")
		s.now += 29 * 60
		s.Forest.Tick(0)
		t.eq(s.attr("SkyrootBloom"), true, "the next bloom")
	end)

	t.test("a sale reveals its figures: the Field Guide, the daily goal, the stamp", function()
		local s = setup()
		s.start()
		local a = s.player(1, "Ada")
		s.Forest.OnSale(a, { burl = 2, curly = 1, bogus = 5 })
		t.eq(s.reveals, { { a, { burl = 2, curly = 1 } } })
		t.eq(s.daily, { { a, "figuredSold", 3 } })
		t.eq(#s.fxOne, 1)
		t.eq(s.fxOne[1].kind, "Reveal")
		t.eq(s.fxOne[1].payload.figures, { { figure = "curly", count = 1 }, { figure = "burl", count = 2 } })
		s.Forest.OnSale(a, {})
		t.eq(#s.fxOne, 1, "nothing figured, nothing to reveal")
	end)

	t.test("a regrown tree rolls a figure at the Healthy chance, planting or not", function()
		local s = setup()
		local rec = s.tree("oak")
		s.start()
		local a = s.player(1, "Ada")
		s.fell(a, rec)
		s.rolls = { 0.08, 0.5, 0.5 } -- over the flat 6%
		s.TreeService.Regrow(rec.uid)
		t.eq(rec.model:FindFirstChild("BarkClue"), nil, "8% misses")
		s.fell(a, rec)
		s.rolls = { 0.05, 0.5, 0.5 }
		s.TreeService.Regrow(rec.uid)
		local clue = rec.model:FindFirstChild("BarkClue")
		t.ok(clue ~= nil, "5% hits")
	end)

	t.test("a storm-struck tree felled in time stays Stormgrain even if the glow runs out while it falls", function()
		local s = setup()
		local rec = s.tree("oak", Vector3.new(10, 0, 0))
		s.start()
		t.eq(s.Forest.Strike(Vector3.new(0, 0, 0)), rec.uid)
		rec.alive, rec.felled = false, true -- the last swing: falling
		s.now += 121
		s.Forest.Tick(1)
		t.ok(rec.model:FindFirstChild("StormGlow") ~= nil, "still struck while it falls")
		local a = s.player(1, "Ada")
		local uids = s.fell(a, rec) -- it lands
		t.eq(s.logs[uids[1]].tags.figure, "stormgrain")
		t.eq(s.profiles[a].heartseeds, nil)
		t.eq(rec.model:FindFirstChild("StormGlow"), nil)
	end)

	local function golden(s)
		for i = 1, 400 do
			table.insert(s.rolls, (i * 0.6180339887) % 1)
		end
	end

	t.test("a Phantom Grove Elder fades at dawn with its grove", function()
		local s = setup()
		s.start()
		golden(s)
		local uid = s.Forest.WakeElder("grove")
		s.rolls = {}
		t.ok(uid ~= nil, "found a spot in the grove")
		t.eq(s.attr("ElderBiome"), "grove")
		s.trees[uid].dormant = true -- dawn (TreeService.SetBiomeDormant)
		s.Forest.Tick(0)
		t.eq(s.trees[uid], nil, "gone with the night")
		t.eq(s.attr("ElderUid"), "")
		t.eq(s.map.ForestMarks:FindFirstChild("ElderAura"), nil, "its aura too")
		local kinds = s.fxKinds()
		t.eq(kinds[#kinds], "ElderFaded")
		t.eq(s.Forest.ElderUid(), nil, "another grove may wake one")
	end)

	t.test("the Phantom Grove only wakes an Elder with four minutes of the night left", function()
		local s = setup()
		s.tree("phantomwood")
		s.start()
		s.workspace:SetAttribute("IsNight", true)
		-- Night is 19:00 to 05:00. Ask the clock (a 24-minute day, faster
		-- after 20:00) for a moment with under five minutes left, and for dusk.
		local WorldTime = s.WorldTime
		s.serverNow = WorldTime.SecondsFromMidnight(4.5)
		local left = WorldTime.SecondsUntilChange(s.serverNow)
		t.ok(WorldTime.IsNight(WorldTime.ClockTime(s.serverNow)), "still night at 04:30")
		t.ok(left < 5 * 60, "under five minutes to dawn: " .. left)
		s.now += 20 * 60
		s.rolls = { 0.5, 0.95, 0 } -- interval, then a pick aimed at the hollow, then wake
		s.Forest.Tick(0)
		t.ok(s.attr("ElderBiome") ~= "grove", "too close to dawn for the hollow")
		s.serverNow = WorldTime.SecondsFromMidnight(19)
		left = WorldTime.SecondsUntilChange(s.serverNow)
		t.ok(WorldTime.IsNight(WorldTime.ClockTime(s.serverNow)), "night at 19:00")
		t.ok(left >= 5 * 60, "the night just started: " .. left)
		s.now += 20 * 60
		-- The dawn check may have woken another grove. Let it fade, then aim at the hollow.
		local woke = s.Forest.ElderUid()
		if woke then
			s.trees[woke].dormant = true
			s.Forest.Tick(0) -- fades it; that tick can also spend the next check
		end
		-- Past the window the fade tick just armed, so this tick actually checks.
		s.now += 20 * 60
		s.rolls = { 0.5, 0.95, 0 }
		golden(s)
		s.Forest.Tick(0)
		t.ok(s.Forest.ElderUid() ~= nil, "an Elder wakes at dusk")
		t.eq(s.attr("ElderBiome"), "grove")
	end)

	t.test("an Elder never stands on a homestead square", function()
		local s = setup()
		s.start()
		local PlotData = t.shared("PlotData")
		local home = PlotData.Homes[1]
		t.ok(not s.Forest.ElderGround(home.x, home.z), home.id)
	end)
end
