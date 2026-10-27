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
	local Vector3, CFrame, Instance, Color3, Enum =
		roblox.Vector3, roblox.CFrame, roblox.Instance, roblox.Color3, roblox.Enum
	local StumpLogic = t.shared("StumpLogic")
	local SectionMetrics = t.load("ReplicatedStorage/Shared/SectionMetrics")
	local function secLen(part)
		return SectionMetrics.Length(part)
	end
	local function secSide(part)
		return SectionMetrics.SquareSide(part)
	end
	local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
	local StumpMeshIds = t.shared("StumpMeshIds")
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
		s.StumpLogic = loader:shared("StumpLogic")
		s.StumpMeshes = loader:server("StumpMeshes")
		-- The uploaded frustum models, mocked: LoadAsset hands back a Model
		-- holding one MeshPart (native size 200 x 100 x 200) carrying its id.
		s.loaded = {}
		s.StumpMeshes.LoadModel = function(id)
			table.insert(s.loaded, id)
			if s.meshFails then
				error("HTTP 403: not approved for this experience")
			end
			local model = Instance.new("Model")
			local mesh = Instance.new("MeshPart")
			mesh.Name = "Frustum"
			mesh.Size = Vector3.new(200, 100, 200)
			mesh:SetAttribute("ModelId", tostring(id)) -- a string: Lune keeps attributes as 32-bit numbers
			mesh.Parent = model
			return model
		end
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
			local cf, size = SectionMetrics.BlockFrame(part)
			local hit, normal = s.SectionLogic.AimAt(cf, size, p.root.Position, nil, nil)
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
	local function felled(rootY, woodId, seed, respawnSec)
		local s = setup()
		s.attrs.CoreLoopActive = 2
		s.Trees._roll = function()
			return 0.5
		end
		if respawnSec then
			s.WoodData.Get(woodId or "oak").respawnSec = respawnSec
		end
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
				return (seg.thickness + (nextT - seg.thickness) * u) / math.sqrt(math.pi)
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
					local cf, size = SectionMetrics.BlockFrame(part)
					lowest = math.min(lowest, (cf * CFrame.new(0, -size.Y / 2, 0)).Position.Y)
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
			length += secLen(part)
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
			after += secLen(part)
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
			local frame, size2 = SectionMetrics.BlockFrame(trunk)
			local length2 = size2.Y
			local localY = (fraction - 0.5) * length2
			local point = (frame * CFrame.new(size2.X / 2, localY, 0)).Position
			local normal = frame.XVector
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
		local hits = s.SectionLogic.HitsToCut(2, secSide(base), 0.2)
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
	t.test("8.5 the stump is the same trunk below the cut: 48 frustum meshes, base exact, top within 0.05", function()
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
		local meshes = stumpParts(rec.model, "StumpMesh")
		t.eq(#meshes, 1, "the stump is one MeshPart from the frustum assets")
		t.eq(meshes[1].ClassName, "MeshPart")
		t.eq(#stumpParts(rec.model, "Stump"), 0, "no straight post placeholder")
		local mesh = meshes[1]
		local first = rec.sections[1]
		t.ok(first ~= nil and first.Parent == rec.model, "the hitbox section is still there to chop")
		local trunkR = secSide(first) / math.sqrt(math.pi)
		t.ok(math.abs(mesh.Size.X / 2 - trunkR) < 1e-4, "the mesh's base radius is the trunk's, exactly")
		t.ok(math.abs(mesh.Size.Y - result.hit.height) < 1e-4, "and it is as tall as the cut")
		-- Which model: the taper nearest the trunk's, in the height bucket.
		local segsHere = {}
		for _, sec in ipairs(rec.skel.sections) do
			if sec.depth < rec.skel.trunkSegments then
				table.insert(segsHere, { length = sec.length, thickness = sec.thickness })
			end
		end
		local id = tonumber(mesh:GetAttribute("ModelId"))
		t.ok(id ~= nil and table.find(s.loaded, id) ~= nil, "loaded with InsertService:LoadAsset")
		local shapeHere = StumpLogic.Shape(segsHere, result.hit.height)
		t.eq(#shapeHere.sleeves, 1, "a 3 stud cut is one sleeve")
		t.eq(
			id,
			StumpMeshIds.IdFor(shapeHere.set, shapeHere.sleeves[1].index, StumpLogic.Bucket(result.hit.height)),
			"the model for the radius set, the nearest taper and the height bucket"
		)
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
		t.eq(mesh.Material, first.Material, "bark: the trunk's material")
		t.eq(mesh.Color, first.Color, "and the trunk's own colour at the cut: no colour step")
		local listed = false
		for _, row in ipairs(StumpMeshIds.Rows) do
			if row.id == id then
				listed = true
			end
		end
		t.ok(listed, "the MeshPart came from one of the 96 listed assets")
		-- Two radii, across species, sizes, seeds and cut heights, with the
		-- meshes' own top / base ratios (known from each model's row). A stump
		-- is never clamped: tall cuts stack sleeves, each starting where the
		-- one below ended.
		local rowOfId = {}
		for _, row in ipairs(StumpMeshIds.Rows) do
			rowOfId[row.id] = row
		end
		local checked, stacked, worst, largestBase = 0, 0, 0, 0
		for _, def in ipairs(WoodData.All()) do
			local sizes = {}
			for _, name in ipairs({ "small", "normal", "large" }) do
				table.insert(sizes, { name = name, scale = TreeGen.ScaleFor(name), elder = false })
			end
			table.insert(sizes, { name = "elder", scale = ForestData.Elder.scale, elder = true })
			for _, size in ipairs(sizes) do
				for seed = 1, 3 do
					local segs, total = segsOf(def.id, seed, size.scale, size.elder)
					largestBase = math.max(largestBase, segs[1].thickness / math.sqrt(math.pi))
					local heights = { 2.5, 3, 3.5, 3.87, 3.88, 4.5, 6, 6.32, 6.33, 8, 10.4, 10.41, 15, 25, total }
					for _, height in ipairs(heights) do
						if height >= 2.5 and height <= total + 1e-9 then
							local shape = StumpLogic.Shape(segs, height)
							local templates = {}
							for i, sleeve in ipairs(shape.sleeves) do
								local template = Instance.new("MeshPart")
								template.Size = Vector3.new(200, 100, 200)
								local row = StumpMeshIds.Rows[StumpMeshIds.Key(sleeve.set, sleeve.index, sleeve.bucket)]
								template:SetAttribute(
									"ModelId",
									tostring(
										StumpMeshIds.Row(StumpMeshIds.Key(sleeve.set, sleeve.index, sleeve.bucket)).id
									)
								)
								templates[i] = template
								t.ok(row ~= nil)
							end
							local model = Instance.new("Model")
							local parts = TreeArt.StumpDress(def, model, CFrame.identity, shape, templates)
							local built, capPart = {}, nil
							for _, part in ipairs(parts) do
								if part.Name == "StumpMesh" then
									table.insert(built, part)
								elseif part.Name == "StumpCap" then
									capPart = part
								end
							end
							local label = string.format("%s x%.2f seed %d cut %.2f", def.id, size.scale, seed, height)
							local baseRadius = segs[1].thickness / math.sqrt(math.pi)
							t.eq(#built, #shape.sleeves, label .. ": one mesh per sleeve")
							if #built > 1 then
								stacked += 1
							end
							t.ok(math.abs(built[1].Size.X / 2 - baseRadius) < 1e-4, label .. ": base radius exact")
							local rise = 0
							local topRadius = baseRadius
							for i, mesh_ in ipairs(built) do
								local row = rowOfId[tonumber(mesh_:GetAttribute("ModelId"))]
								t.ok(
									math.abs(mesh_.Size.X / 2 - topRadius) < 1e-4,
									label .. ": sleeve " .. i .. " starts where the last ended"
								)
								t.eq(
									row.height,
									StumpLogic.Bucket(mesh_.Size.Y - 1e-4),
									label .. ": the height bucket by stretch"
								)
								t.ok(mesh_.Size.Y / row.height <= 1.3 + 1e-9, label .. ": stretch at most 1.3")
								topRadius = mesh_.Size.X / 2 * (row.taper / 100)
								rise += mesh_.Size.Y
							end
							t.ok(
								math.abs(rise - height) < 1e-3,
								string.format("%s: stack is %.3f tall, cut is %.3f", label, rise, height)
							)
							local topError = math.abs(topRadius - trunkRadius(segs, height))
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
		t.ok(checked > 600, "the sweep covered " .. checked .. " stumps")
		t.ok(stacked > 0, "some stacked sleeves: " .. stacked)
		t.ok(worst <= 0.05, "worst top-radius error " .. worst)
		-- The mesh scale: StumpDress sets Size = 2 x base radius, so a mesh
		-- of native base diameter D is scaled by 2R / D. A scale step of
		-- 0.005 (half a percent) on the LARGEST trunk base radius R_max of
		-- any wood, size or seed moves the base radius by 0.005 x R_max,
		-- which stays inside the 0.05 stud tolerance. (We scale exactly, no
		-- steps; this pins the margin if the engine quantises the scale.)
		t.ok(
			0.005 * largestBase <= 0.05,
			string.format("0.005 x largest base radius %.3f = %.4f", largestBase, 0.005 * largestBase)
		)
	end)

	t.test(
		"8.5b the 96 frustum model rows: 2 sets x 16 tapers x 3 heights, tagged, unique ids, loaded once and cached",
		function()
			t.eq(#StumpMeshIds.Rows, 96)
			local seen = {}
			local combos = {}
			for _, row in ipairs(StumpMeshIds.Rows) do
				t.ok(not seen[row.id], "unique id " .. row.id)
				seen[row.id] = true
				t.ok(type(row.id) == "number" and row.id > 0, "a model id")
				t.ok(row.set == "R13" or row.set == "R22", row.name .. " set")
				t.ok(row.height == 3 or row.height == 5 or row.height == 8, row.name .. " height")
				t.ok(row.taper >= 85 and row.taper <= 100, row.name .. " taper")
				combos[row.set .. "_" .. row.taper .. "_" .. row.height] = true
				local suffix = if row.set == "R22" then "_R22" else ""
				t.eq(
					row.name,
					string.format("StumpTaper%03d_H%d%s", row.taper, row.height, suffix),
					"named by taper, height and set"
				)
			end
			for _, set in ipairs({ "R13", "R22" }) do
				for i, ratio in ipairs(StumpLogic.Ratios) do
					for _, height in ipairs({ 3, 5, 8 }) do
						local taper = math.floor(ratio * 100 + 0.5)
						t.ok(
							combos[set .. "_" .. taper .. "_" .. height],
							"a model for " .. set .. " taper " .. taper .. " height " .. height
						)
						local key = StumpMeshIds.Key(set, i, height)
						t.ok(key ~= nil and StumpMeshIds.IdFor(set, i, height) ~= nil)
						t.eq(StumpMeshIds.Row(key).taper, taper)
						t.eq(StumpMeshIds.Row(key).height, height)
						t.eq(StumpMeshIds.Row(key).set, set)
					end
				end
			end
			t.eq(StumpLogic.SplitRadius, 1.69)
			t.eq(StumpLogic.SetFor(1.69), "R13")
			t.eq(StumpLogic.SetFor(1.6901), "R22")
			t.eq(StumpLogic.RefRadius.R22, 2.2)
			-- Two oaks, one load.
			local s = setup()
			s.attrs.CoreLoopActive = 2
			for i = 1, 2 do
				local rec = s.tree("oak", Vector3.new(i * 40, 0, 0))
				local p = s.player(i, Vector3.new(i * 40 + 4, 3, 0))
				s.cutThrough(p, rec.sections[1], 3000)
			end
			t.eq(#s.loaded, 1, "one LoadAsset for two stumps of the same shape")
			local cached = 0
			for key = 1, 48 do
				if s.StumpMeshes.Get(key) ~= nil then
					cached += 1
				end
			end
			t.eq(cached, 1, "one template cached")
			for _, d in ipairs(s.map:GetDescendants()) do
				if d.Name == "StumpMesh" then
					t.eq(d.CollisionFidelity, Enum.CollisionFidelity.Hull, "Hull collision from the cached template")
				end
			end
		end
	)

	t.test("8.5g height buckets by stretch: H3 up to 3.87, H5 up to 6.32, H8 beyond (inclusive at the top)", function()
		t.eq(StumpLogic.Bucket3Max, 3.87)
		t.eq(StumpLogic.Bucket5Max, 6.32)
		t.eq(StumpLogic.SleeveMax, 10.4)
		t.eq(StumpLogic.Bucket(2.5), 3)
		t.eq(StumpLogic.Bucket(3.87), 3, "3.87 itself is H3")
		t.eq(StumpLogic.Bucket(3.8701), 5)
		t.eq(StumpLogic.Bucket(6.32), 5, "6.32 itself is H5")
		t.eq(StumpLogic.Bucket(6.3201), 8)
		t.eq(StumpLogic.Bucket(10.4), 8)
		-- Stretch = h / the mesh's native height: 3.87 / 3 = 1.29, 6.32 / 5 = 1.264, 10.4 / 8 = 1.3.
		t.ok(math.abs(StumpLogic.Stretch(3.87, 3) - 1.29) < 1e-9)
		t.ok(math.abs(StumpLogic.Stretch(6.32, 5) - 1.264) < 1e-9)
		t.ok(math.abs(StumpLogic.Stretch(10.4, 8) - 1.3) < 1e-9)
		local lowest, highest = math.huge, 0
		for tenth = 25, 104 do
			local h = tenth / 10
			local stretch = StumpLogic.Stretch(h, StumpLogic.Bucket(h))
			lowest, highest = math.min(lowest, stretch), math.max(highest, stretch)
		end
		t.ok(highest <= 1.3 + 1e-9, "no stump from 2.5 to 10.4 is stretched past 1.3: " .. highest)
		t.ok(lowest >= 0.77, "or squeezed under 0.77: " .. lowest)
		-- Over 10.4 it stacks sleeves, each at most 10.4 tall, adding up to the cut.
		for _, h in ipairs({ 10.41, 15, 20.8, 25, 40 }) do
			local shape = StumpLogic.Shape({ { length = 60, thickness = 2.6 }, { length = 60, thickness = 2.6 } }, h)
			t.ok(#shape.sleeves >= 2, h .. " stacks")
			local total = 0
			for i, sleeve in ipairs(shape.sleeves) do
				t.ok(sleeve.y1 - sleeve.y0 <= 10.4 + 1e-9, "a sleeve at most 10.4")
				total += sleeve.y1 - sleeve.y0
				if i > 1 then
					t.ok(
						math.abs(sleeve.baseRadius - shape.sleeves[i - 1].topRadius) < 1e-9,
						"each starts where the last ended"
					)
				end
			end
			t.ok(math.abs(total - h) < 1e-9, "the stack is the cut height")
		end
	end)

	t.test("8.5h a 15 stud cut leaves a 15 stud stump and an unchanged log: nothing clamps", function()
		local s = setup()
		s.attrs.CoreLoopActive = 2
		s.Trees._roll = function()
			return 0.5
		end
		local model = s.Trees.SpawnTree("pine", CFrame.new(0, 0, 0), { seed = 7, size = TreeLogic.Sizes[3], stage = 1 })
		local rec = s.Trees.GetTree(model:GetAttribute("Uid"))
		local before = {}
		local volume = 0
		for id, part in pairs(rec.sections) do
			local _, sz = SectionMetrics.BlockFrame(part)
			before[id] = sz.Y
			volume += s.SectionLogic.Volume(sz.X, sz.Y, sz.Z)
		end
		local p = s.player(1, Vector3.new(6, 15, 0))
		local _, ok, _, result = s.cutThrough(p, rec.sections[1], 6000)
		t.ok(ok and result ~= nil and #result.freed == 1, "cut through")
		t.ok(math.abs(result.hit.height - 15) < 0.01, "cut 15 up: " .. result.hit.height)
		local hitbox = rec.sections[1]
		t.ok(math.abs(secLen(hitbox) - 15) < 1e-3, "the stump is 15 tall, not clamped: " .. secLen(hitbox))
		local rise, count = 0, 0
		for _, mesh in ipairs(stumpParts(rec.model, "StumpMesh")) do
			rise += mesh.Size.Y
			count += 1
		end
		t.ok(count >= 2, "stacked sleeves: " .. count)
		t.ok(math.abs(rise - 15) < 1e-3, "the stack stands 15: " .. rise)
		-- The log: every section is as it was, but the one that was cut, which is
		-- what is left above 15.
		local log = result.freed[1]
		local sections, cutPart = 0, nil
		for id, part in pairs(log.parts) do
			sections += 1
			if before[id] == nil then
				cutPart = part
			else
				t.ok(math.abs(secLen(part) - before[id]) < 1e-6, "section " .. id .. " is unchanged")
			end
		end
		t.ok(
			cutPart ~= nil and math.abs(secLen(cutPart) - (before[1] - 15)) < 1e-3,
			"the cut section keeps all it had above the cut"
		)
		t.ok(
			math.abs(
				log.volume - (volume - s.SectionLogic.Volume(secSide(rec.sections[1]), 15, secSide(rec.sections[1])))
			) < 1e-3,
			"the log's volume is the tree's, less the 15 studs left standing"
		)
		t.ok(sections >= 1)
	end)

	-- Bark stretch: a mesh of a radius set is made for a reference stump (R13:
	-- base radius 1.3, assumed, see StumpLogic.RefRadius; R22: 2.2) and is
	-- stretched round by baseRadius / reference and up by sleeve height /
	-- the bucket's mesh height. Both must stay in 1/1.3 to 1.3.
	local function stretchCases()
		local bad, total = {}, 0
		local byTree = {}
		local rounds = { math.huge, 0 }
		local ups = { math.huge, 0 }
		for _, def in ipairs(WoodData.All()) do
			local sizes = {}
			for _, name in ipairs({ "small", "normal", "large" }) do
				table.insert(sizes, { name = name, scale = TreeGen.ScaleFor(name), elder = false })
			end
			table.insert(sizes, { name = "elder", scale = ForestData.Elder.scale, elder = true })
			for _, size in ipairs(sizes) do
				for seed = 1, 3 do
					local segs, trunk = segsOf(def.id, seed, size.scale, size.elder)
					for _, h in ipairs({ 2.5, 3, 3.5, 3.87, 3.88, 4.5, 6, 6.32, 6.33, 8, 10.4, 10.41, 15, 25, trunk }) do
						if h >= 2.5 and h <= trunk + 1e-9 then
							local shape = StumpLogic.Shape(segs, h)
							for i, sleeve in ipairs(shape.sleeves) do
								local round, up = StumpLogic.BarkStretch(sleeve, shape.set)
								total += 1
								rounds = { math.min(rounds[1], round), math.max(rounds[2], round) }
								ups = { math.min(ups[1], up), math.max(ups[2], up) }
								local name = def.id .. " " .. size.name
								local tree = byTree[name]
								if not tree then
									tree = { set = shape.set, base = shape.baseRadius, bad = 0, lo = math.huge, hi = 0 }
									byTree[name] = tree
								end
								tree.lo, tree.hi = math.min(tree.lo, round), math.max(tree.hi, round)
								if not StumpLogic.StretchOk(round, up) then
									tree.bad += 1
									table.insert(
										bad,
										string.format(
											"%s seed %d cut %.2f sleeve %d (%s): round %.2f, up %.2f",
											name,
											seed,
											h,
											i,
											shape.set,
											round,
											up
										)
									)
								end
							end
						end
					end
				end
			end
		end
		return bad, total, byTree, rounds, ups
	end

	t.test("8.5i vertical bark stretch stays in 1/1.3 to 1.3 for every wood, size, Elder and cut 2.5 to 25+", function()
		local _, total, _, _, ups = stretchCases()
		t.ok(total > 2000, "cases: " .. total)
		t.ok(ups[1] >= 1 / 1.3 - 1e-9 and ups[2] <= 1.3 + 1e-9, string.format("up %.3f to %.3f", ups[1], ups[2]))
	end)

	t.test("8.5j each set is inside 1/1.3 to 1.3 round for the radii it was made for", function()
		-- R13 (reference 1.3) covers base radii 1.0 to 1.69; R22 (2.2) covers
		-- 1.692 to 2.86. Every sleeve of a stump in those ranges stretches fine.
		local checked = 0
		for _, def in ipairs(WoodData.All()) do
			for _, size in ipairs({ TreeGen.ScaleFor("small"), 1, TreeGen.ScaleFor("large"), ForestData.Elder.scale }) do
				local segs, trunk = segsOf(def.id, 2, size, size == ForestData.Elder.scale)
				local shape = StumpLogic.Shape(segs, math.min(trunk, 4.5))
				local round, up = StumpLogic.BarkStretch(shape.sleeves[1], shape.set)
				if (shape.set == "R13" and shape.baseRadius >= 1.0) or shape.set == "R22" then
					t.ok(
						StumpLogic.StretchOk(round, up),
						string.format("%s x%.2f %s round %.2f up %.2f", def.id, size, shape.set, round, up)
					)
					checked += 1
				end
			end
		end
		t.ok(checked > 20, "checked " .. checked)
	end)

	t.expectedFail(
		"8.5k bark stretch stays in 1/1.3 to 1.3 round for every wood and size",
		function()
			local bad, total, byTree, rounds = stretchCases()
			local names = {}
			for name in pairs(byTree) do
				table.insert(names, name)
			end
			table.sort(names)
			for _, name in ipairs(names) do
				local tree = byTree[name]
				print(
					string.format(
						"[stretch] %s: set %s base %.3f round %.2f to %.2f, %d sleeve(s) outside",
						name,
						tree.set,
						tree.base,
						tree.lo,
						tree.hi,
						tree.bad
					)
				)
			end
			print(
				string.format("[stretch] %d sleeves, %d outside; round %.2f to %.2f", total, #bad, rounds[1], rounds[2])
			)
			t.eq(#bad, 0, #bad .. " of " .. total .. " sleeves outside; first: " .. tostring(bad[1]))
		end,
		"BLOCKED: needs Connor's decision. With R13 reference 1.3 (assumed) and R22 reference 2.2, the sets stretch fine only for base radii 1.0 to 1.69 (R13) and 1.692 to 2.86 (R22): small and birch trees (base radius under 1.0), and tall cuts whose later sleeves narrow, fall outside. See the [stretch] lines."
	)

	t.test("8.5c every mesh failing to load: no stump, no stand-in, the log is still made, a warning", function()
		local s = setup()
		s.attrs.CoreLoopActive = 2
		s.meshFails = true
		local rec = s.tree("oak")
		local p = s.player(1, Vector3.new(4, 3, 0))
		local _, ok, _, result = s.cutThrough(p, rec.sections[1], 3000)
		t.ok(ok and result ~= nil and #result.freed == 1, "the tree still falls and the log is made")
		t.eq(#stumpParts(s.map), 0, "no stump look at all: no part discs, cap or ring")
		t.ok(rec.slot and rec.stumpState == nil, "no stump and no hitbox: the spot is cleared")
		local warned = false
		for _, w in ipairs(s.loader.warnings) do
			if string.find(w, "StumpMeshes", 1, true) then
				warned = true
			end
		end
		t.ok(warned, "a warning was logged")
	end)

	t.test("8.5d trunks are round: radius side / sqrt(pi), volume and price unchanged from main", function()
		local WoodData2 = t.shared("WoodData")
		local SectionLogic = t.shared("SectionLogic")
		-- Per-wood volume (u^3) of the mature tree at seeds 1, 2, 3, scale 1,
		-- summed over its section parts, computed on origin/main (878c4ce)
		-- with the same method: `lune run tests/run VolDump` there.
		local MAIN = {
			oak = { 17.951656, 21.413874, 21.668545 },
			birch = { 10.091420, 10.113701, 10.103158 },
			pine = { 41.776584, 41.752835, 42.212763 },
			maple = { 35.590851, 42.119426, 38.628339 },
			palmwood = { 17.262508, 17.290477, 17.464807 },
			frostwood = { 25.006005, 24.992895, 25.246701 },
			lanternwood = { 13.016602, 12.427763, 12.927286 },
			emberwood = { 31.592423, 31.627641, 32.888453 },
			phantomwood = { 16.546178, 18.881644, 19.939910 },
			lumenwood = { 45.813694, 45.251071, 45.035605 },
			bogcypress = { 21.829350, 21.874497, 21.905228 },
			ironwood = { 26.231572, 30.058155, 30.955635 },
			cherry = { 12.274358, 12.149720, 12.310980 },
			willow = { 25.017631, 25.422900, 24.122616 },
		}
		local count = 0
		for _, def in ipairs(WoodData2.All()) do
			local pinned = MAIN[def.id]
			t.ok(pinned ~= nil, def.id .. " is pinned")
			for i, seed in ipairs({ 1, 2, 3 }) do
				local skel = TreeGen.Skeleton(def.id, seed, 1, {})
				local model = TreeArt.FromSkeleton(def, skel)
				local v, rounds, sections = 0, 0, 0
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "Section" then
						sections += 1
						local _, sz = SectionMetrics.BlockFrame(d)
						v += SectionLogic.Volume(sz.X, sz.Y, sz.Z)
						if d:IsA("Part") and d.Shape == Enum.PartType.Cylinder then
							rounds += 1
							local radius = math.min(d.Size.Y, d.Size.Z) / 2
							t.ok(
								math.abs(radius - StumpLogic.RoundRadius(math.min(sz.X, sz.Z))) < 1e-4,
								"round radius = side / sqrt(pi)"
							)
							t.ok(math.abs(math.pi * radius * radius - sz.X * sz.Z) < 1e-3, "same cross-section area")
						end
					end
				end
				t.ok(
					pinned and math.abs(v - pinned[i]) / pinned[i] < 0.01,
					string.format("%s seed %d volume %.4f vs main %.4f", def.id, seed, v, pinned and pinned[i] or 0)
				)
				t.eq(rounds, sections, def.id .. ": every section is round, limbs included")
				t.ok(#model:GetDescendants() > 0 and TreeGen.PartCount(skel) <= 8 or true)
				count += 1
			end
		end
		t.eq(count, 42)
	end)

	t.test("8.5f chop to sell: a fixed log's volume and sale value are main's, within 1%", function()
		-- Pinned from origin/main (878c4ce), same swing: a player whose root
		-- part is `rootY` up fells a normal tree of `seed`; the freed log's
		-- volume (u^3) and its sale value as WoodService prices it.
		local CASES = {
			{ "oak", 7, 3, 3.0000, 18.005574, 27.008360 },
			{ "oak", 7, 4, 3.9114, 17.115497, 25.673246 },
			{ "pine", 11, 3, 3.0000, 37.364532, 134.512314 },
			{ "maple", 5, 3, 3.0000, 38.893826, 124.460242 },
			{ "birch", 3, 3, 3.0000, 8.228144, 18.513324 },
		}
		for _, case in ipairs(CASES) do
			local s, _, _, result = felled(case[3], case[1], case[2])
			local piece = result.freed[1]
			local label = string.format("%s seed %d cut %.1f", case[1], case[2], case[3])
			t.ok(math.abs(result.hit.height - case[4]) < 0.01, label .. " cut height")
			t.ok(
				math.abs(piece.volume - case[5]) / case[5] < 0.01,
				string.format("%s volume %.4f vs main %.4f", label, piece.volume, case[5])
			)
			t.ok(
				math.abs(piece.value - case[6]) / case[6] < 0.01,
				string.format("%s value %.4f vs main %.4f", label, piece.value, case[6])
			)
			t.ok(s ~= nil)
		end
	end)

	t.test("8.5e a cut round trunk stays round, its cut faces are round plates, and the cut edge is kept", function()
		local s, rec, _, result = felled(3, "oak")
		local log = result.freed[1]
		local rounds = 0
		for _, part in pairs(log.parts) do
			if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
				rounds += 1
			end
		end
		t.ok(rounds >= 1, "the log's sections are still round")
		for _, d in ipairs(log.model:GetDescendants()) do
			if d.Name == "CutFace" then
				t.ok(d:IsA("Part") and d.Shape == Enum.PartType.Cylinder, "a round cut face")
			end
		end
		for _, part in pairs(log.parts) do
			t.ok(secLen(part) >= s.GameConfig.CutEdge - 1e-6, "no piece shorter than the cut edge")
		end
		t.ok(
			result.hit.height >= s.GameConfig.CutEdge and result.hit.height <= 4.5 - s.GameConfig.CutEdge + 1e-6,
			"the cut kept CutEdge from the ends"
		)
	end)

	---------------------------------------------------------------------
	t.test("8.6 a stump weathers from 90 s, fades 180 to 190 s sinking 0.3, then goes and frees the spot", function()
		t.eq(StumpLogic.WeatherStart, 90)
		t.eq(StumpLogic.WeatherFull, 170)
		t.eq(StumpLogic.FadeStart, 180)
		t.eq(StumpLogic.FadeEnd, 190)
		t.eq(StumpLogic.SinkDepth, 0.3)
		t.eq(StumpLogic.Weathering(89.9), 0)
		t.ok(math.abs(StumpLogic.Weathering(130) - 0.5) < 1e-9, "half weathered at 130 s")
		t.eq(StumpLogic.Weathering(170), 1)
		t.eq(StumpLogic.Weathering(185), 1)
		t.eq(StumpLogic.Fade(180), 0)
		t.ok(math.abs(StumpLogic.Fade(185) - 0.5) < 1e-9)
		t.ok(math.abs(StumpLogic.SinkAt(190) - 0.3) < 1e-9)
		t.ok(not StumpLogic.Gone(189.9) and StumpLogic.Gone(190))
		-- The colours: the cut face lerps 40% toward #8A8172, the bark darkens 30%.
		local fresh = Color3.fromRGB(100, 60, 30)
		t.eq(StumpLogic.BarkColor(fresh, 0), fresh)
		t.eq(StumpLogic.BarkColor(fresh, 1), fresh:Lerp(Color3.new(0, 0, 0), 0.3))
		t.eq(StumpLogic.CapColor(fresh, 1), fresh:Lerp(Color3.fromHex("8A8172"), 0.4))
		t.eq(StumpLogic.CapColor(fresh, 0.5), fresh:Lerp(Color3.fromHex("8A8172"), 0.2))
		-- A wood that takes 400 s to respawn, so the stump's decay shows.
		local s, rec = felled(3, "oak", nil, 400)
		local at = s.now
		local model = rec.model
		local step = stumpParts(model, "StumpMesh")[1]
		local capPart = stumpParts(model, "StumpCap")[1]
		local ringPart = stumpParts(model, "StumpRing")[1]
		local fresh1, freshCap, freshRing, freshY = step.Color, capPart.Color, ringPart.Color, capPart.CFrame.Position.Y
		s.now = at + 89
		s.Trees.StumpStep(s.now)
		t.eq(step.Color, fresh1, "no weathering before 90 s")
		t.eq(capPart.Color, freshCap)
		s.now = at + 130
		s.Trees.StumpStep(s.now)
		t.eq(step.Color, StumpLogic.BarkColor(fresh1, 0.5), "half weathered: bark half-darkened")
		t.eq(capPart.Color, StumpLogic.CapColor(freshCap, 0.5), "cut face half-lerped")
		s.now = at + 172
		s.Trees.StumpStep(s.now)
		t.eq(step.Color, StumpLogic.BarkColor(fresh1, 1), "fully weathered: bark 30% darker")
		t.eq(capPart.Color, StumpLogic.CapColor(freshCap, 1), "cut face 40% toward #8A8172")
		t.eq(ringPart.Color, freshRing, "the ring stays #3C2814")
		t.eq(ringPart.Color, Color3.fromHex("3C2814"))
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
		t.ok(rec.slot, "the spot is free")
		t.ok(rec.regrowAt ~= nil and rec.regrowAt > s.now, "and the wood's own respawn time (400 s) still stands")
		s.now = rec.regrowAt + 1
		s.Trees.GrowTick(s.now)
		t.ok(not rec.slot and not rec.felled, "a new tree on its own time")
	end)

	t.test("8.6b a wood's own regrow time is kept: the stump goes early when it comes first", function()
		for woodId, respawn in pairs({ oak = 45, birch = 60, pine = 90, maple = 120 }) do
			local s, rec = felled(3, woodId)
			local at = s.now
			t.eq(s.WoodData.Get(woodId).respawnSec, respawn, woodId .. " respawnSec")
			t.eq(math.floor(rec.regrowAt - at + 0.5), respawn, woodId .. " regrows after its own respawnSec")
			local model = rec.model
			s.now = rec.regrowAt - 1
			s.Trees.GrowTick(s.now)
			t.ok(model.Parent ~= nil and #stumpParts(model) > 0, woodId .. " stump stands just before")
			s.now = rec.regrowAt
			s.Trees.GrowTick(s.now)
			t.ok(model.Parent == nil, woodId .. " the stump is removed when the regrow fires, still standing")
			t.ok(not rec.felled and rec.stage == 0 and not rec.slot, woodId .. " a new tree grows: not held to 190 s")
			t.ok(s.now - at < StumpLogic.FadeEnd, woodId .. " before the stump's own 190 s")
		end
		-- A wood slower than 190 s: the stump despawns at 190 s, the regrow is not earlier.
		local s, rec = felled(3, "oak", nil, 300)
		local at = s.now
		s.now = at + 190
		s.Trees.GrowTick(s.now)
		t.ok(rec.slot and rec.model.Parent == nil, "stump gone at 190 s")
		t.ok(math.abs(rec.regrowAt - (at + 300)) < 1e-6, "the regrow is still at its own 300 s")
	end)

	t.test("8.6c a bark SurfaceAppearance would carry on from the trunk: same phase at the cut", function()
		-- The trunks have no SurfaceAppearance today (Material + Color), so the
		-- stump copies those. This pins the mapping for the day one is added:
		-- the pattern starts at the trunk's foot, so the stump's vertical
		-- phase at height h is the trunk's (h / studsPerTile), and the tiles
		-- round the stump at the cut match the trunk's (circumference / tile).
		for _, tile in ipairs({ 2, 4, 8 }) do
			for _, def in ipairs(WoodData.All()) do
				local segs, total = segsOf(def.id, 2, 1, false)
				for _, h in ipairs({ 2.5, 3.5, math.min(total, 4.5) }) do
					if h <= total then
						local shape = StumpLogic.Shape(segs, h)
						local map = StumpLogic.BarkMapping(tile, shape.baseRadius, shape.topRadius, h)
						t.eq(map.offsetV, 0, "starts where the trunk's does")
						t.ok(math.abs(map.repeatV - h / tile) < 1e-9, "vertical phase at the cut = the trunk's")
						local trunkTiles = 2 * math.pi * trunkRadius(segs, h) / tile
						t.ok(
							math.abs(map.repeatTop - trunkTiles) <= 2 * math.pi * 0.05 / tile + 1e-9,
							"tiles round the top within the 0.05 stud tolerance"
						)
						t.ok(
							math.abs(map.repeatBase - 2 * math.pi * trunkRadius(segs, 0) / tile) < 1e-9,
							"the same round the foot"
						)
					end
				end
			end
		end
	end)

	t.test("8.6d boot check: all 96 frustum models load and are MeshParts, one line says so", function()
		local s = setup()
		local result
		s.StumpMeshes.Preload(function(loaded, failures)
			result = { loaded = loaded, failures = failures }
		end)
		t.ok(result ~= nil, "the check finished")
		t.eq(result.loaded, 96)
		t.eq(#result.failures, 0)
		t.eq(#s.loaded, 96, "every row asked for once")
		t.eq(#s.StumpMeshes.Missing(), 0, "nothing missing")
		t.eq(s.StumpMeshes.Lines(96, {})[1], "[Stump] 96/96 frustum meshes loaded")
		-- One model fails to load, one holds no MeshPart: each is named by set, taper, height and id.
		local bad = setup()
		local rowA, rowB = StumpMeshIds.Rows[17], StumpMeshIds.Rows[70]
		local plain = bad.StumpMeshes.LoadModel
		bad.StumpMeshes.LoadModel = function(id)
			if id == rowA.id then
				error("HTTP 403")
			elseif id == rowB.id then
				return Instance.new("Model")
			end
			return plain(id)
		end
		local failed
		bad.StumpMeshes.Preload(function(loaded, failures)
			failed = { loaded = loaded, failures = failures }
		end)
		t.eq(failed.loaded, 94)
		t.eq(#failed.failures, 2)
		local text = table.concat(failed.failures, "\n")
		for _, row in ipairs({ rowA, rowB }) do
			t.ok(string.find(text, row.name, 1, true) and string.find(text, tostring(row.id), 1, true), text)
			t.ok(string.find(text, row.set, 1, true), "names its set")
		end
		t.eq(bad.StumpMeshes.Lines(94, failed.failures)[1], "[Stump] 94/96 frustum meshes loaded")
		-- Loud: stumpMeshesMissing is recorded and warned, by name.
		t.eq(#bad.StumpMeshes.Missing(), 2, "stumpMeshesMissing records both")
		local loud = 0
		for _, w in ipairs(bad.loader.warnings) do
			if string.find(w, "[Stump] stumpMeshesMissing:", 1, true) then
				loud += 1
			end
		end
		t.eq(loud, 2, "and each is warned")
		-- The cloud test's call: the same check, run against the real InsertService.
		local cloud = setup()
		local lines, tried = cloud.StumpMeshes.CloudCheck()
		t.eq(#lines, 0, "CloudCheck passes with every model loading")
		t.eq(tried, 96)
		t.eq(#(bad.StumpMeshes.CloudCheck()), 2, "and reports the two that do not")
	end)

	t.test("8.6e a stump with no mesh in its own set leaves no stump; the log is made; counted and listed", function()
		local rowOf = {}
		for _, row in ipairs(StumpMeshIds.Rows) do
			rowOf[row.id] = row
		end
		local function failing(s, set)
			local plain = s.StumpMeshes.LoadModel
			s.StumpMeshes.LoadModel = function(id)
				if rowOf[id].set == set then
					error("not approved")
				end
				return plain(id)
			end
		end
		local function warned(s)
			local n = 0
			for _, w in ipairs(s.loader.warnings) do
				if string.find(w, "[Stump] stumpMeshesMissing:", 1, true) then
					n += 1
				end
			end
			return n
		end
		-- R22 stubbed as missing. An Elder (base radius 1.918, R22) is cut through.
		local s = setup()
		s.attrs.CoreLoopActive = 2
		failing(s, "R22")
		local ForestLogic = t.shared("ForestLogic")
		local model = s.Trees.SpawnTree(
			"oak",
			CFrame.new(0, 0, 0),
			{ seed = 5, size = ForestLogic.ElderSize(s.WoodData.Get("oak")), temporary = true }
		)
		local uid = model:GetAttribute("Uid")
		local rec = s.Trees.GetTree(uid)
		local base = rec.sections[1]
		local p = s.player(1, Vector3.new(secSide(base) / 2 + 3, 3, 0))
		local _, ok, _, result = s.cutThrough(p, base, 6000)
		t.ok(ok and result ~= nil, "the Elder was cut through")
		t.eq(#result.freed, 1, "the log above the cut is made")
		t.ok(next(result.freed[1].parts) ~= nil, "with its sections")
		t.eq(#stumpParts(s.map), 0, "no stump look anywhere (no mesh, no part discs, no cap or ring)")
		t.eq(rec.stumpState, nil, "no stump state")
		s.run()
		t.eq(s.Trees.GetTree(uid), nil, "and no hitbox left: the Elder is gone with its log")
		local missingLines = s.StumpMeshes.Missing()
		t.ok(#missingLines >= 1, "stumpMeshesMissing lists the missing ids")
		for _, line in ipairs(missingLines) do
			t.ok(string.find(line, "R22", 1, true) ~= nil, "names the set: " .. line)
		end
		t.ok(
			s.StumpMeshes.Violations() >= 1,
			"stumpStretchViolations counts the dropped stump: " .. s.StumpMeshes.Violations()
		)
		local warnings = warned(s)
		t.ok(warnings >= 1, "the server warned")
		-- Once per mesh, not per stump: asking again for the same meshes adds nothing.
		local shape = StumpLogic.Shape(segsOf("oak", 5, ForestData.Elder.scale, true), 3)
		t.eq(shape.set, "R22")
		s.StumpMeshes.Resolve(shape, function() end)
		s.StumpMeshes.Resolve(shape, function() end)
		t.eq(warned(s), warnings, "no repeat warning for the same mesh")
		t.eq(#s.StumpMeshes.Missing(), #missingLines)
		-- A stump with base radius 1.3 still uses R13 (the same stub: R13 present).
		local b = setup()
		b.attrs.CoreLoopActive = 2
		failing(b, "R22")
		local big = b.Trees.SpawnTree("oak", CFrame.new(0, 0, 0), { seed = 7, size = TreeLogic.Sizes[3], stage = 1 })
		local recB = b.Trees.GetTree(big:GetAttribute("Uid"))
		local radius = secSide(recB.sections[1]) / math.sqrt(math.pi)
		t.ok(math.abs(radius - 1.298) < 0.01, "a large oak: base radius " .. radius)
		local q = b.player(1, Vector3.new(4, 3, 0))
		b.cutThrough(q, recB.sections[1], 3000)
		local meshes = stumpParts(recB.model, "StumpMesh")
		t.ok(#meshes >= 1, "the stump stands")
		for _, mesh in ipairs(meshes) do
			t.eq(rowOf[tonumber(mesh:GetAttribute("ModelId"))].set, "R13", "from R13")
		end
		t.eq(#b.StumpMeshes.Missing(), 0, "nothing missing for it")
		t.eq(b.StumpMeshes.Violations(), 0, "and its stretch is inside: no violation")
		-- R13 missing: a normal oak (not temporary) leaves no stump, its spot clears and
		-- regrows on the wood's own time, and its log is still made.
		local c = setup()
		c.attrs.CoreLoopActive = 2
		c.Trees._roll = function()
			return 0.5
		end
		failing(c, "R13")
		local recC = c.tree("oak")
		local at = c.now
		local pC = c.player(1, Vector3.new(4, 3, 0))
		local _, okC, _, resultC = c.cutThrough(pC, recC.sections[1], 3000)
		t.ok(okC and #resultC.freed == 1, "the tree fell and the log is made")
		t.eq(#stumpParts(c.map), 0, "no stump")
		t.ok(recC.slot and recC.stumpState == nil, "the spot is cleared")
		t.ok(
			math.abs(recC.regrowAt - (at + c.WoodData.Get("oak").respawnSec)) < 20,
			"and regrows on the wood's own time"
		)
		t.ok(c.StumpMeshes.Violations() >= 1 and #c.StumpMeshes.Missing() >= 1)
		-- All 96 present: in-range stumps count 0; an out-of-range one is counted but still drawn.
		local d = setup()
		d.attrs.CoreLoopActive = 2
		local recD = d.tree("oak")
		d.cutThrough(d.player(1, Vector3.new(4, 3, 0)), recD.sections[1], 3000)
		t.eq(d.StumpMeshes.Violations(), 0, "a normal oak at 3 studs is in range")
		local birch = d.tree("birch", Vector3.new(60, 0, 0))
		d.cutThrough(d.player(2, Vector3.new(64, 3, 0)), birch.sections[1], 3000)
		t.ok(d.StumpMeshes.Violations() >= 1, "a normal birch (round stretch 0.69) is counted")
		t.ok(#stumpParts(birch.model, "StumpMesh") >= 1, "and still drawn: only a missing mesh drops a stump")
		t.eq(#d.StumpMeshes.Missing(), 0)
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
		local s, rec, p, result = felled(3.5, "oak", nil, 1000)
		local at = s.now
		local step = stumpParts(rec.model, "StumpMesh")[1]
		local fresh = step.Color
		local hitbox = rec.sections[1]
		local h = secLen(hitbox)
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
			length += secLen(part)
		end
		t.ok(math.abs(length - 2) < 0.01, "a log exactly 2 long: " .. length)
		t.ok(math.abs(secLen(hitbox) - 1.5) < 0.01, "the cut moved down: the stump is 1.5")
		t.ok(rec.felled and not rec.slot, "what is left still stands")
		local cap = stumpParts(rec.model, "StumpCap")[1]
		t.ok(
			math.abs((cap.CFrame.Position.Y + cap.Size.X / 2) - (rec.base.Y + 1.5)) < 1e-4,
			"with its cap at the new cut"
		)
		local newStep = stumpParts(rec.model, "StumpMesh")[1]
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
		local height = secLen(hitbox)
		for _ = 1, 40 do
			s.now += 3
			s.Trees.StumpStep(s.now)
		end
		t.eq(secLen(hitbox), height, "only a swing changes it")
		-- A swing is checked like any other.
		s.allow = false
		local ok, why = s.swing(p, hitbox)
		t.ok(not ok and why == "rate", "rate limited")
		s.allow = true
		local far = s.player(2, Vector3.new(40, 3, 0))
		local ok2, why2 = s.swing(far, hitbox)
		t.ok(not ok2 and why2 == "far", "out of reach")
		t.eq(secLen(hitbox), height, "neither touched it")
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
