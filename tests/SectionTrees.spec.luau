--!nocheck
-- SectionTrees (V2_PLAN.md M1.3): the v2 loop's standing trees. The Chop
-- remote's checks and their reasons (cooldown, far, noLOS, tooHard), a
-- felling (OnFelled once, a ground cut leaves nothing, a high cut leaves
-- a cuttable base), limbing, the regrow from a sapling through the
-- growth stages, death, the Gloam Hollow's dormancy and the ghost-until-
-- clear. The engine's queries (Raycast, GetPartBoundsInBox), players,
-- physics and timers are faked; WoodService and GrabService are real.
return function(t)
	local roblox = t.roblox
	local Vector2, Vector3, CFrame, Instance = roblox.Vector2, roblox.Vector3, roblox.CFrame, roblox.Instance

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
			obstacles = {},
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
			GetPartBoundsInBox = function(_, cf, size, params)
				if s.blocked then
					return { "someone" }
				end
				local include = if params then params.FilterDescendantsInstances else nil
				if not include then
					return {}
				end
				local function hits(part)
					if params.RespectCanCollide and part.CanCollide == false then
						return false
					end
					local rel = cf:PointToObjectSpace(part.CFrame.Position)
					local reach = part.Size.Magnitude / 2
					local h = size / 2
					return math.abs(rel.X) <= h.X + reach
						and math.abs(rel.Y) <= h.Y + reach
						and math.abs(rel.Z) <= h.Z + reach
				end
				local function scan(inst)
					if typeof(inst) ~= "Instance" then
						return nil
					end
					if inst:IsA("BasePart") and hits(inst) then
						return inst
					end
					for _, d in ipairs(inst:GetDescendants()) do
						if d:IsA("BasePart") and hits(d) then
							return d
						end
					end
					return nil
				end
				for _, inst in ipairs(include) do
					local hit = scan(inst)
					if hit then
						return { hit }
					end
				end
				return {}
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
				if tag == "Truck" then
					return s.trucks
				end
				local list = {}
				for _, model in ipairs(s.obstacles) do
					if model.Parent ~= nil and model:HasTag(tag) then
						table.insert(list, model)
					end
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
		s.loader = loader
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
				zone = opts.zone,
				cap = opts.cap,
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

		-- A solid model tagged `tag`, sitting on `cf`, big enough to overlap a trunk.
		function s.blocker(tag, cf, size)
			local model = Instance.new("Model")
			model.Name = tag
			local part = Instance.new("Part")
			part.Name = "Body"
			part.Size = size or Vector3.new(16, 16, 16)
			part.CFrame = cf
			part.CanCollide = true
			part.Parent = model
			model.PrimaryPart = part
			model:AddTag(tag)
			model.Parent = s.map
			if tag == "Truck" then
				table.insert(s.trucks, model)
			else
				table.insert(s.obstacles, model)
			end
			return model
		end

		function s.clearBlocker(model)
			local list = if model:HasTag("Truck") then s.trucks else s.obstacles
			local i = table.find(list, model)
			if i then
				table.remove(list, i)
			end
			model:Destroy()
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

	t.test("16 swings of the Rusty Axe through an oak's base remove the whole tree", function()
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
		t.eq(rec.model:GetAttribute("HP"), 1, "a standing tree reads as standing")
		local hits = s.SectionLogic.HitsToCut(2, base.Size.X, 0.2)
		t.eq(hits, 16, "the plan's oak: 16 hits with the hatchet")
		local n, ok, _, result = s.cutThrough(p, base)
		t.ok(ok, "every swing accepted")
		t.eq(n, 16)
		t.eq(#felled, 1, "OnFelled fires once")
		t.eq(felled[1].feller, p)
		t.eq(fellCredit, p)
		t.ok(rec.felled and rec.slot and not rec.alive, "the site is an open slot")
		t.eq(rec.stump, nil, "no stump")
		t.eq(rec.model.Parent, nil, "nothing left standing")
		t.eq(next(rec.sections), nil, "no rooted section")
		t.eq(#result.freed, 1)
		local piece = result.freed[1]
		t.eq(felled[1].uids, { piece.uid })
		t.ok(piece.model.Parent == s.Wood.Folder(), "the piece lies in TimberlineMap/Wood")
		t.ok(piece.model:HasTag("Wood"), "tagged Wood")
		t.eq(piece.ownerId, 1, "it's the cutter's")
		t.eq(piece.treeUid, rec.uid)
		t.ok(base:IsDescendantOf(piece.model), "the whole base went with the piece")
		t.ok(piece.model:FindFirstChild("CutFace", true) ~= nil, "a cut face on the freed log")
		for _, d in ipairs(piece.model:GetDescendants()) do
			if d:IsA("BasePart") then
				t.ok(not d.Anchored, d.Name .. " is loose")
			end
		end
		t.ok(felled[1].dir.X < 0, "away from the cutter")
		t.eq(#felled, 1, "still once")
	end)

	t.test("a high cut leaves a cuttable base; a second ground cut removes it", function()
		local s = setup()
		local rec = s.tree("oak")
		local p = s.player(1)
		local felled = 0
		s.Trees.OnFelled = function()
			felled += 1
		end
		local high: BasePart? = nil
		for id, part in pairs(rec.sections) do
			local depth = rec.depth[id] or 0
			if depth > 0 and depth < rec.trunkSegments then
				high = part
				break
			end
		end
		t.ok(high, "an oak has a trunk section above the root")
		local _, ok = s.cutThrough(p, high)
		t.ok(ok)
		t.eq(felled, 1, "OnFelled once, on the first trunk cut")
		t.ok(rec.felled and rec.alive and not rec.slot, "the base is still a tree")
		t.eq(rec.regrowAt, nil, "the slot is not open yet")
		t.ok(not rec.model:HasTag("Stump"))
		t.eq(rec.model:GetAttribute("Felled"), false, "the base does not play the fall")
		t.eq(rec.model:GetAttribute("HP"), 1)
		local base = rec.sections[1]
		t.ok(base and base.Parent == rec.model, "the root is still rooted")
		s.cutThrough(p, base)
		t.eq(felled, 1, "the second cut does not fell it again")
		t.ok(rec.slot and not rec.alive)
		t.eq(rec.model.Parent, nil)
		t.eq(next(rec.sections), nil)
	end)

	t.test("wood on someone's truck bed, or anyone's while they're here, is theirs to cut", function()
		local s = setup()
		local rec = s.tree("oak")
		local owner = s.player(1)
		local _, _, _, result = s.cutThrough(owner, rec.sections[1])
		local piece = result.freed[1]
		local other = s.player(2)
		s.now += 600 -- long past the pickup grace
		local onBed = true
		s.Grab.Hooks.bedOwner = function(p)
			return if onBed and p == piece then owner else nil
		end
		local part = piece.model.PrimaryPart
		local ok, why = s.swing(other, part)
		t.eq(ok, false)
		t.eq(why, "bed")
		onBed = false
		local ok2, why2 = s.swing(other, part)
		t.eq(ok2, false)
		t.eq(why2, "owned", "off the bed it's still its owner's while they're here")
		s.byId[1] = nil -- the owner leaves
		t.ok(s.swing(other, part), "then anyone may cut it")
		s.Grab.Hooks.bedOwner = nil
	end)

	t.test("the first cut claims a tree: nobody else may cut it while its claimer is here and at it", function()
		local s = setup()
		local rec = s.tree("oak")
		local base = rec.sections[1]
		local a = s.player(1)
		local b = s.player(2, Vector3.new(4, 3, 1))
		t.eq(rec.model:GetAttribute("ClaimedBy"), nil, "nobody's yet")
		t.ok(s.swing(a, base), "the first cut")
		t.eq(rec.model:GetAttribute("ClaimedBy"), 1)
		local ok, why = s.swing(b, base)
		t.eq(ok, false)
		t.eq(why, "claimed")
		t.eq(s.toasts[#s.toasts][2], "P1 is cutting this tree. Find another one.")
		-- 59 s after their last hit it's still theirs.
		s.now += s.GameConfig.TreeClaimSec - 1.7
		t.eq(select(2, s.swing(b, base)), "claimed", "still theirs just inside TreeClaimSec")
		local _, okA, _, result = s.cutThrough(a, base)
		t.ok(okA, "the claimer carries on")
		t.eq(result.feller, a)
		t.eq(result.freed[1].ownerId, 1, "what falls is theirs")
		t.eq(rec.claim, nil, "down: the claim is over")
		t.eq(rec.model.Parent, nil, "and the tree is gone")
	end)

	t.test(
		"a claim lapses TreeClaimSec after its holder's last hit, or when they leave; the taker owns what falls",
		function()
			local s = setup()
			local rec = s.tree("oak")
			local base = rec.sections[1]
			local a = s.player(1)
			local b = s.player(2, Vector3.new(4, 3, 1))
			for _ = 1, 12 do
				t.ok(s.swing(a, base))
			end
			s.now += s.GameConfig.TreeClaimSec -- they wander off
			t.ok(s.swing(b, base), "free to take over")
			t.eq(rec.model:GetAttribute("ClaimedBy"), 2)
			t.eq(select(2, s.swing(a, base)), "claimed", "now it's theirs: the first claimer can't cut in")
			local _, _, _, result = s.cutThrough(b, base)
			t.eq(result.feller, b, "the taker fells it, though most of the cut was the first player's")
			t.eq(result.freed[1].ownerId, 2)
			-- Leaving frees a tree at once.
			local other = s.tree("oak", Vector3.new(60, 0, 0))
			local c = s.player(3, Vector3.new(64, 3, 0))
			local d = s.player(4, Vector3.new(64, 3, 1))
			t.ok(s.swing(c, other.sections[1]))
			t.eq(select(2, s.swing(d, other.sections[1])), "claimed")
			s.byId[3] = nil -- c leaves
			t.ok(s.swing(d, other.sections[1]), "their tree is free the moment they've gone")
			t.eq(other.model:GetAttribute("ClaimedBy"), 4)
		end
	)

	t.test("one tree at a time: a player's new claim frees their last tree", function()
		local s = setup()
		local first = s.tree("oak")
		local second = s.tree("oak", Vector3.new(0, 0, 8))
		local a = s.player(1)
		local b = s.player(2, Vector3.new(4, 3, 1))
		t.ok(s.swing(a, first.sections[1]))
		a.root.Position = Vector3.new(4, 3, 8)
		t.ok(s.swing(a, second.sections[1]), "on to another tree")
		t.eq(first.model:GetAttribute("ClaimedBy"), 0, "the first one is free again")
		t.eq(second.model:GetAttribute("ClaimedBy"), 1)
		t.ok(s.swing(b, first.sections[1]), "so someone else may cut it")
	end)

	t.test("an Elder is everyone's: no claim, and helpers cut it together", function()
		local s = setup()
		local ForestLogic = t.shared("ForestLogic")
		local model = s.Trees.SpawnTree("oak", CFrame.new(0, 0, 0), {
			seed = 5,
			size = ForestLogic.ElderSize(s.WoodData.Get("oak")),
			temporary = true,
		})
		local rec = s.Trees.GetTree(model:GetAttribute("Uid"))
		local base = rec.sections[1]
		local reach = base.Size.X / 2 + 3
		local a = s.player(1, Vector3.new(reach, 3, 0))
		local b = s.player(2, Vector3.new(reach, 3, 1))
		t.ok(s.swing(a, base))
		t.ok(s.swing(b, base), "a helper may cut in")
		t.eq(rec.claim, nil)
		t.eq(model:GetAttribute("ClaimedBy"), nil)
	end)

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

	t.test("a section grouped under a folder is still that section; a part with no parent is not", function()
		local s = setup()
		local rec = s.tree("oak")
		local part = rec.sections[1]
		local folder = Instance.new("Folder")
		folder.Name = "Trunk"
		folder.Parent = rec.model
		part.Parent = folder
		local found, id = s.Trees.FromPart(part)
		t.ok(found == rec)
		t.eq(id, part:GetAttribute("Section"))
		local p = s.player(1)
		t.ok(s.swing(p, part), "a swing at the nested section lands")
		part.Parent = nil
		found, id = s.Trees.FromPart(part)
		t.eq(found, nil, "streamed out")
		t.eq(id, nil)
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

	t.test("an open slot waits respawnSec times 0.7 to 1.3, then a sapling grows through four stages", function()
		local s = setup()
		s.Trees._roll = function()
			return 0.5
		end
		local rec = s.tree("oak")
		local old = rec.base
		local p = s.player(1)
		local regrown = 0
		s.Trees.OnRegrown = function()
			regrown += 1
		end
		s.cutThrough(p, rec.sections[1])
		t.ok(rec.slot)
		local def = s.WoodData.Get("oak")
		t.eq(math.floor((s.Trees.RegrowsIn(rec.uid) or 0) + 0.5), def.respawnSec, "the midpoint roll is 1x")
		s.Trees.GrowTick(s.now + def.respawnSec - 1)
		t.ok(rec.slot, "not yet")
		s.now += def.respawnSec
		s.Trees.GrowTick(s.now)
		t.ok(not rec.slot and not rec.felled, "back")
		t.eq(regrown, 1)
		t.eq(rec.stage, 0, "a sapling first")
		t.eq(rec.model:GetAttribute("Sapling"), true)
		t.ok(not rec.alive, "a sapling can't be cut")
		t.ok((rec.base - old).Magnitude >= 10, "a new spot, not the old base")
		t.ok(type(rec.model:GetAttribute("GrewAt")) == "number", "the clients' regrow spring")
		local growSec = def.v2.growSec
		local stages = {}
		for _ = 1, 4 do
			s.now += growSec / 4
			s.Trees.GrowTick(s.now)
			table.insert(stages, rec.stage)
		end
		t.eq(stages, { 0.25, 0.5, 0.75, 1 })
		t.ok(rec.alive, "mature and cuttable")
		t.eq(#s.sectionsOf(rec.model) > 1, true)
	end)

	t.test("the respawn roll is 0.7x at 0 and 1.3x at 1; a blocked spot retries", function()
		local s = setup()
		local rec = s.tree("oak")
		local p = s.player(1)
		local def = s.WoodData.Get("oak")
		s.Trees._roll = function()
			return 0
		end
		s.cutThrough(p, rec.sections[1])
		local low = s.Trees.RegrowsIn(rec.uid) or 0
		t.ok(math.abs(low - def.respawnSec * 0.7) < 0.01, "0.7x")
		s.now += low
		s.Trees.GrowTick(s.now)
		t.ok(not rec.slot, "it came back")
		s.now += def.v2.growSec
		s.Trees.GrowTick(s.now)
		t.ok(rec.sections[1], "mature enough to cut again")
		p.root.Position = rec.base + Vector3.new(4, 3, 0)
		s.Trees._roll = function()
			return 1
		end
		s.cutThrough(p, rec.sections[1])
		local high = s.Trees.RegrowsIn(rec.uid) or 0
		t.ok(math.abs(high - def.respawnSec * 1.3) < 0.01, "1.3x")
		s.Trees.GrowTick(s.now + def.respawnSec)
		t.ok(rec.slot, "1x is not enough for a 1.3 roll")
		-- A zone smaller than the 10-stud gap never yields a spot, so the slot retries.
		local stuck = s.tree("oak", Vector3.new(400, 0, 400), {
			seed = 3,
			zone = { id = "tiny", cx = 400, cz = 400, radius = 4, cap = 1 },
			cap = 1,
		})
		local q = s.player(9, Vector3.new(404, 3, 400))
		s.Trees._roll = function()
			return 0
		end
		s.cutThrough(q, stuck.sections[1])
		t.ok(stuck.slot)
		local due = stuck.regrowAt
		s.now = (due or s.now) + 1
		s.Trees.GrowTick(s.now)
		t.ok(stuck.slot, "no legal spot yet")
		t.eq(stuck.regrowAt, s.now + s.Trees.RetrySec, "a miss waits about 30s")
	end)

	t.test(
		"a tree lives its lifespan: its leaves drop at PreDeadAt, then it dies, sinks and the site regrows",
		function()
			local s = setup()
			s.Trees._roll = function()
				return 0.5
			end
			local rec = s.tree("oak")
			s.player(1) -- near enough to be sent the LeafFall
			local def = s.WoodData.Get("oak")
			local growSec = def.v2.growSec
			t.ok(rec.life >= growSec + 20 * 60 and rec.life <= growSec + 40 * 60, "mature, then 20 to 40 minutes")
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
			t.ok(rec.slot and rec.stump == nil, "an open slot once it has sunk")
			s.now += def.respawnSec + 1
			s.Trees.GrowTick(s.now)
			t.eq(rec.stage, 0, "a new sapling")
		end
	)

	t.test("a zone never grows past its cap across 50 regrows", function()
		local s = setup()
		s.Trees._roll = function()
			return 0
		end
		local zone = { id = "pen", cx = 0, cz = 0, radius = 0, fixed = true, cap = 3 }
		local recs = {}
		for i = 1, 3 do
			recs[i] = s.tree("oak", Vector3.new((i - 1) * 40, 0, 0), { seed = i, zone = zone, cap = 3 })
		end
		local wildZone = { id = "wild", cx = 200, cz = 0, radius = 0, fixed = true, cap = 2 }
		local wild = {}
		for i = 1, 2 do
			wild[i] = s.tree("birch", Vector3.new(200, 0, i * 40), { seed = 20 + i, zone = wildZone, cap = 2 })
		end
		local p = s.player(1)
		local growSec = s.WoodData.Get("oak").v2.growSec
		for cycle = 1, 50 do
			for _, rec in ipairs(recs) do
				p.root.Position = rec.base + Vector3.new(4, 3, 0)
				local _, ok = s.cutThrough(p, rec.sections[1])
				t.ok(ok, "cycle " .. cycle)
				s.now = (rec.regrowAt or s.now)
				s.Trees.GrowTick(s.now)
				s.now += growSec
				s.Trees.GrowTick(s.now)
			end
			local n, w = 0, 0
			for _, rec in pairs(s.Trees.AllTrees()) do
				local id = if rec.zone then rec.zone.id else ""
				if id == "pen" then
					n += 1
				elseif id == "wild" then
					w += 1
				end
			end
			t.eq(n, 3, "oak cap, cycle " .. cycle)
			t.eq(w, 2, "wild cap, cycle " .. cycle)
		end
	end)

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

	t.test(
		"a parked truck, a log or a placed plank on a cut site keeps the regrown tree a ghost until the site is clear",
		function()
			local function regrowBlocked(tag)
				local s = setup()
				local rec = s.tree("oak")
				local p = s.player(1)
				s.Trees._roll = function()
					return 0.5
				end
				s.cutThrough(p, rec.sections[1])
				t.ok(rec.slot, tag .. " felled")
				-- The slot grows back 12 studs off the old base.
				local blocker = s.blocker(tag, CFrame.new(12, 6, 0), Vector3.new(24, 24, 24))
				local def = s.WoodData.Get("oak")
				s.now += def.respawnSec
				s.Trees.GrowTick(s.now)
				t.eq(rec.stage, 0, tag .. " sapling first")
				s.now += def.v2.growSec / 4
				s.Trees.GrowTick(s.now)
				t.ok(rec.stage > 0, tag .. " grew a stage on the cut site")
				t.ok(rec.ghost, tag .. " stays a ghost")
				for _, part in ipairs(s.sectionsOf(rec.model)) do
					t.eq(part.CanCollide, false, tag)
				end
				s.run()
				t.ok(rec.ghost, tag .. " still blocked")
				s.clearBlocker(blocker)
				s.run()
				t.ok(not rec.ghost, tag .. " solid once clear")
				for _, part in ipairs(s.sectionsOf(rec.model)) do
					t.eq(part.CanCollide, true, tag)
				end
			end
			regrowBlocked("Truck")
			regrowBlocked("Wood")
			regrowBlocked("PlacedItem")
		end
	)

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

	-- The live Chop remote (crown clicks included) lands in SectionTrees.Chop.
	-- The Lux tag is decided there from the equipped axe, then copied onto
	-- the piece the cut frees.
	t.test("a Lux chop tags the freed piece; another axe does not", function()
		local s = setup()
		local rec = s.tree("oak")
		local p = s.player(1)
		s.axe = "LuxAxe"
		local _, _, _, result = s.cutThrough(p, rec.sections[1])
		local piece = result.freed[1]
		t.eq(piece.lux, true)
		t.eq(piece.model:GetAttribute("LuxCut"), true)
		local plain = s.tree("oak", Vector3.new(30, 0, 0))
		p.root.Position = Vector3.new(34, 3, 0)
		s.axe = "RustyAxe"
		local _, _, _, other = s.cutThrough(p, plain.sections[1])
		t.eq(other.freed[1].lux, false)
		t.eq(other.freed[1].model:GetAttribute("LuxCut"), nil)
	end)

	t.test(
		"a boot site tells OnPlanted (the forest is planted after the server is up, LOAD-01); other trees don't",
		function()
			local s = setup()
			local planted = {}
			s.Trees.OnPlanted = function(rec)
				table.insert(planted, rec.uid)
			end
			local a = s.Trees.SpawnTree("oak", CFrame.new(Vector3.new(120, 0, 40)), { boot = true })
			t.eq(#planted, 1)
			t.eq(planted[1], a:GetAttribute("Uid"))
			s.Trees.SpawnTree("oak", CFrame.new(Vector3.new(160, 0, 40)), {}) -- a regrow or tutorial tree
			t.eq(#planted, 1, "only boot sites")
		end
	)

	t.test("a boot site stands as GrowLogic.BootTree says (the preview's v2 world draws the same forest)", function()
		local s = setup()
		local young, n = 0, 0
		for i = 1, 40 do
			local pos = Vector3.new(i * 37.3, 0, -i * 11.9)
			local model = s.Trees.SpawnTree("oak", CFrame.new(pos), { boot = true })
			local rec = s.Trees.GetTree(model:GetAttribute("Uid"))
			local boot = s.GrowLogic.BootTree(s.WoodData.Get("oak"), pos)
			t.eq(rec.seed, boot.seed)
			t.eq(rec.scale, boot.scale)
			t.eq(rec.stage, boot.stage)
			t.ok(math.abs((s.now - rec.bornAt) - boot.age) < 1e-6, "the same age")
			t.ok(rec.stage > 0, "never a sapling at boot")
			n += 1
			if rec.stage < 1 then
				young += 1
			end
		end
		t.ok(young > 0 and young < n / 2, "some young, most mature")
	end)

	-- TruckLoad locks from the section's box (CargoLock), never from mesh
	-- triangles. A mesh that keeps that box fits and sells the same.
	t.test("a meshed oak section fits the truck, sells the same, and one chop removes one section", function()
		local plain = setup()
		local plainRec = plain.tree("oak")
		local leafId, plainLeaf = nil, nil
		for sid, section in pairs(plainRec.sections) do
			local node = plainRec.nodes[sid]
			if node and #node.children == 0 then
				leafId, plainLeaf = sid, section
				break
			end
		end
		t.ok(plainLeaf, "an oak has a tip section")

		local meshed = setup()
		local MeshKit = meshed.loader:load("ReplicatedStorage/Shared/Art/MeshKit")
		MeshKit.Reset()
		MeshKit.Override = function(id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
		local rec = meshed.tree("oak")
		MeshKit.Override = nil
		local leaf = rec.sections[leafId]
		t.ok(leaf:IsA("MeshPart"), "the section is the mesh")
		t.ok((leaf.Size - plainLeaf.Size).Magnitude < 1e-3, "the mesh keeps the block's size")
		t.eq(leaf.CanCollide, true)
		t.eq(leaf.CanQuery, true)

		local CargoLock = meshed.loader:shared("CargoLock")
		local bedSize = Vector3.new(8, 1, 16)
		local function lockOf(size)
			-- Sitting on the bed, the pose TruckLoad's box test uses.
			local rel = CFrame.new(0, bedSize.Y / 2 + size.Y / 2, 0)
			local share = CargoLock.InsideShare(bedSize, rel, size)
			local on = CargoLock.ContactsBed(bedSize, rel, size)
			return share, CargoLock.MayLock(share, on, false)
		end
		local plainShare, plainLocks = lockOf(plainLeaf.Size)
		local meshShare, meshLocks = lockOf(leaf.Size)
		t.ok(math.abs(meshShare - plainShare) < 1e-6, "the same share of the bed")
		t.eq(meshLocks, true, "the mesh section fits TruckLoad's lock")
		t.eq(plainLocks, true)

		local SellLogic = meshed.loader:shared("SellLogic")
		local function sell(size)
			local volume = meshed.SectionLogic.Volume(size.X, size.Y, size.Z)
			return SellLogic.PieceValue("oak", "log", volume, nil, 1, false)
		end
		t.eq(sell(leaf.Size), sell(plainLeaf.Size))

		local before = 0
		for _ in pairs(rec.sections) do
			before += 1
		end
		local player = meshed.player(1, leaf.CFrame.Position + Vector3.new(2.5, 0, 0))
		local _, ok, why, result = meshed.cutThrough(player, leaf)
		t.ok(ok, tostring(why))
		t.eq(#result.freed, 1)
		local freedSections = 0
		for _, d in ipairs(result.freed[1].model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Section" then
				freedSections += 1
			end
		end
		t.eq(freedSections, 1, "one oak chop removes one section")
		local after = 0
		for _ in pairs(rec.sections) do
			after += 1
		end
		t.eq(after, before, "the stub stays and no other section leaves")

		local plainPlayer = plain.player(1, plainLeaf.CFrame.Position + Vector3.new(2.5, 0, 0))
		local _, plainOk, _, plainResult = plain.cutThrough(plainPlayer, plainLeaf)
		t.ok(plainOk)
		t.eq(result.freed[1].volume, plainResult.freed[1].volume)
		t.eq(result.freed[1].value, plainResult.freed[1].value)
		MeshKit.Reset()
	end)

	t.test("a boot tree standing in a haul road regrows off it within one tick", function()
		local s = setup()
		-- SectionTrees loads WorldPlan, which binds this loader's TreeFill.
		local WorldLayout = s.loader:load("ReplicatedStorage/Shared/World/WorldLayout")
		local TreeFill = s.loader:load("ReplicatedStorage/Shared/World/TreeFill")
		local TerrainGen = s.loader:load("ReplicatedStorage/Shared/World/TerrainGen")
		local haul = { HillsRoad = true, SnowRoad = true, VolcanoRoad = true, SkyrootRoad = true }
		local spot = nil
		for _, road in ipairs(WorldLayout.Roads) do
			if haul[road.name] and not spot then
				local pts = road.points
				for i = 1, #pts - 1 do
					if spot then
						break
					end
					local mid = pts[i]:Lerp(pts[i + 1], 0.5)
					if TreeFill.InHaulLane(mid.X, mid.Y) then
						local along = pts[i + 1] - pts[i]
						local len = along.Magnitude
						if len > 1 then
							local side = Vector2.new(-along.Y / len, along.X / len)
							for _, reach in ipairs({ 28, 36, 48 }) do
								for _, sign in ipairs({ 1, -1 }) do
									local q = mid + side * (sign * reach)
									if TreeFill.Ground(q.X, q.Y) then
										spot = {
											x = mid.X,
											z = mid.Y,
											qx = q.X,
											qz = q.Y,
											radius = reach + 16,
										}
									end
								end
							end
						end
					end
				end
			end
		end
		t.ok(spot ~= nil, "a haul road has ground beside it")
		local here = spot :: { x: number, z: number, qx: number, qz: number, radius: number }
		local y = TerrainGen.HeightAt(here.x, here.z) - 0.3
		local model = s.Trees.SpawnTree("oak", CFrame.new(here.x, y, here.z), {
			boot = true,
			seed = 11,
			zone = { id = "road", cx = here.x, cz = here.z, radius = here.radius },
		})
		-- The first FindSpot sample lands on the ground beside the road.
		local dx, dz = here.qx - here.x, here.qz - here.z
		local angle = math.atan2(dz, dx)
		if angle < 0 then
			angle += math.pi * 2
		end
		local reach = math.sqrt(dx * dx + dz * dz)
		local want = { angle / (math.pi * 2), (reach / here.radius) ^ 2 }
		local n = 0
		s.Trees._roll = function()
			n += 1
			local target = want[n] or 0
			return (target - n * 0.173) % 1
		end
		t.eq(model, nil, "it does not stand in the lane")
		local rec = nil
		for _, tree in pairs(s.Trees.AllTrees()) do
			if tree.zone and tree.zone.id == "road" then
				rec = tree
			end
		end
		t.ok(rec ~= nil and rec.slot and rec.regrowAt == s.now, "the first regrow is due now")
		s.Trees.GrowTick(s.now)
		t.ok(rec ~= nil and not rec.slot and rec.model ~= nil and rec.model.Parent ~= nil, "standing after one tick")
		t.ok(not TreeFill.InHaulLane(rec.base.X, rec.base.Z), "off the road")
		t.ok(TreeFill.Ground(rec.base.X, rec.base.Z), "on legal ground")
	end)

	t.test("a haul-road boot tree that cannot move waits RetrySec", function()
		local s = setup()
		local WorldLayout = s.loader:load("ReplicatedStorage/Shared/World/WorldLayout")
		local TreeFill = s.loader:load("ReplicatedStorage/Shared/World/TreeFill")
		local TerrainGen = s.loader:load("ReplicatedStorage/Shared/World/TerrainGen")
		local mid = nil
		for _, road in ipairs(WorldLayout.Roads) do
			if road.name == "HillsRoad" then
				mid = road.points[1]:Lerp(road.points[2], 0.5)
			end
		end
		t.ok(mid ~= nil and TreeFill.InHaulLane(mid.X, mid.Y), "the road sample is in the lane")
		local y = TerrainGen.HeightAt(mid.X, mid.Y) - 0.3
		s.Trees.SpawnTree("oak", CFrame.new(mid.X, y, mid.Y), {
			boot = true,
			seed = 12,
			zone = { id = "stuckroad", cx = mid.X, cz = mid.Y, radius = 4 },
		})
		local rec = nil
		for _, tree in pairs(s.Trees.AllTrees()) do
			if tree.zone and tree.zone.id == "stuckroad" then
				rec = tree
			end
		end
		t.ok(rec ~= nil and rec.slot)
		s.Trees.GrowTick(s.now)
		t.ok(rec.slot, "the disc is smaller than the gap from the old spot")
		t.eq(rec.regrowAt, s.now + s.Trees.RetrySec)
	end)

	t.test("rooted trees over the cap hold a regrow for RetrySec", function()
		local s = setup()
		s.Trees._roll = function()
			return 0
		end
		local zone = { id = "packed", cx = 500, cz = 500, radius = 80, cap = 1 }
		local recs = {}
		for i = 1, 3 do
			recs[i] = s.tree("oak", Vector3.new(500 + (i - 1) * 30, 0, 500), { seed = i, zone = zone, cap = 1 })
		end
		local p = s.player(1, recs[1].base + Vector3.new(4, 3, 0))
		local _, ok = s.cutThrough(p, recs[1].sections[1])
		t.ok(ok)
		t.ok(recs[1].slot)
		s.now = recs[1].regrowAt or s.now
		s.Trees.GrowTick(s.now)
		t.ok(recs[1].slot, "two rooted trees still fill a cap of 1")
		t.eq(recs[1].regrowAt, s.now + s.Trees.RetrySec)
	end)

	t.test("a zone at its cap of rooted trees holds the open slot for RetrySec", function()
		local s = setup()
		s.Trees._roll = function()
			return 0
		end
		local cap = 2
		local zone = { id = "full", cx = 800, cz = 800, radius = 80, cap = cap }
		local recs = {}
		for i = 1, cap + 1 do
			recs[i] = s.tree("oak", Vector3.new(800 + (i - 1) * 30, 0, 800), { seed = i, zone = zone, cap = cap })
		end
		local p = s.player(1, recs[1].base + Vector3.new(4, 3, 0))
		local _, ok = s.cutThrough(p, recs[1].sections[1])
		t.ok(ok)
		t.ok(recs[1].slot)
		local rooted = 0
		for i = 2, cap + 1 do
			t.ok(not recs[i].slot)
			rooted += 1
		end
		t.eq(rooted, cap, "the zone is exactly at its cap")
		s.now = recs[1].regrowAt or s.now
		s.Trees.GrowTick(s.now)
		t.ok(recs[1].slot, "tryRegrow leaves the slot open")
		t.eq(recs[1].regrowAt, s.now + s.Trees.RetrySec)
	end)
end
