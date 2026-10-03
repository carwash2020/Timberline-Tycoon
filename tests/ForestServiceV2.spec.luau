--!nocheck
-- The Living Forest on the v2 loop (V2_PLAN.md §3i, M1.3): ForestService
-- with SectionTrees faked (records shaped like the real ones, models built
-- by TreeArt.FromSkeleton) and WoodService's pieces as plain records.
-- Figures on every freed piece (Stormgrain while struck), clues on the
-- trunk section, seeds by scale, the planter's share by value, an Elder's
-- helpers by the value freed, and planting in a stub bringing it back
-- mature through SectionTrees.Regrow (stage 1).
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame

	local function setup()
		local base = t.loader()
		local Schema = base:server("ProfileSchema")
		local Util = base:shared("Util")
		local TreeArt = base:load("ReplicatedStorage/Shared/Art/TreeArt")
		local TreeGen = base:shared("TreeGen")
		local Kit = base:load("ReplicatedStorage/Shared/Art/Kit")
		local WoodData = base:shared("WoodData")
		local ForestLogic = base:shared("ForestLogic")

		local s = {
			profiles = {},
			byId = {},
			fxAll = {},
			fxOne = {},
			toasts = {},
			paid = {},
			delays = {},
			regrows = {},
			figures = {},
			now = 1000,
			rolls = {},
		}
		local workspace = roblox.Instance.new("Model")
		local map = roblox.Instance.new("Folder")
		map.Name = "TimberlineMap"
		map.Parent = workspace
		s.workspace = workspace

		-- A fake SectionTrees: TreeService's API over section-tree records.
		local trees = {}
		local counter = 0
		local Trees = {}
		function Trees.AllTrees()
			return trees
		end
		function Trees.GetTree(uid)
			return trees[uid]
		end
		function Trees.Decorate(uid, build)
			local rec = trees[uid]
			if rec then
				build(rec.model, rec)
			end
		end
		function Trees.Forget() end
		function Trees.Remove(uid)
			trees[uid] = nil
		end
		function Trees.RegrowsIn(uid)
			local rec = trees[uid]
			return if rec and rec.felled then 45 else nil
		end
		function Trees.Regrow(uid, planterId, opts)
			table.insert(s.regrows, { uid = uid, planterId = planterId, opts = opts })
			local rec = trees[uid]
			rec.felled, rec.alive, rec.stump = false, true, nil
			rec.planterId = planterId
			rec.stage = if opts and opts.stage then opts.stage else 0
			rec.damageBy = {}
			if Trees.OnRebuilt then
				Trees.OnRebuilt(rec)
			end
			if Trees.OnRegrown then
				Trees.OnRegrown(rec)
			end
		end
		function Trees.SpawnTree(woodId, cf, opts)
			opts = opts or {}
			local def = WoodData.Get(woodId)
			counter += 1
			local uid = "tree" .. counter
			local scale = if opts.size and opts.size.name == "elder" then 1.7 else (opts.scale or 1)
			local skel = TreeGen.Skeleton(woodId, opts.seed or counter, scale, { elder = scale > 1.5 })
			local model = TreeArt.FromSkeleton(def, skel, { uid = uid })
			Kit.placeAt(model, CFrame.new(cf.Position))
			trees[uid] = {
				uid = uid,
				model = model,
				def = def,
				size = { name = if scale > 1.5 then "elder" elseif scale > 1 then "large" else "normal", scale = scale },
				maxHp = 3,
				hp = 3,
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
				stage = 1,
			}
			return model
		end
		s.Trees, s.trees = Trees, trees

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
		local loader = t.loader({
			mocks = {
				-- ForestService requires SectionTrees at load. The fake above
				-- is the one UseV2 drives; don't pull in GrabService.
				SectionTrees = Trees,
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
				QuestService = { Event = function() end },
				DailyService = { Event = function() end },
				FieldGuideService = { RevealFigures = function() end },
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
			},
			services = { Players = Players },
			globals = {
				workspace = workspace,
				task = {
					delay = function(seconds, fn, ...)
						table.insert(s.delays, { seconds = seconds, fn = fn, args = table.pack(...) })
					end,
					spawn = function(fn, ...)
						fn(...)
					end,
					wait = function()
						return 0
					end,
				},
			},
		})
		s.Forest = loader:server("ForestService")
		s.ForestData = loader:shared("ForestData")
		s.ForestLogic = ForestLogic
		s.WoodData = WoodData

		function s.player(userId, name, pos)
			local root = { Position = pos or Vector3.new(0, 3, 0) }
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
			s.profiles[p] = Util.deepCopy(Schema.Template)
			s.profiles[p].tutorialDone = true
			s.byId[userId] = p
			return p
		end

		function s.tree(woodId, opts)
			local model = Trees.SpawnTree(woodId, CFrame.new(Vector3.zero), opts)
			return trees[model:GetAttribute("Uid")]
		end

		-- A piece freed from `rec` by `p`: `volume` u³ (as WoodService's records).
		local pieceCounter = 0
		function s.free(p, rec, volume)
			pieceCounter += 1
			local price = rec.def.v2.logPrice
			local piece = { uid = "piece" .. pieceCounter, volume = volume, value = volume * price, price = price }
			Trees.OnPieceFreed(p, rec, piece)
			return piece
		end

		-- Fells `rec` the way SectionTrees does: its trunk freed, then OnFelled.
		function s.fell(p, rec, volume)
			local piece = s.free(p, rec, volume or 20)
			rec.alive, rec.felled = false, true
			rec.growth += 1
			rec.stump = rec.model
			Trees.OnFelled(p, rec, { piece.uid }, Vector3.xAxis)
			return piece
		end

		function s.start()
			-- The Elder check's wait is rolled after the standing trees' figures.
			table.insert(s.rolls, 0.5)
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
					return 0
				end,
				random = function()
					return if #s.rolls > 0 then table.remove(s.rolls, 1) else 0.5
				end,
				manual = true,
				-- The live path: Init turns the forest onto these trees once.
				sectionTrees = Trees,
				setFigure = function(piece, figure)
					piece.figure = figure
					piece.value = piece.volume * piece.price * s.ForestLogic.Multiplier(figure)
					table.insert(s.figures, { piece = piece, figure = figure })
				end,
			})
		end

		function s.runDelays()
			local due = s.delays
			s.delays = {}
			for _, d in ipairs(due) do
				d.fn(table.unpack(d.args, 1, d.args.n))
			end
		end
		return s
	end

	t.test("UseV2 hooks the section trees; a standing figured tree shows its clue on the trunk section", function()
		local s = setup()
		local rec = s.tree("oak")
		s.rolls = { 0.01, 0.95, 0.9 } -- figured: a burl
		s.start()
		t.ok(s.Trees.OnFelled and s.Trees.OnRegrown and s.Trees.OnPieceFreed and s.Trees.OnRebuilt, "every hook set")
		local clue = rec.model:FindFirstChild("BarkClue")
		t.ok(clue ~= nil, "the clue")
		t.eq(clue:GetAttribute("Section"), 2, "on the second trunk section (it falls with the trunk)")
	end)

	t.test("every piece freed from a figured tree carries the figure; while struck it's Stormgrain", function()
		local s = setup()
		local rec = s.tree("maple")
		s.rolls = { 0.01, 0.1, 0.9 } -- figured: the first figure by weight
		s.start()
		local p = s.player(1, "Ada")
		local limb = s.free(p, rec, 2)
		t.ok(limb.figure ~= nil, "a limb gets it")
		local figure = limb.figure
		local trunk = s.fell(p, rec)
		t.eq(trunk.figure, figure, "the trunk too")

		local other = s.tree("oak", { seed = 3 })
		s.Forest.Strike(Vector3.new(0, 0, 0))
		local struckPiece = s.fell(p, other)
		t.eq(struckPiece.figure, "stormgrain")
	end)

	t.test("felling: seeds to the feller, a large-scale tree's extra one, the grove thins", function()
		local s = setup()
		local big = s.tree("oak", { scale = 1.15 })
		local small = s.tree("oak", { scale = 0.85, seed = 9 })
		s.start()
		local p = s.player(1, "Ada")
		s.fell(p, small)
		t.eq(s.profiles[p].heartseeds.oak, s.ForestData.Seeds.perTree)
		s.fell(p, big)
		t.eq(s.profiles[p].heartseeds.oak, s.ForestData.Seeds.perTree * 2 + s.ForestData.Seeds.largeBonus)
		t.ok(s.workspace:GetAttribute("Vitality_starter") < 60, "the grove thins")
	end)

	t.test("the planter's share: 15% of the base value of what others freed, paid at the felling", function()
		local s = setup()
		local rec = s.tree("oak", { planterId = 1 })
		s.start()
		local a = s.player(1, "Ada")
		local b = s.player(2, "Bo")
		s.free(a, rec, 10) -- Ada limbing her own tree: no share for that
		s.free(b, rec, 4)
		s.fell(b, rec, 22)
		local expected = s.ForestLogic.RoyaltyByValue((4 + 22) * 1.5)
		t.eq(s.profiles[a].cash, expected)
		t.eq(s.fxOne[#s.fxOne].kind, "Royalty")
		t.eq(s.profiles[b].cash, 0)
		-- Her own felling of her own tree pays nothing.
		local own = s.tree("oak", { planterId = 1, seed = 4 })
		s.fell(a, own, 22)
		t.eq(s.profiles[a].cash, expected, "no share from yourself")
	end)

	t.test("planting a Heartseed in a stub: the sprout sits on the stub's top, then the tree is back mature", function()
		local s = setup()
		local rec = s.tree("oak")
		s.start()
		local a = s.player(1, "Ada")
		s.fell(a, rec)
		t.eq(s.profiles[a].heartseeds.oak, 1)
		s.plant(a, rec.uid)
		local sprout
		for _, e in ipairs(s.fxAll) do
			if e.kind == "Sprout" then
				sprout = e.payload
			end
		end
		t.ok(sprout, "a Sprout")
		local topY = -math.huge
		local width
		for _, d in ipairs(rec.model:GetChildren()) do
			if d:IsA("BasePart") and d.Name == "Section" then
				local y = (d.CFrame * CFrame.new(0, d.Size.Y / 2, 0)).Position.Y
				if y > topY then
					topY, width = y, d.Size.X
				end
			end
		end
		t.ok(math.abs(sprout.pos.Y - topY) < 1e-4, "on the stub's top section")
		t.ok(math.abs(sprout.diameter - width) < 1e-6, "sized to it")
		t.eq(sprout.seconds, s.ForestData.SproutSeconds)
		s.runDelays()
		t.eq(#s.regrows, 1)
		t.eq(s.regrows[1].planterId, 1)
		t.eq(s.regrows[1].opts, { stage = 1 }, "mature at once")
		t.ok(not rec.felled)
		t.eq(rec.planterId, 1)
		local stake = s.workspace.TimberlineMap:FindFirstChild("ForestMarks")
		t.ok(stake and #stake:GetChildren() == 1, "your stake")
	end)

	t.test("an Elder: helpers who did 10% of the damage share 10% of the value freed from it", function()
		local s = setup()
		s.start()
		local a = s.player(1, "Ada")
		local b = s.player(2, "Bo")
		local c = s.player(3, "Cy")
		local uid = s.Forest.WakeElder("starter")
		t.ok(uid, "an Elder wakes")
		local rec = s.trees[uid]
		t.eq(rec.size.name, "elder")
		rec.damageBy = { [1] = 60, [2] = 35, [3] = 5 }
		s.free(a, rec, 30)
		local trunk = s.fell(a, rec, 100)
		t.ok(trunk.figure ~= nil, "always figured")
		local multiplier = s.ForestLogic.Multiplier(trunk.figure)
		local freedValue = 30 * 1.5 * multiplier + 100 * 1.5 * multiplier
		local bonus = s.ForestLogic.HelperBonus(freedValue)
		t.eq(s.profiles[b].cash, bonus, "Bo helped")
		t.eq(s.profiles[c].cash, 0, "Cy did 5%")
		t.eq(s.profiles[b].heartseeds[rec.def.id], s.ForestData.Elder.helperSeeds)
	end)
end
