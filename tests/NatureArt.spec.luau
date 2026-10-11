--!nocheck
-- NatureArt: part counts, decoration flags, and the rain preview field.
return function(t)
	local NatureArt = t.load("ReplicatedStorage/Shared/Art/NatureArt")
	local Vector3 = t.roblox.Vector3
	local Color3 = t.roblox.Color3
	local Enum = t.roblox.Enum

	local function partsOf(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
				t.eq(d.Anchored, true, d.Name .. " anchored")
				t.eq(d.CanCollide, false, d.Name .. " no collide")
				t.eq(d.CanQuery, false, d.Name .. " no query")
				t.eq(d.CanTouch, false, d.Name .. " no touch")
				t.eq(d.CastShadow, false, d.Name .. " no shadow")
			end
			if d:IsA("PointLight") then
				t.eq(d.Shadows, false, "a nature light casts no shadow")
			end
		end
		return n
	end

	t.test("each built piece matches its part budget", function()
		local total, kinds = 0, 0
		for kind, want in pairs(NatureArt.Parts) do
			local model = NatureArt.Build(kind, 3, "mid")
			local n = partsOf(model)
			t.eq(n, want, kind .. " parts")
			t.ok(n >= 2 and n <= 8, kind .. " is 2 to 8 parts")
			total += n
			kinds += 1
		end
		t.ok(total / kinds <= 8, "average piece is 8 parts or fewer")
	end)

	t.test("rocks stay in the rock budget at every size", function()
		local NatureData = t.load("ReplicatedStorage/Shared/NatureData")
		t.eq(#NatureArt.RockShapes, 6, "six families")
		for _, shape in ipairs(NatureArt.RockShapes) do
			t.eq(NatureData.PartCost[shape], NatureArt.Parts[shape], shape .. " cost")
			for _, sizeName in ipairs(NatureArt.Sizes) do
				for _, look in ipairs(NatureArt.RockLooks) do
					local n = partsOf(NatureArt.Build(shape, 1, sizeName, look))
					t.eq(n, NatureArt.Parts[shape], shape .. " " .. sizeName .. " " .. look)
					t.ok(n >= 3 and n <= 8, shape .. " " .. sizeName)
				end
			end
		end
	end)

	local function worldBox(part)
		local hs = part.Size * 0.5
		local cf = part.CFrame
		local minX, minY, minZ = math.huge, math.huge, math.huge
		local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local w = cf:PointToWorldSpace(Vector3.new(hs.X * sx, hs.Y * sy, hs.Z * sz))
					minX = math.min(minX, w.X)
					minY = math.min(minY, w.Y)
					minZ = math.min(minZ, w.Z)
					maxX = math.max(maxX, w.X)
					maxY = math.max(maxY, w.Y)
					maxZ = math.max(maxZ, w.Z)
				end
			end
		end
		return minX, minY, minZ, maxX, maxY, maxZ
	end

	local function overlaps(a, b)
		local a0, a1, a2, a3, a4, a5 = worldBox(a)
		local b0, b1, b2, b3, b4, b5 = worldBox(b)
		return a0 <= b3 and a3 >= b0 and a1 <= b4 and a4 >= b1 and a2 <= b5 and a5 >= b2
	end

	local function blockParts(model)
		local list = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	t.test("no rock block is taller than 1.5 times its width", function()
		local function check(model, label)
			for _, p in ipairs(blockParts(model)) do
				local width = math.min(p.Size.X, p.Size.Z)
				t.ok(p.Size.Y <= width * 1.5 + 1e-4, label .. " " .. p.Name .. " " .. p.Size.Y .. " / " .. width)
			end
		end
		for _, shape in ipairs(NatureArt.RockShapes) do
			for _, sizeName in ipairs(NatureArt.Sizes) do
				check(NatureArt.Build(shape, 4, sizeName, "meadow"), shape .. " " .. sizeName)
				check(
					NatureArt.OreRock(shape, sizeName, Color3.fromRGB(40, 40, 40), Enum.Material.Slate, false),
					"ore " .. shape
				)
			end
		end
	end)

	t.test("every family tilts 8 to 20 degrees and sinks 20 to 30 percent", function()
		for seed = 1, 24 do
			local shape = NatureArt.RockShapes[(seed % #NatureArt.RockShapes) + 1]
			local model = NatureArt.Build(shape, seed, "mid", "snow")
			local tilt = model:GetAttribute("TiltDeg")
			local sink = model:GetAttribute("Sink")
			t.ok(tilt >= 8 and tilt <= 20, "tilt " .. tostring(tilt))
			t.ok(sink >= 0.2 - 1e-6 and sink <= 0.3 + 1e-6, "sink " .. tostring(sink))
			local core = model:FindFirstChild("Core")
			t.ok(core, shape .. " has a Core")
			local deg = math.deg(math.acos(math.clamp(core.CFrame.UpVector.Y, -1, 1)))
			t.ok(math.abs(deg - tilt) < 0.6, shape .. " leans " .. deg)
			local minY, maxY = math.huge, -math.huge
			for _, p in ipairs(blockParts(model)) do
				local _, y0, _, _, y1 = worldBox(p)
				minY = math.min(minY, y0)
				maxY = math.max(maxY, y1)
			end
			local buried = (0 - minY) / (maxY - minY)
			t.ok(buried >= 0.19 and buried <= 0.31, shape .. " buried " .. buried)
		end
	end)

	t.test("a part-built ore rock with an OreData id is 8 parts or fewer, with 2 or 3 flush vein wedges", function()
		-- The previews use this path (shape plus oreId), so pin it too.
		for _, oreId in ipairs({ "coal", "gold", "opal", "heartstone" }) do
			for _, shape in ipairs(NatureArt.RockShapes) do
				for _, sizeName in ipairs(NatureArt.Sizes) do
					local model =
						NatureArt.OreRock(shape, sizeName, Color3.fromRGB(1, 2, 3), Enum.Material.Metal, false, oreId)
					local tag = oreId .. " " .. shape .. " " .. sizeName
					t.eq(model:GetAttribute("OreId"), oreId, tag)
					t.ok(#blockParts(model) <= 8, tag .. " parts " .. #blockParts(model))
					local veins = 0
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("BasePart") and d.Name == "Vein" then
							veins += 1
							t.eq(d.ClassName, "WedgePart", tag .. " vein is a wedge")
						end
						t.ok(not (d:IsA("BasePart") and d.Name == "Plaque"), tag .. " no plaque")
					end
					t.ok(veins == 2 or veins == 3, tag .. " veins " .. veins)
				end
			end
		end
	end)

	t.test("an ore rock is at most 8 parts, with flush vein wedges and a blank OreId", function()
		for _, shape in ipairs(NatureArt.RockShapes) do
			for _, sizeName in ipairs(NatureArt.Sizes) do
				for _, glow in ipairs({ false, true }) do
					local model =
						NatureArt.OreRock(shape, sizeName, Color3.fromRGB(180, 90, 40), Enum.Material.Metal, glow)
					local parts = blockParts(model)
					t.ok(#parts <= 8, shape .. " " .. sizeName .. " parts " .. #parts)
					t.eq(model:GetAttribute("OreId"), "", "OreId is blank for lane M")
					t.eq(model:HasTag("OreRockArt"), true, "OreRockArt tag")
					local veins, lights, neon = 0, 0, 0
					local body = {}
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("BasePart") and d.Name == "Vein" then
							veins += 1
							t.eq(d.ClassName, "WedgePart", "a vein is a wedge")
							local thin = math.min(d.Size.X, d.Size.Y, d.Size.Z)
							local thick = math.max(d.Size.X, d.Size.Y, d.Size.Z)
							t.ok(thin <= thick * 0.45, "a vein is thin")
							if d.Material == Enum.Material.Neon then
								neon += 1
							end
						elseif d:IsA("BasePart") then
							table.insert(body, d)
							t.ok(d.Material ~= Enum.Material.Neon, "the host rock stays stone")
						elseif d:IsA("PointLight") then
							lights += 1
							t.eq(d.Shadows, false, "ore light casts no shadow")
						end
					end
					t.ok(veins == 2 or veins == 3, shape .. " veins " .. veins)
					for _, vein in ipairs(parts) do
						if vein.Name == "Vein" then
							local hit = false
							local _, _, _, _, veinTop = worldBox(vein)
							local rockTop = -math.huge
							for _, host in ipairs(body) do
								if overlaps(vein, host) then
									hit = true
								end
								local _, _, _, _, top = worldBox(host)
								rockTop = math.max(rockTop, top)
							end
							t.ok(hit, shape .. " vein sits in a face")
							t.ok(veinTop <= rockTop + 0.35, shape .. " vein is not stacked on top")
						end
					end
					if glow then
						t.eq(lights, 1, "glow adds one light")
						t.ok(neon >= 1, "glow veins are neon")
					else
						t.eq(lights, 0, "a dull ore has no light")
						t.eq(neon, 0, "a dull ore is not neon")
					end
				end
			end
		end
	end)

	t.test("moss and snow are thin crown patches, at most 0.3 studs proud", function()
		local function capsOf(model)
			local list = {}
			for _, p in ipairs(blockParts(model)) do
				if p.Name == "Cap" then
					table.insert(list, p)
				end
			end
			return list
		end
		local function proudOf(cap, body)
			local c0, c1, c2, c3, c4, c5 = worldBox(cap)
			local b0, b1, b2, b3, b4, b5 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
			for _, host in ipairs(body) do
				local x0, y0, z0, x1, y1, z1 = worldBox(host)
				b0 = math.min(b0, x0)
				b1 = math.min(b1, y0)
				b2 = math.min(b2, z0)
				b3 = math.max(b3, x1)
				b4 = math.max(b4, y1)
				b5 = math.max(b5, z1)
			end
			return math.max(b0 - c0, c3 - b3, b1 - c1, c4 - b4, b2 - c2, c5 - b5)
		end
		for _, shape in ipairs(NatureArt.RockShapes) do
			for _, sizeName in ipairs(NatureArt.Sizes) do
				for _, look in ipairs({ "meadow", "snow" }) do
					local model = NatureArt.Build(shape, 5, sizeName, look)
					local caps = capsOf(model)
					t.ok(#caps == 2 or #caps == 3, shape .. " " .. look .. " caps " .. #caps)
					local body = {}
					for _, p in ipairs(blockParts(model)) do
						if p.Name ~= "Cap" then
							table.insert(body, p)
						end
					end
					for _, cap in ipairs(caps) do
						local wedge = cap.ClassName == "WedgePart"
						local ball = cap.ClassName == "Part" and cap.Shape == Enum.PartType.Ball
						t.ok(wedge or ball, shape .. " patch is a wedge or a ball")
						if look == "meadow" then
							local moss = cap.Material == Enum.Material.Grass or cap.Material == Enum.Material.LeafyGrass
							t.ok(moss, "moss is grass")
						else
							t.eq(cap.Material, Enum.Material.Snow, "snow cap")
						end
						local hit = false
						for _, host in ipairs(body) do
							if overlaps(cap, host) then
								hit = true
							end
						end
						t.ok(hit, shape .. " " .. sizeName .. " patch hugs the stone")
						local proud = proudOf(cap, body)
						t.ok(proud <= 0.3 + 1e-3, shape .. " " .. sizeName .. " proud " .. proud)
					end
				end
			end
		end
	end)

	local function lumOf(color)
		return color.R * 0.299 + color.G * 0.587 + color.B * 0.114
	end

	local function faceArea(part, normal)
		local ax = math.abs(normal:Dot(part.CFrame.XVector))
		local ay = math.abs(normal:Dot(part.CFrame.YVector))
		local az = math.abs(normal:Dot(part.CFrame.ZVector))
		local size = part.Size
		if ax >= ay and ax >= az then
			return size.Y * size.Z
		elseif ay >= ax and ay >= az then
			return size.X * size.Z
		end
		return size.X * size.Y
	end

	local function thinNormal(part)
		local size = part.Size
		if size.X <= size.Y and size.X <= size.Z then
			return part.CFrame.XVector
		elseif size.Y <= size.Z then
			return part.CFrame.YVector
		end
		return part.CFrame.ZVector
	end

	local function overlapVol(a, b)
		local a0, a1, a2, a3, a4, a5 = worldBox(a)
		local b0, b1, b2, b3, b4, b5 = worldBox(b)
		local dx = math.min(a3, b3) - math.max(a0, b0)
		local dy = math.min(a4, b4) - math.max(a1, b1)
		local dz = math.min(a5, b5) - math.max(a2, b2)
		if dx <= 0 or dy <= 0 or dz <= 0 then
			return 0
		end
		return dx * dy * dz
	end

	t.test("each vein covers about a fifth of the face it sits on", function()
		for _, shape in ipairs(NatureArt.RockShapes) do
			for _, sizeName in ipairs(NatureArt.Sizes) do
				local model = NatureArt.OreRock(shape, sizeName, Color3.fromRGB(20, 20, 22), Enum.Material.Slate, false)
				local veins, body = {}, {}
				for _, p in ipairs(blockParts(model)) do
					if p.Name == "Vein" then
						table.insert(veins, p)
					else
						table.insert(body, p)
					end
				end
				for _, vein in ipairs(veins) do
					local host, best = nil, 0
					for _, part in ipairs(body) do
						local vol = overlapVol(vein, part)
						if vol > best then
							host, best = part, vol
						end
					end
					t.ok(host, shape .. " vein meets a face")
					if host then
						local size = vein.Size
						local dims = { size.X, size.Y, size.Z }
						table.sort(dims)
						local ratio = (dims[2] * dims[3]) / faceArea(host, thinNormal(vein))
						t.ok(ratio >= 0.15 and ratio <= 0.25, shape .. " " .. sizeName .. " vein share " .. ratio)
					end
				end
			end
		end
	end)

	t.test("dark ore sits on light stone and bright ore on dark stone", function()
		local coal = NatureArt.OreRock("Boulder", "mid", Color3.fromRGB(12, 12, 14), Enum.Material.Slate, false)
		local silver = NatureArt.OreRock("Slab", "mid", Color3.fromRGB(232, 236, 242), Enum.Material.Metal, false)
		local function coreLum(model)
			return lumOf(model:FindFirstChild("Core").Color)
		end
		local function veinLum(model)
			return lumOf(model:FindFirstChild("Vein").Color)
		end
		t.ok(coreLum(coal) > veinLum(coal) + 0.35, "coal is matte black on light grey")
		t.ok(veinLum(silver) > coreLum(silver) + 0.35, "silver is bright on dark stone")
	end)

	t.test("a pale glow is quieter than a saturated one", function()
		local opal = NatureArt.OreRock("Outcrop", "mid", Color3.fromRGB(214, 206, 230), Enum.Material.Neon, true)
		local heart = NatureArt.OreRock("Boulder", "mid", Color3.fromRGB(255, 70, 118), Enum.Material.Neon, true)
		local function bright(model)
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("PointLight") then
					return d.Brightness
				end
			end
			return 0
		end
		t.ok(bright(opal) < bright(heart), "opal stays subtle")
		t.ok(bright(heart) >= 0.8, "heartstone carries its light")
	end)

	t.test("a missing rock mesh keeps the part build and says so once", function()
		local RockModels = t.load("ReplicatedStorage/Shared/Art/RockModels")
		t.eq(RockModels.UsesMesh(0), false)
		-- The ids are uploaded now, so zero them here to test the fallback.
		local saved = {}
		for _, shape in ipairs(NatureArt.RockShapes) do
			for _, variant in ipairs({ "A", "B" }) do
				local spec = RockModels.Get(shape, variant)
				for _, key in ipairs(RockModels.PieceKeys) do
					table.insert(saved, { spec[key], spec[key].meshId })
					spec[key].meshId = 0
				end
			end
		end
		local ok, err = pcall(function()
			for _, shape in ipairs(NatureArt.RockShapes) do
				local spec = RockModels.Get(shape)
				t.eq(spec.Host.meshId, 0, shape)
				t.eq(spec.Glow.meshId, 0, shape .. " glow")
			end
			local rock = NatureArt.Build("Boulder", 4, "mid", "meadow")
			t.ok(rock:FindFirstChild("Core"), "the part-built core stays")
			t.eq(rock:FindFirstChild("MeshHost"), nil)
			t.eq(rock:GetAttribute("MeshFallback"), "host")
			t.eq(rock:GetAttribute("RockMesh"), nil)
			local fern = NatureArt.Build("Fern", 1)
			t.eq(fern:GetAttribute("MeshFallback"), nil, "plants are not rock meshes")
			local ore = NatureArt.OreRock("Spire", "mid", Color3.fromRGB(255, 0, 0), Enum.Material.Metal, false)
			t.ok(ore:FindFirstChild("Vein"))
			t.eq(ore:GetAttribute("OreId"), "")
			t.eq(ore:GetAttribute("MeshFallback"), "host")
		end)
		for _, row in ipairs(saved) do
			row[1].meshId = row[2]
		end
		if not ok then
			error(err, 0)
		end
	end)

	t.test("an ore id tints the part build from OreData", function()
		local OreData = t.load("ReplicatedStorage/Shared/OreData")
		local coal = OreData.Get("coal")
		local red = Color3.fromRGB(255, 0, 0)
		local model = NatureArt.OreRock("Boulder", "mid", red, Enum.Material.Metal, false, "coal")
		t.eq(model:GetAttribute("OreId"), "coal")
		t.eq(model:FindFirstChild("Vein").Color, coal.color)
		t.eq(model:FindFirstChild("Vein").Material, coal.material)
		local heart = NatureArt.OreRock("Boulder", "mid", red, Enum.Material.Slate, false, "heartstone")
		t.eq(heart:GetAttribute("OreId"), "heartstone")
		local light = 0
		for _, d in ipairs(heart:GetDescendants()) do
			if d:IsA("PointLight") then
				light += 1
				t.eq(d.Shadows, false)
				t.eq(d.Color, OreData.Get("heartstone").color)
			end
		end
		t.eq(light, 1, "heartstone glows even when the caller passed glow = false")
		local unknown = NatureArt.OreRock("Boulder", "mid", red, Enum.Material.Metal, false, "nope")
		t.eq(unknown:GetAttribute("OreId"), "")
		t.eq(unknown:FindFirstChild("Vein").Color, red)
	end)

	t.test("uploaded slots replace the part build and leave the other looks alone", function()
		local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
		local RockModels = t.load("ReplicatedStorage/Shared/Art/RockModels")
		local OreData = t.load("ReplicatedStorage/Shared/OreData")
		local Instance = t.roblox.Instance
		local saved = {}
		local n = 0
		for _, shape in ipairs(NatureArt.RockShapes) do
			local spec = RockModels.Get(shape)
			saved[shape] = {}
			for _, key in ipairs({ "Host", "Moss", "Snow", "Vein1", "Vein2", "Glow" }) do
				n += 1
				saved[shape][key] = spec[key].meshId
				spec[key].meshId = 800000 + n
			end
		end
		local function restore()
			for shape, slots in pairs(saved) do
				local spec = RockModels.Get(shape)
				for key, meshId in pairs(slots) do
					spec[key].meshId = meshId
				end
			end
			MeshKit.Override = nil
			MeshKit.Reset()
		end
		MeshKit.Reset()
		MeshKit.Override = function(_id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local ok, err = pcall(function()
			local function parts(model)
				local list = {}
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						table.insert(list, d)
					end
				end
				return list
			end
			local meadow = NatureArt.Build("Boulder", 4, "mid", "meadow")
			local host = meadow:FindFirstChild("MeshHost")
			local moss = meadow:FindFirstChild("MeshMoss")
			t.ok(host and moss, "meadow is host plus moss")
			t.eq(meadow:FindFirstChild("MeshSnow"), nil)
			t.eq(meadow:FindFirstChild("Core"), nil, "the part build is dropped")
			t.eq(meadow:GetAttribute("RockMesh"), true)
			t.eq(meadow:GetAttribute("MeshFallback"), nil)
			t.eq(moss.Material, Enum.Material.Grass)
			t.eq(host:GetAttribute("VisualMesh"), true)
			t.eq(host.Anchored, true)
			t.eq(host.CanQuery, false)
			t.eq(host.CastShadow, false)
			local spec = RockModels.Get("Boulder")
			t.ok((host.Size - spec.Host.size).Magnitude < 1e-3, "mid host uses the slot size")
			local snow = NatureArt.Build("CrackedBoulder", 4, "large", "snow")
			t.ok(snow:FindFirstChild("MeshSnow"))
			t.eq(snow:FindFirstChild("MeshMoss"), nil)
			t.eq(snow.MeshSnow.Material, Enum.Material.Snow)
			local shore = NatureArt.Build("Slab", 4, "small", "shore")
			t.ok(shore:FindFirstChild("MeshHost"))
			t.eq(shore:FindFirstChild("MeshMoss"), nil)
			t.eq(shore:FindFirstChild("MeshSnow"), nil)
			t.eq(#parts(shore), 1, "a shore rock is only the host mesh")
			local red = Color3.fromRGB(255, 0, 0)
			local coal = NatureArt.OreRock("Boulder", "mid", red, Enum.Material.Neon, true, "coal")
			t.eq(coal:GetAttribute("OreId"), "coal")
			t.eq(coal:FindFirstChild("MeshGlow"), nil, "coal has no glow mesh")
			t.eq(coal:FindFirstChild("Glow", true), nil, "coal has no light")
			local vein = coal:FindFirstChild("MeshVein1")
			t.ok(vein and coal:FindFirstChild("MeshVein2"))
			t.eq(vein.Color, OreData.Get("coal").color)
			t.eq(vein.Material, OreData.Get("coal").material)
			local heart = NatureArt.OreRock("Outcrop", "mid", red, Enum.Material.Slate, false, "heartstone")
			local glow = heart:FindFirstChild("MeshGlow")
			t.ok(glow, "heartstone glow slot")
			t.eq(glow.Material, Enum.Material.Neon)
			t.eq(glow.Color, OreData.Get("heartstone").color)
			local lamp = heart:FindFirstChild("Glow", true)
			t.ok(lamp and lamp:IsA("PointLight") and lamp.Parent == glow)
			t.eq(lamp.Shadows, false)
			local opal = NatureArt.OreRock("Boulder", "mid", red, Enum.Material.Slate, false, "opal")
			t.eq(opal:FindFirstChild("MeshGlow"), nil, "opal is a light, not a glow mesh")
			local opalLamp = opal:FindFirstChild("Glow", true)
			t.ok(opalLamp and opalLamp.Parent == opal:FindFirstChild("MeshVein1"))
			t.ok(opalLamp.Brightness < 0.5, "opal stays dim")
		end)
		restore()
		if not ok then
			error(err, 0)
		end
	end)

	t.test("a mesh that fails to load keeps the part build", function()
		local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
		local RockModels = t.load("ReplicatedStorage/Shared/Art/RockModels")
		local spec = RockModels.Get("Boulder")
		local savedHost, savedMoss = spec.Host.meshId, spec.Moss.meshId
		spec.Host.meshId = 770001
		spec.Moss.meshId = 770002
		MeshKit.Reset()
		MeshKit.Override = function()
			return nil
		end
		local ok, err = pcall(function()
			local model = NatureArt.Build("Boulder", 4, "mid", "meadow")
			t.ok(model:FindFirstChild("Core"))
			t.eq(model:FindFirstChild("MeshHost"), nil)
			t.eq(model:GetAttribute("MeshFallback"), "host")
		end)
		spec.Host.meshId = savedHost
		spec.Moss.meshId = savedMoss
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end)

	t.test("only an uploaded host is required when the look has no cap", function()
		local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
		local RockModels = t.load("ReplicatedStorage/Shared/Art/RockModels")
		local Instance = t.roblox.Instance
		local spec = RockModels.Get("Boulder")
		local saved, savedMoss = spec.Host.meshId, spec.Moss.meshId
		spec.Host.meshId = 770011
		spec.Moss.meshId = 0
		MeshKit.Reset()
		MeshKit.Override = function(_id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local ok, err = pcall(function()
			local shore = NatureArt.Build("Boulder", 4, "mid", "shore")
			t.ok(shore:FindFirstChild("MeshHost"))
			t.eq(shore:FindFirstChild("Core"), nil)
			local meadow = NatureArt.Build("Boulder", 4, "mid", "meadow")
			t.ok(meadow:FindFirstChild("Core"), "moss is still required for a meadow rock")
			t.eq(meadow:GetAttribute("MeshFallback"), "moss")
		end)
		spec.Host.meshId = saved
		spec.Moss.meshId = savedMoss
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end)

	t.test("a real rock mesh id joins the preload list", function()
		local RockModels = t.load("ReplicatedStorage/Shared/Art/RockModels")
		local MeshManifest = t.load("ReplicatedStorage/Shared/Art/MeshManifest")
		local spec = RockModels.Get("Spire")
		local saved = spec.Host.meshId
		spec.Host.meshId = 424242
		local ok, err = pcall(function()
			local found = false
			for _, id in ipairs(RockModels.MeshIds()) do
				if id == 424242 then
					found = true
				end
			end
			t.eq(found, true)
			local listed = false
			for _, entry in ipairs(MeshManifest.Flat(false)) do
				if entry.id == 424242 then
					listed = true
					t.eq(entry.hull, false)
				end
			end
			t.eq(listed, true, "MeshManifest preloads rock meshes")
		end)
		spec.Host.meshId = saved
		if not ok then
			error(err, 0)
		end
	end)

	local function withMeshes(fn)
		local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
		local Instance = t.roblox.Instance
		MeshKit.Reset()
		MeshKit.Override = function(_id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local ok, err = pcall(fn)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	t.test("mesh pieces sit at the host plus their offset times the scale", function()
		local RockModels = t.load("ReplicatedStorage/Shared/Art/RockModels")
		local CFrame = t.roblox.CFrame
		withMeshes(function()
			-- Seed 4 picks variant A and its jitter is exactly 1.
			for _, sizeName in ipairs({ "mid", "large" }) do
				local scale = if sizeName == "large" then 1.45 else 1
				local spec = RockModels.Get("Boulder", "A")
				local flat = NatureArt.BuildFlat("Boulder", 4, sizeName, "meadow")
				local host = flat:FindFirstChild("MeshHost")
				local moss = flat:FindFirstChild("MeshMoss")
				t.ok(host and moss, sizeName .. " has host and moss")
				t.ok(
					(host.CFrame.Position - spec.hostCentre * scale).Magnitude < 1e-3,
					sizeName .. " host sits at hostCentre * scale in build space"
				)
				local want = host.CFrame * CFrame.new(spec.Moss.offset * scale)
				t.ok((moss.CFrame.Position - want.Position).Magnitude < 1e-3, sizeName .. " moss position")
				t.ok((moss.Size - spec.Moss.size * scale).Magnitude < 1e-3, sizeName .. " moss size scales")
				t.ok((host.Size - spec.Host.size * scale).Magnitude < 1e-3, sizeName .. " host size scales")
				-- The tilted build keeps the same relation (the whole model moves as one).
				local tilted = NatureArt.Build("Boulder", 4, sizeName, "meadow")
				local th, tm = tilted:FindFirstChild("MeshHost"), tilted:FindFirstChild("MeshMoss")
				local twant = th.CFrame * CFrame.new(spec.Moss.offset * scale)
				t.ok((tm.CFrame.Position - twant.Position).Magnitude < 1e-3, sizeName .. " moss after settle")
			end
			-- Ore rock: both veins and the glow.
			local red = t.roblox.Color3.fromRGB(255, 0, 0)
			local heart = NatureArt.OreRock("Outcrop", "large", red, t.roblox.Enum.Material.Slate, false, "heartstone")
			local spec = RockModels.Get("Outcrop", "A")
			local host = heart:FindFirstChild("MeshHost")
			-- settle() jitters the whole rock's size and spacing a little.
			local jitter = host.Size.X / (spec.Host.size.X * 1.45)
			t.ok(jitter > 0.9 and jitter < 1.1)
			for key, name in pairs({ Vein1 = "MeshVein1", Vein2 = "MeshVein2", Glow = "MeshGlow" }) do
				local piece = heart:FindFirstChild(name)
				t.ok(piece, name)
				local want = host.CFrame * CFrame.new(spec[key].offset * 1.45 * jitter)
				t.ok((piece.CFrame.Position - want.Position).Magnitude < 1e-3, name .. " offset on the ore rock")
			end
			t.eq(heart:FindFirstChild("MeshHost"):GetAttribute("MeshId"), tostring(spec.Host.meshId))
		end)
	end)

	t.test("scatter variants follow the seed and ore shapes pick their kind", function()
		local RockModels = t.load("ReplicatedStorage/Shared/Art/RockModels")
		withMeshes(function()
			local function hostId(model)
				return model:FindFirstChild("MeshHost"):GetAttribute("MeshId")
			end
			local a = RockModels.Get("Boulder", "A").Host.meshId
			local b = RockModels.Get("Boulder", "B").Host.meshId
			t.eq(hostId(NatureArt.Build("Boulder", 4, "mid", "shore")), tostring(a))
			t.eq(hostId(NatureArt.Build("Boulder", 4, "mid", "shore")), tostring(a), "same seed, same variant")
			t.eq(hostId(NatureArt.Build("Boulder", 2, "mid", "shore")), tostring(b), "another seed can pick B")
			local red = t.roblox.Color3.fromRGB(255, 0, 0)
			local Material = t.roblox.Enum.Material.Metal
			local function ore(shape)
				return NatureArt.OreRock(shape, "mid", red, Material, false, "coal")
			end
			t.eq(hostId(ore("split")), tostring(RockModels.Get("CrackedBoulder", "A").Host.meshId))
			t.eq(hostId(ore("standing")), tostring(RockModels.Get("Spire", "A").Host.meshId))
			t.eq(hostId(ore("pebbles")), tostring(RockModels.Get("PebbleCluster", "A").Host.meshId))
			t.eq(hostId(ore("Slab")), tostring(RockModels.Get("Slab", "A").Host.meshId), "kind names pass through")
			t.eq(hostId(ore("unknown")), tostring(a), "unknown shapes are a Boulder")
			local mossy = ore("mossy")
			t.eq(hostId(mossy), tostring(b))
			t.ok(mossy:FindFirstChild("MeshMoss"), "mossy has a moss cap")
			t.eq(mossy.MeshMoss.Material, t.roblox.Enum.Material.Grass)
			t.eq(ore("boulder"):FindFirstChild("MeshMoss"), nil, "a plain boulder has none")
		end)
	end)

	t.test("with no ids the part build stays and each miss is told once", function()
		local loader = t.loader()
		local Fresh = loader:load("ReplicatedStorage/Shared/Art/NatureArt")
		local FreshRocks = loader:load("ReplicatedStorage/Shared/Art/RockModels")
		for _, variant in ipairs({ "A", "B" }) do
			local spec = FreshRocks.Get("Spire", variant)
			for _, key in ipairs(FreshRocks.PieceKeys) do
				spec[key].meshId = 0
			end
		end
		local ok, err = pcall(function()
			for i = 1, 6 do
				local rock = Fresh.Build("Spire", 4, "mid", "meadow")
				t.ok(rock:FindFirstChild("Core"))
				t.eq(rock:FindFirstChild("MeshHost"), nil)
			end
			local told = 0
			for _, line in ipairs(loader.warnings) do
				if string.find(line, "Spire", 1, true) and string.find(line, "host", 1, true) then
					told += 1
				end
			end
			t.eq(told, 1, "six missing rocks, one log line")
		end)
		if not ok then
			error(err, 0)
		end
	end)

	t.test("with the uploaded ids nothing falls back and nothing is told as missing", function()
		local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
		local Instance = t.roblox.Instance
		local loader = t.loader()
		local Fresh = loader:load("ReplicatedStorage/Shared/Art/NatureArt")
		local FreshKit = loader:load("ReplicatedStorage/Shared/Art/MeshKit")
		FreshKit.Reset()
		FreshKit.Override = function(_id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local RockModels = loader:load("ReplicatedStorage/Shared/Art/RockModels")
		local models = {}
		for _, kind in ipairs(RockModels.Shapes) do
			for seed = 0, 3 do
				for _, look in ipairs(Fresh.RockLooks) do
					for _, size in ipairs(Fresh.Sizes) do
						table.insert(models, Fresh.Build(kind, seed, size, look))
					end
				end
			end
			table.insert(models, Fresh.OreRock(kind, "mid", Color3.fromRGB(255, 0, 0), Enum.Material.Metal, false))
		end
		for _, shape in ipairs({ "boulder", "split", "standing", "slab", "mossy", "pebbles" }) do
			for _, ore in ipairs({ "coal", "copper", "iron", "silver", "gold", "opal", "heartstone" }) do
				table.insert(
					models,
					Fresh.OreRock(shape, "large", Color3.fromRGB(0, 0, 0), Enum.Material.Slate, false, ore)
				)
			end
		end
		table.insert(models, Fresh.CaveMouth())
		local meshed = 0
		for _, m in ipairs(models) do
			t.eq(m:GetAttribute("MeshFallback"), nil, "no fallback on " .. m.Name)
			if m:GetAttribute("RockMesh") == true then
				meshed += 1
			end
		end
		t.eq(meshed, #models, "every rock, ore rock and the cave mouth is meshed")
		for _, line in ipairs(loader.warnings) do
			t.ok(string.find(line, "mesh is missing", 1, true) == nil, line)
		end
		FreshKit.Override = nil
		MeshKit.Reset()
	end)

	t.test("the cave mouth is meshed with a hidden collider, or part-built with a light", function()
		local RockModels = t.load("ReplicatedStorage/Shared/Art/RockModels")
		local spec = RockModels.Scenery("CaveMouth")
		-- No override in Lune: every load misses, so this is the part build.
		local plain = NatureArt.CaveMouth()
		t.ok(plain:FindFirstChild("Body"), "part-built body")
		t.ok(plain:FindFirstChild("Frame"))
		t.eq(plain:GetAttribute("MeshFallback"), "Body")
		t.eq(plain:GetAttribute("RockMesh"), nil)
		local light = plain:FindFirstChild("Glow"):FindFirstChildWhichIsA("PointLight")
		t.ok(light, "the lantern light")
		withMeshes(function()
			local m = NatureArt.CaveMouth()
			t.eq(m:GetAttribute("RockMesh"), true)
			t.eq(m:GetAttribute("MeshFallback"), nil)
			local body, frame, glow, collision = m.Body, m.Frame, m.Glow, m.Collision
			t.eq(body.CanCollide, false, "the body does not collide")
			t.eq(frame.CanCollide, false)
			t.eq(collision.CanCollide, true, "the collider collides")
			t.eq(collision.CanQuery, true)
			t.eq(collision.Transparency, 1)
			-- Two pillars and a lintel round the doorway: a hull or a box would fill it.
			t.eq(collision.CollisionFidelity, t.roblox.Enum.CollisionFidelity.PreciseConvexDecomposition)
			t.eq(glow.Material, t.roblox.Enum.Material.Neon)
			local lamp = glow:FindFirstChildWhichIsA("PointLight")
			t.ok(lamp)
			t.eq(lamp.Range, 14)
			t.eq(lamp.Brightness, 1)
			t.eq(lamp.Shadows, false)
			t.ok((body.CFrame.Position - spec.hostCentre).Magnitude < 1e-3, "body at hostCentre")
			local want = spec.hostCentre + spec.pieces.Frame.offset
			t.ok((frame.CFrame.Position - want).Magnitude < 1e-3, "frame offset from the body")
			t.ok((collision.Size - spec.pieces.Collision.size).Magnitude < 1e-3)
			t.eq(m:FindFirstChildWhichIsA("SurfaceGui", true), nil, "the MINE letters are modelled")
		end)
	end)

	t.test("rain streaks are thin parts and a shelter skips the middle", function()
		local blobs = NatureArt.RainField("blobs", "high", false)
		local streaks = NatureArt.RainField("streaks", "high", false)
		local low = NatureArt.RainField("streaks", "low", false)
		local shop = NatureArt.RainField("streaks", "high", true)
		local function named(model, name)
			local n = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d.Name == name then
					n += 1
				end
			end
			return n
		end
		t.ok(named(blobs, "Blob") > named(streaks, "Blob"), "blobs are the old puff")
		t.eq(named(streaks, "Blob"), 0, "streaks are not blobs")
		t.ok(named(streaks, "Streak") > named(low, "Streak"), "low uses fewer streaks")
		t.ok(named(streaks, "Splash") > 0, "open ground has splashes")
		t.eq(named(shop, "Splash"), 0, "a shelter has no splashes")
		t.ok(named(shop, "Streak") < named(streaks, "Streak"), "a roof cuts the streaks under it")
	end)
end
