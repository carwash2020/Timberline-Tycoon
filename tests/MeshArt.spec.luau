--!nocheck
-- Uploaded meshes (ticket E) and the Lux swing numbers (ticket F).
-- Lune cannot load the meshes, so the default art stays part-built.
-- These tests inject MeshKit.Override and check the mesh path, then
-- clear it. QA: E1–E4 are the economy guard in tools/economy.luau.
-- C10–C12 cargo/section budgets. V1–V10 vehicles. X1–X2 axes. P5–P6 Lux and plots.
return function(t)
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local AxeArt = t.load("ReplicatedStorage/Shared/Art/AxeArt")
	local AxeModels = t.load("ReplicatedStorage/Shared/Art/AxeModels")
	local TreeArt = t.load("ReplicatedStorage/Shared/Art/TreeArt")
	local TreeModels = t.load("ReplicatedStorage/Shared/Art/TreeModels")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local VehicleMeshes = t.load("ReplicatedStorage/Shared/Art/VehicleMeshes")
	local VehicleModels = t.load("ReplicatedStorage/Shared/Art/VehicleModels")
	local LuxEffect = t.shared("LuxEffect")
	local ItemCatalog = t.shared("ItemCatalog")
	local WoodData = t.shared("WoodData")
	local TreeGen = t.shared("TreeGen")
	local SellLogic = t.shared("SellLogic")
	local GameConfig = t.shared("GameConfig")
	local TruckLayout = t.shared("TruckLayout")
	local roblox = t.roblox
	local Instance, Vector3 = roblox.Instance, roblox.Vector3

	local function parts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	local function gameplay(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and MeshKit.Counts(d) then
				n += 1
			end
		end
		return n
	end

	local function withMeshes(fn)
		MeshKit.Reset()
		MeshKit.Override = function(id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	t.test("X2: a mesh id of 0 keeps the current axe", function()
		t.eq(AxeModels.UsesMesh(0), false)
		t.eq(AxeModels.UsesMesh(125228989315064), true)
		local spec = AxeModels.Get("RustyAxe")
		local saved = spec.Handle.meshId
		spec.Handle.meshId = 0
		withMeshes(function()
			local model = AxeArt.Build(ItemCatalog.GetAxe("RustyAxe"))
			t.eq(model:FindFirstChild("MeshHandle", true), nil)
			t.ok(model:FindFirstChild("Knob", true), "the part-built head stays")
			t.eq(model.PrimaryPart.Name, "Handle")
		end)
		spec.Handle.meshId = saved
	end)

	t.test("X1: meshes are visual, and the Handle size and grip stay put", function()
		local grips = {}
		local sizes = {}
		local axes = {}
		for _, def in pairs(ItemCatalog.Axes) do
			table.insert(axes, def)
		end
		table.sort(axes, function(a, b)
			return a.id < b.id
		end)
		for _, def in ipairs(axes) do
			local plain = AxeArt.Build(def)
			sizes[def.id] = plain.PrimaryPart.Size
			grips[def.id] = AxeArt.Grip(def)
			t.eq(plain:FindFirstChild("MeshHandle", true), nil, def.id .. " stays part-built without a mesh")
		end
		withMeshes(function()
			for _, def in ipairs(axes) do
				local model = AxeArt.Build(def)
				local handle = model.PrimaryPart
				t.eq(handle.Name, "Handle")
				t.eq(handle.Size, sizes[def.id], def.id .. " Handle size")
				t.eq(AxeArt.Grip(def), grips[def.id], def.id .. " grip")
				local meshHandle = model:FindFirstChild("MeshHandle", true)
				local meshHead = model:FindFirstChild("MeshHead", true)
				t.ok(meshHandle and meshHead, def.id .. " handle and head meshes")
				t.eq(model:FindFirstChild("Knob", true), nil, def.id .. " drops the part-built decor")
				t.eq(model:FindFirstChild("MeshTrail", true), nil, "the trail guide is not spawned")
				for _, part in ipairs(parts(model)) do
					if part ~= handle then
						t.eq(part:GetAttribute("VisualMesh"), true, def.id .. " " .. part.Name)
						t.eq(part.CanCollide, false)
						t.eq(part.CanTouch, false)
						t.eq(part.CanQuery, false)
						t.eq(part.Massless, true)
						local weld = part:FindFirstChild("Weld")
						t.ok(weld and weld.Part0 == handle and weld.Part1 == part, def.id .. " weld")
					end
				end
				local spec = AxeModels.Get(def.id)
				t.ok(meshHandle.Size.Y >= 3.6 and meshHandle.Size.Y <= 4.06, def.id .. " visual haft length")
				t.ok((meshHandle.Size - spec.Handle.size).Magnitude < 1e-3, def.id .. " visual size")
			end
		end)
	end)

	t.test("X1: a mesh that fails to load keeps the current axe", function()
		MeshKit.Override = function()
			return nil
		end
		local model = AxeArt.Build(ItemCatalog.GetAxe("SteelAxe"))
		MeshKit.Override = nil
		t.ok(model:FindFirstChild("Knob", true))
		t.eq(model:FindFirstChild("MeshHandle", true), nil)
	end)

	t.test("X1: Lux attachments sit on the Handle, offset from the Blender foot", function()
		local def = ItemCatalog.GetAxe("LuxAxe")
		local model = AxeArt.Build(def)
		local handle = model.PrimaryPart
		local len = handle.Size.Y
		t.eq(len, 3.5, "the gameplay haft, not the 4.053 visual one")
		for name, foot in pairs(AxeModels.LuxPoints) do
			local attachment = handle:FindFirstChild(name)
			t.ok(attachment and attachment:IsA("Attachment"), name)
			local want = foot - Vector3.new(0, len / 2, 0)
			t.ok((attachment.CFrame.Position - want).Magnitude < 1e-4, name)
		end
		withMeshes(function()
			local meshed = AxeArt.Build(def)
			t.eq(meshed.PrimaryPart.Size.Y, len)
			t.ok(meshed.PrimaryPart:FindFirstChild("LuxBurst"))
			t.eq(meshed:FindFirstChild("MeshGlow", true) ~= nil, true)
			-- The trail mesh id is stored and never spawned.
			local trailId = tostring(AxeModels.Get("LuxAxe").Trail.meshId)
			for _, part in ipairs(parts(meshed)) do
				t.eq(part:GetAttribute("MeshId") == trailId, false)
			end
		end)
	end)

	t.test("C12: one cut section still counts as one, and crown meshes are not queried", function()
		local def = WoodData.Get("oak")
		local skel = TreeGen.Skeleton("oak", 3, 1)
		local plain = TreeArt.FromSkeleton(def, skel)
		t.eq(plain:GetAttribute("TreeMesh"), nil, "Lune keeps the part-built tree")
		t.eq(#parts(plain), TreeGen.PartCount(skel))
		withMeshes(function()
			local only = { [skel.sections[1].id] = true }
			local one = TreeArt.FromSkeleton(def, skel, { only = only })
			t.eq(gameplay(one), 1, "the section mesh replaces the block")
			local sections = 0
			for _, part in ipairs(parts(one)) do
				if part.Name == "Section" then
					sections += 1
					local want =
						Vector3.new(skel.sections[1].thickness, skel.sections[1].length, skel.sections[1].thickness)
					t.ok((part.Size - want).Magnitude < 1e-3, "section mesh keeps the block's size")
					t.eq(part.CanCollide, true)
					t.eq(part.CanQuery, true)
					t.ok(part:HasTag("WoodSection"))
				else
					t.eq(part:GetAttribute("VisualMesh"), true)
					t.eq(part.CanQuery, false)
					t.eq(part.CanCollide, false)
					t.eq(part.CanTouch, false)
					t.eq(part.Massless, true)
				end
			end
			t.eq(sections, 1)
			local full = TreeArt.FromSkeleton(def, skel)
			local sectionCount = 0
			local visuals = 0
			for _, part in ipairs(parts(full)) do
				if part.Name == "Section" then
					sectionCount += 1
				elseif part:GetAttribute("VisualMesh") == true then
					visuals += 1
				end
			end
			t.eq(sectionCount, #skel.sections)
			t.eq(gameplay(full), #skel.sections, "crown meshes do not add to the wood budget")
			t.ok(visuals <= 7, "oak crown is a handful of meshes, got " .. visuals)
			t.eq(visuals, #TreeModels.Crown("oak"))
		end)
	end)

	t.test("V1-V10: mesh trucks keep the hull, wheels and bed size, inside the part caps", function()
		local plainBed = {}
		for _, def in ipairs(ItemCatalog.TruckList()) do
			local model = TruckArt.Build(def)
			local floor = model:FindFirstChild("BedFloor")
			plainBed[def.id] = if floor then floor.Size else nil
			t.eq(model:GetAttribute("VehicleMesh"), nil, def.id .. " stays part-built in Lune")
		end
		withMeshes(function()
			for _, def in ipairs(ItemCatalog.TruckList()) do
				local layout = TruckLayout.For(def)
				local model = TruckArt.Build(def)
				if VehicleModels.Truck(def.id) == nil then
					t.eq(model:GetAttribute("VehicleMesh"), nil, def.id .. " has no uploaded mesh")
					if def.classic == true then
						t.ok(model:FindFirstChild("LoadGauge", true), "the Classic gauge stays")
						t.ok(model:FindFirstChild("DoorPlate", true), "the Classic door plate stays")
					end
					continue
				end
				t.eq(model:GetAttribute("VehicleMesh"), true, def.id)
				t.eq(model.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic)
				t.ok(model:FindFirstChild("Chassis", true))
				t.ok(model:FindFirstChild("Skid", true))
				t.ok(model:FindFirstChild("DriverSeat", true))
				t.ok(model:FindFirstChild("MeshBody", true))
				t.eq(model:FindFirstChild("MeshTrail", true), nil)
				local floor = model:FindFirstChild("BedFloor")
				if def.bedCapacity > 0 then
					t.ok(floor and floor.Size == plainBed[def.id], def.id .. " bed size")
				else
					t.eq(floor, nil, "Scout keeps having no bed")
					t.eq(model:FindFirstChild("MeshBed", true), nil, "V9: Scout has no bed mesh")
				end
				local wheels = 0
				for _, part in ipairs(parts(model)) do
					if part.Name == "Wheel" and part:GetAttribute("Radius") ~= nil then
						wheels += 1
						t.eq(part:GetAttribute("MeshId"), tostring(VehicleModels.Truck(def.id).Wheel.meshId))
					end
					if part:GetAttribute("VisualMesh") == true then
						t.eq(part.CanQuery, false, part.Name)
						t.eq(part.CanCollide, false)
						t.eq(part.Massless, true)
					end
				end
				t.eq(wheels, #layout.wheelZ * 2, def.id .. " tyres")
				local truckParts = VehicleMeshes.Counts(model)
				t.ok(truckParts <= VehicleMeshes.PartCap(def.id), string.format("%s has %d parts", def.id, truckParts))
			end
			-- C10, C11: Flatbed and Logging Rig stay at or under 80 parts.
			for _, id in ipairs({ "Flatbed", "LoggingRig" }) do
				local model = TruckArt.Build(ItemCatalog.GetTruck(id))
				local n = VehicleMeshes.Counts(model)
				t.ok(n <= 80, string.format("C10/C11 %s mesh parts %d", id, n))
				t.eq(VehicleMeshes.PartCap(id), 80)
			end
			-- A trailer on each tow truck. Hitch size follows the truck.
			-- The colliding hull plus four look meshes lands above the
			-- 15-part wish. Ranch (stakes and rails) is the heaviest, at 25.
			for _, trailer in ipairs(ItemCatalog.TrailerList()) do
				for _, def in ipairs(ItemCatalog.TruckList()) do
					if def.bedCapacity == 0 or VehicleModels.Truck(def.id) == nil then
						continue
					end
					local model = TruckArt.Build(def, nil, trailer)
					local truckParts, trailerParts = VehicleMeshes.Counts(model)
					t.ok(
						truckParts <= VehicleMeshes.PartCap(def.id),
						string.format("%s+%s truck parts %d", def.id, trailer.id, truckParts)
					)
					t.ok(
						trailerParts <= VehicleMeshes.TrailerCap,
						string.format("%s+%s trailer parts %d", def.id, trailer.id, trailerParts)
					)
					t.ok(model:FindFirstChild("TrailerBed", true))
					t.ok(model:FindFirstChild("TrailerSkid", true))
					local hitch = nil
					for _, part in ipairs(parts(model)) do
						if part.Name == "MeshHitch" and part:GetAttribute("RigHalf") == "trailer" then
							hitch = part
						end
					end
					t.ok(hitch, def.id .. " trailer hitch mesh")
					local want = VehicleModels.Trailer(trailer.id, def.id).Hitch.size
					t.ok((hitch.Size - want).Magnitude < 1e-3, def.id .. " hitch size")
				end
			end
		end)
	end)

	t.test("V10: one failed vehicle mesh keeps the part-built truck", function()
		MeshKit.Reset()
		MeshKit.Override = function(id)
			if id == VehicleModels.Truck("Pickup").Glass.meshId then
				return nil
			end
			local part = Instance.new("MeshPart")
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
		local model = TruckArt.Build(ItemCatalog.GetTruck("Pickup"))
		MeshKit.Override = nil
		MeshKit.Reset()
		t.eq(model:GetAttribute("VehicleMesh"), nil)
		t.eq(model:FindFirstChild("MeshBody", true), nil)
		t.ok(model:FindFirstChild("BedFloor", true))
	end)

	t.test("P5: Lux stats and the 10% sell bonus do not move when the effect is on or off", function()
		local lux = ItemCatalog.GetAxe("LuxAxe")
		t.eq(lux.v2.damage, 5.5)
		t.eq(lux.v2.range, 15)
		t.eq(lux.v2.cooldown, 0.42)
		t.eq(GameConfig.LuxSellBonus, 1.1)
		local off = SellLogic.PieceValue("oak", "log", 10, nil, 1, false)
		local on = SellLogic.PieceValue("oak", "log", 10, nil, 1, true)
		t.eq(on, off * GameConfig.LuxSellBonus)
		t.eq(LuxEffect.Gold, roblox.Color3.fromRGB(232, 197, 71))
		t.eq(LuxEffect.TrailLifetime("high"), 0.25)
		t.eq(LuxEffect.TrailLifetime("medium"), 0.25)
		t.ok(LuxEffect.TrailLifetime("low") < 0.25)
		t.eq(LuxEffect.BurstCount("high"), 12)
		t.eq(LuxEffect.BurstCount("low"), 4)
		t.eq(LuxEffect.SparkleRate("high"), 6)
		t.eq(LuxEffect.SparkleRate("low"), 0)
		t.eq(LuxEffect.SparkleDue("low", 10, true), false)
		t.eq(LuxEffect.SparkleDue("high", 1, false), false, "a skipped cosmetic frame emits nothing")
		t.eq(LuxEffect.SparkleDue("high", 1 / 6, true), true)
		-- The effect module builds no light. The client file must not add one either.
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/LuxFX.luau")
		t.eq(string.find(source, "PointLight", 1, true), nil)
		t.ok(string.find(source, "Pass_LuxAxe", 1, true))
		t.eq(string.find(source, "MarketplaceService", 1, true), nil)
	end)

	t.test("one mesh id is loaded once and then cloned", function()
		MeshKit.Reset()
		local calls = 0
		MeshKit.Override = function(id)
			calls += 1
			local part = Instance.new("MeshPart")
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
		local a = MeshKit.Create(99, "One", Vector3.new(1, 2, 3))
		local b = MeshKit.Create(99, "Two", Vector3.new(4, 5, 6))
		MeshKit.Override = nil
		MeshKit.Reset()
		t.eq(calls, 1)
		t.ok(a ~= b, "each use is its own part")
		t.eq(a.Name, "One")
		t.eq(b.Name, "Two")
		t.eq(a:GetAttribute("MeshId"), "99")
		t.eq(b:GetAttribute("MeshId"), "99")
		t.ok((a.Size - Vector3.new(1, 2, 3)).Magnitude < 1e-3)
		t.ok((b.Size - Vector3.new(4, 5, 6)).Magnitude < 1e-3)
	end)

	t.test("a failed mesh is tried once per server, then the part model stays", function()
		MeshKit.Reset()
		local oakMesh = TreeModels.SectionMesh("oak", 1)
		local calls = 0
		MeshKit.Override = function(id, name, size)
			if id == oakMesh then
				calls += 1
				return nil
			end
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local def = WoodData.Get("oak")
		local skel = TreeGen.Skeleton("oak", 3, 1)
		local first = TreeArt.FromSkeleton(def, skel)
		local second = TreeArt.FromSkeleton(def, skel)
		MeshKit.Override = nil
		MeshKit.Reset()
		t.eq(calls, 1, "the failed id is not loaded again")
		t.eq(first:GetAttribute("TreeMesh"), nil, "the first tree keeps its blocks")
		t.eq(second:GetAttribute("TreeMesh"), nil, "the next tree keeps its blocks too")
		t.eq(#parts(first), TreeGen.PartCount(skel))
		t.eq(#parts(second), TreeGen.PartCount(skel))
	end)

	t.test("MeshKit.Visual is the shared looks-only helper", function()
		local part = Instance.new("Part")
		part.CanCollide = true
		part.CanTouch = true
		part.CanQuery = true
		part.Massless = false
		MeshKit.Visual(part, 125228989315064)
		t.eq(part.CanCollide, false)
		t.eq(part.CanTouch, false)
		t.eq(part.CanQuery, false)
		t.eq(part.Massless, true)
		t.eq(part:GetAttribute("VisualMesh"), true)
		t.eq(part:GetAttribute("MeshId"), "125228989315064")
	end)
end
