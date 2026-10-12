--!nocheck
-- Plot machines (sawmills, planers, the chop saw, belts) built before their
-- meshes are cached stay part-built, and swap to the real mesh IN PLACE when
-- it lands (13 October 2026; the same path as the mining machines, PR 174).
-- Lune cannot load a real mesh, so the engine is held: MeshKit.EngineLoad
-- only runs when the spec runs the queued job, exactly as a slow download.
return function(t)
	local roblox = t.roblox

	-- Every machine MachineArt builds that has a Blender body, with its builder.
	local function kinds(MachineArt, Catalog, PlanerLogic)
		local out = {}
		for _, mill in ipairs(Catalog.SawmillList()) do
			table.insert(out, {
				id = mill.id,
				build = function(ghost)
					return MachineArt.Build(mill.id, ghost)
				end,
			})
		end
		for _, machine in ipairs(PlanerLogic.List()) do
			table.insert(out, {
				id = machine.id,
				build = function(ghost)
					return MachineArt.BuildPlaner(machine.id, ghost)
				end,
			})
		end
		table.insert(out, {
			id = "ChopSaw",
			build = function(ghost)
				return MachineArt.BuildChopSaw(ghost)
			end,
		})
		for _, id in ipairs({
			"ConveyorStraight",
			"ConveyorTurn",
			"ConveyorFunnel",
			"SwitchBelt",
			"TiltedBelt",
			"BeltSupport",
			"WoodDetector",
		}) do
			table.insert(out, {
				id = id,
				build = function(ghost)
					return MachineArt.BuildBelt(id, ghost)
				end,
			})
		end
		return out
	end

	local function held()
		local loader = t.loader()
		local MeshKit = loader:shared("Art/MeshKit")
		local MachineSkin = loader:shared("Art/MachineSkin")
		local MachineMeshes = loader:shared("Art/MachineMeshes")
		local MachineArt = loader:shared("Art/MachineArt")
		local Catalog = loader:shared("ItemCatalog")
		local PlanerLogic = loader:shared("PlanerLogic")
		MeshKit.Reset()
		MachineSkin.Reset()
		MeshKit.Override = nil
		MeshKit.Retries = 0
		local jobs = {}
		MeshKit.Scheduler = {
			spawn = function(fn)
				table.insert(jobs, fn)
			end,
			wait = function() end,
			clock = os.clock,
		}
		local failing = {}
		local loads = {}
		MeshKit.EngineLoad = function(meshId)
			table.insert(loads, meshId)
			if failing[meshId] then
				return nil, "no permission"
			end
			local part = roblox.Instance.new("MeshPart")
			part.Name = "Loaded" .. tostring(meshId)
			return part, nil
		end
		local sim = {
			failing = failing,
			loads = loads,
			runJobs = function()
				while #jobs > 0 do
					table.remove(jobs, 1)()
				end
			end,
			done = function()
				MeshKit.EngineLoad = nil
				MeshKit.Scheduler = {
					spawn = function(fn)
						fn()
					end,
					wait = function() end,
					clock = os.clock,
				}
				MeshKit.Reset()
				MachineSkin.Reset()
			end,
		}
		return {
			MeshKit = MeshKit,
			MachineSkin = MachineSkin,
			MachineMeshes = MachineMeshes,
			MachineArt = MachineArt,
			kinds = kinds(MachineArt, Catalog, PlanerLogic),
			sim = sim,
		}
	end

	-- The same machine built when every mesh is already cached (the direct
	-- meshed build): what the swap must end up as.
	local function cachedTwin(id)
		local loader = t.loader()
		local MeshKit = loader:shared("Art/MeshKit")
		local MachineSkin = loader:shared("Art/MachineSkin")
		local MachineArt = loader:shared("Art/MachineArt")
		local Catalog = loader:shared("ItemCatalog")
		local PlanerLogic = loader:shared("PlanerLogic")
		MeshKit.Reset()
		MachineSkin.Reset()
		MeshKit.Override = function(_, name, size)
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local model
		for _, kind in ipairs(kinds(MachineArt, Catalog, PlanerLogic)) do
			if kind.id == id then
				model = kind.build(false)
			end
		end
		MeshKit.Override = nil
		MeshKit.Reset()
		MachineSkin.Reset()
		return model
	end

	local function meshCount(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("VisualMesh") == true then
				n += 1
			end
		end
		return n
	end

	local function child(model, name)
		for _, c in ipairs(model:GetChildren()) do
			if c.Name == name then
				return c
			end
		end
		return nil
	end

	-- "Class Name" of every direct child, sorted: the shape of the machine.
	local function shape(model)
		local out = {}
		for _, c in ipairs(model:GetChildren()) do
			table.insert(out, c.ClassName .. " " .. c.Name)
		end
		table.sort(out)
		return out
	end

	-- Parts that exist only because the machine is part-built (named in
	-- MachineArt's decor lists). Anything else that was there before must be
	-- the very same instance afterwards.
	local DECOR = {
		Deck = true,
		SawBlade = true,
		Post = true,
		Stack = true,
		StackCap = true,
		MakerPlate = true,
		Boiler = true,
		BoilerDome = true,
		Gauge = true,
		Gantry = true,
		GantryLeg = true,
		Lamp = true,
		CutterHead = true,
		Roller = true,
		SteamPipe = true,
		Leg = true,
		Stripe = true,
		Plate = true,
		Pan = true,
		RailCap = true,
		PortCollar = true,
		Gate = true,
		RailClamp = true,
		Saddle = true,
		Brace = true,
		ArchRim = true,
		Face = true,
		FilterPip = true,
	}

	t.test(
		"every plot machine is part-built at once without yielding, and counts no pending load as a failure",
		function()
			local h = held()
			t.ok(#h.kinds >= 14, "found the machine kinds (" .. #h.kinds .. ")")
			for _, kind in ipairs(h.kinds) do
				local co = coroutine.create(function()
					return kind.build(false)
				end)
				local ok, model = coroutine.resume(co)
				t.ok(ok, kind.id .. ": " .. tostring(model))
				t.eq(coroutine.status(co), "dead", kind.id .. " built without yielding")
				t.eq(h.MachineSkin.Wears(model), false, kind.id .. " is part-built for now")
				t.eq(meshCount(model), 0, kind.id)
				t.ok(model.PrimaryPart ~= nil, kind.id .. " is usable: it has its Root")
				t.ok(
					child(model, "Conveyor") ~= nil or kind.id == "ChopSaw" or kind.id == "BeltSupport",
					kind.id .. " carries wood"
				)
			end
			t.eq(#h.sim.loads, 0, "nothing touched the engine on the building thread")
			t.eq(h.MachineSkin.Misses(), 0, "a load still on its way is not logged as a miss")
			h.sim.done()
		end
	)

	t.test("when the meshes land every machine wears them, keeping the same gameplay part instances", function()
		for _, kind in ipairs(held().kinds) do
			local h = held()
			local model
			for _, k in ipairs(h.kinds) do
				if k.id == kind.id then
					model = k.build(false)
				end
			end
			model.Parent = roblox.Instance.new("Folder")
			local before = {} -- descendant -> the name of the model child it sits under
			for _, d in ipairs(model:GetDescendants()) do
				local top = d
				while top.Parent ~= nil and top.Parent ~= model do
					top = top.Parent
				end
				before[d] = top.Name
			end
			local root = model.PrimaryPart
			h.sim.runJobs()
			h.MeshKit.Pump(1)
			t.eq(h.MachineSkin.Wears(model), true, kind.id .. " wears its meshes")
			t.ok(meshCount(model) >= 1, kind.id .. " has mesh parts")
			t.eq(model.PrimaryPart, root, kind.id .. ": the same Root")
			for d, topName in pairs(before) do
				local ok, inside = pcall(function()
					return d:IsDescendantOf(model)
				end)
				if not ok or not inside then
					-- Gone: it must have been part-built decor (or sat inside some).
					t.ok(DECOR[topName] == true, kind.id .. " lost " .. topName .. ", a gameplay part")
				end
			end
			h.sim.done()
		end
	end)

	t.test(
		"the swapped machine is the machine built from cached meshes (same pieces, same signs, same guard)",
		function()
			for _, kind in ipairs(held().kinds) do
				local h = held()
				local model
				for _, k in ipairs(h.kinds) do
					if k.id == kind.id then
						model = k.build(false)
					end
				end
				model.Parent = roblox.Instance.new("Folder")
				h.sim.runJobs()
				h.MeshKit.Pump(1)
				local twin = cachedTwin(kind.id)
				t.eq(
					shape(model),
					shape(twin),
					kind.id .. " has the same parts as a machine built with its meshes cached"
				)
				t.eq(model:GetAttribute("MeshAsset"), twin:GetAttribute("MeshAsset"), kind.id)
				for _, name in ipairs({ "TierSign", "PriceSign", "BladeGuard" }) do
					local a, b = child(model, name), child(twin, name)
					t.eq(a == nil, b == nil, kind.id .. " " .. name)
					if a and b then
						t.ok(
							(a.CFrame.Position - b.CFrame.Position).Magnitude < 1e-3,
							kind.id .. " " .. name .. " stands where the meshed build puts it"
						)
						t.eq(a.Transparency, b.Transparency, kind.id .. " " .. name .. " transparency")
					end
				end
				-- Each mesh piece sits where it does in the cached build.
				local rootA, rootB = model.PrimaryPart, twin.PrimaryPart
				for _, c in ipairs(twin:GetChildren()) do
					if c:IsA("BasePart") and c:GetAttribute("VisualMesh") == true then
						local other = child(model, c.Name)
						t.ok(other ~= nil, kind.id .. " has mesh piece " .. c.Name)
						if other then
							local want = rootB.CFrame:ToObjectSpace(c.CFrame).Position
							local got = rootA.CFrame:ToObjectSpace(other.CFrame).Position
							t.ok(
								(want - got).Magnitude < 1e-3,
								kind.id .. " mesh piece " .. c.Name .. " is placed like the cached build"
							)
						end
					end
				end
				h.sim.done()
			end
		end
	)

	t.test("a machine placed and moved before its meshes land keeps its pivot and its meshes follow", function()
		for _, kind in ipairs(held().kinds) do
			local h = held()
			local model
			for _, k in ipairs(h.kinds) do
				if k.id == kind.id then
					model = k.build(false)
				end
			end
			model.Parent = roblox.Instance.new("Folder")
			-- PlotService: BlueprintModels.Place moves it; a player may then move it again.
			model:PivotTo(roblox.CFrame.new(120, 4, -60) * roblox.CFrame.Angles(0, math.rad(90), 0))
			local placed = model:GetPivot()
			h.sim.runJobs()
			h.MeshKit.Pump(1)
			t.eq(h.MachineSkin.Wears(model), true, kind.id)
			local now = model:GetPivot()
			t.ok((now.Position - placed.Position).Magnitude < 1e-3, kind.id .. " is where it was placed")
			t.ok(now.RightVector:Dot(placed.RightVector) > 0.9999, kind.id .. " keeps its facing")
			-- The meshes are in the machine's frame, not left at the origin.
			local twin = cachedTwin(kind.id)
			local rootA, rootB = model.PrimaryPart, twin.PrimaryPart
			for _, c in ipairs(twin:GetChildren()) do
				if c:IsA("BasePart") and c:GetAttribute("VisualMesh") == true then
					local other = child(model, c.Name)
					local want = rootB.CFrame:ToObjectSpace(c.CFrame).Position
					local got = rootA.CFrame:ToObjectSpace(other.CFrame).Position
					t.ok((want - got).Magnitude < 1e-3, kind.id .. " mesh " .. c.Name .. " follows the moved machine")
				end
			end
			h.sim.done()
		end
	end)

	t.test("a failed load keeps the part-built machine, logs once and never throws", function()
		for _, kind in ipairs(held().kinds) do
			local h = held()
			for _, piece in ipairs(h.MachineMeshes.Get(kind.id).pieces) do
				h.sim.failing[h.MachineMeshes.MeshId(kind.id, piece.name)] = true
			end
			local model
			for _, k in ipairs(h.kinds) do
				if k.id == kind.id then
					model = k.build(false)
				end
			end
			model.Parent = roblox.Instance.new("Folder")
			local count = #model:GetDescendants()
			h.sim.runJobs()
			local ok, err = pcall(h.MeshKit.Pump, 1)
			t.ok(ok, tostring(err))
			t.eq(h.MachineSkin.Wears(model), false, kind.id .. " stays part-built")
			t.eq(meshCount(model), 0, kind.id)
			t.eq(#model:GetDescendants(), count, kind.id .. " is untouched")
			t.ok(h.MachineSkin.Misses() <= 1, kind.id .. " logged at most one line")
			h.sim.done()
		end
	end)

	t.test("a machine of several pieces is dressed whole or not at all", function()
		local seen = 0
		for _, kind in ipairs(held().kinds) do
			local h = held()
			local pieces = h.MachineMeshes.Get(kind.id).pieces
			if #pieces >= 3 then
				seen += 1
				-- The last piece fails: no piece of it may be left on the machine.
				h.sim.failing[h.MachineMeshes.MeshId(kind.id, pieces[#pieces].name)] = true
				local model
				for _, k in ipairs(h.kinds) do
					if k.id == kind.id then
						model = k.build(false)
					end
				end
				model.Parent = roblox.Instance.new("Folder")
				h.sim.runJobs()
				h.MeshKit.Pump(1)
				t.eq(h.MachineSkin.Wears(model), false, kind.id .. " is not half dressed")
				t.eq(meshCount(model), 0, kind.id)
			end
			h.sim.done()
		end
		t.ok(seen >= 3, "checked machines of three or more pieces (" .. seen .. ")")
	end)

	t.test("a machine destroyed before its meshes land is dropped cleanly", function()
		for _, kind in ipairs(held().kinds) do
			local h = held()
			local model
			for _, k in ipairs(h.kinds) do
				if k.id == kind.id then
					model = k.build(false)
				end
			end
			local folder = roblox.Instance.new("Folder")
			model.Parent = folder
			model:Destroy()
			h.sim.runJobs()
			local ok, err = pcall(h.MeshKit.Pump, 1)
			t.ok(ok, tostring(err))
			t.eq(h.MeshKit.SwapStats().swapped, 0, kind.id .. " nothing swapped into a dead model")
			t.ok(h.MeshKit.SwapStats().skipped >= 1, kind.id .. " the swap gave up")
			t.eq(#folder:GetChildren(), 0, kind.id .. " left nothing behind")
			h.sim.done()
		end
	end)

	t.test("a plot restored from a save at join is dressed in one round, whatever order the meshes land", function()
		local h = held()
		local models = {}
		local folder = roblox.Instance.new("Folder")
		-- Every kind twice, as PlotService.buildItem would build a saved plot.
		for _ = 1, 2 do
			for _, kind in ipairs(h.kinds) do
				local model = kind.build(false)
				model:PivotTo(roblox.CFrame.new(#models * 30, 0, 0))
				model.Parent = folder
				table.insert(models, model)
			end
		end
		h.sim.runJobs()
		h.MeshKit.Pump(5)
		for _, model in ipairs(models) do
			t.eq(h.MachineSkin.Wears(model), true, model.Name .. " wears its meshes")
		end
		h.sim.done()
	end)

	t.test("a machine built after its meshes are cached is meshed at once (no swap needed)", function()
		for _, kind in ipairs(held().kinds) do
			local model = cachedTwin(kind.id)
			t.ok(model:GetAttribute("MeshAsset") ~= nil, kind.id)
		end
	end)

	t.test("the placement ghost is swapped too, and stays see-through", function()
		local h = held()
		local ghost = h.MachineArt.BuildChopSaw(true)
		ghost.Parent = roblox.Instance.new("Folder")
		h.sim.runJobs()
		h.MeshKit.Pump(1)
		t.eq(h.MachineSkin.Wears(ghost), true)
		for _, d in ipairs(ghost:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("VisualMesh") == true then
				t.ok(
					d.Transparency >= 0.449,
					"a ghost mesh is see-through: " .. d.Name .. " " .. tostring(d.Transparency)
				)
			end
		end
		h.sim.done()
	end)
end
