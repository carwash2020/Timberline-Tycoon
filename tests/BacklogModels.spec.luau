--!nocheck
-- Job 17: the Blender backlog (BacklogModels) wired through MeshKit. Every
-- row has pieces and real ids, every id has a MeshTemplates file, the
-- wired builders swap in meshes when they load and keep their part build
-- when they do not, and nothing asks MeshKit for an id it cannot find.
return function(t)
	local fs = require("@lune/fs")
	local roblox = t.roblox
	local Vector3, Color3 = roblox.Vector3, roblox.Color3
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local BacklogModels = t.load("ReplicatedStorage/Shared/Art/BacklogModels")
	local TownModels = t.load("ReplicatedStorage/Shared/Art/TownModels")
	local TownMeshes = t.load("ReplicatedStorage/Shared/Art/TownMeshes")
	local BuildingArt = t.load("ReplicatedStorage/Shared/Art/BuildingArt")
	local RobuxBoxArt = t.load("ReplicatedStorage/Shared/Art/RobuxBoxArt")
	local TreeModels = t.load("ReplicatedStorage/Shared/Art/TreeModels")
	local BoxSize = t.shared("BoxSize")
	local RobuxShelf = t.shared("RobuxShelf")

	local TEMPLATES = "src/ReplicatedStorage/MeshTemplates/"

	local function hasTemplate(id)
		local path = TEMPLATES .. tostring(id) .. ".model.json"
		if not fs.isFile(path) then
			return false
		end
		return string.find(fs.readFile(path), "rbxassetid://" .. tostring(id), 1, true) ~= nil
	end

	local function withMeshes(fn)
		MeshKit.Reset()
		TownMeshes.ResetFallbacks()
		MeshKit.Override = function(_id, name, size)
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

	local function meshes(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("VisualMesh") == true then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("every row has pieces, real ids, one id per piece name and a known category", function()
		local categories = {
			shop = true,
			gear = true,
			landmark = true,
			npc = true,
			furniture = true,
			plant = true,
			cave = true,
			critter = true,
			polish = true,
			environment = true,
		}
		local seenAsset, count = {}, 0
		for _, asset in ipairs(BacklogModels.All) do
			count += 1
			t.ok(not seenAsset[asset.id], asset.id .. " listed twice")
			seenAsset[asset.id] = true
			t.ok(categories[asset.category], asset.id .. " category " .. tostring(asset.category))
			t.ok(#asset.pieces >= 1, asset.id .. " has a piece")
			t.ok(asset.modelId > 0, asset.id .. " model id")
			local seenId, seenName = {}, {}
			for _, piece in ipairs(asset.pieces) do
				t.ok(piece.meshId > 0, asset.id .. "." .. piece.name .. " is not 0")
				t.ok(not seenId[piece.meshId], asset.id .. " repeats mesh " .. piece.meshId)
				t.ok(not seenName[piece.name], asset.id .. " repeats piece " .. piece.name)
				seenId[piece.meshId] = true
				seenName[piece.name] = true
				t.ok(
					piece.size.X > 0 and piece.size.Y > 0 and piece.size.Z > 0,
					asset.id .. "." .. piece.name .. " size"
				)
				t.ok(piece.meshId ~= asset.modelId, asset.id .. " never uses the Model id as a MeshId")
			end
			t.ok(#BacklogModels.Ids() == #BacklogModels.All)
		end
		t.eq(count, 109, "every uploaded backlog asset (112 less the three trees)")
	end)

	t.test("the held-back five are not here, and no id clashes with a TownModels row", function()
		for _, held in ipairs({ "Roots", "LavaRock", "Pumpkin", "PumpkinPatch", "PumpkinHat" }) do
			t.eq(BacklogModels.Get(held), nil, held .. " stays part-built")
		end
		local own = {}
		for _, asset in ipairs(TownModels.All) do
			own[asset.id] = true
		end
		for _, asset in ipairs(BacklogModels.All) do
			t.ok(not own[asset.id], asset.id .. " clashes with a TownModels row")
		end
		for _, renamed in ipairs({ "GearLantern", "PlantBush", "StoreBoardV1", "SawdustPileV2", "PathRoundV2" }) do
			t.ok(BacklogModels.Get(renamed) ~= nil, renamed)
		end
	end)

	t.test("every mesh id has a MeshTemplates file that names it", function()
		local missing = {}
		for _, asset in ipairs(BacklogModels.All) do
			for _, piece in ipairs(asset.pieces) do
				if not hasTemplate(piece.meshId) then
					table.insert(missing, asset.id .. "." .. piece.name .. " " .. piece.meshId)
				end
			end
		end
		for _, wood in ipairs({ "lanternwood", "bogcypress", "ironwood" }) do
			for sid = 1, 3 do
				local id = TreeModels.SectionMesh(wood, sid)
				if not hasTemplate(id) then
					table.insert(missing, wood .. " section " .. id)
				end
			end
			for _, piece in ipairs(TreeModels.Crown(wood)) do
				if not hasTemplate(piece.meshId) then
					table.insert(missing, wood .. " " .. piece.name .. " " .. piece.meshId)
				end
			end
		end
		t.eq(#missing, 0, "no template for: " .. table.concat(missing, ", "))
	end)

	t.test("TownModels falls through to the backlog, except the townsfolk", function()
		t.eq(TownModels.Get("OddsAndEnds"), BacklogModels.Get("OddsAndEnds"))
		t.eq(TownModels.Get("RobuxBox").category, "shop")
		t.ok(TownModels.Get("Sawmill") ~= nil, "its own rows still win")
		t.eq(TownModels.Get("Lantern").category, "environment", "the env lantern is not the held one")
		t.eq(TownModels.Get("GearLantern").category, "gear")
		t.eq(TownModels.Get("StoreBoard").category, "environment", "the old board stays until approved")
		t.eq(BacklogModels.Get("Hermit").category, "npc")
		t.eq(TownModels.Get("Hermit"), nil, "NPCs belong to the NPC lane")
		t.eq(TownModels.Get("NoSuchThing"), nil)
	end)

	t.test("the wired assets are all rows, and the backlog manifest group lists their visible pieces", function()
		local MeshManifest = t.load("ReplicatedStorage/Shared/Art/MeshManifest")
		local group
		for _, g in ipairs(MeshManifest.Groups(true)) do
			if g.name == "backlog" then
				group = g
			end
		end
		t.ok(group ~= nil, "MeshManifest has a backlog group")
		local want = {}
		for _, id in ipairs(BacklogModels.Wired) do
			t.ok(BacklogModels.Get(id) ~= nil, id)
			for _, piece in ipairs(BacklogModels.Get(id).pieces) do
				if piece.name ~= "Collision" then
					want[piece.meshId] = true
				end
			end
		end
		local got = {}
		for _, entry in ipairs(group.entries) do
			got[entry.id] = true
			t.ok(hasTemplate(entry.id), entry.id .. " has a template")
		end
		for id in pairs(want) do
			t.ok(got[id], tostring(id) .. " is preloaded")
		end
		for id in pairs(got) do
			t.ok(want[id], tostring(id) .. " is a wired piece")
		end
	end)

	local SHOPS = {
		OddsAndEnds = function()
			return BuildingArt.OddsAndEnds()
		end,
		Sparkworks = function()
			return BuildingArt.Sparkworks()
		end,
		LandOffice = function()
			return BuildingArt.LandOffice()
		end,
		GateKiosk = function()
			return BuildingArt.GateKiosk(Color3.fromRGB(10, 200, 90))
		end,
		ArrivalArch = function()
			return BuildingArt.ArrivalArch()
		end,
	}

	t.test("with no mesh loaded each shop keeps its part build and says so once", function()
		MeshKit.Reset()
		TownMeshes.ResetFallbacks()
		for name, build in pairs(SHOPS) do
			local model = build()
			t.eq(#meshes(model), 0, name .. " has no meshes")
			t.ok(#model:GetDescendants() > 3, name .. " keeps its parts")
			t.eq(model:GetAttribute("MeshFallback"), name, name .. " MeshFallback")
			t.eq(model:GetAttribute("TownMesh"), nil, name)
			t.eq(TownMeshes.FellBack(name), true, name)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					t.ok(d.Transparency < 1 or not d.CanCollide or d.Name ~= "Sign", name .. " " .. d.Name)
				end
			end
		end
		TownMeshes.ResetFallbacks()
	end)

	t.test("with the meshes loaded each shop wears them, signs and counters kept, no mesh missing", function()
		withMeshes(function()
			for name, build in pairs(SHOPS) do
				local model = build()
				t.eq(model:GetAttribute("TownMesh"), name, name .. " dressed")
				t.eq(model:GetAttribute("MeshFallback"), nil, name)
				local asset = BacklogModels.Get(name)
				local made = {}
				for _, part in ipairs(meshes(model)) do
					made[part.Name] = true
					t.eq(part.CanCollide, false, name .. "." .. part.Name .. " is looks-only")
					t.eq(part.Anchored, true, name .. "." .. part.Name)
				end
				for _, piece in ipairs(TownModels.Visual(asset)) do
					t.ok(made[piece.name], name .. " shows " .. piece.name)
				end
				t.ok(not made.Collision, name .. " never draws its collision shell")
				if name == "OddsAndEnds" or name == "LandOffice" then
					local host
					for _, d in ipairs(model:GetDescendants()) do
						if d.Name == "Sign" and d:IsA("BasePart") and d:GetAttribute("VisualMesh") ~= true then
							host = d
						end
					end
					t.ok(host ~= nil, name .. " keeps the Sign that carries its text")
					t.ok(host:FindFirstChildWhichIsA("SurfaceGui", true) ~= nil, name .. " sign text kept")
				end
			end
			t.eq(MeshKit.Stats().failed, 0, "no mesh asked for and not found")
			t.eq(#MeshKit.Stats().failedIds, 0)
		end)
	end)

	t.test("a gate kiosk's glow keeps the gate's own colour", function()
		withMeshes(function()
			local accent = Color3.fromRGB(10, 200, 90)
			local model = BuildingArt.GateKiosk(accent)
			local found = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Name == "Glow" and d:GetAttribute("VisualMesh") == true then
					found += 1
					t.eq(d.Color, accent)
					t.eq(d.Material, roblox.Enum.Material.Neon)
				end
			end
			t.eq(found, 1)
		end)
	end)

	local function crate()
		local model = roblox.Instance.new("Model")
		local body = roblox.Instance.new("Part")
		body.Name = "Box"
		body.Size = BoxSize.Class(RobuxShelf.Class).size
		body.CFrame = roblox.CFrame.new(0, body.Size.Y / 2, 0)
		body.Parent = model
		local added = RobuxBoxArt.Dress(model, body, { name = "Large Cash Pack", key = "Cash10k" })
		return model, body, added
	end

	t.test("a Robux crate wears the mesh: body, window and badge, the name on the window", function()
		withMeshes(function()
			local model, body, added = crate()
			t.eq(#added, 3)
			t.eq(body.Transparency, 1)
			local names = {}
			for _, p in ipairs(added) do
				names[p.Name] = p
				t.eq(p:GetAttribute("VisualMesh"), true, p.Name)
				t.eq(p.CanCollide, false, p.Name)
				t.eq(p.Massless, true, p.Name)
				local weld = p:FindFirstChildWhichIsA("WeldConstraint")
				t.eq(weld.Part0, body, p.Name .. " rides the box")
				local half = body.Size / 2
				local c = p.CFrame.Position - body.CFrame.Position
				t.ok(math.abs(c.X) <= half.X + 0.05, p.Name .. " inside in x")
				t.ok(math.abs(c.Z) <= half.Z + 0.05, p.Name .. " inside in z")
				t.ok(c.Y - p.Size.Y / 2 >= -half.Y - 0.05, p.Name .. " not under the box")
				-- the crate's latch stands a little over its collision box (2.67 against 2.5)
				t.ok(c.Y + p.Size.Y / 2 <= half.Y + 0.2, p.Name .. " not over the box")
			end
			t.ok(names.Body and names.Glow and names.Badge, "three pieces")
			t.eq(names.Glow:FindFirstChild("Name", true).Text, "Large Cash Pack")
			t.eq(model:FindFirstChild("Contents"), nil, "the coins are in the mesh")
			t.eq(model:FindFirstChild("Tag"), nil)
			t.eq(MeshKit.Stats().failed, 0)
		end)
	end)

	t.test("a Robux crate with no mesh is the part-built open crate again", function()
		MeshKit.Reset()
		local model, body, added = crate()
		t.eq(#added, RobuxBoxArt.ShellParts + RobuxBoxArt.CoinParts)
		t.eq(model:FindFirstChild("Tag"):FindFirstChild("Name", true).Text, "Large Cash Pack")
		t.eq(body.Transparency, 1)
	end)

	t.test("the new woods have crowns and three sections, Bog Cypress has knees", function()
		for _, wood in ipairs({ "lanternwood", "bogcypress", "ironwood" }) do
			t.ok(#TreeModels.Crown(wood) >= 6, wood .. " crown")
			for sid = 1, 3 do
				t.ok(TreeModels.SectionMesh(wood, sid) ~= 0, wood .. " section " .. sid)
			end
		end
		local knees = 0
		for _, piece in ipairs(TreeModels.Crown("bogcypress")) do
			if piece.name == "Knees" then
				knees += 1
			end
		end
		t.eq(knees, 1)
	end)
end
