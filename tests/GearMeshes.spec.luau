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
		t.ok(not GearMeshes.Has("Bomb"), "an id without offsets is not dressed")
		t.ok(not GearMeshes.Has("NoSuchGear"))
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
				t.ok((off - GearMeshes.At[id].Head).Magnitude < 0.01, id .. " head off by " .. tostring(off))
				if GearMeshes.At[id].Glow then
					local glow = tool:FindFirstChild("MeshGlow")
					t.ok(glow ~= nil, id .. " has its glow")
					local g = glow.CFrame.Position - handleMesh.CFrame.Position
					t.ok((g - GearMeshes.At[id].Glow).Magnitude < 0.01, id .. " glow off by " .. tostring(g))
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
end
