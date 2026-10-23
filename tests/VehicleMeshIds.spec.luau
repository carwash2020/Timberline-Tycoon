--!nocheck
-- T421: VehicleMeshes keys are exactly the lines of assets/vehicles/t421/mesh_ids.txt (parsed here, so the file and the
-- code cannot drift), 54 of them, an empty id allowed.
return function(t)
	local fs = require("@lune/fs")
	local VehicleMeshes = t.load("ReplicatedStorage/Shared/Art/VehicleMeshes")

	local function parse(files)
		local out, order = {}, {}
		for _, file in ipairs(files or { "mesh_ids.txt", "truck_mesh_ids.txt" }) do
			for line in string.gmatch(fs.readFile("assets/vehicles/t421/" .. file), "[^\r\n]+") do
				local name, id = string.match(line, "^%s*([%w_]+)%s*=%s*(%d*)%s*$")
				t.ok(name, "bad line: " .. line)
				local key = string.gsub(name, "_", "/")
				out[key] = id
				table.insert(order, key)
			end
		end
		return out, order
	end

	t.test("mesh_ids.txt has the 54 T421 lines and truck_mesh_ids.txt the four trucks' 24", function()
		local _, order = parse({ "mesh_ids.txt" })
		t.eq(#order, 54)
		local _, trucks = parse({ "truck_mesh_ids.txt" })
		t.eq(#trucks, 24)
	end)

	t.test("VehicleMeshes has exactly the keys of the id files (54 + 24 = 78)", function()
		local fileIds, order = parse()
		local keys = VehicleMeshes.MeshKeys()
		t.eq(#keys, 78)
		local seen = {}
		for _, key in ipairs(keys) do
			seen[key] = true
			t.ok(fileIds[key] ~= nil, key .. " is not in mesh_ids.txt")
			t.ok(
				string.match(key, "^%a+/%a+/%a+$") ~= nil or string.match(key, "^%a+/%a+$") ~= nil,
				key .. " has a bad form"
			)
			t.eq(VehicleMeshes.MeshId(key), fileIds[key], key .. " id")
		end
		for _, key in ipairs(order) do
			t.ok(seen[key], key .. " is in mesh_ids.txt but not in VehicleMeshes")
		end
	end)

	t.test("an empty id is allowed and reads as missing", function()
		local missing = VehicleMeshes.MissingKeys()
		local fileIds = parse({ "mesh_ids.txt" })
		local empties = 0
		for _, id in pairs(fileIds) do
			if id == "" then
				empties += 1
			end
		end
		t.eq(#missing, empties, "every empty id of the 54 is reported")
		for _, key in ipairs(missing) do
			t.eq(VehicleMeshes.MeshId(key), "")
		end
	end)

	t.test("an unknown key has no id", function()
		t.eq(VehicleMeshes.MeshId("PonyTrailer/Nope/Body"), nil)
	end)
end
