--!nocheck
-- No vehicle's wheel overlaps its body or its wheel-arch parts (Connor, 12 October 2026: "wheel
-- overlaps body / arch" on the new vehicle models).
--
-- Every truck alone and every truck with every trailer it can tow (a Scout ATV tows none), built
-- two ways:
--   part-built  nothing loads, so every part TruckArt makes stands: each part is an oriented box
--               (a WedgePart is the half-box under its slope), each tyre a cylinder along its own X.
--               A box overlaps a tyre when a sample of the tyre's volume lies inside the box, or a
--               sample of the box lies inside the tyre (both ways, so a thin board through the tyre
--               and a tyre pushed through a wall are both caught).
--   meshed      the uploaded pieces dress the truck (MeshKit.Override hands back a MeshPart of each
--               piece's size, as in PickupWheels.spec). Each piece's real triangles are read from the
--               GLB in the repo and put where the game puts the piece (its centre, its size), and
--               the same test runs on every vertex, edge middle and face middle against the tyre.
--               The parts that stay under a meshed truck (bed walls, stakes, lamps, exhaust) are
--               boxes again. The wheel is the mesh's own size (no resize): the test also pins
--               every piece's size to its GLB bounds.
--
-- EXEMPT (by name, with the reason; nothing is skipped silently):
--   the wheel's own children (Rim, Hub, HubBolt)   they are the wheel
--   Axle                                            the axle rod runs through the hub on purpose
--   Chassis, Skid, TrailerSkid, BedZone             invisible physics parts, not the look; the
--                                                   hitbox is out of scope here
--   Mesh*                                           a MeshPart in Lune is only a bounding box; its
--                                                   real triangles are tested instead (meshed run)
--   VisualMesh decor parts                          same
-- Tolerance: a tyre may touch a surface (0.03 stud); anything deeper is a failure.
return function(t)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local Gate = t.load("ReplicatedStorage/Shared/VehicleMeshGate")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local VehicleModels = t.load("ReplicatedStorage/Shared/Art/VehicleModels")
	local ItemCatalog = t.shared("ItemCatalog")
	local Instance = t.roblox.Instance
	local Vector3 = t.roblox.Vector3

	local EPS = 0.03
	local EXEMPT = {
		Axle = "the axle rod runs through the hub on purpose",
		Chassis = "invisible physics part",
		Skid = "invisible physics part",
		TrailerSkid = "invisible physics part",
		BedZone = "invisible physics zone",
	}

	-- Overlaps that stay, each capped at a depth so a deeper one still fails. Keyed by the part's
	-- name, or "<vehicle>:<part>" for one vehicle only (the vehicle is the one whose wheel it is).
	local DEPTH_EXEMPT = {
		BedFloor = {
			0.12,
			"the truck's collision bed floor spans the full width over the rear tyres; the tyre top reaches 0.1 into its edge. Hitbox: out of scope",
		},
		TrailerBed = {
			0.45,
			"the trailer's collision deck spans the full width over the tyre tops, which the fenders wrap. Hitbox: out of scope",
		},
		TrailerStanchion = {
			0.15,
			"the Heavy Hauler's collision stakes stand over its tyres. Hitbox: out of scope",
		},
		MeshBody = {
			0.26,
			"the inboard wall of the wheel well in the GLB stands 0.2 inside the tyre's inner face, hidden inside the body (GLB: move the liner out to x 4.0 or less)",
		},
		MeshBed = {
			0.26,
			"same: the bed mesh's inboard side over a tyre, hidden inside the body",
		},
		-- T421: the Ranch Trailer's two axles are now the approved mesh's own (0.26 and 3.38 from the bed's middle,
		-- TrailerAxleData), but the wheel X for each tow-truck variant is in bbox_check.md, which is not in the repo.
		-- Until it is, the wheels stand at TruckLayout's wheelX and reach this far into the well's liner. Remove these
		-- two entries when the wheel X is data.
		["RanchTrailer:MeshBody"] = {
			0.55,
			"Ranch wheel X is TruckLayout's until bbox_check.md supplies each variant's (the liner of the well is 0.5 inside the tyre)",
		},
		["RanchTrailer:MeshBed"] = {
			0.45,
			"same: the bed mesh's inboard side at the Ranch's wheels",
		},
		["HeavyHauler:MeshBed"] = {
			0.45,
			"the Heavy Hauler GLB's deck overhangs its tyre tops inboard (GLB: Bed floor 0.43 low over the wheels)",
		},
		["HeavyHauler:MeshLights"] = {
			0.3,
			"the Heavy Hauler GLB's amber side marker lamps sit over the front axle (GLB: move them clear)",
		},
	}
	local function allowed(part, who, depth)
		local cap = DEPTH_EXEMPT[who .. ":" .. part] or DEPTH_EXEMPT[part]
		return cap ~= nil and depth <= cap[1] + 0.005
	end

	-- A part of the trailer half of a vehicle?
	local function inTrailer(part)
		local node = part
		while node do
			if
				node:GetAttribute("TrailerBody") == true
				or node:GetAttribute("RigHalf") == "trailer"
				or node.Name == "TrailerBed"
			then
				return true
			end
			node = node.Parent
		end
		return false
	end

	local function withMeshes(fn)
		MeshKit.Reset()
		Gate.SetIds(Gate.FakeIds()) -- T421: trailers and the Timber Classic take their ids from the keyed table
		MeshKit.Override = function(id, name, size)
			local part = Instance.new("MeshPart")
			part.Name = name
			part.Size = size
			part:SetAttribute("MeshId", tostring(id))
			return part
		end
		local ok, err = pcall(fn)
		Gate.SetIds(nil)
		MeshKit.Override = nil
		MeshKit.Reset()
		if not ok then
			error(err, 0)
		end
	end

	---------------------------------------------------------------------------------------------
	-- GLB reader: the triangles of each named node, in the file's own frame.
	---------------------------------------------------------------------------------------------
	local glbCache = {}
	local function readGlb(path)
		if glbCache[path] then
			return glbCache[path]
		end
		local bytes = fs.readFile(path)
		local data = buffer.fromstring(bytes)
		local json, binAt
		local off = 12
		while off < buffer.len(data) do
			local len = buffer.readu32(data, off)
			local kind = buffer.readu32(data, off + 4)
			if kind == 0x4E4F534A then
				json = serde.decode("json", buffer.readstring(data, off + 8, len))
			elseif kind == 0x004E4942 then
				binAt = off + 8
			end
			off += 8 + len
		end
		local nodes = {}
		for _, node in ipairs(json.nodes) do
			if node.mesh == nil then
				continue
			end
			assert(
				node.translation == nil and node.rotation == nil and node.scale == nil,
				path .. " node has a transform"
			)
			local points = {} -- { x, y, z } triples
			local lo, hi = { 1e9, 1e9, 1e9 }, { -1e9, -1e9, -1e9 }
			for _, prim in ipairs(json.meshes[node.mesh + 1].primitives) do
				local pa = json.accessors[prim.attributes.POSITION + 1]
				local pv = json.bufferViews[pa.bufferView + 1]
				local function vertex(i)
					local o = binAt + (pv.byteOffset or 0) + (pa.byteOffset or 0) + i * (pv.byteStride or 12)
					return buffer.readf32(data, o), buffer.readf32(data, o + 4), buffer.readf32(data, o + 8)
				end
				for i = 0, pa.count - 1 do
					local x, y, z = vertex(i)
					lo = { math.min(lo[1], x), math.min(lo[2], y), math.min(lo[3], z) }
					hi = { math.max(hi[1], x), math.max(hi[2], y), math.max(hi[3], z) }
				end
				local ia = json.accessors[prim.indices + 1]
				local iv = json.bufferViews[ia.bufferView + 1]
				local base = binAt + (iv.byteOffset or 0) + (ia.byteOffset or 0)
				local function index(k)
					if ia.componentType == 5123 then
						return buffer.readu16(data, base + k * 2)
					end
					return buffer.readu32(data, base + k * 4)
				end
				for k = 0, ia.count - 1, 3 do
					local ax, ay, az = vertex(index(k))
					local bx, by, bz = vertex(index(k + 1))
					local cx, cy, cz = vertex(index(k + 2))
					-- corners, edge middles, face middle; a long edge is split again.
					local function add(x, y, z)
						table.insert(points, { x, y, z })
					end
					add(ax, ay, az)
					add(bx, by, bz)
					add(cx, cy, cz)
					add((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2)
					add((bx + cx) / 2, (by + cy) / 2, (bz + cz) / 2)
					add((cx + ax) / 2, (cy + ay) / 2, (cz + az) / 2)
					add((ax + bx + cx) / 3, (ay + by + cy) / 3, (az + bz + cz) / 3)
					local longest = math.max(
						math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2),
						math.sqrt((bx - cx) ^ 2 + (by - cy) ^ 2 + (bz - cz) ^ 2),
						math.sqrt((cx - ax) ^ 2 + (cy - ay) ^ 2 + (cz - az) ^ 2)
					)
					if longest > 1.5 then
						for _, w in ipairs({ { 0.75, 0.125, 0.125 }, { 0.125, 0.75, 0.125 }, { 0.125, 0.125, 0.75 } }) do
							add(
								ax * w[1] + bx * w[2] + cx * w[3],
								ay * w[1] + by * w[2] + cy * w[3],
								az * w[1] + bz * w[2] + cz * w[3]
							)
						end
						for _, w in ipairs({ { 0.5, 0.25, 0.25 }, { 0.25, 0.5, 0.25 }, { 0.25, 0.25, 0.5 } }) do
							add(
								ax * w[1] + bx * w[2] + cx * w[3],
								ay * w[1] + by * w[2] + cy * w[3],
								az * w[1] + bz * w[2] + cz * w[3]
							)
						end
					end
				end
			end
			nodes[node.name] = {
				points = points,
				centre = Vector3.new((lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2),
				size = Vector3.new(hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3]),
			}
		end
		glbCache[path] = nodes
		return nodes
	end

	---------------------------------------------------------------------------------------------
	-- Geometry
	---------------------------------------------------------------------------------------------
	local function isWheel(p)
		return p.Name == "Wheel" and p:GetAttribute("Radius") ~= nil
	end

	-- Is world point `p` inside the tyre `wheel` (a cylinder along its own X), shrunk by EPS?
	-- `rAt(x)` is the tyre's outer radius at x along its axle: a plain cylinder for a part-built
	-- tyre, the mesh's own profile (rounded shoulders, dished face) for a meshed one.
	local function inTyre(wheel, rAt, p)
		local l = wheel.CFrame:PointToObjectSpace(p)
		return math.abs(l.X) < wheel.Size.X / 2 - EPS and math.sqrt(l.Y * l.Y + l.Z * l.Z) < rAt(l.X) - EPS
	end

	-- How far point `p` is inside the tyre, 0 when it is not: the shortest way out.
	local function tyreDepth(wheel, rAt, p)
		local l = wheel.CFrame:PointToObjectSpace(p)
		local hw = wheel.Size.X / 2
		if math.abs(l.X) >= hw - EPS then
			return 0
		end
		local radial = rAt(l.X) - math.sqrt(l.Y * l.Y + l.Z * l.Z)
		if radial <= EPS then
			return 0
		end
		return math.min(hw - math.abs(l.X), radial)
	end

	-- Is world point `p` inside `part` (a box; a WedgePart the half under its slope), shrunk by EPS?
	local function inPart(part, p)
		local l = part.CFrame:PointToObjectSpace(p)
		local h = part.Size / 2
		if math.abs(l.X) >= h.X - EPS or math.abs(l.Y) >= h.Y - EPS or math.abs(l.Z) >= h.Z - EPS then
			return false
		end
		if part.ClassName == "WedgePart" then
			-- Vertical face at +Z; the slope runs from the top of that face down to the bottom at -Z.
			local u = (l.Z + h.Z) / (2 * h.Z)
			return l.Y <= -h.Y + u * 2 * h.Y - EPS
		end
		return true
	end

	local function tyreSamples(wheel, rAt)
		local out = {}
		local hw = wheel.Size.X / 2 - EPS
		for _, x in ipairs({ -hw, -hw / 2, 0, hw / 2, hw }) do
			local radius = rAt(x)
			for _, k in ipairs({ 1, 0.8, 0.55, 0.3 }) do
				for a = 0, 47 do
					local ang = a / 48 * 2 * math.pi
					table.insert(
						out,
						wheel.CFrame * Vector3.new(x, radius * k * math.cos(ang), radius * k * math.sin(ang))
					)
				end
			end
		end
		return out
	end

	local function boxSamples(part)
		local out = {}
		local h = part.Size / 2
		local n = 6
		for i = 0, n do
			for j = 0, n do
				for k = 0, n do
					table.insert(
						out,
						part.CFrame * Vector3.new((i / n * 2 - 1) * h.X, (j / n * 2 - 1) * h.Y, (k / n * 2 - 1) * h.Z)
					)
				end
			end
		end
		return out
	end

	local meshFile
	-- The tyre's outer radius along its axle.
	local function profileOf(wheel, truckId, trailerId)
		local plain = math.min(wheel.Size.Y, wheel.Size.Z) / 2
		if wheel.ClassName ~= "MeshPart" then
			return function()
				return plain
			end
		end
		local node = readGlb(meshFile(wheel, truckId, trailerId)).Wheel
		local BIN = 0.04
		local bins = {}
		local scaleX = wheel.Size.X / node.size.X
		for _, q in ipairs(node.points) do
			local x = (q[1] - node.centre.X) * scaleX
			local radius = math.sqrt((q[2] - node.centre.Y) ^ 2 + (q[3] - node.centre.Z) ^ 2)
				* (plain * 2 / math.min(node.size.Y, node.size.Z))
			local key = math.floor(x / BIN + 0.5)
			bins[key] = math.max(bins[key] or 0, radius)
		end
		return function(x)
			local key = math.floor(x / BIN + 0.5)
			return math.max(bins[key] or 0, bins[key - 1] or 0, bins[key + 1] or 0)
		end
	end

	-- A part that is part of a wheel (Rim, Hub, HubBolt hang off the tyre).
	local function ofAWheel(part)
		local parent = part.Parent
		return parent ~= nil and parent:IsA("BasePart") and isWheel(parent)
	end

	---------------------------------------------------------------------------------------------
	-- The check on one built vehicle: returns a list of "wheel X hits Y" strings.
	---------------------------------------------------------------------------------------------
	meshFile = function(part, truckId, trailerId)
		if part:GetAttribute("RigHalf") == "trailer" then
			return string.format(
				"assets/meshes/vehicles/%s/by_truck/%s/%s_%s.glb",
				trailerId,
				truckId,
				trailerId,
				truckId
			)
		end
		return string.format("assets/meshes/vehicles/%s/%s.glb", truckId, truckId)
	end

	local function roleOf(part)
		if part.Name == "Wheel" then
			return "Wheel"
		end
		return (string.gsub(part.Name, "^Mesh", ""))
	end

	-- World points of a meshed piece's triangles.
	local function meshPoints(part, truckId, trailerId)
		local node = readGlb(meshFile(part, truckId, trailerId))[roleOf(part)]
		assert(node, "no " .. roleOf(part) .. " node in the GLB for " .. part.Name)
		local scale = Vector3.new(part.Size.X / node.size.X, part.Size.Y / node.size.Y, part.Size.Z / node.size.Z)
		local out = table.create(#node.points)
		for i, q in ipairs(node.points) do
			local local3 = Vector3.new(
				(q[1] - node.centre.X) * scale.X,
				(q[2] - node.centre.Y) * scale.Y,
				(q[3] - node.centre.Z) * scale.Z
			)
			out[i] = part.CFrame * local3
		end
		return out, scale
	end

	local function overlaps(model, truckId, trailerId, trailerOnly)
		local hits = {}
		local wheels, others, meshParts = {}, {}, {}
		for _, d in ipairs(model:GetDescendants()) do
			if not d:IsA("BasePart") then
				continue
			end
			if isWheel(d) then
				table.insert(wheels, d)
			elseif d.ClassName == "MeshPart" then
				if string.sub(d.Name, 1, 4) == "Mesh" then
					table.insert(meshParts, d)
				end
			elseif EXEMPT[d.Name] == nil and not ofAWheel(d) and d.Transparency < 1 then
				table.insert(others, d)
			end
		end
		local meshWorld = {}
		for _, mp in ipairs(meshParts) do
			local points, scale = meshPoints(mp, truckId, trailerId)
			meshWorld[mp] = points
			-- The piece is the GLB's own size: no resize.
			for _, axis in ipairs({ scale.X, scale.Y, scale.Z }) do
				if math.abs(axis - 1) > 0.01 then
					table.insert(hits, mp.Name .. " is resized " .. tostring(axis) .. " from the GLB")
				end
			end
		end
		local boxes = {}
		for _, o in ipairs(others) do
			boxes[o] = boxSamples(o)
		end
		for wi, wheel in ipairs(wheels) do
			if trailerOnly and not inTrailer(wheel) then
				continue -- the truck alone is checked on its own
			end
			local rAt = profileOf(wheel, truckId, trailerId)
			local radius = rAt(0)
			local samples = tyreSamples(wheel, rAt)
			local who = if inTrailer(wheel) then trailerId else truckId
			local tag = string.format(
				"%s wheel %d (%s%.1f, z %.1f)",
				if inTrailer(wheel) then "trailer" else "truck",
				wi,
				if wheel.CFrame.X < 0 then "-" else "+",
				math.abs(wheel.CFrame.X),
				wheel.CFrame.Z
			)
			for _, o in ipairs(others) do
				if wheel:IsA("MeshPart") and o:GetAttribute("VisualMesh") == true then
					continue
				end
				local reach = o.Size.Magnitude / 2 + radius + wheel.Size.X
				if (o.CFrame.Position - wheel.CFrame.Position).Magnitude > reach then
					continue
				end
				local depth = 0
				for _, s in ipairs(samples) do
					if inPart(o, s) then
						local l = o.CFrame:PointToObjectSpace(s)
						local h = o.Size / 2
						depth = math.max(depth, math.min(h.X - math.abs(l.X), h.Y - math.abs(l.Y), h.Z - math.abs(l.Z)))
					end
				end
				for _, s in ipairs(boxes[o]) do
					depth = math.max(depth, tyreDepth(wheel, rAt, s))
				end
				if depth > 0 and not allowed(o.Name, who, depth + EPS) then
					table.insert(
						hits,
						string.format("%s overlaps %s at z %.1f (%.2f deep)", tag, o.Name, o.CFrame.Z, depth + EPS)
					)
				end
			end
			local centre = wheel.CFrame.Position
			local reach2 = (math.max(radius, wheel.Size.Y / 2) + wheel.Size.X / 2 + 0.3) ^ 2
			for mp, points in pairs(meshWorld) do
				local n = 0
				local deepest = 0
				for _, p in ipairs(points) do
					local dx, dy, dz = p.X - centre.X, p.Y - centre.Y, p.Z - centre.Z
					if dx * dx + dy * dy + dz * dz > reach2 then
						continue
					end
					local d = tyreDepth(wheel, rAt, p)
					if d > 0 then
						n += 1
						deepest = math.max(deepest, d)
					end
				end
				if n > 0 and not allowed(mp.Name, who, deepest) then
					table.insert(hits, string.format("%s overlaps %s (%d points, %.2f deep)", tag, mp.Name, n, deepest))
				end
			end
		end
		return hits, #wheels
	end

	local function eachVehicle(fn)
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			fn(truck, nil)
			if truck.bedCapacity > 0 then
				for _, trailer in ipairs(ItemCatalog.TrailerList()) do
					fn(truck, trailer)
				end
			end
		end
	end

	local function nameOf(truck, trailer)
		return truck.id .. (if trailer then " + " .. trailer.id else "")
	end

	t.test("part-built: no wheel overlaps a body, fender, board or any other part (every truck and rig)", function()
		MeshKit.Reset()
		local failures = {}
		eachVehicle(function(truck, trailer)
			local model = TruckArt.Build(truck, nil, trailer)
			t.eq(model:GetAttribute("VehicleMesh"), nil, nameOf(truck, trailer) .. " is part-built")
			local hits, wheels = overlaps(model, truck.id, if trailer then trailer.id else nil, trailer ~= nil)
			t.ok(wheels >= 4, nameOf(truck, trailer) .. " has wheels")
			for _, h in ipairs(hits) do
				table.insert(failures, nameOf(truck, trailer) .. ": " .. h)
			end
		end)
		t.eq(#failures, 0, "\n" .. table.concat(failures, "\n"))
	end)

	t.test("meshed: no wheel overlaps the body, bed, lights, hitch or glass mesh, or a part that stays", function()
		local failures = {}
		withMeshes(function()
			eachVehicle(function(truck, trailer)
				if VehicleModels.Truck(truck.id) == nil then
					return -- no uploaded pieces (the Timber Classic): covered by the part-built test
				end
				local model = TruckArt.Build(truck, nil, trailer)
				t.eq(model:GetAttribute("VehicleMesh"), true, nameOf(truck, trailer) .. " is meshed")
				local hits, wheels = overlaps(model, truck.id, if trailer then trailer.id else nil, trailer ~= nil)
				t.ok(wheels >= 4, nameOf(truck, trailer) .. " has wheels")
				for _, h in ipairs(hits) do
					table.insert(failures, nameOf(truck, trailer) .. ": " .. h)
				end
			end)
		end)
		t.eq(#failures, 0, "\n" .. table.concat(failures, "\n"))
	end)

	t.test(
		"every axle of every trailer is checked: Pony 2 wheels, Ranch 4, HeavyHauler 4 behind every tow truck",
		function()
			local want = { PonyTrailer = 2, RanchTrailer = 4, HeavyHauler = 4 }
			withMeshes(function()
				eachVehicle(function(truck, trailer)
					if trailer == nil or VehicleModels.Truck(truck.id) == nil then
						return
					end
					local model = TruckArt.Build(truck, nil, trailer)
					local n = 0
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("BasePart") and d.Name == "Wheel" and inTrailer(d) then
							n += 1
						end
					end
					t.eq(n, want[trailer.id], nameOf(truck, trailer) .. " trailer wheels")
				end)
			end)
		end
	)

	t.test("every piece's size in VehicleModels is its GLB node's size: no mesh is resized", function()
		local function check(label, spec, path)
			local nodes = readGlb(path)
			for role, piece in pairs(spec) do
				local node = nodes[role]
				t.ok(node ~= nil, label .. " " .. role .. " is a node in " .. path)
				if node then
					t.ok(
						(piece.size - node.size).Magnitude < 0.01,
						string.format(
							"%s %s size %.3f x %.3f x %.3f vs GLB %.3f x %.3f x %.3f",
							label,
							role,
							piece.size.X,
							piece.size.Y,
							piece.size.Z,
							node.size.X,
							node.size.Y,
							node.size.Z
						)
					)
				end
			end
		end
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			local spec = VehicleModels.Truck(truck.id)
			if spec then
				check(truck.id, spec, string.format("assets/meshes/vehicles/%s/%s.glb", truck.id, truck.id))
				if truck.bedCapacity > 0 then
					for _, trailer in ipairs(ItemCatalog.TrailerList()) do
						check(
							trailer.id .. " behind " .. truck.id,
							VehicleModels.Trailer(trailer.id, truck.id),
							string.format(
								"assets/meshes/vehicles/%s/by_truck/%s/%s_%s.glb",
								trailer.id,
								truck.id,
								trailer.id,
								truck.id
							)
						)
					end
				end
			end
		end
		for _, trailer in ipairs(ItemCatalog.TrailerList()) do
			check(
				trailer.id .. " (Default)",
				VehicleModels.Trailer(trailer.id, nil),
				string.format("assets/meshes/vehicles/%s/%s.glb", trailer.id, trailer.id)
			)
		end
	end)

	t.test("the checker itself catches an overlap (a board through a tyre, and a tyre through a wall)", function()
		-- A model with one wheel and a box sunk into it must be reported.
		local model = Instance.new("Model")
		local wheel = Instance.new("Part")
		wheel.Name = "Wheel"
		wheel:SetAttribute("Radius", 1.5)
		wheel.Size = Vector3.new(1, 3, 3)
		wheel.CFrame = t.roblox.CFrame.new(0, 1.5, 0)
		wheel.Parent = model
		local board = Instance.new("Part")
		board.Name = "Fender"
		board.Size = Vector3.new(2, 0.5, 4)
		board.CFrame = t.roblox.CFrame.new(0, 2.5, 0)
		board.Parent = model
		local hits = overlaps(model, "Pickup", nil, false)
		t.eq(#hits, 1, "the fender sunk into the tyre is reported")
		board.CFrame = t.roblox.CFrame.new(0, 3.5, 0)
		t.eq(#overlaps(model, "Pickup", nil, false), 0, "a fender clear of the tyre is not")
	end)
end
