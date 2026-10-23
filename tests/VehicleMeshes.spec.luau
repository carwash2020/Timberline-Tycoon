--!nocheck
-- T390, the dealership trucks: a display truck and a bought truck are dressed by one path, in the
-- right order, and a mesh that cannot be had keeps the whole part-built vehicle.
--
--   HARD (must pass now)
--     1. every piece in VehicleModels has a mesh id;
--     4. the lot's display copy and the bought vehicle have the same mesh parts at the same offsets
--        (MeshKit.Override hands back fake templates), the display copy only scaled by its ceiling fit;
--     5. a mesh that is missing keeps the full part-built vehicle and says so ONCE (vehicle and part),
--        and a vehicle whose templates all load is never left on the fallback;
--     6. a copy marked Fitted refuses a late mesh (VehicleMeshes.Apply);
--     plus the order, the anchoring and the decoration of the display copy.
--
--   EXPECTED FAIL until Connor re-uploads the 38 stale vehicle meshes (assets/UPLOAD_LIST.md, "Vehicle
--   meshes: re-upload"), run with t.expectedFail so CI stays green while the failure is on record:
--     2. every VehicleModels mesh id has a row in ASSETS.md marked checked;
--     3. the cab, body, hood, fenders and bed (the Body, Glass, Lights and Bed pieces) stand within
--        0.05 stud of their `at` offsets and nothing floats above the chassis. The repo can only check
--        the offsets against the file they were measured from; the Roblox meshes behind the stale ids
--        are the OLD ones, so this stays failing until each stale id is replaced (the same ASSETS.md
--        table lists them).
--   The day the re-upload lands (new ids pasted, `lune run tools/assets`, rows checked) these two flip to
--   passing and the runner fails them as "now passes": change them to t.test then.
return function(t)
	local fs = require("@lune/fs")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local Gate = t.load("ReplicatedStorage/Shared/VehicleMeshGate")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local VehicleMeshes = t.load("ReplicatedStorage/Shared/Art/VehicleMeshes")
	local VehicleModels = t.load("ReplicatedStorage/Shared/Art/VehicleModels")
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local ItemCatalog = t.shared("ItemCatalog")
	local TruckLayout = t.shared("TruckLayout")
	local Instance = t.roblox.Instance

	local warnings = {}
	VehicleMeshes.Warn = function(message)
		table.insert(warnings, message)
	end

	local function templates()
		MeshKit.Reset()
		VehicleMeshes.ResetWarnings()
		table.clear(warnings)
		Gate.SetIds(Gate.FakeIds()) -- T421: trailers and the Timber Classic take their ids from the keyed table
		MeshKit.Override = function(id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
	end

	local function done()
		Gate.SetIds(nil)
		MeshKit.Override = nil
		MeshKit.Reset()
		VehicleMeshes.ResetWarnings()
	end

	local function withTemplates(fn)
		templates()
		local ok, err = pcall(fn)
		done()
		if not ok then
			error(err, 0)
		end
	end

	-- Every distinct piece table: each truck's, and each trailer's (the default and every truck's variant).
	local function allSpecs()
		local list, seen = {}, {}
		local function add(label, spec)
			if spec and not seen[spec] then
				seen[spec] = true
				table.insert(list, { label = label, spec = spec })
			end
		end
		for _, truck in pairs(ItemCatalog.Trucks) do
			if truck.id ~= "TimberClassic" then -- its ids are the TimberClassic/<Part> keys, not VehicleModels'
				add(truck.id, VehicleModels.Truck(truck.id))
			end
		end
		for _, trailer in pairs(ItemCatalog.Trailers) do
			add(trailer.id, VehicleModels.Trailer(trailer.id, nil))
			for _, truck in pairs(ItemCatalog.Trucks) do
				add(trailer.id .. " behind " .. truck.id, VehicleModels.Trailer(trailer.id, truck.id))
			end
		end
		return list
	end

	local function meshParts(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d:GetAttribute("VisualMesh") == true then
				table.insert(out, d)
			end
		end
		return out
	end

	local function partCount(model)
		local n = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		return n
	end

	local function bedOf(model)
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "TrailerBed" then
				return d
			end
		end
		return nil
	end

	---------------------------------------------------------------------------
	-- 1. HARD: no piece has mesh id 0
	---------------------------------------------------------------------------

	t.test("every piece in VehicleModels has a mesh id (none is 0)", function()
		local rows = 0
		for _, entry in ipairs(allSpecs()) do
			for role, piece in pairs(entry.spec) do
				rows += 1
				t.ok(
					type(piece.meshId) == "number" and piece.meshId ~= 0,
					entry.label .. " " .. role .. " has mesh id " .. tostring(piece.meshId)
				)
			end
		end
		t.ok(rows >= 90, "the walk found the pieces: " .. rows)
	end)

	---------------------------------------------------------------------------
	-- 2. EXPECTED FAIL: every mesh id has a checked row in ASSETS.md
	---------------------------------------------------------------------------

	local function assetsRows()
		local rows = {}
		for _, line in ipairs(string.split(fs.readFile("ASSETS.md"), "\n")) do
			local id, status = string.match(line, "^| (%d+) | .- | %d+ | (.-) |$")
			if id then
				rows[tonumber(id)] = status
			end
		end
		return rows
	end

	local function isChecked(status)
		return status ~= nil
			and string.find(status, "checked", 1, true) ~= nil
			and string.find(status, "not checked yet", 1, true) == nil
			and string.find(status, "needs re-upload", 1, true) == nil
	end

	t.expectedFail("every VehicleModels mesh id has a row in ASSETS.md marked checked", function()
		local rows = assetsRows()
		local unchecked, total, seen = {}, 0, {}
		for _, entry in ipairs(allSpecs()) do
			for role, piece in pairs(entry.spec) do
				if not seen[piece.meshId] then
					seen[piece.meshId] = true
					total += 1
					if not isChecked(rows[piece.meshId]) then
						table.insert(unchecked, tostring(piece.meshId) .. " (" .. entry.label .. " " .. role .. ")")
					end
				end
			end
		end
		t.ok(total >= 40, "the walk found the ids: " .. total)
		t.eq(#unchecked, 0, #unchecked .. " of " .. total .. " vehicle mesh ids are not marked checked")
	end, "the 38 stale vehicle meshes need Connor's re-upload (assets/UPLOAD_LIST.md), then the ASSETS.md check")

	---------------------------------------------------------------------------
	-- 3. EXPECTED FAIL: the body pieces stand at their `at` offsets, on the new uploads
	---------------------------------------------------------------------------

	local ROLE_PART =
		{ Body = "MeshBody", Glass = "MeshGlass", Lights = "MeshLights", Bed = "MeshBed", Hitch = "MeshHitch" }

	t.expectedFail(
		"cab, body, hood, fenders and bed stand within 0.05 stud of their `at` offsets; nothing floats",
		function()
			withTemplates(function()
				for _, def in ipairs(ItemCatalog.TruckList()) do
					local spec = VehicleModels.Truck(def.id)
					if spec == nil then
						continue
					end
					local model = TruckArt.Build(def)
					t.ok(model:GetAttribute("VehicleMesh") == true, def.id .. " is meshed")
					local chassis = model:FindFirstChild("Chassis", true)
					local chassisTop = chassis.CFrame.Position.Y + chassis.Size.Y / 2
					for role, partName in pairs(ROLE_PART) do
						local piece = spec[role]
						if piece == nil then
							continue
						end
						local part = model:FindFirstChild(partName, true)
						t.ok(part, def.id .. " has " .. partName)
						t.ok(
							(part.CFrame.Position - piece.at).Magnitude <= 0.05,
							def.id
								.. " "
								.. role
								.. " is "
								.. (part.CFrame.Position - piece.at).Magnitude
								.. " from its `at`"
						)
						-- nothing floats: the body stands on the chassis, every other piece reaches the body
						local bodyPart = model:FindFirstChild("MeshBody", true)
						local supportTop = if role == "Body"
							then chassisTop
							else bodyPart.CFrame.Position.Y + bodyPart.Size.Y / 2
						t.ok(
							part.CFrame.Position.Y - part.Size.Y / 2 <= supportTop,
							def.id .. " " .. role .. " floats above its support"
						)
					end
				end
			end)
			-- the file the offsets were measured from is only half the answer: a stale upload is the OLD mesh
			local stale = {}
			for line in string.gmatch(fs.readFile("ASSETS.md"), "[^\n]+") do
				local id, node, who = string.match(
					line,
					"^| (%d+) | `assets/meshes/vehicles/[^`]+` | (%w+) | (%w+) | new GLB in repo, needs re%-upload |$"
				)
				if id and node ~= "Wheel" and node ~= "Hitch" then
					table.insert(stale, id .. " " .. who .. " " .. node)
				end
			end
			t.eq(
				#stale,
				0,
				#stale .. " body/bed/lights uploads are still the old meshes (first: " .. tostring(stale[1]) .. ")"
			)
		end,
		"the body, bed and lights uploads are the old meshes until Connor re-uploads (assets/UPLOAD_LIST.md)"
	)

	---------------------------------------------------------------------------
	-- 4. HARD: the display copy and the bought vehicle are the same, part for part
	---------------------------------------------------------------------------

	local function keyOf(part, bed)
		-- a trailer's pieces are measured from its bed's middle, a truck's from the origin
		local trailer = part:GetAttribute("RigHalf") == "trailer"
		local rel = if trailer and bed then part.CFrame.Position - bed.CFrame.Position else part.CFrame.Position
		return part.Name .. (if trailer then "/trailer" else "/truck"), rel
	end

	local function describe(model)
		local bed = bedOf(model)
		local out = {}
		for _, p in ipairs(meshParts(model)) do
			local key, rel = keyOf(p, bed)
			out[key] = out[key] or {}
			table.insert(out[key], { pos = rel, size = p.Size })
		end
		for _, list in pairs(out) do
			table.sort(list, function(a, b)
				if a.pos.X ~= b.pos.X then
					return a.pos.X < b.pos.X
				end
				return a.pos.Z < b.pos.Z
			end)
		end
		return out
	end

	-- `scale` is the display copy's ceiling fit (1 unless the vehicle was too tall).
	local function same(display, bought, scale, label)
		local a, b = describe(display), describe(bought)
		for key, list in pairs(b) do
			t.ok(a[key] ~= nil, label .. " display copy has " .. key)
			t.eq(#a[key], #list, label .. " " .. key .. " count")
			for i, want in ipairs(list) do
				local got = a[key][i]
				t.ok(
					(got.pos / scale - want.pos).Magnitude <= 0.05,
					label .. " " .. key .. " #" .. i .. " is off by " .. (got.pos / scale - want.pos).Magnitude
				)
			end
		end
		for key in pairs(a) do
			t.ok(b[key] ~= nil, label .. " bought vehicle has " .. key)
		end
	end

	t.test("a display truck and a bought truck have the same mesh parts at the same offsets", function()
		withTemplates(function()
			for _, def in ipairs(ItemCatalog.TruckList()) do
				if VehicleModels.Truck(def.id) == nil then
					continue
				end
				local bought = TruckArt.Build(def, TruckLayout.For(def))
				local display = DealershipLot.Vehicle("Truck", def.id)
				t.ok(display and display:GetAttribute("VehicleMesh") == true, def.id .. " display copy is meshed")
				t.ok(bought:GetAttribute("VehicleMesh") == true, def.id .. " bought truck is meshed")
				local scale = 1
				local db, bb = display:FindFirstChild("MeshBody", true), bought:FindFirstChild("MeshBody", true)
				if db and bb then
					scale = db.Size.Y / bb.Size.Y
				end
				same(display, bought, scale, def.id)
				t.ok(scale <= 1 and scale > 0.5, def.id .. " fit scale " .. scale)
			end
		end)
	end)

	t.test("a display trailer and a bought trailer have the same mesh parts at the same offsets", function()
		withTemplates(function()
			local pickup = ItemCatalog.GetTruck("Pickup")
			for _, trailer in ipairs(ItemCatalog.TrailerList()) do
				local lay = TruckLayout.ForTrailer(trailer, TruckLayout.For(pickup))
				local bought = TruckArt.Build(pickup, TruckLayout.For(pickup), trailer, lay)
				local display = DealershipLot.Vehicle("Trailer", trailer.id)
				t.ok(
					display and display:GetAttribute("VehicleMesh") == true,
					trailer.id .. " display trailer is meshed"
				)
				local boughtTrailer = {}
				for _, p in ipairs(meshParts(bought)) do
					if p:GetAttribute("RigHalf") == "trailer" then
						table.insert(boughtTrailer, p)
					end
				end
				t.ok(#boughtTrailer >= 3, trailer.id .. " bought trailer has mesh pieces")
				local a, b = describe(display), describe(bought)
				for key, list in pairs(b) do
					if string.find(key, "/trailer", 1, true) then
						t.ok(a[key] ~= nil, trailer.id .. " display trailer has " .. key)
						t.eq(#a[key], #list, trailer.id .. " " .. key .. " count")
						for i, want in ipairs(list) do
							t.ok(
								(a[key][i].pos - want.pos).Magnitude <= 0.05,
								trailer.id
									.. " "
									.. key
									.. " #"
									.. i
									.. " is off by "
									.. (a[key][i].pos - want.pos).Magnitude
							)
						end
					end
				end
				for key in pairs(a) do
					t.ok(b[key] ~= nil, trailer.id .. " bought trailer has " .. key)
				end
			end
		end)
	end)

	t.test("the display copy is meshed first, fitted after, and every mesh piece is anchored decoration", function()
		withTemplates(function()
			local lot = DealershipLot.Build()
			local seen = 0
			for _, d in ipairs(lot:GetChildren()) do
				if d:IsA("Model") and d:GetAttribute("ItemId") ~= nil then
					seen += 1
					t.eq(d:GetAttribute("VehicleMesh"), true, d.Name .. " is meshed")
					t.eq(d:GetAttribute("Fitted"), true, d.Name .. " was fitted after the meshes")
					local pieces = meshParts(d)
					t.ok(#pieces >= 3, d.Name .. " has mesh pieces: " .. #pieces)
					for _, p in ipairs(pieces) do
						t.eq(p.Anchored, true, d.Name .. " " .. p.Name .. " is anchored")
						t.eq(p.CanCollide, false, d.Name .. " " .. p.Name .. " CanCollide")
						t.eq(p.CanQuery, false, d.Name .. " " .. p.Name .. " CanQuery")
						t.eq(p.CanTouch, false, d.Name .. " " .. p.Name .. " CanTouch")
						t.eq(p.CastShadow, false, d.Name .. " " .. p.Name .. " CastShadow")
					end
				end
			end
			t.eq(seen, #DealershipLot.Layout().bays, "every bay holds a vehicle model")
		end)
	end)

	---------------------------------------------------------------------------
	-- 5. HARD: a missing mesh keeps the whole part-built vehicle, with one warning
	---------------------------------------------------------------------------

	t.test(
		"a missing template keeps the full part-built truck and warns once, naming the truck and the part",
		function()
			local rust = ItemCatalog.GetTruck("Rustbucket")
			templates()
			local missingId = tonumber(Gate.IdOf("trucks/Rustbucket/Bed")) -- the keyed id is the one the truck uses (T421)
			MeshKit.Override = function(id, name, size)
				if id == missingId then
					return nil
				end
				local part = Instance.new("MeshPart")
				part.Name = name
				part.Size = size
				return part
			end
			-- what part-built looks like: every id missing
			local reference
			do
				local saved = MeshKit.Override
				MeshKit.Override = function()
					return nil
				end
				reference = TruckArt.Build(rust)
				MeshKit.Reset()
				VehicleMeshes.ResetWarnings()
				table.clear(warnings)
				MeshKit.Override = saved
			end
			local first = TruckArt.Build(rust)
			local second = TruckArt.Build(rust)
			t.eq(first:GetAttribute("VehicleMesh"), nil, "not meshed")
			t.eq(#meshParts(first), 0, "no mesh piece was placed")
			t.eq(partCount(first), partCount(reference), "the full part-built truck is kept, part for part")
			t.ok(
				first:FindFirstChild("BedFloor", true) ~= nil and first:FindFirstChild("DriverSeat", true) ~= nil,
				"its bed and seat are still there"
			)
			t.eq(#meshParts(second), 0)
			t.eq(
				#warnings,
				1,
				"one warning for the truck, however often it is built: " .. table.concat(warnings, " | ")
			)
			t.ok(string.find(warnings[1], "Rustbucket", 1, true), "it names the truck")
			t.ok(string.find(warnings[1], "Bed", 1, true), "and the part")
			done()
		end
	)

	t.test("a vehicle whose templates all load is never left on the fallback", function()
		withTemplates(function()
			for _, def in ipairs(ItemCatalog.TruckList()) do
				if VehicleModels.Truck(def.id) == nil then
					continue
				end
				local model = TruckArt.Build(def)
				t.eq(model:GetAttribute("VehicleMesh"), true, def.id .. " fell back although every template loads")
			end
			t.eq(#warnings, 0, "and nothing was warned: " .. table.concat(warnings, " | "))
		end)
	end)

	---------------------------------------------------------------------------
	-- 6. HARD: a fitted copy refuses a late mesh
	---------------------------------------------------------------------------

	t.test("a copy marked Fitted is refused by Apply", function()
		local rust = ItemCatalog.GetTruck("Rustbucket")
		templates()
		-- part-built first (nothing loads), then the meshes become available
		MeshKit.Override = function()
			return nil
		end
		local model = TruckArt.Build(rust)
		MeshKit.Reset()
		VehicleMeshes.ResetWarnings()
		table.clear(warnings)
		MeshKit.Override = function(id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			return part
		end
		model:SetAttribute("Fitted", true)
		t.eq(VehicleMeshes.Apply(model, "Rustbucket", nil), false, "refused")
		t.eq(#meshParts(model), 0, "nothing was placed on it")
		t.eq(model:GetAttribute("VehicleMesh"), nil)
		t.eq(#warnings, 1, "and it says so once")
		-- the same copy without the mark takes the meshes
		model:SetAttribute("Fitted", nil)
		t.eq(VehicleMeshes.Apply(model, "Rustbucket", nil), true, "an unfitted copy is dressed")
		t.ok(#meshParts(model) >= 4)
		done()
	end)

	t.test("DealershipLot's fit marks every copy Fitted, scaled or not", function()
		withTemplates(function()
			for _, bay in ipairs(DealershipLot.Layout().bays) do
				local model = DealershipLot.Vehicle(bay.kind, bay.id)
				t.eq(model:GetAttribute("Fitted"), true, bay.id)
			end
		end)
	end)
end
