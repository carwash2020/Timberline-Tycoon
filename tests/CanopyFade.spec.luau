--!nocheck
-- CanopyFade (StarterPlayerScripts/CanopyFade, NAT-02) against a fake
-- world: a workspace whose Raycast and GetPartBoundsInRadius test boxes,
-- a frame clock, the local character's Head and HumanoidRootPart, and
-- TreeFX's IsBusy. It proves what Studio can't show us by reading code:
--   * a canopy between the camera and you fades to 0.7 (all of it, on a
--     real oak and pine) and comes back 0.3 s after it's out of the way;
--     trunks, branches and roots never fade, and nothing's CanCollide or
--     CanQuery changes;
--   * the rays only see trees (Include), each tree hit is left out of the
--     next ray, at most six rays per target per look, ten looks a second;
--   * a canopy around the camera itself fades too;
--   * felled, dormant and falling or regrowing trees are left to TreeFX: a
--     fading tree that starts to fall is handed back at once, and a part
--     someone else set (TreeFX's fade to 1) is never written;
--   * a tree that streams out mid-fade is dropped with nothing left
--     see-through, the Trees folder may stream in late, and no character
--     or first person does nothing.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame, Enum = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Enum

	local AXES = { "X", "Y", "Z" }

	-- Where the segment origin -> origin + dir first enters `part`'s box
	-- (0-1 along it), or nil. Like Roblox, a ray that starts inside a part
	-- doesn't hit it.
	local function rayBox(part, origin, dir)
		local cf = part.CFrame
		local o = cf:PointToObjectSpace(origin)
		local d = cf:VectorToObjectSpace(dir)
		local h = part.Size / 2
		if math.abs(o.X) < h.X and math.abs(o.Y) < h.Y and math.abs(o.Z) < h.Z then
			return nil
		end
		local lo, hi = 0, 1
		for _, axis in ipairs(AXES) do
			local oa, da, ha = o[axis], d[axis], h[axis]
			if math.abs(da) < 1e-9 then
				if math.abs(oa) > ha then
					return nil
				end
			else
				local t1, t2 = (-ha - oa) / da, (ha - oa) / da
				if t1 > t2 then
					t1, t2 = t2, t1
				end
				lo, hi = math.max(lo, t1), math.min(hi, t2)
				if lo > hi then
					return nil
				end
			end
		end
		return lo
	end

	-- The queryable parts under a filter list.
	local function queryable(list)
		local out = {}
		for _, inst in ipairs(list) do
			if inst:IsA("BasePart") and inst.CanQuery then
				table.insert(out, inst)
			end
			for _, d in ipairs(inst:GetDescendants()) do
				if d:IsA("BasePart") and d.CanQuery then
					table.insert(out, d)
				end
			end
		end
		return out
	end

	local function world()
		local w = {
			clock = 100,
			heartbeat = {},
			rays = {}, -- every ray cast: { origin, direction, include }
			busy = {}, -- [tree] = true while TreeFX animates it
		}

		local map = Instance.new("Folder")
		map.Name = "TimberlineMap"
		local trees = Instance.new("Folder")
		trees.Name = "Trees"
		trees.Parent = map
		w.map, w.trees = map, trees
		w.mapVisible = true

		local camera = { CFrame = CFrame.new(0, 20, 20) }
		w.camera = camera
		local workspace = { CurrentCamera = camera }
		function workspace.FindFirstChild(_, name)
			if name == "TimberlineMap" and w.mapVisible then
				return map
			end
			return nil
		end
		function workspace.Raycast(_, origin, direction, params)
			assert(params.FilterType == Enum.RaycastFilterType.Include, "rays only see what they include")
			local include = params.FilterDescendantsInstances
			table.insert(w.rays, { origin = origin, direction = direction, include = table.clone(include) })
			local part, at = w.hit(origin, direction, include)
			if not part then
				return nil
			end
			return { Instance = part, Position = origin + direction * at }
		end
		-- The first part under `include` the segment enters, and how far along.
		function w.hit(origin, direction, include)
			local best, bestT
			for _, part in ipairs(queryable(include)) do
				local at = rayBox(part, origin, direction)
				if at and (bestT == nil or at < bestT) then
					best, bestT = part, at
				end
			end
			return best, bestT
		end
		function workspace.GetPartBoundsInRadius(_, position, radius, params)
			assert(params.FilterType == Enum.RaycastFilterType.Include)
			local out = {}
			for _, part in ipairs(queryable(params.FilterDescendantsInstances)) do
				local o = part.CFrame:PointToObjectSpace(position)
				local h = part.Size / 2
				local c =
					Vector3.new(math.clamp(o.X, -h.X, h.X), math.clamp(o.Y, -h.Y, h.Y), math.clamp(o.Z, -h.Z, h.Z))
				if (o - c).Magnitude <= radius then
					table.insert(out, part)
				end
			end
			return out
		end
		w.workspace = workspace

		-- The local character: an R15-ish Head over a HumanoidRootPart.
		local character = Instance.new("Model")
		character.Name = "Player1"
		local function bodyPart(name, size)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.Parent = character
			return p
		end
		w.head = bodyPart("Head", Vector3.new(1.2, 1.2, 1.2))
		w.root = bodyPart("HumanoidRootPart", Vector3.new(2, 2, 1))
		w.player = { Character = character }
		function w.stand(at)
			w.root.CFrame = CFrame.new(at)
			w.head.CFrame = CFrame.new(at + Vector3.new(0, 1.5, 0))
		end
		w.stand(Vector3.new(0, 3, 0))

		local loader = t.loader({
			services = {
				Players = { LocalPlayer = w.player },
				RunService = {
					Heartbeat = {
						Connect = function(_, fn)
							table.insert(w.heartbeat, fn)
							return { Disconnect = function() end }
						end,
					},
				},
			},
			mocks = {
				TreeFX = {
					IsBusy = function(tree)
						return w.busy[tree] == true
					end,
				},
			},
			globals = {
				workspace = workspace,
				os = {
					clock = function()
						return w.clock
					end,
				},
				RaycastParams = {
					new = function()
						return {}
					end,
				},
				OverlapParams = {
					new = function()
						return {}
					end,
				},
			},
		})
		w.CanopyFade = loader:load("StarterPlayer/StarterPlayerScripts/CanopyFade")
		w.CanopyLogic = loader:shared("CanopyLogic")
		w.TreeArt = loader:shared("Art/TreeArt")
		w.WoodData = loader:shared("WoodData")

		function w.frame(dt)
			w.clock += dt
			for _, fn in ipairs(w.heartbeat) do
				fn(dt)
			end
		end
		function w.run(seconds)
			for _ = 1, math.floor(seconds * 60 + 0.5) do
				w.frame(1 / 60)
			end
		end

		-- Roblox's default LocalTransparencyModifier is 0 (@lune/roblox
		-- can't read one that was never set).
		local function settle(model)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 0
				end
			end
			model:SetAttribute("HomePivot", model:GetPivot())
			model:SetAttribute("Felled", false)
			model.Parent = trees
			return model
		end

		-- A plain tree whose leaf cube is centred on `leafAt`: a 10-stud
		-- trunk under it (2 studs below the cube), a branch and a root.
		function w.tree(leafAt)
			local base = leafAt - Vector3.new(0, 12, 0)
			local model = Instance.new("Model")
			model.Name = "Tree_test"
			local function part(name, size, cf, query)
				local p = Instance.new("Part")
				p.Name = name
				p.Size = size
				p.CFrame = cf
				p.CanCollide = name == "Trunk"
				p.CanQuery = query
				p.Parent = model
				return p
			end
			model.PrimaryPart = part(
				"Trunk",
				Vector3.new(10, 1, 1),
				CFrame.new(base + Vector3.new(0, 5, 0)) * CFrame.Angles(0, 0, math.pi / 2),
				true
			)
			part("Leaves", Vector3.new(8, 6, 8), CFrame.new(leafAt), true)
			part("Branch", Vector3.new(0.4, 0.4, 3), CFrame.new(base + Vector3.new(0, 8, 0)), false)
			part("Root", Vector3.new(0.3, 0.6, 0.8), CFrame.new(base + Vector3.new(0, 0.3, 0.7)), false)
			return settle(model)
		end

		-- A real tree of `woodId` at `at`.
		function w.real(woodId, at, seed)
			local model = w.TreeArt.Build(w.WoodData.Get(woodId), seed or 3, 1)
			model:PivotTo(CFrame.new(at) * model:GetPivot())
			return settle(model)
		end

		-- The point `s` of the way from the camera to the head.
		function w.along(s)
			local eye = camera.CFrame.Position
			return eye + (w.head.CFrame.Position - eye) * s
		end
		return w
	end

	local function ltm(part)
		return part.LocalTransparencyModifier
	end
	local function faded(part)
		return math.abs(ltm(part) - 0.7) < 1e-3
	end
	local function partNamed(model, name)
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end

	t.test("a canopy between the camera and you fades to 0.7; trunk, branch and root don't", function()
		local w = world()
		local tree = w.tree(w.along(0.5))
		local before = {}
		for _, d in ipairs(tree:GetDescendants()) do
			before[d] = { d.CanCollide, d.CanQuery }
		end
		w.CanopyFade.Start()
		w.run(0.2)
		t.ok(faded(partNamed(tree, "Leaves")), "the leaves fade: " .. ltm(partNamed(tree, "Leaves")))
		t.eq(ltm(tree.PrimaryPart), 0)
		t.eq(ltm(partNamed(tree, "Branch")), 0)
		t.eq(ltm(partNamed(tree, "Root")), 0)
		for _, d in ipairs(tree:GetDescendants()) do
			t.eq({ d.CanCollide, d.CanQuery }, before[d], d.Name .. "'s CanCollide and CanQuery stay")
		end
		t.eq(partNamed(tree, "Leaves").CanCollide, false)
		t.eq(w.CanopyFade.Tracked(), 1)
	end)

	t.test("it holds while in the way, and comes back 0.3 s after it's out of it", function()
		local w = world()
		local tree = w.tree(w.along(0.5))
		local leaves = partNamed(tree, "Leaves")
		w.CanopyFade.Start()
		w.run(2)
		t.ok(faded(leaves), "still faded while you stand behind it")
		-- You walk out from behind it.
		w.stand(Vector3.new(40, 3, 0))
		w.run(0.15)
		t.ok(faded(leaves), "held for 0.3 s after the last hit")
		w.run(0.3)
		t.ok(ltm(leaves) > 0 and ltm(leaves) < 0.7, "easing back")
		w.run(0.5)
		t.eq(ltm(leaves), 0)
		t.eq(w.CanopyFade.Tracked(), 0)
	end)

	t.test("a real oak's and pine's whole canopy fades, and nothing else", function()
		for _, woodId in ipairs({ "oak", "pine" }) do
			local w = world()
			local tree = w.real(woodId, Vector3.new(0, 0, 0))
			local canopy = w.CanopyLogic.CanopyParts(tree)
			-- Stand 8 studs out, with the camera beyond the canopy's middle.
			local c = canopy[1].CFrame.Position
			w.stand(Vector3.new(c.X + 8, 3, c.Z + 8))
			local head = w.head.CFrame.Position
			w.camera.CFrame = CFrame.new(c + (c - head).Unit * 30)
			w.CanopyFade.Start()
			w.run(0.2)
			local isCanopy = {}
			for _, p in ipairs(canopy) do
				isCanopy[p] = true
				t.ok(faded(p), woodId .. ": a " .. p.Name .. " stayed solid")
			end
			for _, d in ipairs(tree:GetDescendants()) do
				if d:IsA("BasePart") and not isCanopy[d] then
					t.eq(ltm(d), 0, woodId .. ": its " .. d.Name .. " faded")
				end
			end
		end
	end)

	t.test("rays see only trees, skip each tree found, at most six per target", function()
		local w = world()
		local row = {}
		for i = 1, 8 do
			-- Leaf cubes along the line, the first just clear of the camera.
			table.insert(row, w.tree(w.along(0.25 + i * 0.08)))
		end
		local far = w.tree(Vector3.new(500, 12, 500)) -- nowhere near the line
		w.CanopyFade.Start()
		w.frame(1 / 60) -- the first look
		local head, root = w.head.CFrame.Position, w.root.CFrame.Position
		local toHead, toRoot = 0, 0
		for _, ray in ipairs(w.rays) do
			local stop = ray.origin + ray.direction
			if (stop - head).Magnitude < 1e-3 then
				toHead += 1
			elseif (stop - root).Magnitude < 1e-3 then
				toRoot += 1
			end
			for _, inst in ipairs(ray.include) do
				t.ok(inst.Parent == w.trees, "only trees")
				t.ok(inst ~= far, "only trees near the line of sight")
			end
		end
		t.eq(toHead, 6)
		t.ok(toRoot <= 6, "at most six to the root")
		t.eq(toHead + toRoot, #w.rays)
		-- The first ray to your head sees the whole row; each one after it
		-- leaves out the tree the one before it hit (the nearest first).
		t.eq(#w.rays[1].include, 8)
		for i = 2, 6 do
			local prev, now = w.rays[i - 1], w.rays[i].include
			t.eq(#now, #prev.include - 1, "one fewer tree each time")
			local part = w.hit(prev.origin, prev.direction, prev.include)
			t.ok(part and part.Parent == row[i - 1], "ray " .. (i - 1) .. " hit the next tree along")
			t.eq(table.find(now, row[i - 1]), nil, "the tree just hit is left out")
		end
		-- The six nearest the camera are fading.
		for i = 1, 6 do
			t.ok(ltm(partNamed(row[i], "Leaves")) > 0, "tree " .. i .. " fades")
		end
		-- Ten looks a second (each starts with a ray that sees the whole row).
		w.rays = {}
		w.run(1)
		local looks = 0
		for _, ray in ipairs(w.rays) do
			if #ray.include == 8 and (ray.origin + ray.direction - head).Magnitude < 1e-3 then
				looks += 1
			end
		end
		t.eq(looks, 10)
	end)

	t.test("a canopy around the camera itself fades too", function()
		local w = world()
		local tree = w.tree(Vector3.new(0, 14, 10))
		local leaves = partNamed(tree, "Leaves")
		w.camera.CFrame = CFrame.new(0, 14, 11) -- inside the leaf cube
		w.CanopyFade.Start()
		w.frame(1 / 60) -- the first look
		t.ok(#w.rays > 0, "it looked")
		for _, ray in ipairs(w.rays) do
			-- Rays that start inside the cube can't see it ...
			t.eq(w.hit(ray.origin, ray.direction, ray.include), nil)
		end
		w.run(0.2)
		t.ok(faded(leaves), "... but the camera's own canopy fades")
	end)

	t.test("felled, dormant and falling or regrowing trees are left alone", function()
		local w = world()
		local felled = w.tree(w.along(0.3))
		local dormant = w.tree(w.along(0.5))
		local busy = w.tree(w.along(0.7))
		felled:SetAttribute("Felled", true)
		dormant:SetAttribute("Dormant", true)
		w.busy[busy] = true
		w.CanopyFade.Start()
		w.run(0.5)
		for _, tree in ipairs({ felled, dormant, busy }) do
			t.eq(ltm(partNamed(tree, "Leaves")), 0)
		end
		t.eq(#w.rays, 0, "no ray even looks at them")
		t.eq(w.CanopyFade.Tracked(), 0)
	end)

	t.test("a fading tree that starts to fall is handed back, never undoing TreeFX's fade", function()
		local w = world()
		local tree = w.tree(w.along(0.5))
		-- A second leaf cube that someone else (TreeFX) has set meanwhile.
		local other = partNamed(tree, "Leaves"):Clone()
		other.CFrame = other.CFrame + Vector3.new(0, 0, 0.5)
		other.Parent = tree
		other.LocalTransparencyModifier = 0
		local leaves = partNamed(tree, "Leaves")
		w.CanopyFade.Start()
		w.run(0.3)
		t.ok(faded(leaves) and faded(other))
		other.LocalTransparencyModifier = 1 -- not CanopyFade's any more
		w.run(0.3)
		t.eq(ltm(other), 1, "a part someone else set is left alone")
		-- It's felled: TreeFX owns it now.
		tree:SetAttribute("Felled", true)
		w.frame(1 / 60)
		t.eq(ltm(leaves), 0, "what CanopyFade faded is put back at once")
		t.eq(ltm(other), 1, "TreeFX's fade is never undone")
		t.eq(w.CanopyFade.Tracked(), 0)
		w.run(1)
		t.eq(ltm(leaves), 0, "and it stays out of the way of the fall")
		-- The same once TreeFX starts animating it (a regrow, say).
		local w2 = world()
		local tree2 = w2.tree(w2.along(0.5))
		w2.CanopyFade.Start()
		w2.run(0.3)
		t.ok(faded(partNamed(tree2, "Leaves")))
		w2.busy[tree2] = true
		w2.frame(1 / 60)
		t.eq(ltm(partNamed(tree2, "Leaves")), 0)
		t.eq(w2.CanopyFade.Tracked(), 0)
	end)

	t.test("a tree that streams out mid-fade is dropped, with nothing left see-through", function()
		local w = world()
		local tree = w.tree(w.along(0.5))
		local leaves = partNamed(tree, "Leaves")
		w.CanopyFade.Start()
		w.run(0.3)
		t.ok(faded(leaves))
		tree.Parent = nil -- streamed out
		w.frame(1 / 60)
		t.eq(w.CanopyFade.Tracked(), 0)
		t.eq(ltm(leaves), 0)
		w.run(1)
		t.eq(w.CanopyFade.Tracked(), 0)
	end)

	t.test("no Trees folder yet, no character, or first person: nothing happens, nothing breaks", function()
		local w = world()
		local tree = w.tree(w.along(0.5))
		local leaves = partNamed(tree, "Leaves")
		w.mapVisible = false -- not streamed in yet
		w.CanopyFade.Start()
		w.run(0.5)
		t.eq(#w.rays, 0)
		t.eq(ltm(leaves), 0)
		w.mapVisible = true
		w.run(0.2)
		t.ok(faded(leaves), "works once it streams in")
		-- No character (respawning).
		local w2 = world()
		local tree2 = w2.tree(w2.along(0.5))
		w2.player.Character = nil
		w2.CanopyFade.Start()
		w2.run(0.5)
		t.eq(#w2.rays, 0)
		t.eq(ltm(partNamed(tree2, "Leaves")), 0)
		-- First person: the camera is in your head.
		local w3 = world()
		w3.tree(Vector3.new(0, 14, 0))
		w3.camera.CFrame = CFrame.new(w3.head.CFrame.Position)
		w3.CanopyFade.Start()
		w3.run(0.5)
		t.eq(#w3.rays, 0)
	end)
end
