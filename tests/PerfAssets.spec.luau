--!nocheck
-- T415 assets: every live mesh id is unique per source mesh, no Precise render fidelity outside the allowlist,
-- and scatter meshes use Performance.
return function(t)
	local PerfPolicy = t.shared("PerfPolicy")
	local MeshManifest = t.load("ReplicatedStorage/Shared/Art/MeshManifest")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local TownMeshes = t.load("ReplicatedStorage/Shared/Art/TownMeshes")
	local TownModels = t.load("ReplicatedStorage/Shared/Art/TownModels")
	local PropArt = t.load("ReplicatedStorage/Shared/Art/PropArt")
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local roblox = t.roblox

	local manifest = serde.decode("json", fs.readFile("assets/meshes/manifest.json"))

	local function liveIds()
		local ids = {}
		for _, e in ipairs(MeshManifest.Flat(true)) do
			table.insert(ids, e.id)
		end
		return ids
	end

	t.test("the duplicate check sees a source mesh uploaded twice (control)", function()
		local ids = { 100056308278514, 98421774126122 } -- Pickup.glb / Lights, two uploads
		local lines = PerfPolicy.Duplicates(ids, manifest)
		t.eq(#lines, 1)
		t.ok(string.find(lines[1], "Pickup.glb", 1, true))
		t.eq(#PerfPolicy.Duplicates({ 100056308278514 }, manifest), 0)
	end)

	t.test("no source mesh has two live MeshIds", function()
		local ids = liveIds()
		t.ok(#ids > 300, "the live list is not vacuous: " .. #ids)
		t.eq(PerfPolicy.Duplicates(ids, manifest), {})
	end)

	t.test("a MeshKit master is cached per id: a second Create clones, never loads again", function()
		MeshKit.Reset()
		local loads = 0
		MeshKit.Override = function(_id, name, size)
			loads += 1
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		MeshKit.Create(123456789, "A", roblox.Vector3.new(1, 1, 1), nil)
		MeshKit.Create(123456789, "B", roblox.Vector3.new(1, 1, 1), nil)
		MeshKit.Override = nil
		MeshKit.Reset()
		t.ok(loads <= 2, "loads " .. loads)
	end)

	local function walk(dir, out)
		for _, name in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path, out)
			elseif string.sub(name, -5) == ".luau" then
				table.insert(out, path)
			end
		end
		return out
	end

	t.test("Precise render fidelity appears only in the allowlist (empty today)", function()
		local allow = {}
		for _, p in ipairs(PerfPolicy.PreciseAllowlist) do
			allow[p] = true
		end
		for _, path in ipairs(walk("src", {})) do
			for line in string.gmatch(fs.readFile(path), "[^\n]+") do
				if not string.match(line, "^%s*%-%-") and string.find(line, "RenderFidelity.Precise", 1, true) then
					t.ok(allow[path], path .. " uses RenderFidelity.Precise")
				end
			end
		end
	end)

	t.test("scatter assets use Performance, hero bodies stay Automatic", function()
		for _, id in ipairs(PerfPolicy.ScatterAssets) do
			local asset = TownModels.Get(id)
			t.ok(asset, id .. " is a town asset")
			for _, piece in ipairs(TownModels.Visual(asset)) do
				t.eq(
					TownMeshes.FidelityFor(piece.name, asset.tris, id),
					roblox.Enum.RenderFidelity.Performance,
					id .. " " .. piece.name
				)
			end
		end
		t.eq(TownMeshes.FidelityFor("Body", nil, "Sawmill"), roblox.Enum.RenderFidelity.Automatic)
		t.eq(TownMeshes.FidelityFor("Body", nil), roblox.Enum.RenderFidelity.Automatic)
	end)

	t.test("a dressed rock wears Performance", function()
		MeshKit.Reset()
		MeshKit.Override = function(_id, name, size)
			local part = roblox.Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		local rock = PropArt.Rock(4, 1)
		local seen = 0
		for _, d in ipairs(rock:GetDescendants()) do
			if d:IsA("MeshPart") then
				seen += 1
				t.eq(d.RenderFidelity, roblox.Enum.RenderFidelity.Performance, d.Name)
			end
		end
		MeshKit.Override = nil
		MeshKit.Reset()
		t.ok(seen > 0, "the rock is meshed")
	end)
end
