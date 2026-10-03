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
				SectionTrees = TreeService,
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
			globals = { workspace = workspace, task = fakeTask },
		})
		s.Forest = loader:server("ForestService")
		s.ForestData = loader:shared("ForestData")
		s.ForestLogic = loader:shared("ForestLogic")
		s.GameConfig = loader:shared("GameConfig")
		s.WorldTime = loader:shared("WorldTime")
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
				PlantSeed = {
					OnServerEvent = {
						Connect = function(_, fn)
							s.plant = fn
						end,
					},
				},
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

	t.test("Init: groves start at 60 (Healthy), standing trees get their hidden figures", function()
		local s = setup()
		local rec = s.tree("oak")
		s.rolls = { 0.01, 0.95, 0.9 } -- under 6%; a burl
		s.start()
		t.eq(s.attr("Vitality_starter"), 60)
		t.eq(s.attr("VitalityTier_starter"), "Healthy")
		t.eq(s.attr("Vitality_grove"), 60)
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
		t.eq(s.profiles[a].heartseeds.oak, 1)
		t.eq(a.attrs.Seeds_oak, 1)
		t.eq(a.attrs.Heartseeds, 1)
		t.eq(s.fxKinds(), { "SeedPop" })
		t.eq(s.fxAll[1].payload.userId, 1)
		t.eq(s.attr("Vitality_starter"), 58.5, "a wild tree costs 1.5")
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
		t.eq(s.profiles[a].heartseeds.pine, 3, "1 + large + lucky")
		t.eq(s.fxAll[1].payload.reasons, { "big tree", "lucky" })
		t.eq(s.attr("Vitality_hills"), 58.5)
	end)

	t.test("the pouch is capped: a full wood says so", function()
		local s = setup()
		local rec = s.tree("oak")
		s.start()
		local a = s.player(1, "Ada")
		s.profiles[a].heartseeds.oak = 50
		s.fell(a, rec)
		t.eq(s.profiles[a].heartseeds.oak, 50)
		t.ok(string.find(s.lastToast(a), "pouch is full") ~= nil)
		t.eq(s.fxKinds(), {}, "no seed flies when none fit")
	end)

	t.test("PlantSeed checks everything, then sprouts, regrows the tree as yours and puts up a stake", function()
		local s = setup()
		local rec = s.tree("oak", Vector3.new(10, 0, 10))
		local elderStump = s.tree("oak", Vector3.new(60, 0, 60), { temporary = true })
		s.start()
		local a = s.player(1, "Ada", Vector3.new(14, 0, 10))
		local b = s.player(2, "Bo", Vector3.new(12, 0, 12))
		local far = s.player(3, "Cy", Vector3.new(40, 0, 10))
		s.fell(a, rec)
		s.fell(a, elderStump)
		s.fxAll = {}
		s.plant(a, 42) -- not a uid
		s.plant(b, rec.uid) -- no oak seed
		t.ok(string.find(s.lastToast(b), "no oak Heartseeds") ~= nil)
		s.profiles[far].heartseeds.oak = 1
		s.plant(far, rec.uid)
		t.ok(string.find(s.lastToast(far), "Walk closer") ~= nil)
		t.eq(s.profiles[far].heartseeds.oak, 1)
		s.plant(a, elderStump.uid)
		t.eq(s.profiles[a].heartseeds.oak, 2, "not in an Elder's stump")
		s.allow = false
		s.plant(a, rec.uid)
		t.eq(s.profiles[a].heartseeds.oak, 2, "rate limited")
		s.allow = true

		local before = s.attr("Vitality_starter")
		s.plant(a, rec.uid)
		t.eq(s.profiles[a].heartseeds.oak, 1)
		t.eq(a.attrs.Seeds_oak, 1)
		t.eq(s.profiles[a].forest.planted, 1)
		t.eq(s.attr("Vitality_starter"), before + 4)
		t.eq(s.quest, { { a, "seedPlanted" } })
		t.eq(s.daily, { { a, "seedPlanted", 1 } })
		t.eq(s.fxKinds(), { "Sprout" })
		t.eq(s.fxAll[1].payload.uid, rec.uid)
		t.eq(s.fxAll[1].payload.seconds, 8)
		t.eq(#s.delays, 1)
		t.eq(s.delays[1].seconds, 8)
		t.ok(rec.felled, "still a stump while the sapling sprouts")
		s.plant(a, rec.uid)
		t.ok(string.find(s.lastToast(a), "already sprouting") ~= nil)
		t.eq(s.profiles[a].heartseeds.oak, 1, "the second try costs nothing")

		s.runDelays()
		t.ok(not rec.felled, "standing again")
		t.eq(rec.planterId, 1)
		local marks = s.map:FindFirstChild("ForestMarks")
		local stake = marks and marks:FindFirstChild("NameStake")
		t.ok(stake ~= nil, "a name stake at its foot")
		t.eq(stake:GetAttribute("TreeUid"), rec.uid)
		t.eq(stake:GetAttribute("PlanterId"), 1)
		local board = find(stake, "Board")
		t.ok(board ~= nil and find(board, "TextLabel").Text == "Ada", "it says who planted it")
	end)

	t.test("Murph's tutorial: no planting before its plant step, and the seed is kept", function()
		local s = setup()
		local rec = s.tree("oak", Vector3.new(10, 0, 10))
		s.start()
		local TutorialData = t.shared("TutorialData")
		local a = s.player(1, "Ada", Vector3.new(12, 0, 10))
		local profile = s.profiles[a]
		profile.tutorialDone = false
		s.fell(a, rec)
		t.eq(profile.heartseeds.oak, 1)
		s.fxAll = {}
		for step = 1, TutorialData.PlantStep - 1 do
			profile.tutorialStep = step
			a.attrs.TutorialStep = TutorialData.PlantStep -- the client's word counts for nothing
			s.plant(a, rec.uid)
			t.eq(s.lastToast(a), "Hang onto it: Murph will show you where.", "step " .. step)
			t.eq(profile.heartseeds.oak, 1, "the seed is kept")
			t.eq(profile.forest.planted, 0)
			t.eq(s.fxKinds(), {}, "nothing sprouts")
			t.eq(s.quest, {})
			t.ok(rec.felled and rec.stump ~= nil, "the stump waits")
		end
		profile.tutorialStep = TutorialData.PlantStep
		s.plant(a, rec.uid)
		t.eq(profile.heartseeds.oak, nil, "at the plant step it goes in")
		t.eq(s.fxKinds(), { "Sprout" })
		t.eq(s.quest, { { a, "seedPlanted" } })
	end)

	t.test("players who skipped the tutorial (or are past its plant step) plant as before", function()
		local s = setup()
		local one = s.tree("oak", Vector3.new(10, 0, 10))
		local two = s.tree("oak", Vector3.new(-10, 0, -10))
		s.start()
		local skipped = s.player(1, "Ada", Vector3.new(12, 0, 10))
		s.profiles[skipped].tutorialStep = 2 -- skipped on step 2
		s.profiles[skipped].tutorialDone = true
		local later = s.player(2, "Bo", Vector3.new(-12, 0, -10))
		s.profiles[later].tutorialDone = false
		s.profiles[later].tutorialStep = 6 -- selling loads, after planting
		s.fell(skipped, one)
		s.fell(later, two)
		s.fxAll = {}
		s.plant(skipped, one.uid)
		s.plant(later, two.uid)
		t.eq(s.profiles[skipped].heartseeds.oak, nil, "planted")
		t.eq(s.profiles[later].heartseeds.oak, nil, "planted")
		t.eq(s.fxKinds(), { "Sprout", "Sprout" })
	end)

	t.test("a tree that grew back on its own while sprouting is still yours, from then on", function()
		local s = setup()
		local rec = s.tree("oak")
		s.start()
		local a = s.player(1, "Ada")
		local b = s.player(2, "Bo")
		s.fell(a, rec)
		s.plant(a, rec.uid)
		s.TreeService.Regrow(rec.uid) -- its natural regrowth came first
		t.eq(rec.planterId, 1, "the sapling took")
		t.eq(rec.model:GetAttribute("PlanterId"), 1)
		t.ok(s.map.ForestMarks:FindFirstChild("NameStake") ~= nil)
		-- Felled again before the sprout's timer: the planter's share, and the
		-- old timer doesn't pop it back up.
		s.fell(b, rec)
		t.eq(#s.paid, 1, "Ada's share")
		s.runDelays()
		t.ok(rec.felled, "still down: that sapling was used up")
	end)

	t.test("a sprout never pops up a tree felled again since (not even mid-fall)", function()
		local s = setup()
		local rec = s.tree("oak")
		s.start()
		local a = s.player(1, "Ada")
		local b = s.player(2, "Bo")
		s.fell(a, rec)
		s.plant(a, rec.uid)
		-- It stood up again unseen by the hooks and was felled again: still
		-- falling (no stump yet) when the sapling's timer runs.
		rec.felled, rec.alive, rec.stump = false, true, nil
		rec.alive, rec.felled = false, true
		rec.growth += 1
		s.runDelays()
		t.ok(rec.felled, "it stays down and lands as felled")
		t.eq(rec.planterId, nil)
		-- Its new stump takes a seed again.
		s.fell(b, rec)
		s.plant(b, rec.uid)
		t.eq(s.profiles[b].heartseeds.oak, nil, "Bo planted the seed it gave")
		s.runDelays()
		t.ok(not rec.felled)
		t.eq(rec.planterId, 2)
	end)

	t.test("the planter's share: someone else fells your tree, you earn 15% of its base value", function()
		local s = setup()
		local rec = s.tree("pine", nil, { planterId = 1 })
		s.start()
		local a = s.player(1, "Ada")
		local b = s.player(2, "Bo")
		s.fell(b, rec)
		local share = s.ForestLogic.Royalty(7, 5)
		t.eq(share, 5)
		t.eq(s.profiles[a].cash, share)
		t.eq(s.profiles[a].forest.harvested, 1)
		t.eq(s.profiles[a].forest.royalties, share)
		t.eq(s.profiles[b].cash, 0, "the feller loses nothing (paid at the mill as usual)")
		t.eq(s.profiles[b].heartseeds.pine, 1, "no steward's bonus for someone else's tree")
		t.eq(#s.fxOne, 1)
		t.eq(s.fxOne[1].player, a)
		t.eq(s.fxOne[1].kind, "Royalty")
		t.eq(s.fxOne[1].payload, { woodId = "pine", feller = "Bo", amount = share })
		t.eq(s.attr("Vitality_hills"), 59.5, "a planted tree costs the grove 0.5")
	end)

	t.test("your own planted tree: the steward's seed instead of a share; an absent planter gets nothing", function()
		local s = setup()
		local own = s.tree("oak", nil, { planterId = 1 })
		local gone = s.tree("birch", nil, { planterId = 99 })
		s.start()
		local a = s.player(1, "Ada")
		s.fell(a, own)
		t.eq(s.profiles[a].heartseeds.oak, 2, "1 + the steward's bonus")
		t.eq(s.profiles[a].cash, 0)
		t.eq(s.fxAll[1].payload.reasons, { "steward's bonus" })
		s.fell(a, gone)
		t.eq(#s.paid, 0, "the planter isn't here")
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
		t.eq(s.profiles[a].heartseeds.oak, 2, "+1 for a storm-struck tree")
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
		t.eq(s.profiles[a].heartseeds[rec.def.id], 2 + 2, "the feller's own (1 + big) and the helper's 2")
		t.eq(s.profiles[b].heartseeds[rec.def.id], 2)
		t.eq(s.profiles[c].heartseeds[rec.def.id], nil)
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

	t.test("vitality drifts back to 60 by a point a minute", function()
		local s = setup()
		local rec = s.tree("oak")
		s.start()
		s.fell(s.player(1, "Ada"), rec)
		t.eq(s.attr("Vitality_starter"), 58.5)
		s.Forest.Tick(60)
		t.eq(s.attr("Vitality_starter"), 59.5)
		s.Forest.Tick(60)
		t.eq(s.attr("Vitality_starter"), 60)
	end)

	t.test("replanting every grove makes the Skyroot bloom for 8 minutes, then it rests 30", function()
		local s = setup()
		local groves =
			{ starter = "oak", hills = "pine", snow = "frostwood", volcano = "emberwood", grove = "phantomwood" }
		local recs = {}
		for biome, woodId in pairs(groves) do
			recs[biome] = s.tree(woodId)
		end
		s.start()
		local a = s.player(1, "Ada")
		local b = s.player(2, "Bo")
		-- Two players fell each other's trees and replant: each round nets
		-- the grove +2.5 (a wild tree) or +3.5 (one the other planted).
		for round = 1, 5 do
			local p = if round % 2 == 1 then a else b
			for _, rec in pairs(recs) do
				s.fell(p, rec)
				s.plant(p, rec.uid)
			end
			s.runDelays()
		end
		for biome in pairs(groves) do
			t.ok(s.attr("Vitality_" .. biome) >= 75, biome .. " thriving")
			t.eq(s.attr("VitalityTier_" .. biome), "Thriving")
		end
		t.eq(s.attr("SkyrootBloom"), false, "it waits for the clock")
		s.Forest.Tick(0)
		t.eq(s.attr("SkyrootBloom"), true)
		-- Figure chances double while it lasts (6% Thriving x1.5 +4% planted, x2).
		t.ok(math.abs(s.ForestLogic.FigureChance("Thriving", true, true) - 0.26) < 1e-9)
		s.now += 8 * 60
		s.Forest.Tick(0)
		t.eq(s.attr("SkyrootBloom"), false)
		s.now += 60
		s.Forest.Tick(0)
		t.eq(s.attr("SkyrootBloom"), false, "resting")
		s.now += 30 * 60
		s.Forest.Tick(0)
		t.eq(s.attr("SkyrootBloom"), true, "blooms again")
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

	t.test("joining cleans the pouch and shows it", function()
		local s = setup()
		s.start()
		local a = s.player(1, "Ada")
		s.profiles[a].heartseeds = { oak = 80, unicorn = 3, birch = 2 }
		s.Forest.PlayerJoined(a, s.profiles[a])
		t.eq(s.profiles[a].heartseeds, { oak = 50, birch = 2 })
		t.eq(a.attrs.Seeds_oak, 50)
		t.eq(a.attrs.Seeds_birch, 2)
		t.eq(a.attrs.Seeds_pine, 0)
		t.eq(a.attrs.Heartseeds, 52)
	end)

	t.test("a regrown tree rolls a new figure (planted ones get +4%)", function()
		local s = setup()
		local rec = s.tree("oak")
		s.start()
		local a = s.player(1, "Ada")
		s.fell(a, rec)
		s.rolls = { 0.08, 0.5, 0.5 } -- 8%: over a wild tree's 6%, under a planted one's 10%
		s.TreeService.Regrow(rec.uid)
		t.eq(rec.model:FindFirstChild("BarkClue"), nil, "wild: no figure at 8%")
		s.fell(a, rec)
		s.plant(a, rec.uid)
		s.rolls = { 0.08, 0.5, 0.5 }
		s.runDelays()
		local clue = rec.model:FindFirstChild("BarkClue")
		t.ok(clue ~= nil, "planted: a figure at 8%")
		t.eq(clue:GetAttribute("Figure"), "birdseye")
	end)

	t.test(
		"refelling your own tree straight after it sprouts: no steward's seed, the planting's vitality goes back",
		function()
			local s = setup()
			local rec = s.tree("oak")
			s.start()
			local a = s.player(1, "Ada")
			local b = s.player(2, "Bo")
			s.fell(a, rec)
			s.plant(a, rec.uid)
			s.runDelays()
			t.eq(rec.planterId, 1)
			t.eq(s.attr("Vitality_starter"), 62.5, "-1.5 for the wild tree, +4 for the planting")
			s.fxAll = {}
			s.fell(a, rec)
			t.eq(s.profiles[a].heartseeds.oak, 1, "the seed planted, one back: no gain")
			t.eq(s.fxAll[1].payload.reasons, {}, "no steward's bonus")
			t.eq(s.attr("Vitality_starter"), 58, "-0.5 for the felling and the planting's 4 back")
			-- Left standing ten minutes, it's a steward's tree.
			s.plant(a, rec.uid)
			s.runDelays()
			s.now += 10 * 60
			s.fxAll = {}
			s.fell(a, rec)
			t.eq(s.profiles[a].heartseeds.oak, 2, "1 + the steward's bonus")
			t.eq(s.fxAll[1].payload.reasons, { "steward's bonus" })
			t.eq(s.attr("Vitality_starter"), 61.5, "+4 planted, -0.5 felled")
			-- Someone else felling a fresh one still pays the planter.
			s.plant(a, rec.uid)
			s.runDelays()
			s.fell(b, rec)
			t.eq(#s.paid, 1)
			t.eq(s.paid[1].player, a)
			t.eq(s.attr("Vitality_starter"), 65, "+4 planted, -0.5 felled: Bo's felling keeps it")
		end
	)

	t.test("a quick solo refell of a big tree on a lucky roll still gives back just the planted seed", function()
		local s = setup()
		local TreeLogic = t.shared("TreeLogic")
		local large
		for _, size in ipairs(TreeLogic.Sizes) do
			if size.name == "large" then
				large = size
			end
		end
		local rec = s.tree("oak", nil, { seed = 7, size = large })
		s.start()
		local a = s.player(1, "Ada")
		s.fell(a, rec)
		local before = s.profiles[a].heartseeds.oak
		s.plant(a, rec.uid)
		s.runDelays()
		s.rolls = { 0.01, 0.01, 0.01 } -- every roll lucky
		s.fxAll = {}
		s.fell(a, rec)
		t.eq(s.profiles[a].heartseeds.oak, before, "planted one, got one back")
		t.eq(s.fxAll[1].payload.reasons, {}, "no big-tree, lucky or steward's extras")
	end)

	t.test("woods outside the groves keep their slow regrowth: half of it to sprout, never past their own", function()
		local s = setup()
		local lumen = s.tree("lumenwood")
		local palm = s.tree("palmwood", Vector3.new(30, 0, 0))
		local oak = s.tree("oak", Vector3.new(-30, 0, 0))
		s.start()
		local a = s.player(1, "Ada")
		s.fell(a, lumen)
		s.fell(a, palm)
		s.fell(a, oak)
		s.fxAll = {}
		s.plant(a, lumen.uid)
		t.eq(s.fxAll[1].payload.seconds, 450, "half of Lumenwood's 15 minutes")
		t.eq(s.delays[1].seconds, 450)
		t.ok(string.find(s.lastToast(a), "in about 8 minutes") ~= nil)
		t.eq(lumen.stump:GetAttribute("Sprouting"), true, "the stump says so to everyone (ForestUI)")
		a.root.Position = Vector3.new(30, 0, 0)
		palm.regrowsIn = 40 -- its own regrowth comes sooner
		s.plant(a, palm.uid)
		t.eq(s.fxAll[2].payload.seconds, 40)
		a.root.Position = Vector3.new(-30, 0, 0)
		oak.regrowsIn = 3
		s.plant(a, oak.uid)
		t.eq(s.fxAll[3].payload.seconds, 8, "never under the 8 seconds")
		t.ok(string.find(s.lastToast(a), "in a moment") ~= nil)
		t.eq(s.attr("Vitality_island"), nil, "the island has no meter")
	end)

	t.test("a sprout is sized to its stump: the payload and a slow wood's SproutMark carry its diameter", function()
		local s = setup()
		local birch = s.tree("birch", Vector3.new(0, 0, 0), { size = s.TreeLogic.Sizes[1] }) -- the smallest cut
		local lumen = s.tree("lumenwood", Vector3.new(30, 0, 0))
		s.start()
		local a = s.player(1, "Ada")
		s.fell(a, birch)
		s.fell(a, lumen)
		s.fxAll = {}
		s.plant(a, birch.uid)
		-- TreeArt.Stump is an upright cylinder: Size.X its height, Size.Y its diameter.
		local cut = birch.stump.PrimaryPart
		t.ok(cut.Size.Y < cut.Size.Z + 1e-6 and cut.Size.Y > cut.Size.Z - 1e-6, "Y and Z are the round axes")
		t.eq(s.fxAll[1].kind, "Sprout")
		t.eq(s.fxAll[1].payload.diameter, cut.Size.Y)
		t.ok(math.abs(s.fxAll[1].payload.pos.Y - (cut.CFrame.Position.Y + cut.Size.X / 2)) < 1e-4, "on the cut")
		t.eq(birch.stump:FindFirstChild("SproutMark"), nil, "a grove wood's sprout is the client's (ForestUI)")

		a.root.Position = Vector3.new(30, 0, 0)
		s.plant(a, lumen.uid)
		local lumenCut = lumen.stump.PrimaryPart
		t.eq(s.fxAll[2].payload.diameter, lumenCut.Size.Y)
		local mark = lumen.stump:FindFirstChild("SproutMark")
		t.ok(mark ~= nil, "a slow wood's sapling sits on the stump for everyone")
		local mound = mark:FindFirstChild("Mound")
		t.ok(math.abs(mound.Size.X - lumenCut.Size.Y * 0.8) < 1e-4, "the mound is 0.8 of the cut")
		local halo = mark:FindFirstChild("Halo")
		t.ok(math.abs(halo.Size.Y - lumenCut.Size.Y * 0.95) < 1e-4, "the halo rings the cut")
	end)

	t.test("a dormant grove's stump: planting says why it can't", function()
		local s = setup()
		local rec = s.tree("phantomwood")
		s.start()
		local a = s.player(1, "Ada")
		s.fell(a, rec)
		rec.dormant = true
		s.plant(a, rec.uid)
		t.ok(string.find(s.lastToast(a), "sleeps by day") ~= nil)
		t.eq(s.profiles[a].heartseeds.phantomwood, 1, "the seed is kept")
		t.eq(#s.delays, 0)
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
		t.eq(s.profiles[a].heartseeds.oak, 2, "+1 for the storm")
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

	t.test("the Phantom Grove only wakes an Elder with five minutes of the night left", function()
		local s = setup()
		local rec = s.tree("phantomwood")
		s.start()
		local a = s.player(1, "Ada")
		local b = s.player(2, "Bo")
		for round = 1, 5 do
			local p = if round % 2 == 1 then a else b
			s.fell(p, rec)
			s.plant(p, rec.uid)
			s.runDelays()
		end
		t.ok(s.attr("Vitality_grove") >= 75, "thriving")
		s.workspace:SetAttribute("IsNight", true)
		-- Night is 19:00 to 05:00: 500 real seconds from 950 into each 1200 s day.
		local WorldTime = s.WorldTime
		s.serverNow = 1200 -- midnight: 250 s of night left
		t.ok(math.abs(WorldTime.SecondsUntilChange(s.serverNow) - 250) < 1e-6)
		s.now += 20 * 60
		s.rolls = { 0.5, 0, 0 } -- the next check's interval, then the grove pick and wake rolls
		s.Forest.Tick(0)
		t.eq(s.Forest.ElderUid(), nil, "too close to dawn")
		s.serverNow = 950 -- dusk: the whole night ahead
		t.ok(math.abs(WorldTime.SecondsUntilChange(s.serverNow) - 500) < 1e-6)
		s.now += 20 * 60
		s.rolls = { 0.5, 0, 0 }
		golden(s)
		s.Forest.Tick(0)
		t.ok(s.Forest.ElderUid() ~= nil, "an Elder wakes at dusk")
		t.eq(s.attr("ElderBiome"), "grove")
	end)
end
