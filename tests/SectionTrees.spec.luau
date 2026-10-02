--!nocheck
-- SectionTrees (V2_PLAN.md M1.3): the v2 loop's standing trees. The Chop
-- remote's checks and their reasons (cooldown, far, noLOS, tooHard), a
-- felling (OnFelled once, the stub stays anchored and becomes the Stump,
-- the trunk a loose piece), limbing, the regrow from a sapling through the
-- growth stages, death, the Gloam Hollow's dormancy and the ghost-until-
-- clear. The engine's queries (Raycast, GetPartBoundsInBox), players,
-- physics and timers are faked; WoodService and GrabService are real.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance

	local function setup()
		local s = {
			now = 1000,
			delays = {},
			fx = {},
			toasts = {},
			due = {},
			byId = {},
			blocked = false,
			rayHit = nil, -- what the sight line hits (nil: nothing in the way)
			trucks = {},
			attrs = {},
		}
		local map = Instance.new("Folder")
		map.Name = "TimberlineMap"
		s.map = map
		local workspace = {
			WaitForChild = function(_, name)
				return if name == "TimberlineMap" then map else nil
			end,
			FindFirstChild = function(_, name)
				return if name == "TimberlineMap" then map else nil
			end,
			GetAttribute = function(_, name)
				return s.attrs[name]
			end,
			GetServerTimeNow = function()
				return s.now
			end,
			Raycast = function(_, origin, direction)
				s.lastRay = { origin = origin, direction = direction }
				return s.rayHit
			end,
			GetPartBoundsInBox = function()
				return if s.blocked then { "someone" } else {}
			end,
		}
		local Players = {
			GetPlayers = function()
				local list = {}
				for _, p in pairs(s.byId) do
					table.insert(list, p)
				end
				return list
			end,
			GetPlayerByUserId = function(_, id)
				return s.byId[id]
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
			GetTagged = function(_, tag)
				return if tag == "Truck" then s.trucks else {}
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
		local params = {
			new = function()
				return {}
			end,
		}
		local loader = t.loader({
			services = {
				Players = Players,
				CollectionService = CollectionService,
				PhysicsService = {},
			},
			mocks = {
				RateLimiter = {
					Allow = function()
						return s.allow ~= false
					end,
				},
			},
			globals = {
				workspace = workspace,
				task = fakeTask,
				RaycastParams = params,
				OverlapParams = params,
				os = setmetatable({
					clock = function()
						return s.now
					end,
				}, { __index = os }),
			},
		})
		s.Trees = loader:server("SectionTrees")
		s.Wood = loader:server("WoodService")
		s.Grab = loader:server("GrabService")
		s.ItemCatalog = loader:shared("ItemCatalog")
		s.SectionLogic = loader:shared("SectionLogic")
		s.TreeLogic = loader:shared("TreeLogic")
		s.GrowLogic = loader:shared("GrowLogic")
		s.WoodData = loader:shared("WoodData")
		s.GameConfig = loader:shared("GameConfig")

		-- No physics in Lune: record what the services ask of it.
		s.owners, s.velocities = {}, {}
		s.Wood.Physics = {
			SetOwner = function(part, player)
				s.owners[part] = player or "server"
				return true
			end,
			SetAuto = function(part)
				s.owners[part] = "auto"
			end,
			GetOwner = function(part)
				local o = s.owners[part]
				return if type(o) == "table" then o else nil
			end,
			Speed = function()
				return 0, 0
			end,
			GetVelocity = function()
				return Vector3.zero, Vector3.zero
			end,
			SetVelocity = function(part, linear, angular)
				s.velocities[part] = { linear = linear, angular = angular }
			end,
		}
		local remote = {
			FireClient = function(_, player, kind, payload)
				table.insert(s.fx, { player = player, kind = kind, payload = payload })
			end,
		}
		s.Wood.Init({
			worldFx = remote,
			manual = true,
			clock = function()
				return s.now
			end,
		})
		s.axe = "RustyAxe"
		s.Trees.Init({
			notify = function(p, message)
				table.insert(s.toasts, { p, message })
			end,
			worldFx = remote,
			getAxe = function()
				return if s.axe then s.ItemCatalog.GetAxe(s.axe) else nil
			end,
			canChop = function()
				if s.biomeSays then
					return false, s.biomeSays
				end
				return true, nil
			end,
			swingDue = function(p)
				return s.due[p.UserId] or 0
			end,
			setSwingDue = function(p, at)
				s.due[p.UserId] = at
			end,
			clock = function()
				return s.now
			end,
			manual = true,
		})

		-- A player whose root part stands at `pos` (feet 3 studs under it).
		function s.player(userId, pos)
			local root = {
				Position = pos or Vector3.new(4, 3, 0),
				IsA = function(_, class)
					return class == "BasePart"
				end,
			}
			local char = {
				FindFirstChild = function(_, name)
					return if name == "HumanoidRootPart" then root else nil
				end,
				FindFirstChildOfClass = function(_, class)
					return if class == "Humanoid" then { Health = 100, SeatPart = nil } else nil
				end,
			}
			local p = {
				UserId = userId,
				Name = "P" .. userId,
				DisplayName = "P" .. userId,
				Character = char,
				Parent = Players,
			}
			p.root = root
			s.byId[userId] = p
			return p
		end

		-- A mature, normal-size oak standing at `pos`.
		function s.tree(woodId, pos, opts)
			opts = opts or {}
			local model = s.Trees.SpawnTree(woodId or "oak", CFrame.new(pos or Vector3.zero), {
				seed = opts.seed or 7,
				size = s.TreeLogic.Sizes[2],
				stage = opts.stage or 1,
				planterId = opts.planterId,
			})
			return s.Trees.GetTree(model:GetAttribute("Uid"))
		end

		-- One swing at section `id` of `rec` from `p`, aimed as CutController
		-- aims (knee to chest on a trunk, on the side facing you). The clock
		-- moves on by the axe's cooldown first.
		function s.swing(p, part, wait)
			s.now += wait or 0.7
			local hit, normal = s.SectionLogic.AimAt(part.CFrame, part.Size, p.root.Position, nil, nil)
			return s.Trees.Chop(p, part, hit, normal)
		end

		-- Swings until `part` is cut through (or `max` swings).
		function s.cutThrough(p, part, max)
			local n, ok, why, result = 0, nil, nil, nil
			repeat
				n += 1
				ok, why, result = s.swing(p, part)
			until not ok or (result and #result.freed > 0) or n >= (max or 200)
			return n, ok, why, result
		end

		-- Runs the timers due within `seconds` (all by default).
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

		function s.fxOf(kind)
			local out = {}
			for _, f in ipairs(s.fx) do
				if f.kind == kind then
					table.insert(out, f)
				end
			end
			return out
		end

		function s.sectionsOf(model)
			local out = {}
			for _, d in ipairs(model:GetChildren()) do
				if d:IsA("BasePart") and d.Name == "Section" then
					table.insert(out, d)
				end
			end
			return out
		end
		return s
	end

	t.test(
		"16 swings of the Rusty Axe at an oak's knee fell it: OnFelled once, a loose trunk, an anchored stub",
		function()
			local s = setup()
			local rec = s.tree("oak")
			local p = s.player(1)
			local felled = {}
			s.Trees.OnFelled = function(feller, r, uids, dir)
				table.insert(felled, { feller = feller, rec = r, uids = uids, dir = dir })
			end
			local fellCredit
			s.Trees.Hooks.onFelled = function(feller)
				fellCredit = feller
			end
			local base = rec.sections[1]
			local hits = s.SectionLogic.HitsToCut(2, base.Size.X, 0.2)
			t.eq(hits, 16, "the plan's oak: 16 hits with the hatchet")
			local n, ok, _, result = s.cutThrough(p, base)
			t.ok(ok, "every swing accepted")
			t.eq(n, 16)
			t.eq(#felled, 1, "OnFelled fires once")
			t.eq(felled[1].feller, p)
			t.eq(fellCredit, p)
			t.ok(rec.felled and not rec.alive, "down")
			t.eq(#result.freed, 1)
			local piece = result.freed[1]
			t.eq(felled[1].uids, { piece.uid })
			t.ok(piece.model.Parent == s.Wood.Folder(), "the piece lies in TimberlineMap/Wood")
			t.ok(piece.model:HasTag("Wood"), "tagged Wood")
			t.eq(piece.ownerId, 1, "it's the cutter's")
			t.eq(piece.treeUid, rec.uid)
			for _, d in ipairs(piece.model:GetDescendants()) do
				if d:IsA("BasePart") then
					t.ok(not d.Anchored, d.Name .. " is loose")
				end
			end
			-- The stub: the tree's own model, anchored, tagged Stump, a cut face on top.
			t.ok(rec.stump == rec.model and rec.model:HasTag("Stump"), "the stub is the Stump")
			t.eq(rec.model:GetAttribute("TreeUid"), rec.uid)
			t.eq(rec.model:GetAttribute("Felled"), true)
			for _, part in ipairs(s.sectionsOf(rec.model)) do
				t.ok(part.Anchored, "the stub stays anchored")
			end
			t.ok(rec.model:FindFirstChild("CutFace"), "a cut face on the stub")
			-- It tips away from the cutter (who stands at +X).
			t.ok(felled[1].dir.X < 0, "away from the cutter")
			-- And nothing more to cut there: the stub isn't a target.
			local again, why = s.swing(p, base)
			t.eq(again, false)
			t.eq(why, "gone")
			t.eq(#felled, 1, "still once")
		end
	)

	t.test("the swing schedule: too soon is refused (cooldown), on time is taken", function()
		local s = setup()
		local rec = s.tree("oak")
		local p = s.player(1)
		local part = rec.sections[1]
		t.ok(s.swing(p, part, 0), "the first swing")
		local ok, why = s.swing(p, part, 0.2)
		t.eq(ok, false)
		t.eq(why, "cooldown")
		t.eq(#s.toasts, 0, "a swing too soon is ignored quietly")
		ok = s.swing(p, part, 0.35) -- 0.55 after the first: inside SwingTolerance of 0.65
		t.ok(ok, "a swing a moment early (network jitter) is taken")
	end)

	t.test("reasons: far, noLOS, tooHard, no axe, unknown, biome", function()
		local s = setup()
		local rec = s.tree("oak")
		local part = rec.sections[1]
		local far = s.player(1, Vector3.new(30, 3, 0))
		local ok, why = s.swing(far, part)
		t.eq(ok, false)
		t.eq(why, "far")
		t.ok(string.find(s.toasts[#s.toasts][2], "Too far", 1, true), "a toast")

		local p = s.player(2)
		local wall = Instance.new("Part")
		wall.Name = "Rock"
		s.rayHit = { Instance = wall, Position = Vector3.new(2.5, 2.6, 0) }
		ok, why = s.swing(p, part)
		t.eq(why, "noLOS")
		t.ok(string.find(s.toasts[#s.toasts][2], "in the way", 1, true))
		s.rayHit = { Instance = part, Position = Vector3.new(1, 1.4, 0) }
		ok = s.swing(p, part)
		t.ok(ok, "a sight line ending on the section itself is clear")
		s.rayHit = nil

		-- An axe that can't dent it (a stand-in: no damage against oak).
		local GoldAxe = s.ItemCatalog.GetAxe("GoldAxe")
		local saved = GoldAxe.v2.vs
		GoldAxe.v2.vs = { oak = { damage = 0 } }
		s.axe = "GoldAxe"
		ok, why = s.swing(p, part)
		GoldAxe.v2.vs = saved
		t.eq(why, "tooHard")
		t.ok(#s.fxOf("Clink") >= 1, "a clink")
		s.axe = nil
		ok, why = s.swing(p, part)
		t.eq(why, "noAxe")
		s.axe = "RustyAxe"

		local stray = Instance.new("Part")
		ok, why = s.Trees.Chop(p, stray, Vector3.new(0, 1, 0), Vector3.xAxis)
		t.eq(why, "unknown")
		ok, why = s.Trees.Chop(p, part, "not a vector", Vector3.xAxis)
		t.eq(why, "bad")
		ok, why = s.Trees.Chop(p, part, Vector3.new(3.2, 3, 0), Vector3.xAxis)
		t.eq(why, "bad", "a hit point off the section's box")

		s.biomeSays = "You need a Lantern to chop gloamwood."
		ok, why = s.swing(p, part)
		t.eq(why, "biome")
		t.eq(s.toasts[#s.toasts][2], "You need a Lantern to chop gloamwood.")
	end)

	t.test("a swing in a cut window adds to that cut; a new height starts another, at most two a section", function()
		local s = setup()
		local rec = s.tree("oak")
		local p = s.player(1)
		local part = rec.sections[1]
		s.swing(p, part)
		s.swing(p, part)
		t.eq(#rec.cuts[1], 1, "the same height: one cut")
		t.eq(rec.cuts[1][1].damage, 0.4)
		-- Different heights (the root part higher, then lower: knee to chest).
		p.root.Position = Vector3.new(4, 4.4, 0)
		s.swing(p, part)
		p.root.Position = Vector3.new(4, 2.2, 0)
		s.swing(p, part)
		t.eq(#rec.cuts[1], 2, "never more than MaxCutsPerSection")
		local notches = 0
		for _, d in ipairs(rec.model:GetChildren()) do
			if d.Name == "Notch" and d:GetAttribute("Section") == 1 then
				notches += 1
				t.ok(d.Anchored, "a standing tree's notch is anchored")
				t.ok(type(d:GetAttribute("Required")) == "number", "the ring reads Required")
			end
		end
		t.eq(notches, 2, "one notch per cut")
		t.ok(not rec.felled, "nothing finished")
		t.ok(rec.cut, "a cut tree stops growing")
		local cuts = s.fxOf("Cut")
		t.ok(#cuts >= 4 and cuts[#cuts].payload.progress > 0, "Cut WorldFX with progress")
	end)

	t.test("limbing: a branch cut through falls free and the tree stays standing", function()
		local s = setup()
		local rec = s.tree("oak")
		local felledCount = 0
		s.Trees.OnFelled = function()
			felledCount += 1
		end
		local freedSeen = {}
		s.Trees.OnPieceFreed = function(_, r, piece)
			table.insert(freedSeen, { r = r, piece = piece })
		end
		-- The lowest branch (past the trunk): cut it from beside it.
		local limbId, limb
		for id, part in pairs(rec.sections) do
			if rec.depth[id] >= rec.trunkSegments and (not limb or part.CFrame.Position.Y < limb.CFrame.Position.Y) then
				limbId, limb = id, part
			end
		end
		t.ok(limb, "an oak has branches")
		local p = s.player(1, limb.CFrame.Position + Vector3.new(0, 0, 2.5))
		local sectionsBefore = 0
		for _ in pairs(rec.sections) do
			sectionsBefore += 1
		end
		local _, ok, _, result = s.cutThrough(p, limb)
		t.ok(ok)
		t.eq(#result.freed, 1)
		t.eq(felledCount, 0, "limbing never fells")
		t.ok(not rec.felled and rec.alive)
		t.eq(#freedSeen, 1, "OnPieceFreed for the limb")
		t.ok(rec.sections[limbId] ~= nil, "the limb's base stays on the tree")
		local piece = result.freed[1]
		t.ok(piece.volume > 0)
		local after = 0
		for _ in pairs(rec.sections) do
			after += 1
		end
		t.ok(after < sectionsBefore + 1, "the freed sections left the tree")
	end)

	t.test("regrow: the stub waits respawnSec, then a sapling grows in four stages over growSec", function()
		local s = setup()
		local rec = s.tree("oak")
		local p = s.player(1)
		local regrown = 0
		s.Trees.OnRegrown = function()
			regrown += 1
		end
		s.cutThrough(p, rec.sections[1])
		t.ok(rec.felled)
		local def = s.WoodData.Get("oak")
		t.eq(math.floor(s.Trees.RegrowsIn(rec.uid) + 0.5), def.respawnSec)
		s.Trees.GrowTick(s.now + def.respawnSec - 1)
		t.ok(rec.felled, "not yet")
		s.now += def.respawnSec
		s.Trees.GrowTick(s.now)
		t.ok(not rec.felled, "back")
		t.eq(regrown, 1)
		t.eq(rec.stage, 0, "a sapling first")
		t.eq(rec.model:GetAttribute("Sapling"), true)
		t.ok(not rec.alive, "a sapling can't be cut")
		t.ok(not rec.model:HasTag("Stump"), "the stub is gone")
		t.ok(type(rec.model:GetAttribute("GrewAt")) == "number", "the clients' regrow spring")
		local growSec = def.v2.growSec
		local stages = {}
		for k = 1, 4 do
			s.now += growSec / 4
			s.Trees.GrowTick(s.now)
			table.insert(stages, rec.stage)
		end
		t.eq(stages, { 0.25, 0.5, 0.75, 1 })
		t.ok(rec.alive, "mature and cuttable")
		t.eq(#s.sectionsOf(rec.model) > 1, true)
	end)

	t.test("HoldRegrow keeps a stub (the tutorial), planting brings it back mature at once", function()
		local s = setup()
		local rec = s.tree("oak")
		local p = s.player(1)
		s.Trees.StumpHold = function()
			return 120
		end
		s.cutThrough(p, rec.sections[1])
		t.ok(s.Trees.RegrowsIn(rec.uid) >= 119, "held")
		s.now += 60
		s.Trees.GrowTick(s.now)
		t.ok(rec.felled, "still a stub")
		s.Trees.Regrow(rec.uid, 1, { stage = 1 })
		t.eq(rec.stage, 1, "mature at once")
		t.eq(rec.planterId, 1)
		t.eq(rec.model:GetAttribute("PlanterId"), 1)
		t.ok(rec.alive)
	end)

	t.test(
		"a tree lives its lifespan: its leaves drop at PreDeadAt, then it dies, sinks and the site regrows",
		function()
			local s = setup()
			local rec = s.tree("oak")
			s.player(1) -- near enough to be sent the LeafFall
			local def = s.WoodData.Get("oak")
			local lo, hi = def.v2.lifespan[1] * def.v2.growSec, def.v2.lifespan[2] * def.v2.growSec
			t.ok(rec.life >= lo and rec.life <= hi, "inside the wood's lifespan")
			s.now = rec.bornAt + rec.life * s.GameConfig.PreDeadAt + 1
			s.Trees.GrowTick(s.now)
			t.ok(rec.preDead)
			t.eq(rec.model:FindFirstChild("Leaves"), nil, "the leaves are gone")
			t.ok(#s.fxOf("LeafFall") >= 1, "clients flutter the leaves down")
			s.now = rec.bornAt + rec.life + 1
			s.Trees.GrowTick(s.now)
			t.ok(rec.dead and not rec.alive)
			t.eq(rec.model:GetAttribute("Dead"), true)
			for _, part in ipairs(s.sectionsOf(rec.model)) do
				t.ok(not part:HasTag("WoodSection") and not part.CanQuery, "nothing to cut")
			end
			local model = rec.model
			s.now += s.GameConfig.DeadSinkSec + 1
			s.Trees.GrowTick(s.now)
			t.eq(model.Parent, nil, "sunk and gone")
			t.ok(rec.felled and rec.stump == nil, "an empty site (no stub to plant in)")
			s.now += def.respawnSec + 1
			s.Trees.GrowTick(s.now)
			t.eq(rec.stage, 0, "a new sapling")
		end
	)

	t.test("the growth tick changes at most TreesPerGrowTick trees, the most overdue first", function()
		local s = setup()
		for i = 1, 20 do
			s.tree("oak", Vector3.new(i * 30, 0, 0), { seed = i, stage = 0.25 })
		end
		s.now += 600
		local picked = s.Trees.GrowTick(s.now)
		t.eq(#picked, s.GameConfig.TreesPerGrowTick)
	end)

	t.test("dormant (the Gloam Hollow by day): hidden, uncuttable, a half-cut tree whole again at night", function()
		local s = setup()
		local rec = s.tree("phantomwood")
		local p = s.player(1)
		local part = rec.sections[1]
		t.ok(s.swing(p, part), "cut at night")
		t.ok(rec.cuts[1] and #rec.cuts[1] == 1)
		s.Trees.SetBiomeDormant("grove", true)
		t.ok(rec.dormant and not rec.alive)
		t.eq(part.Transparency, 1)
		t.ok(not part.CanCollide and not part.CanQuery, "no invisible obstacle")
		local ok, why = s.swing(p, part)
		t.eq(why, "gone")
		t.eq(rec.cuts[1], nil, "the cut is forgotten")
		t.eq(next(rec.damageBy), nil)
		t.eq(rec.model:GetAttribute("Dormant"), true)
		s.Trees.SetBiomeDormant("grove", false)
		t.ok(rec.alive)
		t.ok(part.Transparency < 1 and part.CanCollide)
	end)

	t.test("ghost: a tree that grows where someone stands doesn't collide until the spot is clear", function()
		local s = setup()
		local rec = s.tree("oak", Vector3.zero, { stage = 0.25 })
		s.player(1, Vector3.new(0, 3, 0))
		s.blocked = true
		s.now += 130 -- a stage on, well inside its life
		s.Trees.GrowTick(s.now)
		t.ok(rec.stage > 0.25, "it grew a stage")
		t.ok(rec.ghost)
		for _, part in ipairs(s.sectionsOf(rec.model)) do
			t.eq(part.CanCollide, false, "a ghost")
		end
		s.run() -- still blocked: it waits again
		t.ok(rec.ghost)
		s.blocked = false
		s.run()
		t.ok(not rec.ghost)
		for _, part in ipairs(s.sectionsOf(rec.model)) do
			t.eq(part.CanCollide, true, "solid once clear")
		end
	end)

	t.test("an Elder is a 1.7x tree; removing one sinks it and forgets it", function()
		local s = setup()
		local ForestLogic = t.shared("ForestLogic")
		local def = s.WoodData.Get("oak")
		local model = s.Trees.SpawnTree("oak", CFrame.new(0, 0, 0), {
			seed = 5,
			size = ForestLogic.ElderSize(def),
			temporary = true,
		})
		local rec = s.Trees.GetTree(model:GetAttribute("Uid"))
		t.ok(rec.elder and rec.scale == 1.7)
		t.eq(model:GetAttribute("Elder"), true)
		t.eq(rec.size.name, "elder")
		s.Trees.Remove(rec.uid)
		t.eq(s.Trees.GetTree(rec.uid), nil)
		t.eq(model:GetAttribute("Dead"), true, "it sinks like a dead tree")
		s.run()
		t.eq(model.Parent, nil)
	end)

	t.test("2x Wood: pieces cut while it lasts carry boost 2", function()
		local s = setup()
		local rec = s.tree("oak")
		local p = s.player(1)
		s.Trees.LogMultiplier = function()
			return 2
		end
		local _, _, _, result = s.cutThrough(p, rec.sections[1])
		t.eq(result.freed[1].boost, 2)
		t.eq(result.freed[1].model:GetAttribute("Boost"), 2)
	end)
end
