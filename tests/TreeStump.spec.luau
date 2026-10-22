--!nocheck
-- TreeStump (T420): what a felled tree leaves and how the logs behave.
-- Numbered 8.1 to 8.9, one per rule of Connor's brief:
--   8.1 a tree falls from the cut point toward the side that was cut
--   8.2 logs never break on their own; players cut a trunk anywhere
--   8.3 the chop line (the notch) is dark and deepens with every hit
--   8.4 a cut below 2.5 studs is a base cut: no stump, the whole tree drops
--   8.5 the stump is the same trunk below the cut: tapered frustum (one of
--       16, ratios 0.85 to 1.00), base radius exact, top radius within
--       0.05 of the trunk's radius at the cut, flush cap with a 0.1 ring
--   8.6 weathering from 90 s, fade 180 to 190 s sinking 0.3, then gone and
--       the spot is free
--   8.7 a re-cut makes a normal log of at least 2 studs (the cut moves
--       down to keep it); the remainder restarts the timer and weathering
--   8.8 a stump is only ever re-cut through the server's Chop handler
--   8.9 a standing stump cannot be dragged or sold, and is never saved
-- The harness (setup) is SectionTrees.spec's: engine queries, players,
-- physics and timers faked; WoodService and GrabService are real.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Instance, Color3 = roblox.Vector3, roblox.CFrame, roblox.Instance, roblox.Color3
	local StumpLogic = t.shared("StumpLogic")
	local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
	local TreeGen = t.shared("TreeGen")
	local TreeLogic = t.shared("TreeLogic")
	local WoodData = t.shared("WoodData")
	local ForestData = t.shared("ForestData")

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

		-- Cuts a tree's root until the whole site is open: the first cut
		-- leaves a stump, the second takes it.
		function s.clearSite(p, rec)
			local result = nil
			for _ = 1, 4 do
				if rec.slot then
					break
				end
				local sec = rec.sections[1]
				if not sec then
					break
				end
				local _, _, _, r = s.cutThrough(p, sec)
				result = result or r
			end
			return result
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

	local function stumpParts(model, name)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and (name == nil and d:GetAttribute("StumpDress") == true or d.Name == name) then
				table.insert(out, d)
			end
		end
		table.sort(out, function(a, b)
			return a.CFrame.Position.Y < b.CFrame.Position.Y
		end)
		return out
	end

	local function brightness(c)
		return c.R + c.G + c.B
	end

	-- A felled tree: a player whose root part is at height `rootY` aims at
	-- that height, so the cut is about `rootY` up the trunk.
	local function felled(rootY, woodId, seed)
		local s = setup()
		s.attrs.CoreLoopActive = 2
		local rec = s.tree(woodId or "oak", Vector3.zero, { seed = seed })
		local p = s.player(1, Vector3.new(4, rootY, 0))
		local before = {}
		for id, part in pairs(rec.sections) do
			before[id] = part
		end
		local base = rec.sections[1]
		local _, ok, _, result = s.cutThrough(p, base, 3000)
		t.ok(ok and result ~= nil and #result.freed > 0, "the tree was cut through")
		return s, rec, p, result, before
	end

	-- A trunk's segments from a real skeleton.
	local function segsOf(woodId, seed, scale, elder)
		local skel = TreeGen.Skeleton(woodId, seed, scale, { elder = elder })
		local trunk = {}
		for _, sec in ipairs(skel.sections) do
			if sec.depth < skel.trunkSegments then
				table.insert(trunk, sec)
			end
		end
		table.sort(trunk, function(a, b)
			return a.depth < b.depth
		end)
		local segs, total = {}, 0
		for _, sec in ipairs(trunk) do
			table.insert(segs, { length = sec.length, thickness = sec.thickness })
			total += sec.length
		end
		return segs, total
	end

	-- The trunk's radius at height h, worked out here from the segments
	-- (each tapers in a line to the next one's thickness), not by the module.
	local function trunkRadius(segs, h)
		local y = 0
		for i, seg in ipairs(segs) do
			if h <= y + seg.length + 1e-9 or i == #segs then
				local nextT = if segs[i + 1] then segs[i + 1].thickness else seg.thickness
				local u = math.clamp((h - y) / seg.length, 0, 1)
				return (seg.thickness + (nextT - seg.thickness) * u) / 2
			end
			y += seg.length
		end
		return 0
	end

	---------------------------------------------------------------------
	t.test("8.1 a tree falls from the cut point toward the side that was cut", function()
		local d = StumpLogic.FallDirection(Vector3.new(0.6, 0.4, 0.8))
		t.ok(
			d ~= nil and math.abs(d.X - 0.6) < 1e-6 and math.abs(d.Z - 0.8) < 1e-6 and d.Y == 0,
			"flat unit toward the face"
		)
		t.eq(StumpLogic.FallDirection(Vector3.new(0, 1, 0)), nil, "a face with no side has no direction")
		for _, spot in ipairs({
			Vector3.new(4, 3, 0),
			Vector3.new(-4, 3, 0),
			Vector3.new(0, 3, 4),
			Vector3.new(0, 3, -4),
		}) do
			local s = setup()
			local rec = s.tree("oak")
			local p = s.player(1, spot)
			local dir
			s.Trees.OnFelled = function(_, _, _, fallDir)
				dir = fallDir
			end
			local _, ok, _, result = s.cutThrough(p, rec.sections[1])
			t.ok(ok and dir ~= nil, "felled")
			local toCutter = Vector3.new(spot.X, 0, spot.Z).Unit
			-- The face cut is the trunk's own face nearest the cutter (a
			-- trunk turned up to 45 degrees), and the tree goes that way.
			t.ok(dir:Dot(toCutter) > 0.7, string.format("falls toward the side cut from %s", tostring(spot)))
			t.ok(math.abs(dir.Magnitude - 1) < 1e-6 and dir.Y == 0, "a flat unit direction")
			-- It tips from the cut: the log's lowest point is the cut height.
			local piece = result.freed[1]
			local lowest = math.huge
			for _, part in ipairs(piece.model:GetDescendants()) do
				if part:IsA("BasePart") and part.Name == "Section" then
					lowest = math.min(lowest, (part.CFrame * CFrame.new(0, -part.Size.Y / 2, 0)).Position.Y)
				end
			end
			t.ok(math.abs(lowest - result.hit.height) < 0.3, "the trunk starts at the cut point")
		end
	end)

	---------------------------------------------------------------------
	t.test("8.2 logs never break on their own, and a trunk can be cut anywhere", function()
		local s, _, p, result = felled(3, "oak")
		local piece = result.freed[1]
		local function count(tbl)
			local n = 0
			for _ in pairs(tbl) do
				n += 1
			end
			return n
		end
		local sections, length = count(piece.parts), 0 -- sections and their total length
		for _, part in pairs(piece.parts) do
			length += part.Size.Y
		end
		for _ = 1, 24 do
			s.now += 5
			s.Wood.StepFalls(s.now)
			s.Wood.Tick(s.now)
			s.run()
		end
		t.ok(not piece.dead and s.Wood.Get(piece.uid) == piece, "the log is still there")
		t.eq(count(piece.parts), sections, "no section split off by itself")
		local after = 0
		for _, part in pairs(piece.parts) do
			after += part.Size.Y
		end
		t.ok(math.abs(after - length) < 1e-6, "and none got shorter")
		local pieces = 0
		for _, q in pairs(s.Wood.All()) do
			if q.treeUid == piece.treeUid then
				pieces += 1
			end
		end
		t.eq(pieces, 1, "one log after two minutes of lying there")
		-- Cut anywhere: a third, a half, a stretch near either end.
		for _, fraction in ipairs({ 0.2, 0.5, 0.8 }) do
			local s2, _, p2, r2 = felled(3, "oak")
			local log = r2.freed[1]
			local trunk = log.root
			local length2 = trunk.Size.Y
			local localY = (fraction - 0.5) * length2
			local point = (trunk.CFrame * CFrame.new(trunk.Size.X / 2, localY, 0)).Position
			local normal = trunk.CFrame.XVector
			p2.root.Position = point + normal * 2
			local freed
			for _ = 1, 400 do
				s2.now += 0.7
				local ok, _, r = s2.Trees.Chop(p2, trunk, point, normal)
				t.ok(ok, "swing accepted")
				if r and #r.freed > 0 then
					freed = r
					break
				end
			end
			t.ok(freed ~= nil, "cut through at " .. fraction)
			t.ok(math.abs(freed.hit.height - fraction * length2) < 0.01, "right where it was swung at")
			t.ok(#freed.freed >= 1, "it came apart there")
		end
	end)

	---------------------------------------------------------------------
	t.test("8.3 the chop line is dark and deepens with every hit", function()
		local s = setup()
		local rec = s.tree("oak")
		local p = s.player(1)
		local base = rec.sections[1]
		local def = WoodData.Get("oak")
		local face = TreeArt.FaceLook(def)
		local depths = {}
		local hits = s.SectionLogic.HitsToCut(2, base.Size.X, 0.2)
		for i = 1, hits - 1 do
			local ok = s.swing(p, base)
			t.ok(ok, "swing " .. i)
			local notches = {}
			for _, d in ipairs(rec.model:GetDescendants()) do
				if d.Name == "Notch" then
					table.insert(notches, d)
				end
			end
			t.eq(#notches, 1, "one chop line, not one per hit")
			local n = notches[1]
			t.ok(brightness(n.Color) < brightness(face) - 0.05, "darker than the cut wood")
			table.insert(depths, math.min(n.Size.X, n.Size.Z) - 0.02)
		end
		t.ok(depths[1] > 0, "the first hit already shows a line")
		for i = 2, #depths do
			t.ok(depths[i] > depths[i - 1] + 1e-6, "deeper on hit " .. i)
		end
		t.ok(TreeArt.NotchDepth(2, 0.5, 1) > TreeArt.NotchDepth(2, 0.25, 1), "depth follows the damage dealt")
	end)

	---------------------------------------------------------------------
	t.test("8.4 a cut below 2.5 studs is a base cut: no stump, the whole tree drops", function()
		t.ok(StumpLogic.IsBaseCut(2.49) and StumpLogic.IsBaseCut(0.5), "below 2.5")
		t.ok(not StumpLogic.IsBaseCut(2.5) and not StumpLogic.IsBaseCut(4), "2.5 and up keeps a stump")
		for _, rootY in ipairs({ 1.5, 2.49 }) do
			local s = setup()
			s.attrs.CoreLoopActive = 2
			local rec = s.tree("oak")
			local p = s.player(1, Vector3.new(4, rootY, 0))
			local model = rec.model
			local sections = 0
			for _ in pairs(rec.sections) do
				sections += 1
			end
			local falls = 0
			s.Trees.OnFelled = function()
				falls += 1
			end
			local _, ok, _, result = s.cutThrough(p, rec.sections[1], 3000)
			t.ok(ok and result ~= nil, "cut")
			t.eq(falls, 1, "the tree fell")
			t.ok(result.hit.height < 2.5, "a base cut")
			local piece = result.freed[1]
			local carried = 0
			for _ in pairs(piece.parts) do
				carried += 1
			end
			t.eq(carried, sections, "every section of the tree is in the one log, base and all")
			t.ok(model.Parent == nil and rec.slot, "nothing is left standing: the spot is open")
			t.eq(#stumpParts(s.map), 0, "no stump anywhere")
		end
		local s, rec = felled(2.5, "oak")
		t.ok(#stumpParts(rec.model) > 0, "a cut at 2.5 up is a stump")
	end)

	---------------------------------------------------------------------
	t.test("8.5 the stump is the same trunk below the cut: 16 frustums, base exact, top within 0.05", function()
		-- The 16 shapes.
		t.eq(#StumpLogic.Ratios, 16)
		for i, r in ipairs(StumpLogic.Ratios) do
			t.ok(math.abs(r - (0.84 + i * 0.01)) < 1e-9, "ratio " .. i .. " is " .. r)
		end
		t.eq(StumpLogic.Ratios[1], 0.85)
		t.eq(StumpLogic.Ratios[16], 1)
		local r, i = StumpLogic.NearestRatio(0.934)
		t.ok(r == 0.93 and i == 9, "nearest of the 16")
		t.eq((StumpLogic.NearestRatio(0.5)), 0.85, "below the range takes the smallest")
		t.eq((StumpLogic.NearestRatio(1.3)), 1, "above takes the largest")
		-- Built: oak cut 3 up, measured on the parts.
		local s, rec, _, result = felled(3, "oak")
		local steps = stumpParts(rec.model, "StumpStep")
		t.ok(#steps >= 1, "a stump stands")
		t.eq(#stumpParts(rec.model, "Stump"), 0, "no straight post placeholder")
		local cap = stumpParts(rec.model, "StumpCap")[1]
		local ring = stumpParts(rec.model, "StumpRing")[1]
		t.ok(cap and ring, "cap and ring")
		local h = result.hit.height
		local baseY = rec.base.Y
		t.ok(
			math.abs((cap.CFrame.Position.Y + cap.Size.X / 2) - (baseY + h)) < 1e-4,
			"the cap is flush at the cut height"
		)
		t.ok(math.abs((cap.Size.Y / 2 + 0.1) - ring.Size.Y / 2) < 1e-4, "the ring shows 0.1 stud round the cap")
		t.eq(ring.Color, Color3.fromHex("3C2814"), "ring colour #3C2814")
		local core = TreeArt.FaceLook(WoodData.Get("oak"))
		t.eq(cap.Color, core, "cap is the core wood")
		t.ok(cap.CFrame.Position.Y > ring.CFrame.Position.Y, "the cap stands over the ring")
		local first = rec.sections[1]
		t.ok(first ~= nil and first.Parent == rec.model, "the hitbox section is still there to chop")
		-- Two radii, across species, sizes, seeds and cut heights.
		local checked, worst = 0, 0
		for _, def in ipairs(WoodData.All()) do
			local sizes = {}
			for _, size in ipairs(TreeLogic.Sizes) do
				table.insert(sizes, { scale = size.scale, elder = false })
			end
			table.insert(sizes, { scale = ForestData.Elder.scale, elder = true })
			for _, size in ipairs(sizes) do
				for seed = 1, 3 do
					local segs, total = segsOf(def.id, seed, size.scale, size.elder)
					local heights = { 2.5, 3, 3.5, 4, 4.5, 5, 6, math.min(total, 6) }
					for _, height in ipairs(heights) do
						if height >= 2.5 and height <= total + 1e-9 then
							local shape = StumpLogic.Shape(segs, height)
							local model = Instance.new("Model")
							local parts = TreeArt.StumpDress(def, model, CFrame.identity, shape)
							local bottom, ringPart, capPart = nil, nil, nil
							for _, part in ipairs(parts) do
								if
									part.Name == "StumpStep"
									and (bottom == nil or part.CFrame.Position.Y < bottom.CFrame.Position.Y)
								then
									bottom = part
								elseif part.Name == "StumpRing" then
									ringPart = part
								elseif part.Name == "StumpCap" then
									capPart = part
								end
							end
							local label = string.format("%s x%.2f seed %d cut %.1f", def.id, size.scale, seed, height)
							local baseRadius = segs[1].thickness / 2
							t.ok(math.abs(bottom.Size.Y / 2 - baseRadius) < 1e-4, label .. ": base radius exact")
							local topError = math.abs(ringPart.Size.Y / 2 - trunkRadius(segs, height))
							worst = math.max(worst, topError)
							t.ok(topError <= 0.05, string.format("%s: top radius off by %.4f", label, topError))
							t.ok(
								math.abs(capPart.CFrame.Position.Y + capPart.Size.X / 2 - height) < 1e-4,
								label .. ": cap flush"
							)
							checked += 1
						end
					end
				end
			end
		end
		t.ok(checked > 400, "the sweep covered " .. checked .. " stumps")
		t.ok(worst <= 0.05, "worst top-radius error " .. worst)
	end)

	---------------------------------------------------------------------
	t.test("8.6 a stump weathers from 90 s, fades 180 to 190 s sinking 0.3, then goes and frees the spot", function()
		t.eq(StumpLogic.WeatherStart, 90)
		t.eq(StumpLogic.FadeStart, 180)
		t.eq(StumpLogic.FadeEnd, 190)
		t.eq(StumpLogic.SinkDepth, 0.3)
		t.eq(StumpLogic.Weathering(89.9), 0)
		t.ok(StumpLogic.Weathering(135) > 0 and StumpLogic.Weathering(135) < 1)
		t.eq(StumpLogic.Weathering(180), 1)
		t.eq(StumpLogic.Fade(180), 0)
		t.ok(math.abs(StumpLogic.Fade(185) - 0.5) < 1e-9)
		t.ok(math.abs(StumpLogic.SinkAt(190) - 0.3) < 1e-9)
		t.ok(not StumpLogic.Gone(189.9) and StumpLogic.Gone(190))
		local s, rec = felled(3, "oak")
		local at = s.now
		local model = rec.model
		local step = stumpParts(model, "StumpStep")[1]
		local capPart = stumpParts(model, "StumpCap")[1]
		local fresh, freshY = step.Color, capPart.CFrame.Position.Y
		s.now = at + 89
		s.Trees.StumpStep(s.now)
		t.eq(step.Color, fresh, "no weathering before 90 s")
		s.now = at + 100
		s.Trees.StumpStep(s.now)
		local early = step.Color
		t.ok(early ~= fresh, "weathering has begun")
		s.now = at + 170
		s.Trees.StumpStep(s.now)
		t.ok(
			math.abs(step.Color.R - fresh.R) + math.abs(step.Color.G - fresh.G)
				> math.abs(early.R - fresh.R) + math.abs(early.G - fresh.G),
			"and deepens"
		)
		s.now = at + 179
		s.Trees.StumpStep(s.now)
		t.eq(step.Transparency, 0, "solid until 180 s")
		t.ok(math.abs(capPart.CFrame.Position.Y - freshY) < 1e-4, "not yet sinking")
		s.now = at + 185
		s.Trees.StumpStep(s.now)
		t.ok(math.abs(step.Transparency - 0.5) < 0.05, "half faded at 185 s")
		t.ok(math.abs((freshY - capPart.CFrame.Position.Y) - 0.15) < 0.02, "half sunk")
		s.now = at + 189.9
		s.Trees.StumpStep(s.now)
		t.ok(
			freshY - capPart.CFrame.Position.Y > 0.28 and freshY - capPart.CFrame.Position.Y <= 0.3 + 1e-4,
			"sunk 0.3 studs"
		)
		s.now = at + 190
		s.Trees.GrowTick(s.now)
		t.ok(model.Parent == nil, "the stump is gone")
		t.eq(#stumpParts(s.map), 0)
		t.ok(rec.slot or (not rec.felled and rec.stage == 0), "and the spot is free for a new tree")
		-- The site grows back on the wood's own clock at the latest.
		s.now = math.max(s.now, rec.regrowAt or 0) + 1
		s.Trees.GrowTick(s.now)
		t.ok(not rec.slot and not rec.felled, "a new tree")
	end)

	---------------------------------------------------------------------
	t.test("8.7 a re-cut frees a normal log of at least 2 studs; the remainder restarts its timer", function()
		local a = StumpLogic.Recut(3.5, 2)
		t.ok(
			not a.whole and math.abs(a.cutAt - 1.5) < 1e-9 and math.abs(a.logLength - 2) < 1e-9,
			"a cut 1.5 from the top moves down to leave 2"
		)
		local b = StumpLogic.Recut(3.5, 0.6)
		t.ok(not b.whole and b.cutAt == 0.6 and math.abs(b.logLength - 2.9) < 1e-9, "a deeper cut stays where it is")
		local c = StumpLogic.Recut(1.5, 1)
		t.ok(c.whole and c.logLength == 1.5, "a stump too short for a log comes away whole")
		local d = StumpLogic.Recut(2.4, 1)
		t.ok(d.whole, "a remainder under the cut edge is not kept")
		local s, rec, p, result = felled(3.5, "oak")
		local at = s.now
		local step = stumpParts(rec.model, "StumpStep")[1]
		local fresh = step.Color
		local hitbox = rec.sections[1]
		local h = hitbox.Size.Y
		t.ok(math.abs(h - result.hit.height) < 0.01, "the stump is as tall as the cut: " .. h)
		s.now = at + 100
		s.Trees.StumpStep(s.now)
		t.ok(step.Color ~= fresh, "weathered by 100 s")
		-- Cut it again low, from a player standing lower.
		local q = s.player(2, Vector3.new(4, 2, 0))
		local before = {}
		for uid in pairs(s.Wood.All()) do
			before[uid] = true
		end
		local _, ok, _, again = s.cutThrough(q, hitbox, 3000)
		t.ok(ok and again ~= nil and #again.freed == 1, "the re-cut frees one log")
		local log = again.freed[1]
		t.ok(not before[log.uid], "a new log")
		local length = 0
		for _, part in pairs(log.parts) do
			length += part.Size.Y
		end
		t.ok(math.abs(length - 2) < 0.01, "a log exactly 2 long: " .. length)
		t.ok(math.abs(hitbox.Size.Y - 1.5) < 0.01, "the cut moved down: the stump is 1.5")
		t.ok(rec.felled and not rec.slot, "what is left still stands")
		local cap = stumpParts(rec.model, "StumpCap")[1]
		t.ok(
			math.abs((cap.CFrame.Position.Y + cap.Size.X / 2) - (rec.base.Y + 1.5)) < 1e-4,
			"with its cap at the new cut"
		)
		local newStep = stumpParts(rec.model, "StumpStep")[1]
		t.eq(newStep.Color, fresh, "weathering restarted")
		t.ok(newStep.Transparency == 0)
		-- The clock restarted: the original 190 s mark leaves it standing, and
		-- 190 s after the re-cut it goes.
		local recutAt = s.now
		s.now = at + 190
		s.Trees.GrowTick(s.now)
		t.ok(rec.model.Parent ~= nil and not rec.slot, "still there at the old deadline")
		s.now = recutAt + 189
		s.Trees.GrowTick(s.now)
		t.ok(rec.model.Parent ~= nil and not rec.slot, "and 189 s after the re-cut")
		s.now = recutAt + 190
		s.Trees.GrowTick(s.now)
		t.ok(rec.model.Parent == nil or rec.slot or not rec.felled, "gone 190 s after the re-cut")
	end)

	---------------------------------------------------------------------
	t.test("8.8 a stump is only re-cut through the server's Chop handler", function()
		local s, rec, p = felled(3.5, "oak")
		local hitbox = rec.sections[1]
		t.eq(s.Wood.FromPart(hitbox), nil, "WoodService (and so ChopSaw) does not know it")
		for _, part in ipairs(stumpParts(rec.model)) do
			t.eq(s.Wood.FromPart(part), nil, part.Name .. " is not wood")
			t.ok(part.Anchored, part.Name .. " is anchored")
		end
		for name in pairs(s.Trees) do
			local lower = string.lower(name)
			t.ok(
				not string.find(lower, "cut") and not string.find(lower, "split"),
				"SectionTrees." .. name .. " is another way to cut"
			)
		end
		-- Time never shortens it.
		local height = hitbox.Size.Y
		for _ = 1, 40 do
			s.now += 3
			s.Trees.StumpStep(s.now)
		end
		t.eq(hitbox.Size.Y, height, "only a swing changes it")
		-- A swing is checked like any other.
		s.allow = false
		local ok, why = s.swing(p, hitbox)
		t.ok(not ok and why == "rate", "rate limited")
		s.allow = true
		local far = s.player(2, Vector3.new(40, 3, 0))
		local ok2, why2 = s.swing(far, hitbox)
		t.ok(not ok2 and why2 == "far", "out of reach")
		t.eq(hitbox.Size.Y, height, "neither touched it")
		local ok3 = s.swing(p, hitbox)
		t.ok(ok3, "the handler takes a swing at the stump")
		t.ok(#s.fxOf("Cut") > 0)
	end)

	---------------------------------------------------------------------
	t.test("8.9 a standing stump can't be dragged or sold, and is never saved", function()
		local s, rec, p, _, _ = felled(3, "oak")
		local hitbox = rec.sections[1]
		local near = s.player(2, hitbox.CFrame.Position + Vector3.new(3, 1, 0))
		local targets = { hitbox }
		for _, part in ipairs(stumpParts(rec.model)) do
			table.insert(targets, part)
		end
		for _, part in ipairs(targets) do
			local ok, why = s.Grab.Grab(near, part, part.CFrame.Position)
			t.ok(not ok and why == "unknown", part.Name .. " can't be grabbed: " .. tostring(why))
			t.eq(s.Wood.FromPart(part), nil, part.Name .. " is not a sellable piece")
		end
		for _, piece in pairs(s.Wood.All()) do
			for _, part in ipairs(targets) do
				t.ok(not part:IsDescendantOf(piece.model), "no piece carries the stump")
			end
		end
		local Schema = t.loader():server("ProfileSchema")
		local function scan(tbl, path, seen)
			if seen[tbl] then
				return
			end
			seen[tbl] = true
			for k, v in pairs(tbl) do
				t.ok(
					not string.find(string.lower(tostring(k)), "stump"),
					"the save has no stump field: " .. path .. "." .. tostring(k)
				)
				if type(v) == "table" then
					scan(v, path .. "." .. tostring(k), seen)
				end
			end
		end
		scan(Schema.Template, "Template", {})
	end)
end
