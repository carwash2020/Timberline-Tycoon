--!nocheck
-- TreeFX (StarterPlayerScripts/TreeFX) against fakes: the services, the
-- frame clock (task, Heartbeat, os.clock) and flat ground at y = 0 under
-- workspace:Raycast. It proves what Studio can't show us by reading code:
--   * chips are client-side anchored parts that never collide, query or
--     touch; they arc out, land on the ground (never below it), rest, fade
--     and go back to a capped pool;
--   * a landing tree throws smoke-textured dust in its biome's colour and
--     about ten leaf wedges in its palette that flutter down and fade;
--   * once down, the felled tree fades out (LocalTransparencyModifier 0 to
--     1, from FallTime + 0.1 to FallTime + 0.4, as its logs appear), and
--     regrowing undoes it, also for a tree that streamed out while faded
--     and came back; a standing tree that streams in is always made solid
--     (the weak `faded` set may have forgotten it), a felled one is left.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

	-- Methods @lune/roblox lacks. They're shared by the whole test run, so
	-- they reach the running fake world through `current`.
	local current
	roblox.implementMethod("Model", "GetAttributeChangedSignal", function(model, name)
		return current.signal(model, name)
	end)
	roblox.implementMethod("Model", "ScaleTo", function(model, scale)
		current.scaled[model] = scale
	end)
	roblox.implementMethod("Workspace", "GetServerTimeNow", function()
		return current.serverNow
	end)
	roblox.implementMethod("Workspace", "Raycast", function(_, origin, direction, params)
		table.insert(current.rays, { origin = origin, direction = direction, params = params })
		if origin.Y >= 0 and origin.Y + direction.Y <= 0 then
			return { Position = Vector3.new(origin.X, 0, origin.Z), Normal = Vector3.new(0, 1, 0) }
		end
		return nil
	end)
	roblox.implementMethod("ParticleEmitter", "Emit", function(emitter, count)
		table.insert(current.emitted, { emitter = emitter, count = count })
	end)

	local function world()
		local w = {
			clock = 100,
			serverNow = 50,
			rays = {},
			emitted = {},
			signals = {}, -- [model][attribute] = { fn }
			threads = {},
			heartbeat = {},
			scaled = {},
			debris = {},
			tagged = { Tree = {} },
			added = {},
			removed = {},
		}
		current = w

		function w.signal(model, name)
			w.signals[model] = w.signals[model] or {}
			local list = w.signals[model][name] or {}
			w.signals[model][name] = list
			return {
				Connect = function(_, fn)
					table.insert(list, fn)
					return {
						Disconnect = function()
							for i, f in ipairs(list) do
								if f == fn then
									table.remove(list, i)
									break
								end
							end
						end,
					}
				end,
			}
		end
		-- Sets an attribute the way replication does: listeners hear it.
		function w.set(model, name, value)
			model:SetAttribute(name, value)
			local list = w.signals[model] and w.signals[model][name] or {}
			for _, fn in ipairs(table.clone(list)) do
				fn()
			end
		end

		local game = Instance.new("DataModel")
		local workspace = game:GetService("Workspace")
		local camera = Instance.new("Camera")
		camera.CFrame = CFrame.new(0, 6, 14)
		camera.Parent = workspace
		workspace.CurrentCamera = camera
		w.workspace, w.camera = workspace, camera

		local function store(list)
			return {
				Connect = function(_, fn)
					table.insert(list, fn)
				end,
			}
		end
		local loader = t.loader({
			services = {
				CollectionService = {
					GetTagged = function(_, tag)
						return w.tagged[tag] or {}
					end,
					GetInstanceAddedSignal = function(_, tag)
						w.added[tag] = w.added[tag] or {}
						return store(w.added[tag])
					end,
					GetInstanceRemovedSignal = function(_, tag)
						w.removed[tag] = w.removed[tag] or {}
						return store(w.removed[tag])
					end,
				},
				Debris = {
					AddItem = function(_, inst)
						table.insert(w.debris, inst)
					end,
				},
				Players = {
					LocalPlayer = { Character = nil },
					GetPlayers = function()
						return {}
					end,
				},
				RunService = {
					Heartbeat = {
						Wait = function()
							return coroutine.yield()
						end,
						Connect = function(_, fn)
							local entry = { fn = fn }
							table.insert(w.heartbeat, entry)
							return {
								Disconnect = function()
									entry.dead = true
								end,
							}
						end,
					},
				},
			},
			mocks = {
				SoundData = { PlayAt = function() end },
				CameraShake = { Shake = function() end },
			},
			globals = {
				workspace = workspace,
				task = {
					spawn = function(fn, ...)
						local co = coroutine.create(fn)
						table.insert(w.threads, co)
						assert(coroutine.resume(co, ...))
					end,
					wait = function()
						return coroutine.yield()
					end,
				},
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
			},
		})
		w.TreeFX = loader:load("StarterPlayer/StarterPlayerScripts/TreeFX")
		w.TreeArt = loader:shared("Art/TreeArt")
		w.TreeLogic = loader:shared("TreeLogic")
		w.WoodData = loader:shared("WoodData")

		-- One frame, dt seconds long: every waiting thread, then Heartbeat.
		function w.frame(dt)
			w.clock += dt
			w.serverNow += dt
			local waiting = w.threads
			w.threads = {}
			for _, co in ipairs(waiting) do
				if coroutine.status(co) == "suspended" then
					assert(coroutine.resume(co, dt))
					if coroutine.status(co) == "suspended" then
						table.insert(w.threads, co)
					end
				end
			end
			local live = {}
			for _, entry in ipairs(w.heartbeat) do
				if not entry.dead then
					entry.fn(dt)
				end
				if not entry.dead then
					table.insert(live, entry)
				end
			end
			w.heartbeat = live
		end
		function w.run(seconds, each)
			local steps = math.floor(seconds * 60 + 0.5)
			for _ = 1, steps do
				w.frame(1 / 60)
				if each then
					each()
				end
			end
		end

		-- A tree standing at the origin, as TreeService sets it up.
		function w.tree(woodId)
			local def = w.WoodData.Get(woodId)
			local tree = w.TreeArt.Build(def, 7, 1)
			tree:SetAttribute("WoodId", woodId)
			tree:SetAttribute("MaxHP", 10)
			tree:SetAttribute("HP", 10)
			tree:SetAttribute("HomePivot", tree:GetPivot())
			tree:SetAttribute("Felled", false)
			tree.Parent = workspace
			table.insert(w.tagged.Tree, tree)
			return tree
		end

		function w.pieces(name)
			local out = {}
			local folder = workspace:FindFirstChild("TreeFXPieces")
			for _, p in ipairs(if folder then folder:GetChildren() else {}) do
				if p.Name == name then
					table.insert(out, p)
				end
			end
			return out
		end
		return w
	end

	-- A part's LocalTransparencyModifier (@lune/roblox can't read one that
	-- was never set: that's Roblox's default, 0).
	local function ltm(part)
		local ok, value = pcall(function()
			return part.LocalTransparencyModifier
		end)
		return if ok then value else 0
	end

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	-- Fells `tree` (the server's order: FallDir and FellAt, then Felled).
	local function fell(w, tree)
		w.set(tree, "HP", 0)
		tree:SetAttribute("FallDir", Vector3.new(1, 0, 0))
		tree:SetAttribute("FellAt", w.serverNow)
		w.set(tree, "Felled", true)
	end

	t.test("chips are anchored client parts that never collide, query or touch", function()
		local w = world()
		local tree = w.tree("oak")
		w.TreeFX.Start()
		w.set(tree, "HP", 8)
		local chips = w.pieces("WoodChip")
		t.eq(#chips, 6)
		for _, chip in ipairs(chips) do
			t.eq(chip.Anchored, true)
			t.eq(chip.CanCollide, false)
			t.eq(chip.CanQuery, false)
			t.eq(chip.CanTouch, false)
			t.eq(chip.CastShadow, false)
		end
		-- One ground ray per chip, skipping the tree and anything that doesn't collide.
		t.eq(#w.rays, 6)
		for _, ray in ipairs(w.rays) do
			t.eq(ray.params.FilterType, roblox.Enum.RaycastFilterType.Exclude)
			t.eq(ray.params.RespectCanCollide, true)
			t.ok(table.find(ray.params.FilterDescendantsInstances, tree), "the ray skips the tree")
			t.ok(ray.direction.Y < 0, "it looks down")
		end
	end)

	t.test("chips arc out, land on the ground, rest, fade and go", function()
		local w = world()
		local tree = w.tree("oak")
		w.TreeFX.Start()
		w.set(tree, "HP", 8)
		local chips = w.pieces("WoodChip")
		local start = {}
		local highest = {}
		for _, chip in ipairs(chips) do
			start[chip] = chip.CFrame.Position
			highest[chip] = chip.CFrame.Position.Y
		end
		w.run(0.6, function()
			for _, chip in ipairs(chips) do
				local y = chip.CFrame.Position.Y
				t.ok(y >= 0.1 - 1e-3, "a chip went below the ground: " .. y)
				highest[chip] = math.max(highest[chip], y)
			end
		end)
		local landed = {}
		for _, chip in ipairs(chips) do
			local p = chip.CFrame.Position
			t.ok(highest[chip] > start[chip].Y + 0.5, "it arcs up first")
			t.ok(math.abs(p.Y - 0.1) < 1e-3, "it lies on the ground")
			local out = Vector3.new(p.X - start[chip].X, 0, p.Z - start[chip].Z).Magnitude
			t.ok(out > 0.5 and out < 5, "it lands around the trunk's foot")
			t.ok(chip.CFrame.UpVector.Y > 0.999, "it lies flat")
			t.eq(chip.Transparency, 0)
			landed[chip] = p
		end
		-- Resting: still there, solid, not moving, a second after the swing.
		w.run(0.4)
		for _, chip in ipairs(chips) do
			t.eq(chip.Parent ~= nil, true)
			t.eq(chip.Transparency, 0)
			t.ok((chip.CFrame.Position - landed[chip]).Magnitude < 1e-4, "it stays put")
		end
		-- Fading over 0.4 s, then gone by 1.8 s, and nothing left running.
		w.run(0.45)
		local fading = 0
		for _, chip in ipairs(chips) do
			if chip.Parent and chip.Transparency > 0 then
				fading += 1
			end
		end
		t.ok(fading > 0, "they fade out")
		w.run(0.4)
		t.eq(#w.pieces("WoodChip"), 0)
		t.eq(#w.heartbeat, 0)
	end)

	t.test("chips come from a capped pool", function()
		local w = world()
		local tree = w.tree("oak")
		w.TreeFX.Start()
		local seen = {}
		local count = 0
		for hit = 1, 12 do
			w.set(tree, "HP", 10 - hit * 0.5)
			t.ok(#w.pieces("WoodChip") <= 36, "at most 36 chips at once")
			for _, chip in ipairs(w.pieces("WoodChip")) do
				if not seen[chip] then
					seen[chip] = true
					count += 1
				end
			end
			w.run(0.1)
		end
		t.ok(count <= 36, "chips are reused, not made for ever: " .. count)
		w.run(2)
		-- Later swings reuse the parked chips.
		w.set(tree, "HP", 1)
		for _, chip in ipairs(w.pieces("WoodChip")) do
			t.ok(seen[chip], "a parked chip is reused")
		end
	end)

	t.test("a landing tree puffs smoke dust in its biome's colour", function()
		for _, woodId in ipairs({ "oak", "frostwood", "emberwood" }) do
			local w = world()
			local tree = w.tree(woodId)
			w.TreeFX.Start()
			fell(w, tree)
			w.run(1.2)
			local dust
			for _, e in ipairs(w.emitted) do
				if e.emitter.Parent and e.emitter.Parent.Name == "FellBurst" then
					dust = e
				end
			end
			t.ok(dust, woodId .. ": a dust burst")
			local emitter = dust.emitter
			t.eq(emitter.Texture, "rbxasset://textures/particles/smoke_main.dds")
			local def = w.WoodData.Get(woodId)
			t.eq(emitter.Color.Keypoints[1].Value, w.TreeArt.DustColor(def))
			local size = emitter.Size.Keypoints
			t.eq(size[1].Value, 2)
			t.eq(size[#size].Value, 6)
			t.ok(dust.count >= 10 and dust.count <= 30, "a puff, not a storm")
			-- No sparkle-textured leaf emitter any more.
			for _, e in ipairs(w.emitted) do
				t.ok(e.emitter == emitter, "only the dust is a particle burst")
			end
		end
	end)

	t.test("about ten leaves flutter down in the wood's palette and go", function()
		local w = world()
		local tree = w.tree("oak")
		w.TreeFX.Start()
		fell(w, tree)
		w.run(1.0)
		local leaves = w.pieces("FallingLeaf")
		t.eq(#leaves, 10)
		local palette = {}
		for _, c in ipairs(w.TreeArt.Palette(w.WoodData.Get("oak")).leaves) do
			palette[tostring(c)] = true
		end
		for _, leaf in ipairs(leaves) do
			t.eq(leaf.ClassName, "WedgePart")
			t.ok(palette[tostring(leaf.Color)], "a leaf in the oak's palette")
			t.eq(leaf.Anchored, true)
			t.eq(leaf.CanCollide, false)
			t.eq(leaf.CanQuery, false)
			t.eq(leaf.CanTouch, false)
		end
		w.run(2.6, function()
			for _, leaf in ipairs(leaves) do
				if leaf.Parent then
					t.ok(leaf.CFrame.Position.Y >= 0.05 - 1e-3, "a leaf went below the ground")
				end
			end
		end)
		w.run(2.0) -- the highest leaves take about 3.7 s to land, rest and fade
		t.eq(#w.pieces("FallingLeaf"), 0)
	end)

	t.test("a dead tree drops no leaves", function()
		local w = world()
		local tree = w.tree("phantomwood")
		w.TreeFX.Start()
		fell(w, tree)
		w.run(1.2)
		t.eq(#w.pieces("FallingLeaf"), 0)
	end)

	t.test("once down, the felled tree fades out", function()
		local w = world()
		local tree = w.tree("oak")
		local visible = {}
		for _, p in ipairs(parts(tree)) do
			if p.Transparency < 1 then
				table.insert(visible, p)
			end
		end
		w.TreeFX.Start()
		fell(w, tree)
		local fall = w.TreeLogic.FallTime
		w.run(fall * 0.9)
		for _, p in ipairs(visible) do
			t.eq(ltm(p), 0) -- still falling: solid
		end
		w.run(fall * 0.1 + 0.05)
		for _, p in ipairs(visible) do
			t.eq(ltm(p), 0) -- landed a moment ago: still solid
		end
		w.run(0.2) -- FallTime + 0.25: halfway
		for _, p in ipairs(visible) do
			t.ok(ltm(p) > 0.3 and ltm(p) < 0.7, "fading: " .. ltm(p))
		end
		w.run(0.17) -- FallTime + 0.42: gone, as the logs reach this client
		for _, p in ipairs(visible) do
			t.eq(ltm(p), 1)
		end
	end)

	t.test("a regrown tree is fully opaque again, near the camera or far away", function()
		for _, far in ipairs({ false, true }) do
			local w = world()
			local tree = w.tree("pine")
			w.TreeFX.Start()
			fell(w, tree)
			w.run(1.5)
			if far then
				w.camera.CFrame = CFrame.new(0, 6, 500)
			end
			w.set(tree, "HP", 10)
			w.set(tree, "Felled", false)
			for _, p in ipairs(parts(tree)) do
				t.eq(ltm(p), 0)
			end
			w.run(3)
			for _, p in ipairs(parts(tree)) do
				t.eq(ltm(p), 0)
			end
		end
	end)

	t.test("a standing tree that streams in is solid, even one this client forgot it faded", function()
		local w = world()
		local tree = w.tree("oak")
		w.TreeFX.Start()
		-- See-through from before it streamed away, and not in `faded` any
		-- more (a weak key: the record can be gone).
		for _, p in ipairs(parts(tree)) do
			p.LocalTransparencyModifier = 1
		end
		for _, fn in ipairs(w.removed.Tree) do
			fn(tree)
		end
		for _, fn in ipairs(w.added.Tree) do
			fn(tree)
		end
		for _, p in ipairs(parts(tree)) do
			t.eq(ltm(p), 0)
		end
		-- The same for one that's there when TreeFX starts.
		local w2 = world()
		local tree2 = w2.tree("pine")
		for _, p in ipairs(parts(tree2)) do
			p.LocalTransparencyModifier = 0.7
		end
		w2.TreeFX.Start()
		for _, p in ipairs(parts(tree2)) do
			t.eq(ltm(p), 0)
		end
	end)

	t.test("a felled tree that streams in is left as it is until it regrows", function()
		local w = world()
		local tree = w.tree("birch")
		w.TreeFX.Start()
		fell(w, tree)
		w.run(2)
		for _, fn in ipairs(w.removed.Tree) do
			fn(tree)
		end
		for _, fn in ipairs(w.added.Tree) do
			fn(tree) -- still felled (the server hides it)
		end
		for _, p in ipairs(parts(tree)) do
			if p.Transparency < 1 then
				t.eq(ltm(p), 1)
			end
		end
		w.set(tree, "HP", 10)
		w.set(tree, "Felled", false)
		for _, p in ipairs(parts(tree)) do
			t.eq(ltm(p), 0)
		end
	end)

	t.test("a faded tree that streams out and back in isn't left see-through", function()
		local w = world()
		local tree = w.tree("maple")
		w.TreeFX.Start()
		fell(w, tree)
		w.run(1.5)
		-- It streams out, regrows while it's away, then streams back in.
		for _, fn in ipairs(w.removed.Tree) do
			fn(tree)
		end
		tree:SetAttribute("HP", 10)
		w.set(tree, "Felled", false) -- nobody's listening: it's streamed out
		for _, fn in ipairs(w.added.Tree) do
			fn(tree)
		end
		for _, p in ipairs(parts(tree)) do
			t.eq(ltm(p), 0)
		end
	end)
end
