--!nocheck
-- Planting end to end on the server: the real TreeService, ForestService
-- and QuestService together (the profiles, money, remotes, timers and the
-- clock faked). The short tutorial has no Heartseed beat, so a seed plants
-- any time and a stump uses the tree's own regrowth.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame

	local function setup()
		local s = {
			delays = {},
			clock = 100,
			byId = {},
			profiles = {},
			toasts = {},
			fx = {},
		}

		-- The workspace: attributes and the map from a real instance, the
		-- physics queries faked (no ground hit: logs lie at the stump's height).
		local world = roblox.Instance.new("Model")
		world.Name = "Workspace"
		local map = roblox.Instance.new("Folder")
		map.Name = "TimberlineMap"
		map.Parent = world
		s.map = map
		local workspace = setmetatable({
			Raycast = function()
				return nil
			end,
			GetPartBoundsInBox = function()
				return {}
			end,
			GetServerTimeNow = function()
				return 0
			end,
		}, {
			__index = function(_, key)
				local value = world[key]
				if type(value) == "function" then
					return function(_, ...)
						return value(world, ...)
					end
				end
				return value
			end,
		})

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
		local CollectionService = {
			AddTag = function(_, inst, tag)
				inst:AddTag(tag)
			end,
			HasTag = function(_, inst, tag)
				return inst:HasTag(tag)
			end,
			RemoveTag = function(_, inst, tag)
				inst:RemoveTag(tag)
			end,
			GetTagged = function()
				return {} -- no trucks about
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
		-- @lune/roblox instances have no events: a stand-in pickup prompt.
		local Instance = {
			new = function(class)
				if class == "ProximityPrompt" then
					return { Triggered = { Connect = function() end } }
				end
				return roblox.Instance.new(class)
			end,
		}
		local function params()
			return {
				new = function()
					return {}
				end,
			}
		end

		local base = t.loader()
		local Schema = base:server("ProfileSchema")
		local Util = base:shared("Util")
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return s.profiles[p]
					end,
				},
				EconomyService = {
					AddCash = function(p, amount)
						s.profiles[p].cash += amount
						return amount, 0
					end,
				},
				FieldGuideService = {
					Refresh = function() end,
					RevealFigures = function() end,
				},
				MilestoneService = { Mark = function() end },
				DailyService = { Event = function() end },
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
			},
			services = { Players = Players, CollectionService = CollectionService },
			globals = {
				workspace = workspace,
				task = fakeTask,
				Instance = Instance,
				RaycastParams = params(),
				OverlapParams = params(),
				os = setmetatable({
					clock = function()
						return s.clock
					end,
				}, { __index = os }),
			},
		})
		s.Trees = loader:server("TreeService")
		s.Forest = loader:server("ForestService")
		s.Quest = loader:server("QuestService")
		s.ItemCatalog = loader:shared("ItemCatalog")
		s.TreeLogic = loader:shared("TreeLogic")
		s.TutorialData = loader:shared("TutorialData")

		local function notify(p, message)
			table.insert(s.toasts, { player = p, message = message })
		end
		s.Quest.Init({
			OnServerEvent = {
				Connect = function(_, fn)
					s.skip = fn
				end,
			},
		}, notify)
		s.Forest.Init(
			{
				PlantSeed = {
					OnServerEvent = {
						Connect = function(_, fn)
							s.plant = fn
						end,
					},
				},
				WorldFX = {
					FireAllClients = function(_, kind, payload)
						table.insert(s.fx, { kind = kind, payload = payload })
					end,
					FireClient = function() end,
				},
			},
			notify,
			{
				clock = function()
					return s.clock
				end,
				serverTime = function()
					return 0
				end,
				random = function()
					return 0.5 -- no figure, no lucky seed
				end,
				manual = true,
			}
		)

		-- A player with a fresh save, standing at `pos`, their tutorial started.
		function s.player(userId, pos)
			local root = { Position = pos }
			local p = {
				UserId = userId,
				Name = "P" .. userId,
				DisplayName = "P" .. userId,
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
			s.byId[userId] = p
			s.Quest.Start(p, s.profiles[p])
			return p
		end

		-- A normal oak at `pos`.
		function s.oak(pos)
			local model = s.Trees.SpawnTree("oak", CFrame.new(pos), { seed = 7, size = s.TreeLogic.Sizes[2] })
			return s.Trees.GetTree(model:GetAttribute("Uid"))
		end

		-- Chops it down with the Rusty Axe and reports it the way GameServer
		-- does; the tree lands and leaves its stump and logs.
		function s.fell(p, rec)
			local axe = s.ItemCatalog.GetAxe("RustyAxe")
			local hp, feller
			repeat
				hp, _, feller = s.Trees.ApplyChop(p, rec.uid, axe)
			until hp == nil or hp <= 0
			s.Quest.Event(feller, "treeFelled")
			s.run(s.TreeLogic.FallTime + 1)
		end

		-- Runs the timers due within `seconds` (all of them by default).
		function s.run(seconds)
			local due, later = {}, {}
			for _, d in ipairs(s.delays) do
				table.insert(if seconds == nil or d.seconds <= seconds then due else later, d)
			end
			s.delays = later
			for _, d in ipairs(due) do
				d.fn(table.unpack(d.args, 1, d.args.n))
			end
		end

		-- Moves the clock on, running each timer as its time comes.
		function s.wait(seconds)
			local untilAt = s.clock + seconds
			while true do
				local next
				for _, d in ipairs(s.delays) do
					if not next or d.seconds < next.seconds then
						next = d
					end
				end
				if not next or s.clock + next.seconds > untilAt then
					break
				end
				local step = next.seconds
				s.clock += step
				for _, d in ipairs(s.delays) do
					d.seconds -= step
				end
				s.run(0)
			end
			for _, d in ipairs(s.delays) do
				d.seconds -= untilAt - s.clock
			end
			s.clock = untilAt
		end

		function s.lastToast(p)
			for i = #s.toasts, 1, -1 do
				if s.toasts[i].player == p then
					return s.toasts[i].message
				end
			end
			return nil
		end

		function s.stepId(p)
			local step = s.TutorialData.Steps[s.profiles[p].tutorialStep]
			return if s.profiles[p].tutorialDone then "done" else step.id
		end
		return s
	end

	t.test("a tutorial player's seed plants straight away, and the stump isn't held", function()
		local s = setup()
		local rec = s.oak(Vector3.new(0, 0, 0))
		local ada = s.player(1, Vector3.new(4, 0, 0))
		local profile = s.profiles[ada]
		t.eq(s.stepId(ada), "plot")
		s.fell(ada, rec)
		t.eq(s.stepId(ada), "plot", "felling waits until the plot is claimed")
		t.ok(rec.felled and rec.stump ~= nil, "a stump")
		t.eq(profile.heartseeds.oak, 1, "and an oak Heartseed")
		t.eq(s.Trees.RegrowsIn(rec.uid), rec.def.respawnSec, "no tutorial hold")

		s.plant(ada, rec.uid)
		t.eq(profile.heartseeds.oak, nil, "planted")
		t.eq(profile.forest.planted, 1)
		t.ok(string.find(s.lastToast(ada), "Planted!") ~= nil)
		t.eq(s.stepId(ada), "plot", "planting isn't a tutorial step")
		s.wait(10) -- the sapling sprouts
		t.ok(rec.alive and not rec.felled, "it stands again")
		t.eq(rec.planterId, 1, "as Ada's tree")
	end)

	t.test("left unplanted, a stump grows back on the oak's own timer", function()
		local s = setup()
		local rec = s.oak(Vector3.new(0, 0, 0))
		local ada = s.player(1, Vector3.new(4, 0, 0))
		s.fell(ada, rec)
		s.wait(rec.def.respawnSec - 1)
		t.ok(rec.felled, "still the stump")
		s.wait(2)
		t.ok(rec.alive and not rec.felled, "grown back on its own")
		t.eq(rec.planterId, nil)
	end)

	t.test("a player who skipped the tutorial: the usual regrowth, and planting works", function()
		local s = setup()
		local rec = s.oak(Vector3.new(0, 0, 0))
		local bo = s.player(2, Vector3.new(4, 0, 0))
		s.skip(bo)
		t.eq(s.stepId(bo), "done")
		s.fell(bo, rec)
		t.eq(s.Trees.RegrowsIn(rec.uid), rec.def.respawnSec, "no hold")
		s.plant(bo, rec.uid)
		t.eq(s.profiles[bo].heartseeds.oak, nil, "planted")
		local other = s.oak(Vector3.new(40, 0, 0))
		bo.Character:FindFirstChild("HumanoidRootPart").Position = Vector3.new(44, 0, 0)
		s.fell(bo, other)
		s.wait(rec.def.respawnSec)
		t.ok(other.alive and not other.felled, "back after the oak's 45 s")
	end)
end
