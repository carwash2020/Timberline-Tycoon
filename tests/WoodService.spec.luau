--!nocheck
-- WoodService (V2_PLAN.md §3f, §3g, §4a): loose wood. A freed piece's
-- model and record, the fall (WoodFalling, the cutter's device, the leaves
-- dropping, Felled once it lands), cutting a loose piece in two (exactly
-- two, volume kept, owner and figure kept), despawn (owner lost, then
-- gone), the caps, and WoodWatch putting a teleported piece back. The
-- clock, players, physics and remotes are faked.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance

	local function setup()
		local s = { now = 100, fx = {}, byId = {}, owners = {}, velocities = {}, speed = { 0, 0 }, attrs = {} }
		local map = Instance.new("Folder")
		map.Name = "TimberlineMap"
		local workspace = {
			FindFirstChild = function(_, name)
				return if name == "TimberlineMap" then map else nil
			end,
			GetAttribute = function(_, name)
				return s.attrs[name]
			end,
			GetServerTimeNow = function()
				return s.now
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
		local loader = t.loader({
			services = { Players = Players, PhysicsService = {} },
			globals = {
				workspace = workspace,
				task = {
					delay = function() end,
					spawn = function(fn, ...)
						fn(...)
					end,
				},
				os = setmetatable({
					clock = function()
						return s.now
					end,
				}, { __index = os }),
			},
		})
		s.Wood = loader:server("WoodService")
		s.Grab = loader:server("GrabService")
		s.SectionLogic = loader:shared("SectionLogic")
		s.GameConfig = loader:shared("GameConfig")
		s.loader = loader
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
				return s.speed[1], s.speed[2]
			end,
			GetVelocity = function()
				return Vector3.new(1, 0, 0), Vector3.zero
			end,
			SetVelocity = function(part, linear, angular)
				s.velocities[part] = { linear = linear, angular = angular }
			end,
		}
		s.Wood.Init({
			worldFx = {
				FireClient = function(_, player, kind, payload)
					table.insert(s.fx, { player = player, kind = kind, payload = payload })
				end,
			},
			manual = true,
			clock = function()
				return s.now
			end,
		})

		function s.player(userId, pos)
			local root = {
				Position = pos or Vector3.new(0, 3, 0),
				IsA = function(_, class)
					return class == "BasePart"
				end,
			}
			local p = {
				UserId = userId,
				Name = "P" .. userId,
				Parent = Players,
				Character = {
					FindFirstChild = function(_, name)
						return if name == "HumanoidRootPart" then root else nil
					end,
				},
			}
			s.byId[userId] = p
			return p
		end

		-- A log of `n` sections (`length` studs each, `thick` a side) lying
		-- along +X at `at`, adopted as a freed piece (no fall unless given).
		function s.log(n, length, thick, at, info)
			info = info or {}
			local model = s.Wood.NewModel()
			local nodes, parts = {}, {}
			local origin = at or Vector3.new(0, 1, 0)
			for i = 1, n do
				local part = Instance.new("Part")
				part.Name = "Section"
				part.Anchored = true
				part.Size = Vector3.new(thick, length, thick)
				-- Length along the part's Y, laid along world +X.
				part.CFrame = CFrame.new(origin + Vector3.new((i - 0.5) * length, 0, 0))
					* CFrame.Angles(0, 0, -math.pi / 2)
				part:SetAttribute("Section", i)
				part.Parent = model
				parts[i] = part
				nodes[i] = { parent = if i > 1 then i - 1 else nil, children = if i < n then { i + 1 } else {} }
			end
			local leaf = Instance.new("Part")
			leaf.Name = "Leaves"
			leaf.Anchored = true
			leaf.Size = Vector3.one
			leaf.CFrame = CFrame.new(origin + Vector3.new(n * length, 1, 0))
			leaf:SetAttribute("Section", n)
			leaf.Parent = model
			return s.Wood.Adopt(model, {
				woodId = info.woodId or "oak",
				nodes = nodes,
				parts = parts,
				ownerId = info.ownerId or 1,
				figure = info.figure,
				boost = info.boost,
				lux = info.lux,
				fall = info.fall,
				elder = info.elder,
			})
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
		return s
	end

	t.test(
		"a freed piece: Wood_<uid> in TimberlineMap/Wood, tagged, welded to its largest section, its attributes",
		function()
			local s = setup()
			local p = s.log(2, 4, 2, nil, { figure = "curly" })
			local m = p.model
			t.eq(m.Name, "Wood_" .. p.uid)
			t.eq(m.Parent.Name, "Wood")
			t.eq(m.Parent.Parent.Name, "TimberlineMap")
			t.ok(m:HasTag("Wood"))
			t.eq(m.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic)
			t.ok(m.PrimaryPart == p.root)
			t.eq(m:GetAttribute("Owner"), 1)
			t.eq(m:GetAttribute("WoodId"), "oak")
			t.eq(m:GetAttribute("Kind"), "log")
			t.eq(m:GetAttribute("Figure"), "curly")
			t.eq(m:GetAttribute("HeldBy"), 0)
			local volume = s.SectionLogic.Volume(2, 8, 2)
			t.ok(math.abs(p.volume - volume) < 1e-9, "server-computed u³")
			t.ok(math.abs(m:GetAttribute("Volume") - math.floor(volume * 100 + 0.5) / 100) < 1e-9)
			t.ok(math.abs(p.value - volume * 1.5 * 1.5) < 1e-9, "oak log price x Curly 1.5")
			local welds = 0
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					t.ok(not d.Anchored, "unanchored")
					if d.Name == "Section" then
						t.ok(d.CustomPhysicalProperties ~= nil, "wood physics")
						t.ok(d:HasTag("WoodSection"))
					else
						t.ok(d.Massless and not d.CanCollide, "dress is massless and never collides")
					end
				elseif d:IsA("WeldConstraint") then
					welds += 1
					t.ok(d.Part0 == p.root, "welded to the root")
				end
			end
			t.eq(welds, 2, "every other part welded")
			t.ok(s.Wood.FromPart(p.parts[2]) == p, "FromPart finds the record")
		end
	)

	t.test("the fall: WoodFalling, the cutter's device, spun away; the leaves drop; Felled once it lands", function()
		local s = setup()
		local cutter = s.player(1)
		local p = s.log(
			2,
			5,
			2,
			Vector3.new(0, 1, 0),
			{ fall = { cutter = cutter, dir = Vector3.new(0, 0, 1), felled = true, pivot = Vector3.new(0, 1, 0) } }
		)
		t.eq(p.parts[1].CollisionGroup, "WoodFalling", "passes through players while it falls")
		t.ok(s.owners[p.root] == cutter, "the cutter's device simulates it")
		local v = s.velocities[p.root]
		t.ok(v and v.angular.Magnitude > 0, "set spinning")
		t.ok(v.angular:Dot(Vector3.xAxis) > 0, "about the axis that tips it toward +Z")
		t.eq(s.Wood.Falling(), 1)
		-- The leaves after LeafDropSec.
		s.now += s.GameConfig.LeafDropSec + 0.01
		s.Wood.RunTimers(s.now)
		t.eq(p.model:FindFirstChild("Leaves"), nil, "leaves gone")
		t.eq(#s.fxOf("LeafFall"), 1, "clients flutter them down")
		-- Players again after FallNoCollideSec, and back to automatic ownership.
		s.now += s.GameConfig.FallNoCollideSec
		s.Wood.RunTimers(s.now)
		t.eq(p.parts[1].CollisionGroup, "Wood")
		s.now += 1
		s.Wood.RunTimers(s.now)
		t.eq(s.owners[p.root], "auto")
		-- It speeds up, then stops: landed.
		s.speed = { 20, 1 }
		s.Wood.StepFalls(s.now - 2)
		s.speed = { 0.5, 0 }
		s.Wood.StepFalls(s.now)
		local felled = s.fxOf("Felled")
		t.eq(#felled, 1)
		t.ok(felled[1].payload.mass > 5, "a trunk's mass, for the camera shake")
		s.Wood.StepFalls(s.now + 1)
		t.eq(#s.fxOf("Felled"), 1, "once")
	end)

	t.test("cutting a loose log through: exactly two pieces, volume kept, owner, figure and boost kept", function()
		local s = setup()
		local p = s.log(3, 4, 2, nil, { ownerId = 7, figure = "birdseye", boost = 2 })
		local cutter = s.player(9)
		local before = p.volume
		local part = p.parts[2]
		local required = s.SectionLogic.Required(2, 2, 2)
		local result
		local n = 0
		repeat
			n += 1
			result = s.Wood.CutPiece(cutter, p, part, part.CFrame.Position + Vector3.new(0, 1, 0), Vector3.yAxis, 0.5)
		until #result.pieces > 0 or n > 100
		t.eq(n, math.ceil(required / 0.5 - 1e-9))
		t.eq(#result.pieces, 2, "exactly two")
		local a, b = result.pieces[1], result.pieces[2]
		t.ok(a == p, "the low side keeps the record")
		t.ok(math.abs(a.volume + b.volume - before) < 1e-9, "the volume is shared exactly")
		for _, q in ipairs({ a, b }) do
			t.eq(q.ownerId, 7, "cutting a loose piece keeps its owner")
			t.eq(q.figure, "birdseye")
			t.eq(q.boost, 2)
			t.eq(q.lux, false)
			t.eq(q.model:GetAttribute("Figure"), "birdseye")
			t.ok(q.model.Parent ~= nil)
		end
		t.ok(a.uid ~= b.uid and a.model ~= b.model)
		t.eq(b.createdAt, a.createdAt, "the grace window carries on")
		-- Each side has a fresh cut face where it was parted.
		local faces = 0
		for _, q in ipairs({ a, b }) do
			for _, d in ipairs(q.model:GetChildren()) do
				if d.Name == "CutFace" then
					faces += 1
				end
			end
		end
		t.eq(faces, 2)
		t.ok(s.velocities[b.root] ~= nil, "the new piece keeps the assembly's motion")
	end)

	t.test("a Lux tag passes to both pieces, and a Lux chop tags a plain log", function()
		local s = setup()
		local tagged = s.log(3, 4, 2, nil, { lux = true })
		t.eq(tagged.model:GetAttribute("LuxCut"), true)
		local part = tagged.parts[2]
		local result
		local n = 0
		repeat
			n += 1
			result = s.Wood.CutPiece(s.player(1), tagged, part, part.CFrame.Position, Vector3.yAxis, 5, false)
		until #result.pieces > 0 or n > 20
		t.eq(#result.pieces, 2)
		t.eq(result.pieces[1].lux, true)
		t.eq(result.pieces[2].lux, true)
		t.eq(result.pieces[2].model:GetAttribute("LuxCut"), true)
		local plain = s.log(2, 4, 2, nil, { lux = false })
		local side = plain.parts[1]
		local swung
		local m = 0
		repeat
			m += 1
			swung = s.Wood.CutPiece(s.player(1), plain, side, side.CFrame.Position, Vector3.yAxis, 5, true)
		until #swung.pieces > 0 or m > 20
		for _, q in ipairs(swung.pieces) do
			t.eq(q.lux, true, "this chop is the final chop")
		end
	end)

	t.test("an offcut under MinPieceVolume becomes chips", function()
		local s = setup()
		local p = s.log(1, 6, 0.4, nil)
		local cutter = s.player(1)
		local part = p.parts[1]
		local result
		repeat
			-- Right by the end: the edge clamp keeps it CutEdge (0.3) in.
			result = s.Wood.CutPiece(cutter, p, part, part.CFrame * Vector3.new(0, 2.95, 0), part.CFrame.XVector, 5)
		until #result.pieces > 0
		t.eq(#result.pieces, 1, "the tiny end is chips")
		t.eq(#s.fxOf("Chips"), 1, "chips fly for the players near")
	end)

	t.test("despawn: untouched off a plot it loses its owner, then it goes", function()
		local s = setup()
		local p = s.log(1, 4, 2)
		local unowned = s.GameConfig.WoodUnownedAfterSec
		local despawn = s.GameConfig.WoodDespawnAfterSec
		s.Wood.Tick(s.now + unowned - 1)
		t.eq(p.ownerId, 1)
		s.Wood.Tick(s.now + unowned)
		t.eq(p.ownerId, 0, "the owner is lost")
		t.eq(p.model:GetAttribute("Owner"), 0)
		s.Wood.Tick(s.now + unowned + despawn - 1)
		t.ok(p.model.Parent ~= nil)
		s.Wood.Tick(s.now + unowned + despawn)
		t.eq(p.model.Parent, nil, "gone")
		t.eq(s.Wood.Get(p.uid), nil)
	end)

	t.test("touched wood never ages: held, or on its owner's bed; plot wood keeps its owner", function()
		local s = setup()
		local p = s.log(1, 4, 2)
		local owner = s.player(1)
		s.Wood.Hooks.onBed = function()
			return owner
		end
		s.Wood.Tick(s.now + 5000)
		t.eq(p.ownerId, 1, "resting on its owner's bed")
		s.Wood.Hooks.onBed = nil
		s.Wood.Hooks.onPlot = function()
			return true
		end
		s.Wood.Tick(s.now + 50000)
		t.eq(p.ownerId, 1, "on a plot")
		s.Wood.Hooks.onPlot = nil
	end)

	t.test(
		"caps: a player's oldest untouched go past MaxWoodPiecesPerPlayer; the part cap takes unowned first",
		function()
			local s = setup()
			local Wood = s.Wood
			local entries = {}
			for i = 1, 5 do
				table.insert(entries, { uid = "a" .. i, ownerId = 1, parts = 10, lastInteracted = i })
			end
			table.insert(entries, { uid = "held", ownerId = 1, parts = 10, lastInteracted = 0, protected = true })
			t.eq(Wood.PickEvictions(entries, 4, 10000), { "a1", "a2" }, "the oldest untouched, never the held one")
			local mixed = {
				{ uid = "mine-old", ownerId = 2, parts = 40, lastInteracted = 1 },
				{ uid = "free-new", ownerId = 0, parts = 40, lastInteracted = 9 },
				{ uid = "free-old", ownerId = 0, parts = 40, lastInteracted = 5 },
				{ uid = "mine-new", ownerId = 2, parts = 40, lastInteracted = 8 },
			}
			t.eq(Wood.PickEvictions(mixed, 150, 100), { "free-old", "free-new" }, "unowned first")
			t.eq(
				Wood.PickEvictions(mixed, 150, 60),
				{ "free-old", "free-new", "mine-old" },
				"then the oldest untouched"
			)
			-- Live: a sixth piece over a cap of 5 removes the oldest.
			local GameConfig = s.GameConfig
			local saved = GameConfig.MaxWoodPiecesPerPlayer
			GameConfig.MaxWoodPiecesPerPlayer = 5
			local first = s.log(1, 2, 1)
			for _ = 1, 5 do
				s.now += 1
				s.log(1, 2, 1)
			end
			GameConfig.MaxWoodPiecesPerPlayer = saved
			t.eq(first.model.Parent, nil, "the oldest went")
			t.eq(Wood.Get(first.uid), nil)
		end
	)

	t.test("sawmill planks count toward MaxWoodPartsServer; the oldest loose wood goes first", function()
		local s = setup()
		local saved = s.GameConfig.MaxWoodPartsServer
		s.GameConfig.MaxWoodPartsServer = 4
		-- One section plus its leaf: two parts, unowned, older than the planks.
		local loose = s.log(1, 4, 2, nil, { ownerId = 0 })
		t.eq(loose.partCount, 2, "the log's parts are counted")
		s.now += 5
		local planks = {}
		for i = 1, 3 do
			s.now += 1
			local plank = s.Wood.SpawnPlank({
				woodId = "oak",
				size = Vector3.new(1.6, 4, 1),
				cf = CFrame.new(i * 3, 2, 0),
				ownerId = 2,
			})
			t.ok(plank, "the mill made a plank")
			t.eq(plank.kind, "plank")
			t.eq(plank.partCount, 1, "a plank is a part the cap can see")
			table.insert(planks, plank)
		end
		t.eq(loose.model.Parent, nil, "the older loose log went before the new planks")
		t.eq(s.Wood.Get(loose.uid), nil)
		for _, plank in ipairs(planks) do
			t.ok(plank.model.Parent ~= nil, "the newer planks stayed")
		end
		-- Only planks left (3 parts). Two more put the pile over 4, so the oldest plank goes.
		s.now += 1
		s.Wood.SpawnPlank({
			woodId = "oak",
			size = Vector3.new(1.6, 4, 1),
			cf = CFrame.new(20, 2, 0),
			ownerId = 2,
		})
		s.now += 1
		s.Wood.SpawnPlank({
			woodId = "oak",
			size = Vector3.new(1.6, 4, 1),
			cf = CFrame.new(24, 2, 0),
			ownerId = 2,
		})
		t.eq(planks[1].model.Parent, nil, "the oldest plank went next")
		t.ok(planks[3].model.Parent ~= nil, "a newer plank stayed")
		s.GameConfig.MaxWoodPartsServer = saved
	end)

	t.test(
		"WoodWatch: a player-simulated piece that teleports is put back, stopped, the server's for a moment",
		function()
			local s = setup()
			local p = s.log(1, 4, 2)
			local cheat = s.player(3)
			local home = p.root.CFrame
			s.Wood.Watch(s.now)
			t.ok(s.Wood.VerdictOk(p))
			s.owners[p.root] = cheat
			s.now += 0.5
			p.model:PivotTo(home + Vector3.new(2, 0, 0))
			s.Wood.Watch(s.now)
			t.ok(s.Wood.VerdictOk(p), "a believable move")
			s.now += 0.5
			p.model:PivotTo(home + Vector3.new(500, 0, 0))
			s.Wood.Watch(s.now)
			t.ok(not s.Wood.VerdictOk(p), "the sell pad won't take it")
			t.ok(
				(p.root.CFrame.Position - (home.Position + Vector3.new(2, 0, 0))).Magnitude < 1e-6,
				"back where it was last good"
			)
			t.eq(s.owners[p.root], "server", "kept by the server")
			t.ok(s.velocities[p.root].linear.Magnitude == 0, "stopped")
			t.ok(#s.loader.warnings >= 1 and string.find(s.loader.warnings[#s.loader.warnings], "AntiExploit", 1, true))
			s.now += s.Wood.PutBackHoldSec + 0.1
			s.Wood.Watch(s.now)
			t.eq(s.owners[p.root], "auto", "then automatic again")
			t.ok(s.Wood.VerdictOk(p), "the server's simulation is trusted")
		end
	)

	t.test("Register files a Studio piece (one section) like any other", function()
		local s = setup()
		local model = Instance.new("Model")
		local part = Instance.new("Part")
		part.Name = "Section"
		part.Size = Vector3.new(2, 9, 2)
		part:SetAttribute("Section", 1)
		part.Parent = model
		model:SetAttribute("Uid", "dev-1")
		model:SetAttribute("WoodId", "oak")
		model.Parent = s.Wood.Folder()
		local p = s.Wood.Register(model, { woodId = "oak", nodes = {}, parts = {}, ownerId = 4 })
		t.eq(p.uid, "dev-1")
		t.eq(p.ownerId, 4)
		t.ok(s.Wood.FromPart(part) == p)
		t.ok(part:HasTag("WoodSection"), "the axe can cut it")
	end)

	t.test("Forget (sold) drops the record but leaves the model to its seller", function()
		local s = setup()
		local p = s.log(1, 4, 2)
		s.Wood.Forget(p.model)
		t.eq(s.Wood.Get(p.uid), nil)
		t.eq(s.Wood.FromPart(p.root), nil)
		t.ok(p.model.Parent ~= nil)
		s.player(1)
		s.Wood.SaleFx(p.model, 12)
		local sold = s.fxOf("Sold")
		t.eq(#sold, 1, "the pad's +$ pop")
		t.eq(sold[1].payload.amount, 12)
	end)

	-- The lead's wiring for M1.6 loads rebuilt off a bed (no saved graph).
	t.test("LinkByContact grows one tree from the largest section through touching ones", function()
		local s = setup()
		local function section(id, size, cf)
			local part = Instance.new("Part")
			part.Name = "Section"
			part.Size = size
			part.CFrame = cf
			part:SetAttribute("Section", id)
			return part
		end
		local parts = {
			[1] = section(1, Vector3.new(2, 9, 2), CFrame.new(0, 4.5, 0)),
			[2] = section(2, Vector3.new(1.8, 9, 1.8), CFrame.new(0, 13.5, 0)),
			[3] = section(3, Vector3.new(1.6, 9, 1.6), CFrame.new(0, 22.5, 0)),
			-- a limb off the second section, sticking out sideways
			[4] = section(4, Vector3.new(1, 1, 6), CFrame.new(0, 12, 3.9)),
			-- a stray far away: hangs off the root
			[5] = section(5, Vector3.new(1, 1, 1), CFrame.new(40, 0, 0)),
		}
		local nodes = s.Wood.LinkByContact(parts)
		t.eq(nodes[1].parent, nil, "the largest is the root")
		t.eq(nodes[2].parent, 1)
		t.eq(nodes[3].parent, 2, "not linked to the root: they don't touch")
		t.eq(nodes[4].parent, 2, "the limb joins the section it touches")
		t.eq(nodes[5].parent, 1)
		local count = 0
		for _ in pairs(nodes) do
			count += 1
		end
		t.eq(count, 5)
		t.eq(s.Wood.LinkByContact({}), {})
	end)

	t.test("Moved takes a piece's new place as WoodWatch's last good one", function()
		local s = setup()
		local p = s.log(1, 4, 2)
		p.root.CFrame = CFrame.new(500, 10, 0)
		s.now += 0.1
		s.Wood.Moved(p.model)
		t.eq(p.lastGood.Position, Vector3.new(500, 10, 0))
		t.eq(p.lastGoodAt, s.now)
		t.ok(s.Wood.VerdictOk(p))
	end)

	t.test("mill groups: logs pass the cage, the belt carries only loose wood", function()
		local pairs = {}
		local Physics = {
			IsCollisionGroupRegistered = function()
				return true
			end,
			RegisterCollisionGroup = function() end,
			CollisionGroupSetCollidable = function(_, a, b, on)
				pairs[a .. "|" .. b] = on
			end,
		}
		local loader = t.loader({
			services = {
				PhysicsService = Physics,
				Players = {
					GetPlayers = function()
						return {}
					end,
				},
			},
		})
		local Wood = loader:server("WoodService")
		t.eq(Wood.RegisterGroups(), true)
		t.eq(pairs["Mill|Wood"], false, "a loose log passes the blade cage")
		t.eq(pairs["Mill|WoodHeld"], false, "a carried log can be pushed in")
		t.eq(pairs["MillBelt|Players"], false)
		t.eq(pairs["MillBelt|WoodHeld"], false)
		t.eq(pairs["MillBelt|WoodFalling"], false, "a falling tree is not launched")
		t.eq(pairs["MillBelt|Mill"], false)
		-- Loose wood still hits the belt: that pair is never turned off.
		t.eq(pairs["MillBelt|Wood"], nil)
		t.eq(pairs["Mill|WoodFalling"], nil, "a falling tree still hits the mill")
	end)
end
