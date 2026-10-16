--!nocheck
-- PendingMeshes: nothing swaps in until a real upload id is pasted, and the
-- moment one is, the mesh path takes over (headless: a fake non-zero id).
return function(t)
	local roblox = t.roblox
	local Instance = roblox.Instance
	local Pending = t.load("ReplicatedStorage/Shared/Art/PendingMeshes")
	local EventArt = t.load("ReplicatedStorage/Shared/Art/EventArt")
	local PropArt = t.load("ReplicatedStorage/Shared/Art/PropArt")
	local NatureArt = t.load("ReplicatedStorage/Shared/Art/NatureArt")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")

	local FAKE = 1234567890123

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

	local function withId(name, id, fn)
		local before = Pending.Ids[name]
		Pending.Ids[name] = id
		local ok, err = pcall(fn)
		Pending.Ids[name] = before
		if not ok then
			error(err, 0)
		end
	end

	local function parts(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		return n
	end

	-- The five MeshIds uploaded on 15 October 2026 (the MeshPart ids, never the
	-- Model containers).
	local EXPECTED = {
		Pumpkin = 114164133748804,
		PumpkinPatch = 75317089677312,
		PumpkinHat = 123436760448077,
		LavaRock = 132224124506530,
		Roots = 96379929372711,
	}

	t.test("the table is exactly the five uploaded ids, and Id() returns each", function()
		local n = 0
		for name, id in pairs(Pending.Ids) do
			n += 1
			t.ok(EXPECTED[name] ~= nil, name .. " is one of the five")
			t.eq(id, EXPECTED[name], name .. " is the uploaded MeshId")
			t.ok(id ~= 0, name .. " is no longer pending")
			t.eq(Pending.Id(name), id, name)
		end
		t.eq(n, 5, "exactly Pumpkin, PumpkinPatch, PumpkinHat, LavaRock and Roots")
		t.eq(Pending.Id("NoSuchMesh"), nil)
		-- 0 still means pending.
		withId("Roots", 0, function()
			t.eq(Pending.Id("Roots"), nil, "a 0 is pending")
		end)
	end)

	t.test("each mesh has its MeshTemplates file, in the shape of the others", function()
		local fs = require("@lune/fs")
		for name, id in pairs(EXPECTED) do
			local text = fs.readFile("src/ReplicatedStorage/MeshTemplates/" .. id .. ".model.json")
			t.eq(
				text,
				'{\n\t"className": "MeshPart",\n\t"properties": {\n\t\t"MeshId": "rbxassetid://' .. id .. '"\n\t}\n}\n',
				name .. " template"
			)
		end
	end)

	t.test("the swapped-in mesh carries vertex colours: white Color, no texture", function()
		withMeshes(function()
			local model = EventArt.Pumpkin(7)
			local mesh = model:FindFirstChild("PumpkinMesh", true)
			t.ok(mesh ~= nil)
			t.eq(mesh.Color, roblox.Color3.new(1, 1, 1), "white: it multiplies the vertex colours")
			t.eq(mesh.TextureID, "", "no texture")
		end)
	end)

	-- Each builder: id 0 = the part-built prop, no mesh; a fake id = the mesh.
	local BUILDERS = {
		{
			"Pumpkin",
			function()
				return EventArt.Pumpkin(7)
			end,
		},
		{
			"PumpkinPatch",
			function()
				return EventArt.PumpkinPatch(7)
			end,
		},
		{
			"PumpkinHat",
			function()
				return EventArt.Hat()
			end,
		},
		{
			"LavaRock",
			function()
				return PropArt.LavaRock(7, 2)
			end,
		},
		{
			"Roots",
			function()
				return NatureArt.Build("Roots", 7)
			end,
		},
	}

	for _, case in ipairs(BUILDERS) do
		local name, build = case[1], case[2]
		t.test(name .. ": id 0 keeps the part-built version", function()
			withMeshes(function()
				withId(name, 0, function()
					local model = build()
					t.ok(parts(model) > 0, "the part-built prop")
					t.ok(model:FindFirstChild(name .. "Mesh", true) == nil, "no mesh")
				end)
			end)
		end)

		t.test(name .. ": a fake non-zero id takes the mesh path", function()
			withMeshes(function()
				withId(name, FAKE, function()
					local model = build()
					local mesh = model:FindFirstChild(name .. "Mesh", true)
					t.ok(mesh ~= nil, "the mesh is built")
					t.eq(mesh:GetAttribute("MeshId"), tostring(FAKE))
					t.ok(mesh:GetAttribute("VisualMesh") == true, "looks-only")
					t.ok(mesh.Size.X > 0 and mesh.Size.Y > 0 and mesh.Size.Z > 0, "the prop's bounding box")
				end)
			end)
		end)

		t.test(name .. ": a mesh that is not loaded leaves the part-built prop alone", function()
			MeshKit.Reset()
			MeshKit.Override = function()
				return nil
			end
			withId(name, FAKE, function()
				local model = build()
				t.ok(parts(model) > 0, "still the part-built prop")
				t.ok(model:FindFirstChild(name .. "Mesh", true) == nil)
			end)
			MeshKit.Override = nil
			MeshKit.Reset()
		end)
	end

	t.test("the hat keeps HatBase (it welds to the head)", function()
		withMeshes(function()
			withId("PumpkinHat", FAKE, function()
				local hat = EventArt.Hat()
				t.ok(hat:FindFirstChild("HatBase") ~= nil)
				t.ok(hat.PrimaryPart ~= nil and hat.PrimaryPart.Name == "HatBase")
			end)
		end)
	end)

	t.test("store items: every item named in the brief has a slot with a meshId (0 = part-built fallback)", function()
		local Slots = t.load("ReplicatedStorage/Shared/Art/ModelSlots")
		local StoreSlots = t.load("ReplicatedStorage/Shared/StoreModelSlots")
		local fs = require("@lune/fs")
		local blob = fs.readFile("src/ReplicatedStorage/Shared/Art/ModelSlots.luau")
			.. fs.readFile("src/ReplicatedStorage/Shared/StoreModelSlots.luau")
		for _, name in ipairs({
			"Barrel",
			"Crate",
			"GlowWire",
			"SkyBin",
			"Parcel",
			"RobuxCoins",
			"Flashlight",
			"Lantern",
			"WoodSign",
			"ShedBlueprint",
		}) do
			t.ok(string.find(blob, name, 1, true) ~= nil, name .. " has a slot")
		end
		t.ok(Slots ~= nil and StoreSlots ~= nil)
	end)
end
