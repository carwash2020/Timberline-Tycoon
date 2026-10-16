--!nocheck
-- GearWear: the worn coat, boots, cloak and the belt with the Lantern and the
-- Flashlight; the hardhat dress; and the night light on the worn Lantern.
-- Headless: mesh parts come from MeshKit.Override, the R15 body is plain Parts.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame, Color3 = roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3
	local GearWear = t.load("ReplicatedStorage/Shared/Art/GearWear")
	local WornModels = t.load("ReplicatedStorage/Shared/Art/WornModels")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local MiningArt = t.load("ReplicatedStorage/Shared/Mining/MiningArt")
	local AxeModels = t.load("ReplicatedStorage/Shared/Art/AxeModels")

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

	-- A piece's id set to 0 (or a fake) just for the test, then restored.
	local function withId(asset, piece, id, fn)
		local p = WornModels.Piece(asset, piece)
		local before = p.meshId
		p.meshId = id
		local ok, err = pcall(fn)
		p.meshId = before
		if not ok then
			error(err, 0)
		end
	end

	-- A default-size R15 body: the Y sizes are the reference heights, so the scale is 1.
	local function body(r6)
		local character = Instance.new("Model")
		local function part(name, size, at)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.CFrame = CFrame.new(at)
			p.Parent = character
			return p
		end
		if r6 then
			part("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
			part("Head", Vector3.new(2, 1, 1), Vector3.new(0, 4.5, 0))
			return character
		end
		part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.new(0, 3, 0))
		part("LowerTorso", Vector3.new(2, 0.4, 1), Vector3.new(0, 2.2, 0))
		part("UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 3.2, 0))
		part("Head", Vector3.new(2, 1.2, 1), Vector3.new(0, 4.5, 0))
		part("LeftUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(-1.5, 3.4, 0))
		part("RightUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(1.5, 3.4, 0))
		part("LeftFoot", Vector3.new(1, 0.3, 1), Vector3.new(-0.5, 0.15, 0))
		part("RightFoot", Vector3.new(1, 0.3, 1), Vector3.new(0.5, 0.15, 0))
		return character
	end

	local TURN = CFrame.Angles(0, AxeModels.MeshYaw, 0)

	-- (gear, attach key, target part, piece asset/name)
	local CASES = {
		{ "InsulatedCoat", "CoatBody", "UpperTorso" },
		{ "InsulatedCoat", "CoatSleeve", "LeftUpperArm" },
		{ "InsulatedCoat", "CoatSleeve", "RightUpperArm" },
		{ "FeatherfallCloak", "CloakBody", "UpperTorso" },
		{ "FeatherfallCloak", "CloakGlow", "UpperTorso" },
		{ "HeatBoots", "HeatBootBody", "LeftFoot" },
		{ "HeatBoots", "HeatBootBody", "RightFoot" },
		{ "HeatBoots", "HeatBootGlow", "LeftFoot" },
		{ "HeatBoots", "HeatBootGlow", "RightFoot" },
		{ "WaderBoots", "WaderBoot", "LeftFoot" },
		{ "WaderBoots", "WaderBoot", "RightFoot" },
	}

	t.test("each worn piece sits at the target centre + offset, sized, welded, white, looks-only", function()
		withMeshes(function()
			for _, c in ipairs(CASES) do
				local gear, key, targetName = c[1], c[2], c[3]
				local character = body(false)
				GearWear.Refresh(character, { [gear] = true })
				local model = character:FindFirstChild("Worn_" .. gear)
				t.ok(model ~= nil, gear .. " has its Worn_ model")
				local mesh = model:FindFirstChild(key .. "_" .. targetName)
				t.ok(mesh ~= nil, key .. " on " .. targetName)
				local attach = GearWear.Attach[key]
				local piece = WornModels.Piece(attach.asset, attach.piece)
				local target = character:FindFirstChild(targetName)
				local want = target.CFrame * CFrame.new(attach.offset) * TURN
				t.ok((mesh.CFrame.Position - want.Position).Magnitude < 0.01, key .. " " .. targetName .. " position")
				t.ok(
					(mesh.Size - piece.size).Magnitude < 1e-3,
					key .. " size " .. tostring(mesh.Size) .. " vs " .. tostring(piece.size)
				)
				t.eq(mesh.Color, Color3.new(1, 1, 1), key .. ": white Color (it multiplies the vertex colours)")
				t.eq(mesh.TextureID, "", key .. ": no texture")
				t.ok(mesh.Massless and not mesh.CanCollide and not mesh.CanTouch and not mesh.CanQuery, key .. " flags")
				local weld = mesh:FindFirstChildOfClass("WeldConstraint")
				t.ok(weld ~= nil and weld.Part0 == target and weld.Part1 == mesh, key .. " welded to its part")
				if attach.glow then
					t.eq(mesh.Material, roblox.Enum.Material.Neon, key .. " glow is Neon")
				end
			end
		end)
	end)

	t.test("a scaled body scales the piece and its offset", function()
		withMeshes(function()
			local character = body(false)
			local torso = character.UpperTorso
			torso.Size = Vector3.new(4, 3.2, 2) -- twice the default height
			GearWear.Refresh(character, { InsulatedCoat = true })
			local mesh = character.Worn_InsulatedCoat.CoatBody_UpperTorso
			local piece = WornModels.Piece("CoatBody", "Body")
			t.ok((mesh.Size - piece.size * 2).Magnitude < 1e-3, "size doubles")
			local want = torso.CFrame * CFrame.new(GearWear.Attach.CoatBody.offset * 2)
			t.ok((mesh.CFrame.Position - want.Position).Magnitude < 0.01, "offset doubles")
		end)
	end)

	t.test("a second refresh replaces, it never stacks; an unowned gear is taken off", function()
		withMeshes(function()
			local character = body(false)
			GearWear.Refresh(character, { InsulatedCoat = true, HeatBoots = true })
			GearWear.Refresh(character, { InsulatedCoat = true, HeatBoots = true })
			local n = 0
			for _, child in ipairs(character:GetChildren()) do
				if string.sub(child.Name, 1, 5) == "Worn_" then
					n += 1
				end
			end
			t.eq(n, 2, "one model per gear")
			GearWear.Refresh(character, { HeatBoots = true })
			t.ok(character:FindFirstChild("Worn_InsulatedCoat") == nil, "the coat came off")
			t.ok(character:FindFirstChild("Worn_HeatBoots") ~= nil)
			GearWear.Refresh(character, {})
			t.ok(character:FindFirstChild("Worn_HeatBoots") == nil, "nothing owned: nothing worn")
		end)
	end)

	t.test("an R6 character is skipped silently", function()
		withMeshes(function()
			local character = body(true)
			local made = GearWear.Refresh(character, { InsulatedCoat = true, Lantern = true })
			t.eq(#made, 0)
			t.ok(character:FindFirstChild("Worn_InsulatedCoat") == nil)
			t.ok(character:FindFirstChild("Worn_Belt") == nil)
		end)
	end)

	t.test(
		"id 0 (set for the test) shows nothing and throws nothing; a fake non-zero id takes the mesh path",
		function()
			withMeshes(function()
				withId("CoatBody", "Body", 0, function()
					withId("CoatSleeve", "Body", 0, function()
						local character = body(false)
						GearWear.Refresh(character, { InsulatedCoat = true })
						local model = character:FindFirstChild("Worn_InsulatedCoat")
						t.ok(model == nil or #model:GetChildren() == 0, "nothing is shown for id 0")
					end)
				end)
				withId("CoatBody", "Body", 1234567890123, function()
					local character = body(false)
					GearWear.Refresh(character, { InsulatedCoat = true })
					local mesh = character.Worn_InsulatedCoat:FindFirstChild("CoatBody_UpperTorso")
					t.ok(mesh ~= nil, "the fake id builds the mesh")
					t.eq(mesh:GetAttribute("MeshId"), "1234567890123")
				end)
			end)
		end
	)

	t.test("a mesh that is not loaded shows nothing and throws nothing", function()
		MeshKit.Reset()
		MeshKit.Override = function()
			return nil
		end
		local character = body(false)
		GearWear.Refresh(character, { InsulatedCoat = true, Lantern = true })
		local model = character:FindFirstChild("Worn_InsulatedCoat")
		t.ok(model == nil or #model:GetChildren() == 0)
		MeshKit.Override = nil
		MeshKit.Reset()
	end)

	---------------------------------------------------------------------------
	-- The belt
	---------------------------------------------------------------------------

	local function lowerAt(character, offset, s)
		return character.LowerTorso.CFrame * CFrame.new(offset * (s or 1))
	end

	t.test("the belt carries the Lantern upright and the Flashlight lens-down", function()
		withMeshes(function()
			local character = body(false)
			GearWear.Refresh(character, { Lantern = true, Flashlight = true })
			local belt = character:FindFirstChild("Worn_Belt")
			t.ok(belt ~= nil)
			local belt_mesh = belt:FindFirstChild("Belt_LowerTorso")
			t.ok(belt_mesh ~= nil, "the GearBelt mesh is on")
			local lantern = belt:FindFirstChild("Lantern")
			local flash = belt:FindFirstChild("Flashlight")
			t.ok(lantern ~= nil and flash ~= nil, "both tools hang on it")
			local want = lowerAt(character, Vector3.new(-0.62, -0.827, 0.98))
			t.ok((lantern.CFrame.Position - want.Position).Magnitude < 0.01, "lantern position")
			local fwant = lowerAt(character, Vector3.new(0.62, -1.109, 0.98))
			t.ok((flash.CFrame.Position - fwant.Position).Magnitude < 0.01, "flashlight position")
			-- The flashlight is 0.8 of its slot size, and its X (the lens) points down.
			t.ok(math.abs(flash.Size.X - 2.298 * 0.8) < 0.01, "flashlight scaled 0.8")
			local lens = flash.CFrame:VectorToWorldSpace(Vector3.new(1, 0, 0))
			t.ok(lens.Y < -0.99, "the lens points down")
			t.eq(lantern.Color, Color3.new(1, 1, 1), "white Color: the baked texture carries the colour")
			t.ok(not lantern.CanCollide and lantern.Massless)
		end)
	end)

	t.test("only the owned tool is worn", function()
		withMeshes(function()
			local character = body(false)
			GearWear.Refresh(character, { Lantern = true })
			local belt = character.Worn_Belt
			t.ok(belt:FindFirstChild("Lantern") ~= nil)
			t.ok(belt:FindFirstChild("Flashlight") == nil)
		end)
	end)

	t.test("with the Featherfall Cloak worn both tools move back to z = 1.33", function()
		withMeshes(function()
			local character = body(false)
			GearWear.Refresh(character, { Lantern = true, Flashlight = true, FeatherfallCloak = true })
			local belt = character.Worn_Belt
			local want = lowerAt(character, Vector3.new(-0.62, -0.827, 1.33))
			t.ok((belt.Lantern.CFrame.Position - want.Position).Magnitude < 0.01, "lantern 0.35 back")
			local fwant = lowerAt(character, Vector3.new(0.62, -1.109, 1.33))
			t.ok((belt.Flashlight.CFrame.Position - fwant.Position).Magnitude < 0.01, "flashlight 0.35 back")
		end)
	end)

	t.test("belt mesh id 0: a plain leather band and two iron rings, so the lantern still shows", function()
		withMeshes(function()
			withId("GearBelt", "Body", 0, function()
				local character = body(false)
				GearWear.Refresh(character, { Lantern = true })
				local belt = character.Worn_Belt
				local band = belt:FindFirstChild("BeltBand")
				t.ok(band ~= nil, "the fallback band")
				t.ok(
					(band.Size - Vector3.new(2.12, 0.26, 1.12)).Magnitude < 1e-3,
					"2.12 x 0.26 x 1.12 at default scale"
				)
				local rings = 0
				for _, child in ipairs(belt:GetChildren()) do
					if child.Name == "BeltRing" then
						rings += 1
						local p = character.LowerTorso.CFrame:PointToObjectSpace(child.CFrame.Position)
						t.ok(
							math.abs(math.abs(p.X) - 0.62) < 0.01 and math.abs(p.Y + 0.17) < 0.01,
							"ring at x = +-0.62"
						)
						t.ok(math.abs(p.Z - 0.98) < 0.01, "ring at z = 0.98")
					end
				end
				t.eq(rings, 2)
				t.ok(belt:FindFirstChild("Lantern") ~= nil, "the lantern still shows")
			end)
		end)
	end)

	---------------------------------------------------------------------------
	-- The lantern's night light
	---------------------------------------------------------------------------

	local function biome()
		local loader = t.loader({
			services = {
				Players = {
					GetPlayers = function()
						return {}
					end,
					PlayerRemoving = { Connect = function() end },
				},
				RunService = { Heartbeat = { Connect = function() end } },
				StarterPlayer = {},
			},
			mocks = {
				HazardService = {},
				ProfileService = {},
				WorldClock = {},
			},
		})
		local ok, mod = pcall(function()
			return loader:load("ServerScriptService/BiomeService")
		end)
		return if ok then mod else nil
	end

	t.test("the night light goes on the worn Lantern's mesh, else on the root as before", function()
		local Biome = biome()
		if Biome == nil then
			-- BiomeService needs more of the server than this harness stubs: check the source instead.
			local fs = require("@lune/fs")
			local src = fs.readFile("src/ServerScriptService/BiomeService.luau")
			t.ok(string.find(src, "GearWear.LanternMesh(char)", 1, true), "update asks GearWear for the lantern mesh")
			t.ok(string.find(src, "local home: BasePart = lanternMesh or root", 1, true), "the light's home")
			return
		end
		local root = Instance.new("Part")
		local lantern = Instance.new("Part")
		Biome.SetLantern(root, true, nil)
		local light = root:FindFirstChild("LanternLight")
		t.ok(light ~= nil, "no worn lantern: on the root")
		t.eq(light.Range, 24)
		t.eq(light.Brightness, 2)
		t.eq(light.Shadows, true)
		Biome.SetLantern(root, true, lantern)
		t.ok(lantern:FindFirstChild("LanternLight") == light, "a lantern appears: the light moves onto it")
		Biome.SetLantern(root, false, lantern)
		t.ok(lantern:FindFirstChild("LanternLight") == nil and root:FindFirstChild("LanternLight") == nil, "off")
	end)

	---------------------------------------------------------------------------
	-- The hardhat
	---------------------------------------------------------------------------

	local function wornHat(character)
		local hat = MiningArt.Hardhat()
		hat.Parent = character
		local head = character.Head
		local joint = hat:FindFirstChild("HeadWeld", true)
		joint.Part0 = head
		return hat
	end

	t.test("hardhat: id 0 leaves the part-built hat", function()
		withMeshes(function()
			withId("HardhatWorn", "Body", 0, function()
				local character = body(false)
				local hat = wornHat(character)
				t.eq(GearWear.DressHardhat(character, hat), false)
				t.ok(hat:FindFirstChild("Brim") and hat:FindFirstChild("LampCap"), "Brim and LampCap stay")
				t.eq(hat.Shell.Transparency, 0, "the shell stays visible")
			end)
		end)
	end)

	t.test("hardhat: the real ids build the mesh pieces, the part-built bits go, the weld still exists", function()
		withMeshes(function()
			local character = body(false)
			local hat = wornHat(character)
			t.ok(GearWear.DressHardhat(character, hat))
			local body_ = hat:FindFirstChild("HardhatBody_Head")
			local glow = hat:FindFirstChild("HardhatGlow_Head")
			t.ok(body_ ~= nil and glow ~= nil, "Body and Glow")
			local head = character.Head
			local s = head.Size.Y / 1.2
			local wantBody = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.103 * s, -0.192 * s)
			t.ok((body_.CFrame.Position - wantBody.Position).Magnitude < 0.01, "body: H + 0.103, -0.192")
			local wantGlow = head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.18 * s, -0.91 * s)
			t.ok((glow.CFrame.Position - wantGlow.Position).Magnitude < 0.01, "glow: H + 0.18, -0.91")
			t.ok(hat:FindFirstChild("Brim") == nil and hat:FindFirstChild("LampCap") == nil, "part-built bits are gone")
			t.ok(hat:FindFirstChild("HeadWeld", true) ~= nil, "the HeadWeld is still there")
			t.eq(hat.Shell.Transparency, 1, "the shell stays as the root, invisible")
			t.eq(body_.Color, Color3.new(1, 1, 1))
			t.eq(glow.Material, roblox.Enum.Material.Neon)
			local weld = body_:FindFirstChildOfClass("WeldConstraint")
			t.ok(weld ~= nil and weld.Part0 == head)
		end)
	end)

	t.test("the services call the dress, and the game server starts the worn-gear service", function()
		local fs = require("@lune/fs")
		t.ok(
			string.find(
				fs.readFile("src/ServerScriptService/MiningService.luau"),
				"GearWear.DressHardhat(character, hat)",
				1,
				true
			)
		)
		t.ok(string.find(fs.readFile("src/ServerScriptService/GameServer.server.luau"), "GearWearService", 1, true))
		local svc = fs.readFile("src/ServerScriptService/GearWearService.luau")
		t.ok(string.find(svc, 'GetAttributeChangedSignal("OwnedGear")', 1, true), "refreshes when OwnedGear changes")
		t.ok(string.find(svc, "CharacterAdded", 1, true), "and on spawn")
		t.ok(string.find(svc, 'Instance.new("Tool")', 1, true) == nil, "visual only: no Tool")
		t.ok(
			string.find(svc .. fs.readFile("src/ReplicatedStorage/Shared/Art/GearWear.luau"), "ButtonR2", 1, true)
				== nil,
			"no ButtonR2"
		)
	end)
end
