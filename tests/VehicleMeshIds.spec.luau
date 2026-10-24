--!nocheck
-- T421: VehicleMeshes keys are exactly the lines of assets/vehicles/t421/mesh_ids.txt, Connor's 78-line file as supplied
-- (parsed here, so the file and the code cannot drift): 48 trailer lines, 6 Timber Classic lines and 24
-- trucks/<Truck>/<Part> lines. An empty id is allowed and stays an empty string.
return function(t)
	local fs = require("@lune/fs")
	local process = require("@lune/process")
	local VehicleMeshes = t.load("ReplicatedStorage/Shared/Art/VehicleMeshes")

	-- The file as Connor wrote it: '#' comment lines, then `name = id` (an empty id, a trailing space). Trailers and the
	-- Timber Classic use underscores (PonyTrailer_Pickup_Body), the four trucks the slash form (trucks/Pickup/Body).
	local function parse()
		local out, order = {}, {}
		for line in string.gmatch(fs.readFile("assets/vehicles/t421/mesh_ids.txt"), "[^\r\n]+") do
			if string.match(line, "^%s*#") or string.match(line, "^%s*$") then
				continue
			end
			local name, id = string.match(line, "^%s*([%w_/]+)%s*=%s*(%d*)%s*$")
			t.ok(name, "bad line: " .. line)
			local key = if string.find(name, "/", 1, true) then name else (string.gsub(name, "_", "/"))
			out[key] = id
			table.insert(order, key)
		end
		return out, order
	end

	t.test("mesh_ids.txt holds 78 lines: 48 trailer + 6 Timber Classic + 24 trucks/<Truck>/<Part>", function()
		local _, order = parse()
		t.eq(#order, 78)
		local trailers, classic, trucks = 0, 0, 0
		for _, key in ipairs(order) do
			if string.sub(key, 1, 7) == "trucks/" then
				trucks += 1
			elseif string.sub(key, 1, 14) == "TimberClassic/" then
				classic += 1
			else
				trailers += 1
				t.ok(string.match(key, "^%a+/%a+/%a+$") ~= nil, key .. " is <Trailer>/<Truck>/<Part>")
			end
		end
		t.eq({ trailers, classic, trucks }, { 48, 6, 24 })
		t.eq(fs.isFile("assets/vehicles/t421/truck_mesh_ids.txt"), false, "the stand-in truck file is gone")
	end)

	t.test(
		"the REAL file through the generator: --check passes and the module has exactly 78 keys, 48 + 6 + 24",
		function()
			local result = process.exec("lune", { "run", "tools/gen_vehicle_mesh_ids", "--check" })
			t.ok(result.ok, "generator check: " .. result.stdout .. result.stderr)
			local keys = VehicleMeshes.MeshKeys()
			t.eq(#keys, 78)
			local trucks, classic, trailers, empties = 0, 0, 0, 0
			for _, key in ipairs(keys) do
				if string.sub(key, 1, 7) == "trucks/" then
					trucks += 1
				elseif string.sub(key, 1, 14) == "TimberClassic/" then
					classic += 1
				else
					trailers += 1
				end
				if VehicleMeshes.MeshId(key) == "" then
					empties += 1
				end
			end
			t.eq({ trailers, classic, trucks }, { 48, 6, 24 }, "the truck keys stay trucks/<Truck>/<Part>")
			local fileEmpties = 0
			for _, id in pairs((parse())) do
				if id == "" then
					fileEmpties += 1
				end
			end
			t.eq(empties, fileEmpties, "an empty id stays an empty string")
		end
	)

	t.test("VehicleMeshes has exactly the keys of the file, each with the file's id", function()
		local fileIds, order = parse()
		local keys = VehicleMeshes.MeshKeys()
		t.eq(#keys, 78)
		local seen = {}
		for _, key in ipairs(keys) do
			seen[key] = true
			t.ok(fileIds[key] ~= nil, key .. " is not in mesh_ids.txt")
			t.eq(VehicleMeshes.MeshId(key), fileIds[key], key .. " id")
		end
		for _, key in ipairs(order) do
			t.ok(seen[key], key .. " is in mesh_ids.txt but not in VehicleMeshes")
		end
	end)

	t.test("an empty id reads as missing: the T421 keys with no id are reported", function()
		local missing = VehicleMeshes.MissingKeys()
		local fileIds = parse()
		local empties = 0
		for key, id in pairs(fileIds) do
			if id == "" and string.sub(key, 1, 7) ~= "trucks/" then
				empties += 1
			end
		end
		t.eq(#missing, empties, "every empty id of the 54 T421 meshes is reported (the trucks' are optional)")
		for _, key in ipairs(missing) do
			t.eq(VehicleMeshes.MeshId(key), "")
		end
	end)

	t.test("an unknown key has no id", function()
		t.eq(VehicleMeshes.MeshId("PonyTrailer/Nope/Body"), nil)
	end)
end
