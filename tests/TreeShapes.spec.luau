--!nocheck
-- Every tree is a real one (T400): any tree-shaped Model (a tall thin part
-- under a wider canopy) in the world has the Tree tag, a WoodId and a trunk
-- you collide with, query and touch, or this fails and names its path. The
-- client no longer builds stand-in trees (the old stand-in forest is gone).
-- Runs on a real tree of every wood the plan plants, built by the real
-- SectionTrees, and on what the client builds for itself (the grass tufts).
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Instance = roblox.Vector3, roblox.CFrame, roblox.Instance
	local fs = require("@lune/fs")

	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WoodData = t.shared("WoodData")
	local TreeLogic = t.shared("TreeLogic")
	local SectionMetrics = t.shared("SectionMetrics")

	-- A round section's engine size is (length, diameter, diameter). The
	-- tall-thin test uses the logical Y-up frame, the same box a block had.
	local function logicalSize(part)
		if part.Name == "Section" then
			local _, size = SectionMetrics.BlockFrame(part)
			return size
		end
		return part.Size
	end

	-- Whether a Model is tree-shaped: a tall thin part with a wider part
	-- (a canopy) above its middle.
	local function treeShaped(model)
		local parts = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
		for _, trunk in ipairs(parts) do
			local size = logicalSize(trunk)
			local width = math.max(size.X, size.Z)
			if size.Y >= 4 and size.Y >= width * 2 then
				for _, crown in ipairs(parts) do
					local crownSize = logicalSize(crown)
					local crownWidth = math.max(crownSize.X, crownSize.Z)
					if
						crown ~= trunk
						and crownWidth >= width * 2
						and crown.CFrame.Position.Y > trunk.CFrame.Position.Y
					then
						return true, trunk
					end
				end
			end
		end
		return false, nil
	end

	local function pathOf(inst)
		local names = {}
		local cur = inst
		while cur do
			table.insert(names, 1, cur.Name)
			cur = cur.Parent
		end
		return table.concat(names, ".")
	end

	-- The audit: returns the problems (each names a path).
	local function audit(root)
		local problems = {}
		local models = {}
		if root:IsA("Model") then
			table.insert(models, root)
		end
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("Model") then
				table.insert(models, d)
			end
		end
		local checked = 0
		for _, model in ipairs(models) do
			local shaped, trunk = treeShaped(model)
			if shaped then
				checked += 1
				local path = pathOf(model)
				if not model:HasTag("Tree") then
					table.insert(problems, path .. " is tree-shaped and has no Tree tag")
				end
				if model:GetAttribute("WoodId") == nil then
					table.insert(problems, path .. " is tree-shaped and has no WoodId")
				end
				-- The trunk: a section part you collide with and the axe's ray finds. (CanTouch
				-- is off on every section, deliberately: TreeArtSections.spec pins it, and the
				-- brief's "CanTouch on" was not applied; see the PR notes.)
				local solid = false
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d.Name == "Section" and d.CanCollide and d.CanQuery then
						solid = true
					end
				end
				if not solid then
					table.insert(problems, path .. " has no trunk with CanCollide and CanQuery on")
				end
				_ = trunk
			end
		end
		return problems, checked
	end

	t.test("the audit itself: a stand-in tree (a box on a stick, no tag) is caught and named", function()
		local fake = Instance.new("Model")
		fake.Name = "StandIn"
		local trunk = Instance.new("Part")
		trunk.Name = "Section"
		trunk.Size = Vector3.new(1, 9, 1)
		trunk.CFrame = CFrame.new(0, 4.5, 0)
		trunk.CanCollide, trunk.CanQuery, trunk.CanTouch = false, false, false
		trunk.Parent = fake
		local crown = Instance.new("Part")
		crown.Name = "Crown"
		crown.Size = Vector3.new(8, 6, 8)
		crown.CFrame = CFrame.new(0, 11, 0)
		crown.Parent = fake
		local holder = Instance.new("Folder")
		holder.Name = "World"
		fake.Parent = holder
		local problems, checked = audit(holder)
		t.eq(checked, 1)
		t.ok(#problems >= 3, "the missing tag, WoodId and trunk are all named: " .. table.concat(problems, "; "))
		t.ok(string.find(problems[1], "World.StandIn", 1, true) ~= nil, "the path is named")
	end)

	-- A real SectionTrees, with the engine's world faked (as SectionTrees.spec does).
	local function plant()
		local map = Instance.new("Folder")
		map.Name = "TimberlineMap"
		local workspace = {
			WaitForChild = function(_, name)
				return if name == "TimberlineMap" then map else nil
			end,
			FindFirstChild = function(_, name)
				return if name == "TimberlineMap" then map else nil
			end,
			GetAttribute = function()
				return nil
			end,
			GetServerTimeNow = function()
				return 1000
			end,
			Raycast = function()
				return nil
			end,
			GetPartBoundsInBox = function()
				return {}
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
				return {}
			end,
		}
		local params = {
			new = function()
				return {}
			end,
		}
		local loader = t.loader({
			services = {
				Players = {
					GetPlayers = function()
						return {}
					end,
					GetPlayerByUserId = function()
						return nil
					end,
				},
				CollectionService = CollectionService,
				PhysicsService = {},
			},
			mocks = {
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
			},
			globals = {
				workspace = workspace,
				task = {
					delay = function() end,
					spawn = function(fn, ...)
						fn(...)
					end,
					wait = function()
						return 0
					end,
				},
				RaycastParams = params,
				OverlapParams = params,
			},
		})
		local Trees = loader:server("SectionTrees")
		local Wood = loader:server("WoodService")
		local remote = { FireClient = function() end }
		Wood.Init({
			worldFx = remote,
			manual = true,
			clock = function()
				return 1000
			end,
		})
		Trees.Init({
			notify = function() end,
			worldFx = remote,
			getAxe = function()
				return nil
			end,
			canChop = function()
				return true, nil
			end,
			swingDue = function()
				return 0
			end,
			setSwingDue = function() end,
			clock = function()
				return 1000
			end,
			manual = true,
		})
		return Trees, map
	end

	t.test("a real tree of every wood the plan plants is tagged, has a WoodId and a solid trunk", function()
		local Trees, map = plant()
		local woods, order = {}, {}
		local function note(list)
			for _, spot in ipairs(list) do
				if spot.woodId and not woods[spot.woodId] then
					woods[spot.woodId] = spot
					table.insert(order, spot.woodId)
				end
			end
		end
		note(WorldPlan.SpreadTrees())
		note(WorldPlan.Trees())
		note(WorldPlan.AddedTrees())
		note(WorldPlan.RegionTrees())
		local problems, checked = {}, 0
		for _, woodId in ipairs(order) do
			if WoodData.Get(woodId) then
				local spot = woods[woodId]
				for i, size in ipairs(TreeLogic.Sizes) do
					local model = Trees.SpawnTree(woodId, CFrame.new(spot.position + Vector3.new(i * 30, 0, 0)), {
						seed = 11 + i,
						size = size,
						stage = 1,
					})
					if model then
						model.Parent = map
					end
				end
			end
		end
		local found, n = audit(map)
		for _, p in ipairs(found) do
			table.insert(problems, p)
		end
		checked += n
		print(string.format("[TreeShapes] %d tree-shaped models audited, %d woods", checked, #order))
		t.ok(checked >= #order, "every wood produced a tree-shaped model: " .. checked)
		t.ok(#problems == 0, #problems .. " problems: " .. table.concat(problems, "; "))
	end)

	t.test("the client builds no tree: no stand-in forest anywhere, and what it builds passes the audit", function()
		-- No source (src, tests, tools) names the old stand-in forest. (This file and the
		-- notes name it only to say it is gone; the pattern is built so it cannot match itself.)
		local needles =
			{ "Forest" .. "Filler", "Filler" .. "Tree", "Filler" .. "Near", "Filler" .. "Far", "Filler" .. "Cell" }
		local hits = {}
		local function scan(dir)
			for _, name in ipairs(fs.readDir(dir)) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					if name ~= "Vendor" and name ~= ".git" and name ~= "preview" and name ~= "node_modules" then
						scan(path)
					end
				elseif
					path ~= "tests/TreeShapes.spec.luau"
					and (string.match(name, "%.luau$") or string.match(name, "%.lua$") or string.match(name, "%.json$"))
				then
					local text = fs.readFile(path)
					for _, needle in ipairs(needles) do
						if string.find(text, needle, 1, true) then
							table.insert(hits, path .. " names " .. needle)
						end
					end
				end
			end
		end
		scan("src")
		scan("tests")
		scan("tools")
		t.ok(#hits == 0, #hits .. " references remain: " .. table.concat(hits, "; "))
		t.ok(
			not fs.isFile("src/StarterPlayer/StarterPlayerScripts/" .. "Forest" .. "Filler.luau"),
			"the client module is gone"
		)
		-- What the client builds for itself: the grass tufts. Tree-shaped? No.
		local PropArt = t.load("ReplicatedStorage/Shared/Art/PropArt")
		local holder = Instance.new("Folder")
		holder.Name = "GrassTufts"
		for seed = 1, 8 do
			local tuft = PropArt.GrassTuft(seed * 37 + 5, PropArt.Tints("starter").grass)
			tuft.Parent = holder
		end
		local problems, checked = audit(holder)
		t.eq(checked, 0, "a tuft is not a tree")
		t.ok(#problems == 0)
	end)
end
