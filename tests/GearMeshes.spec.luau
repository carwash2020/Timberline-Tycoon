--!nocheck
-- GearMeshes: the Hammer and the pickaxes get their uploaded meshes on the Tool,
-- each piece where Blender put it, and nothing breaks without them.
return function(t)
	local roblox = t.roblox
	local Vector3, Instance, CFrame = roblox.Vector3, roblox.Instance, roblox.CFrame
	local GearMeshes = t.load("ReplicatedStorage/Shared/Art/GearMeshes")
	local BacklogModels = t.load("ReplicatedStorage/Shared/Art/BacklogModels")
	local MiningArt = t.load("ReplicatedStorage/Shared/Mining/MiningArt")
	local HammerArt = t.load("ReplicatedStorage/Shared/Art/HammerArt")
	local PickaxeData = t.load("ReplicatedStorage/Shared/Mining/PickaxeData")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")

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

	-- A Tool the way the services build one: the part-built model's children.
	local function toolFrom(model)
		local tool = Instance.new("Tool")
		for _, child in ipairs(model:GetChildren()) do
			child.Parent = tool
		end
		return tool
	end

	local IDS = { "Hammer", "RustyPick", "CopperPick", "IronPick", "SteelPick", "ObsidianPick", "LuxPickaxe" }

	t.test("every dressed id has uploaded Handle and Head meshes (and a Glow where it has an offset)", function()
		for _, id in ipairs(IDS) do
			t.ok(GearMeshes.Has(id), id .. " is dressed")
			t.ok(BacklogModels.Get(id) ~= nil, id .. " is in BacklogModels")
		end
		t.ok(not GearMeshes.Has("NoSuchGear"), "an id without offsets is not dressed")
	end)

	t.test("pickaxe ids map straight onto the dress table", function()
		for _, pick in ipairs(PickaxeData.All()) do
			t.ok(GearMeshes.Has(pick.id), pick.id)
		end
		t.ok(GearMeshes.Has(PickaxeData.LuxId))
	end)

	t.test("a dressed Tool: mesh head at the haft mesh centre + at, part-built bits gone, Handle kept", function()
		withMeshes(function()
			for _, id in ipairs(IDS) do
				local model = if id == "Hammer" then HammerArt.Held() else MiningArt.Pickaxe(PickaxeData.Get(id))
				local tool = toolFrom(model)
				t.ok(GearMeshes.Dress(tool, id), id .. " dresses")
				local handle = tool:FindFirstChild("Handle")
				local handleMesh = tool:FindFirstChild("MeshHandle")
				local head = tool:FindFirstChild("MeshHead")
				t.ok(handle and handleMesh and head, id .. " has Handle, MeshHandle, MeshHead")
				local off = head.CFrame.Position - handleMesh.CFrame.Position
				t.ok((off - GearMeshes.Offsets[id].Head).Magnitude < 0.01, id .. " head off by " .. tostring(off))
				if GearMeshes.Offsets[id].Glow then
					local glow = tool:FindFirstChild("MeshGlow")
					t.ok(glow ~= nil, id .. " has its glow")
					local g = glow.CFrame.Position - handleMesh.CFrame.Position
					t.ok((g - GearMeshes.Offsets[id].Glow).Magnitude < 0.01, id .. " glow off by " .. tostring(g))
				end
				for _, d in ipairs(tool:GetDescendants()) do
					if d:IsA("BasePart") and d ~= handle then
						t.ok(d:GetAttribute("VisualMesh") == true, id .. ": " .. d.Name .. " is a mesh, not part-built")
						t.ok(d:FindFirstChild("Weld") ~= nil, id .. ": " .. d.Name .. " is welded to the Handle")
					end
				end
				t.eq(handle.Transparency, 1, id .. ": the Handle stays but is invisible")
			end
		end)
	end)

	t.test("no mesh available: the part-built tool is left exactly as it was", function()
		MeshKit.Reset()
		MeshKit.Override = function()
			return nil
		end
		local tool = toolFrom(MiningArt.Pickaxe(PickaxeData.Get("RustyPick")))
		local before = #tool:GetChildren()
		t.eq(GearMeshes.Dress(tool, "RustyPick"), false)
		t.eq(#tool:GetChildren(), before, "nothing added or removed")
		t.ok(tool:FindFirstChild("MeshHead") == nil)
		MeshKit.Override = nil
		MeshKit.Reset()
	end)

	t.test("both services dress the Tool they build", function()
		local fs = require("@lune/fs")
		t.ok(
			string.find(
				fs.readFile("src/ServerScriptService/MiningService.luau"),
				"GearMeshes.Dress(tool, gearId)",
				1,
				true
			)
		)
		t.ok(
			string.find(
				fs.readFile("src/ServerScriptService/BlueprintService.luau"),
				'GearMeshes.Dress(tool, "Hammer")',
				1,
				true
			)
		)
	end)

	-- The audit's numbers, as given (name -> piece -> size): every piece the
	-- offsets table names exists in BacklogModels at exactly this size.
	local SIZES = {
		BlueprintScroll = { Body = { 0.4, 1.389, 0.693 }, Handle = { 0.628, 2.4, 0.628 } },
		Bomb = { Body = { 0.928, 2.267, 0.928 }, Glow = { 0.266, 0.27, 0.28 } },
		CopperPick = { Handle = { 0.36, 3.2, 0.468 }, Head = { 0.62, 0.765, 2.52 } },
		FeatherfallCloak = { Body = { 2.96, 3.302, 1.12 }, Glow = { 0.248, 0.248, 0.26 } },
		Flashlight = { Glow = { 0.734, 0.734, 0.12 }, Handle = { 0.618, 1.7, 0.684 }, Head = { 0.87, 0.87, 1.595 } },
		Hammer = { Handle = { 0.34, 3.4, 0.42 }, Head = { 0.55, 0.625, 1.565 } },
		Hardhat = { Body = { 1.7, 1.616, 2.05 }, Glow = { 0.3, 0.22, 0.08 } },
		HeatBoots = { Body = { 2.35, 1.83, 1.55 }, Glow = { 1.9, 0.06, 0.7 } },
		InsulatedCoat = { Body = { 2.95, 3.35, 1.225 } },
		IronPick = { Handle = { 0.36, 3.3, 0.468 }, Head = { 0.62, 0.765, 2.52 } },
		Lantern = { Body = { 1.05, 1.725, 1.05 }, Glow = { 0.78, 1.0, 0.78 }, Handle = { 0.85, 1.0, 0.2 } },
		LuxPickaxe = {
			Glow = { 0.612, 0.19, 2.38 },
			Handle = { 0.36, 3.5, 0.468 },
			Head = { 0.62, 0.765, 2.52 },
		},
		MinersLamp = { Body = { 0.85, 1.728, 0.736 }, Glow = { 0.304, 0.304, 0.32 }, Handle = { 0.56, 1.098, 0.08 } },
		ObsidianPick = {
			Glow = { 0.19, 0.19, 2.17 },
			Handle = { 0.36, 3.5, 0.468 },
			Head = { 0.62, 0.765, 2.52 },
		},
		RopeLadder = { Body = { 1.6, 3.919, 0.329 } },
		RustyPick = { Handle = { 0.36, 3.1, 0.468 }, Head = { 0.62, 0.765, 2.52 } },
		SteelPick = { Handle = { 0.36, 3.4, 0.468 }, Head = { 0.62, 0.765, 2.52 } },
		WaderBoots = { Body = { 2.55, 2.615, 1.75 } },
	}

	t.test("every gear entry has its pieces and sizes from the audit, uploaded (no id 0)", function()
		local n = 0
		for id, pieces in pairs(SIZES) do
			n += 1
			local asset = BacklogModels.Get(id == "Lantern" and "GearLantern" or id)
			t.ok(asset ~= nil, id .. " is in BacklogModels")
			t.ok(GearMeshes.Offsets[id] ~= nil, id .. " has an offsets entry")
			for name, want in pairs(pieces) do
				local piece
				for _, p in ipairs(asset.pieces) do
					if p.name == name then
						piece = p
					end
				end
				t.ok(piece ~= nil, id .. "." .. name .. " exists")
				t.ok(piece.meshId ~= 0, id .. "." .. name .. " is uploaded")
				t.ok(
					math.abs(piece.size.X - want[1]) < 0.01
						and math.abs(piece.size.Y - want[2]) < 0.01
						and math.abs(piece.size.Z - want[3]) < 0.01,
					id .. "." .. name .. " size " .. tostring(piece.size)
				)
			end
			for name in pairs(GearMeshes.Offsets[id]) do
				t.ok(pieces[name] ~= nil, id .. " offsets name " .. name .. ", which the audit has")
			end
			t.ok(GearMeshes.Has(id), id .. " can be dressed")
		end
		t.eq(n, 18, "the audit's 18 gear entries (the Maul is an axe: AxeHeadPlacement)")
	end)

	t.test("every dressed piece lands at the root's centre + its offset (all 18, within 0.01)", function()
		withMeshes(function()
			for id, offsets in pairs(GearMeshes.Offsets) do
				local holder = Instance.new("Model")
				local handle = Instance.new("Part")
				handle.Name = "Handle"
				handle.Size = Vector3.new(0.3, 3, 0.3)
				handle.CFrame = CFrame.new(0, 1.5, 0)
				handle.Parent = holder
				t.ok(GearMeshes.Dress(holder, id), id .. " dresses")
				local root = holder:FindFirstChild("MeshHandle")
				t.ok(root ~= nil, id .. " has its root mesh")
				for name, at in pairs(offsets) do
					local mesh = holder:FindFirstChild("Mesh" .. name)
					t.ok(mesh ~= nil, id .. " has Mesh" .. name)
					local off = mesh.CFrame.Position - root.CFrame.Position
					t.ok((off - at).Magnitude < 0.01, id .. "." .. name .. " off by " .. tostring(off - at))
				end
			end
		end)
	end)

	t.test("the Miner's Lamp keeps its light: it moves onto the glow mesh", function()
		withMeshes(function()
			local tool = toolFrom(MiningArt.MinersLamp())
			local cage = tool:FindFirstChild("Cage")
			cage.Name = "Handle"
			t.ok(tool:FindFirstChild("LampLight", true) ~= nil, "built with a light")
			t.ok(GearMeshes.Dress(tool, "MinersLamp"))
			local light = tool:FindFirstChild("LampLight", true)
			t.ok(light ~= nil, "the light survived the dress")
			t.ok(light.Parent == tool:FindFirstChild("MeshGlow"), "on the glow mesh")
		end)
	end)

	t.test("the Bomb and the lamp are dressed by the service, with their root named Handle", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/ServerScriptService/MiningService.luau")
		t.ok(string.find(src, '"Bomb", "1", "Bomb")', 1, true))
		t.ok(string.find(src, '"MinersLamp", "1", "MinersLamp")', 1, true))
		t.ok(string.find(src, 'handle.Name = "Handle"', 1, true))
	end)
end
