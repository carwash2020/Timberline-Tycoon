--!nocheck
-- T381: the town Sky Forge Court and the isle's Starfall Forge wear their
-- uploaded meshes. The part build shows only until every mesh (the
-- collision piece too) has loaded; the hosts the server and the client look
-- up by name stay where they were; the court is walked on through its
-- Collision piece alone.
return function(t)
	local fs = require("@lune/fs")
	local roblox = t.roblox
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local BacklogModels = t.load("ReplicatedStorage/Shared/Art/BacklogModels")
	local TownModels = t.load("ReplicatedStorage/Shared/Art/TownModels")
	local TownMeshes = t.load("ReplicatedStorage/Shared/Art/TownMeshes")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local BlenderAssets = t.load("ReplicatedStorage/Shared/Art/BlenderAssets")

	-- Everything the server (SkyForgeService, AetherService, MapBuilder) or the
	-- client (ForgeUI) finds by name or attachment name, and the world anchors
	-- that make the 20-stud forge range and the prompts work.
	local COURT_HOSTS = {
		{ part = "Anvil", attachment = "TemperSpot" }, -- SkyForgeService.addSpot: the 20-stud range, the prompt
		{ part = "Floor", attachment = "KeeperSpot" }, -- the keeper's spot
		{ part = "RelicGem", attachment = "Socket_FrostRelic" }, -- ForgeUI.LightSockets
		{ part = "RelicGem", attachment = "Socket_EmberRelic" },
		{ part = "RelicGem", attachment = "Socket_GloamRelic" },
		{ part = "RelicGem", attachment = "Socket_LumenRelic" },
		{ part = "OrderBoard", gui = "OrderBoard" }, -- the order board's face GUI
		{ part = "FurnaceMouth", light = true }, -- the furnace light
		{ part = "Sign", gui = true }, -- the name board's text
	}

	local function withMeshes(fn, skip)
		MeshKit.Reset()
		TownMeshes.ResetFallbacks()
		MeshKit.Override = function(id, name, size)
			if skip and skip[id] then
				return nil
			end
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		MeshKit.Reset()
		TownMeshes.ResetFallbacks()
		if not ok then
			error(err, 0)
		end
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

	local function isMesh(part)
		return part:GetAttribute("VisualMesh") == true
	end

	local function named(model, name, wantMesh)
		for _, d in ipairs(parts(model)) do
			if d.Name == name and isMesh(d) == (wantMesh == true) then
				return d
			end
		end
		return nil
	end

	local function countClass(model, class, name)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d.ClassName == class and d.Name == name then
				n += 1
			end
		end
		return n
	end

	-- The part build's bounds, from the corners of every part.
	local function bounds(model)
		local lo, hi
		for _, p in ipairs(parts(model)) do
			local h = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local w = p.CFrame * roblox.Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
						lo = if lo
							then roblox.Vector3.new(math.min(lo.X, w.X), math.min(lo.Y, w.Y), math.min(lo.Z, w.Z))
							else w
						hi = if hi
							then roblox.Vector3.new(math.max(hi.X, w.X), math.max(hi.Y, w.Y), math.max(hi.Z, w.Z))
							else w
					end
				end
			end
		end
		return lo, hi
	end

	local function piece(id, name)
		return TownModels.Piece(TownModels.Get(id), name)
	end

	-- The brief: print the part build's bounds before deciding on a scale.
	t.test("the part builds are within a stud of their Body meshes, so no scale is passed", function()
		for _, row in ipairs({
			{ "SkyForgeCourt", BuildingArt.SkyForgeCourt },
			{ "StarfallForge", BuildingArt.StarfallForge },
		}) do
			MeshKit.Reset()
			local model = row[2]()
			local lo, hi = bounds(model)
			local size = hi - lo
			local body = piece(row[1], "Body").size
			print(
				string.format(
					"[T381] %s part build min (%.2f, %.2f, %.2f) max (%.2f, %.2f, %.2f) size %.2f x %.2f x %.2f; Body mesh %.2f x %.2f x %.2f",
					row[1],
					lo.X,
					lo.Y,
					lo.Z,
					hi.X,
					hi.Y,
					hi.Z,
					size.X,
					size.Y,
					size.Z,
					body.X,
					body.Y,
					body.Z
				)
			)
			t.ok(math.abs(size.X - body.X) <= 1, row[1] .. " width")
			t.ok(math.abs(size.Y - body.Y) <= 1, row[1] .. " height")
			t.ok(math.abs(size.Z - body.Z) <= 1, row[1] .. " depth")
		end
	end)

	t.test("both forges are wired, the registry row says so, and their collision pieces are preloaded", function()
		local wired = {}
		for _, id in ipairs(BacklogModels.Wired) do
			wired[id] = true
		end
		t.ok(wired.SkyForgeCourt, "SkyForgeCourt is in BacklogModels.Wired")
		t.ok(wired.StarfallForge, "StarfallForge is in BacklogModels.Wired")
		local row = BlenderAssets.Get("shops/SkyForgeCourt")
		t.eq(row.status, "wired")
		t.eq(row.wiredBy, "BuildingArt")
		t.eq(row.meshId, piece("SkyForgeCourt", "Body").meshId)
		local seen = {}
		for _, id in ipairs(BlenderAssets.MeshIds()) do
			seen[id] = true
		end
		t.ok(not seen[row.meshId], "the blender group leaves a wired row to the backlog group")
		local manifest = t.load("ReplicatedStorage/Shared/Art/MeshManifest")
		local hulls = {}
		for _, g in ipairs(manifest.Groups(true)) do
			if g.name == "backlog" then
				for _, entry in ipairs(g.entries) do
					if entry.hull then
						hulls[entry.id] = true
					end
				end
			end
		end
		t.ok(hulls[piece("SkyForgeCourt", "Collision").meshId], "the court's collision mesh is preloaded as a hull")
		t.ok(
			hulls[piece("StarfallForge", "Collision").meshId],
			"the isle forge's collision mesh is preloaded as a hull"
		)
	end)

	t.test("the court wears its meshes: one Body, one Sign, one Collision, nothing else visible", function()
		withMeshes(function()
			local court = BuildingArt.SkyForgeCourt()
			t.eq(court:GetAttribute("TownMesh"), "SkyForgeCourt")
			t.eq(court:GetAttribute("MeshFallback"), nil)
			t.eq(countClass(court, "MeshPart", "Body"), 1)
			t.eq(countClass(court, "MeshPart", "Sign"), 1)
			t.eq(countClass(court, "MeshPart", "Collision"), 1)
			local rows = {}
			for _, p in ipairs(TownModels.Visual(TownModels.Get("SkyForgeCourt"))) do
				rows[p.name] = true
			end
			local exempt = {}
			for _, h in ipairs(COURT_HOSTS) do
				exempt[h.part] = true
			end
			for _, p in ipairs(parts(court)) do
				if p.Transparency < 1 then
					if isMesh(p) then
						t.ok(p.ClassName == "MeshPart" and rows[p.Name], p.Name .. " is a row MeshPart")
					else
						t.ok(exempt[p.Name], p.Name .. " is visible but is not an exempt host")
					end
				end
			end
			for _, gone in ipairs({
				"Wall",
				"WallCap",
				"Furnace",
				"FurnaceBand",
				"FurnacePost",
				"Chimney",
				"ChimneyBand",
				"ChimneyCap",
				"Stump",
				"Altar",
				"Trough",
			}) do
				t.eq(named(court, gone), nil, gone .. " is gone")
			end
			t.eq(MeshKit.Stats().failed, 0)
		end)
	end)

	t.test("the court has no extra Neon, no sparkles, and walks on the Collision piece alone", function()
		withMeshes(function()
			local court = BuildingArt.SkyForgeCourt()
			for _, p in ipairs(parts(court)) do
				if p.Material == roblox.Enum.Material.Neon and p.Transparency < 1 then
					t.eq(p.Name, "Glow", "the only visible Neon is the Glow mesh")
				end
			end
			for _, d in ipairs(court:GetDescendants()) do
				t.ok(not d:IsA("ParticleEmitter"), "no sparkles over the Smokestack")
			end
			local collider = named(court, "Collision", true)
			t.eq(collider, nil, "the collider is not a looks piece")
			for _, p in ipairs(parts(court)) do
				if p.Name == "Collision" then
					t.eq(p.CanCollide, true)
					t.eq(p.Anchored, true)
					t.eq(p.Transparency, 1)
					t.eq(p.CollisionFidelity, roblox.Enum.CollisionFidelity.Hull)
					t.ok(
						math.abs(p.Size.X - 30) < 0.01
							and math.abs(p.Size.Y - 8.8) < 0.01
							and math.abs(p.Size.Z - 24) < 0.01
					)
				else
					t.eq(p.CanCollide, false, p.Name .. " does not collide")
				end
			end
		end)
	end)

	t.test("every host the server and client look up survives where it was", function()
		MeshKit.Reset()
		local before = BuildingArt.SkyForgeCourt()
		local want = {}
		for _, h in ipairs(COURT_HOSTS) do
			local p
			for _, d in ipairs(parts(before)) do
				if d.Name == h.part and (not h.attachment or d:FindFirstChild(h.attachment)) then
					p = d
					break
				end
			end
			t.ok(p ~= nil, h.part .. " exists in the part build")
			want[h] = p.CFrame
		end
		withMeshes(function()
			local after = BuildingArt.SkyForgeCourt()
			t.eq(after:GetAttribute("TownMesh"), "SkyForgeCourt", "dressed")
			-- Hosts named twice (the four gems) are matched by attachment.
			local function host(h)
				for _, p in ipairs(parts(after)) do
					if p.Name == h.part and not isMesh(p) then
						if not h.attachment or p:FindFirstChild(h.attachment) then
							return p
						end
					end
				end
				return nil
			end
			for _, h in ipairs(COURT_HOSTS) do
				local p = host(h)
				t.ok(p ~= nil, h.part .. (h.attachment and (" " .. h.attachment) or "") .. " survives")
				if p then
					local was = want[h]
					t.ok((p.CFrame.Position - was.Position).Magnitude <= 0.05, h.part .. " has not moved")
					t.ok((p.CFrame.LookVector - was.LookVector).Magnitude <= 0.05, h.part .. " has not turned")
					if h.attachment then
						t.ok(p:FindFirstChild(h.attachment) ~= nil, h.attachment)
					end
					if h.gui then
						t.ok(p:FindFirstChildWhichIsA("SurfaceGui", true) ~= nil, h.part .. " keeps its face GUI")
					end
					if h.light then
						t.ok(p:FindFirstChildWhichIsA("PointLight", true) ~= nil, h.part .. " keeps its light")
					end
				end
			end
			-- All four sockets, by the exact names the client lights.
			local sockets = 0
			for _, d in ipairs(after:GetDescendants()) do
				if d:IsA("Attachment") and string.sub(d.Name, 1, 7) == "Socket_" then
					sockets += 1
				end
			end
			t.eq(sockets, 4)
		end)
	end)

	t.test("the isle forge keeps its tagged anvil top, hearth fire and lights, and gets its collider", function()
		MeshKit.Reset()
		local before = BuildingArt.StarfallForge()
		local anvilBefore = named(before, "StarfallForge")
		t.ok(anvilBefore ~= nil)
		local coalsBefore = named(before, "ForgeCoals")
		withMeshes(function()
			local forge = BuildingArt.StarfallForge()
			t.eq(forge:GetAttribute("TownMesh"), "StarfallForge")
			local anvil = named(forge, "StarfallForge")
			t.ok(anvil ~= nil, "the anvil's top is still there (a host, not the mesh of the same name)")
			t.ok((anvil.CFrame.Position - anvilBefore.CFrame.Position).Magnitude <= 0.05)
			t.ok(anvil:FindFirstChildOfClass("PointLight") ~= nil, "the anvil still glows")
			t.ok(anvil:FindFirstChildOfClass("ParticleEmitter") ~= nil, "and sparkles")
			t.ok(named(forge, "StarfallForge", true) ~= nil, "the anvil mesh is dressed beside it")
			local coals = named(forge, "ForgeCoals")
			t.ok(coals ~= nil and coals:FindFirstChildOfClass("Fire") ~= nil, "the coals keep their fire")
			t.ok((coals.CFrame.Position - coalsBefore.CFrame.Position).Magnitude <= 0.05)
			t.eq(countClass(forge, "MeshPart", "Body"), 1)
			t.eq(countClass(forge, "MeshPart", "Collision"), 1)
			for _, p in ipairs(parts(forge)) do
				if p.Name ~= "Collision" then
					t.eq(p.CanCollide, false, p.Name)
				end
				if p.Transparency < 1 then
					t.ok(
						isMesh(p) or p.Name == "StarfallForge" and false,
						p.Name .. " is a visible part inside the Body mesh"
					)
				end
			end
		end)
	end)

	t.test("one mesh missing (the collision piece too) keeps the whole part build", function()
		for _, case in ipairs({
			{ "SkyForgeCourt", BuildingArt.SkyForgeCourt, "Collision" },
			{ "SkyForgeCourt", BuildingArt.SkyForgeCourt, "Body" },
			{ "StarfallForge", BuildingArt.StarfallForge, "Collision" },
		}) do
			local skip = {}
			skip[piece(case[1], case[3]).meshId] = true
			withMeshes(function()
				local model = case[2]()
				t.eq(model:GetAttribute("TownMesh"), nil, case[1] .. " without " .. case[3])
				t.eq(model:GetAttribute("MeshFallback"), case[1])
				for _, p in ipairs(parts(model)) do
					t.ok(not isMesh(p) and p.Name ~= "Collision", p.Name .. " is part build")
				end
				t.ok(
					named(model, if case[1] == "SkyForgeCourt" then "Wall" else "ForgeWall") ~= nil,
					"walls still stand"
				)
				t.ok(
					named(model, if case[1] == "SkyForgeCourt" then "Floor" else "ForgeHearth").CanCollide,
					"and still collide"
				)
			end, skip)
		end
	end)

	-- The sweep: a builder that names a backlog asset must dress it, and what
	-- it dresses must be in Wired (MeshManifest preloads only those).
	t.test("every backlog id a builder uses has a Dress call and is wired", function()
		local src = fs.readFile("src/ReplicatedStorage/Shared/Art/BuildingArt.luau")
		local wired = {}
		for _, id in ipairs(BacklogModels.Wired) do
			wired[id] = true
		end
		-- Part builds of backlog assets with no dressing yet: waiting on a design
		-- call, not forgotten (see BacklogModels.Wired's note).
		local WAITING = { SkyMarket = true, SkyTurnstile = true, PlotMapBoard = true }
		local checked = 0
		for id in string.gmatch(src, 'Kit%.model%("([%w]+)"%)') do
			if BacklogModels.Get(id) ~= nil and not WAITING[id] then
				checked += 1
				t.ok(
					string.find(src, 'TownMeshes.Dress(model, "' .. id .. '"', 1, true) ~= nil,
					id .. " has a Dress call"
				)
				t.ok(wired[id], id .. " is in BacklogModels.Wired")
			end
		end
		t.ok(checked >= 6, "the sweep sees the builders (" .. checked .. ")")
		for id in string.gmatch(src, 'TownMeshes%.Dress%(model, "([%w]+)"') do
			if BacklogModels.Get(id) ~= nil then
				t.ok(wired[id], id .. " is dressed but not preloaded")
			end
		end
		-- The isle forge's model is not named after its asset.
		t.ok(string.find(src, 'TownMeshes.Dress(model, "StarfallForge"', 1, true) ~= nil, "StarfallForge is dressed")
	end)
end
