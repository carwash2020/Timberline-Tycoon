--!nocheck
-- T417: Roblox game scripts cannot assign MeshPart.CollisionFidelity ("The current thread
-- cannot write 'CollisionFidelity' (lacking capability PluginOrOpenCloud)"). main did, in
-- MeshKit.finish (swallowed), VehicleMeshes.addRole (NOT swallowed: it aborted the whole
-- Dealership lot) and StumpMeshes (a warning per stump). Fidelity now comes from the
-- creation options (AssetService:CreateMeshPartAsync) or the uploaded asset itself.
-- Lune's MeshPart accepts the write (it is a real Instance, whose setter cannot be made to
-- throw), so this spec scans the source for an assignment instead.
return function(t)
	local fs = require("@lune/fs")

	local function walk(dir, out)
		for _, name in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				if name ~= "Vendor" then
					walk(path, out)
				end
			elseif string.match(name, "%.luau$") then
				table.insert(out, path)
			end
		end
		return out
	end

	t.test("no script under src/ assigns CollisionFidelity on a MeshPart", function()
		local seen = 0
		for _, path in ipairs(walk("src", {})) do
			local n = 0
			for line in string.gmatch(fs.readFile(path), "[^\n]+") do
				n += 1
				local code = string.gsub(line, "%-%-.*$", "")
				-- `x.CollisionFidelity = v` (a member write); `CollisionFidelity = v,` in a table is creation.
				if
					string.find(code, "[%w_%)%]]%.CollisionFidelity%s*=[^=]")
					and not string.find(line, "t417-seam", 1, true)
				then
					seen += 1
					t.ok(false, path .. ":" .. n .. " assigns CollisionFidelity: " .. line)
				end
			end
		end
		t.eq(seen, 0)
	end)

	t.test("MeshKit still asks for the fidelity at creation (the engine path's options)", function()
		local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
		local Enum = t.roblox.Enum
		MeshKit.Reset()
		local asked
		MeshKit.EngineLoad = function(_id, fidelity)
			asked = fidelity
			local part = t.roblox.Instance.new("MeshPart")
			part.Size = t.roblox.Vector3.new(1, 1, 1)
			return part, nil
		end
		local part = MeshKit.CreateAwait(424242, "Probe", t.roblox.Vector3.new(2, 2, 2), Enum.CollisionFidelity.Hull)
		MeshKit.EngineLoad = nil
		MeshKit.Reset()
		t.ok(part ~= nil, "a part came back")
		t.eq(asked, Enum.CollisionFidelity.Hull, "creation was asked for Hull")
	end)
end
