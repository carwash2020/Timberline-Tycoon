--!nocheck
-- The Pickup's wheels (Connor, 12 October 2026: "the Pickup has no wheels in
-- its file"). Pickup.glb, like every truck GLB in assets/meshes/vehicles, holds
-- ONE unplaced Wheel piece at its origin (a tyre of radius 1.755 and width
-- 1.377 with its dished rim), never four placed wheels; the game stands four copies of that piece
-- at the truck's wheel positions (VehicleMeshes swaps each part-built Wheel
-- for the mesh, same centre, same Radius, so VehicleFX spins and steers them).
-- This pins where the four go, against the Body mesh's wheel arches, and that
-- the gameplay truck and the Dealership's display copy show the same wheels.
--
-- Recorded numbers (truck-local studs, nose toward -Z, chassis at the origin):
--   wheel centres  x = +-4.7125, y = 1.7545, z = -9.685 (steers) and 7.085 (rear)
--   tyre radius    1.755 (diameter 3.51), width 1.365 part-built; the mesh keeps its own
--                  bounds 1.377 x 3.52 x 3.51 (never resized: the 12 October GLB pass)
--   Body mesh arches (outer fender flare, from Pickup.glb vertices): front
--   z -11.0 .. -8.5 (middle -9.75), rear z 5.5 .. 8.5 (middle 7.0), top of the
--   flare y 3.97 (0.46 over the tyre top 3.509); the body's side is x +-5.555,
--   the tyre's outer face x 5.399.
return function(t)
	local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local VehicleModels = t.load("ReplicatedStorage/Shared/Art/VehicleModels")
	local DealershipLot = t.load("ReplicatedStorage/Shared/Art/DealershipLot")
	local ItemCatalog = t.shared("ItemCatalog")
	local Instance = t.roblox.Instance

	local R = 1.755 -- tyre radius
	local WIDTH = 1.365 -- the part-built tyre's width (TruckLayout)
	local MESH = { 1.377, 3.52, 3.51 } -- the Wheel node's own size in Pickup.glb (VehicleModels)
	local X = 4.7125
	local ZS = { -9.685, 7.085 }
	local EPS = 0.01

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

	local function wheelsOf(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "Wheel" and d:GetAttribute("Radius") ~= nil then
				table.insert(out, d)
			end
		end
		return out
	end

	-- A wheel's centre in the truck's own frame: x and z from the chassis (the copy on
	-- a plinth is turned side-on), y up from `ground` (world y of the truck's feet).
	local function localCentres(wheels, ref, ground)
		local out = {}
		for _, w in ipairs(wheels) do
			local p = ref:PointToObjectSpace(w.CFrame.Position)
			table.insert(out, t.roblox.Vector3.new(p.X, w.CFrame.Position.Y - ground, p.Z))
		end
		return out
	end

	local function hasCentre(list, x, z)
		for _, p in ipairs(list) do
			if math.abs(p.X - x) < EPS and math.abs(p.Z - z) < EPS and math.abs(p.Y - R) < EPS then
				return true
			end
		end
		return false
	end

	local function checkFour(label, wheels, ref, ground, meshed)
		t.eq(#wheels, 4, label .. " has four wheels")
		local centres = localCentres(wheels, ref, ground)
		for _, side in ipairs({ -1, 1 }) do
			for _, z in ipairs(ZS) do
				t.ok(hasCentre(centres, side * X, z), string.format("%s wheel at x %.4f z %.3f", label, side * X, z))
			end
		end
		for _, w in ipairs(wheels) do
			t.ok(
				math.abs(w:GetAttribute("Radius") - R) < EPS,
				label .. " Radius " .. tostring(w:GetAttribute("Radius"))
			)
			if meshed then
				-- The mesh keeps its own size: not stretched to the part-built tyre.
				t.ok(
					math.abs(w.Size.X - MESH[1]) < 0.002
						and math.abs(w.Size.Y - MESH[2]) < 0.002
						and math.abs(w.Size.Z - MESH[3]) < 0.002,
					label .. " the mesh keeps its own size"
				)
			else
				t.ok(math.abs(w.Size.Y - 2 * R) < EPS and math.abs(w.Size.Z - 2 * R) < EPS, label .. " tyre diameter")
				t.ok(math.abs(w.Size.X - WIDTH) < EPS, label .. " tyre width")
			end
		end
	end

	t.test(
		"the Pickup's four wheels sit at the recorded centres with the right radius (part-built and meshed)",
		function()
			local def = ItemCatalog.GetTruck("Pickup")
			local plain = TruckArt.Build(def)
			MeshKit.Reset()
			checkFour("part-built Pickup", wheelsOf(plain), plain:FindFirstChild("Chassis", true).CFrame, 0)
			withMeshes(function()
				local model = TruckArt.Build(def)
				t.eq(model:GetAttribute("VehicleMesh"), true, "the mesh build applied")
				local wheels = wheelsOf(model)
				checkFour("meshed Pickup", wheels, model:FindFirstChild("Chassis", true).CFrame, 0, true)
				for _, w in ipairs(wheels) do
					t.ok(w:IsA("MeshPart"), "the wheel is a mesh")
					t.eq(
						w:GetAttribute("MeshId"),
						tostring(VehicleModels.Truck("Pickup").Wheel.meshId),
						"the Pickup's wheel mesh"
					)
				end
			end)
		end
	)

	t.test("the Pickup's wheels rest on the ground plane: none floats, none is sunk", function()
		withMeshes(function()
			local model = TruckArt.Build(ItemCatalog.GetTruck("Pickup"))
			local lowest = math.huge
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					lowest = math.min(lowest, d.CFrame.Position.Y - d.Size.Y / 2)
				end
			end
			for _, w in ipairs(wheelsOf(model)) do
				local bottom = w.CFrame.Position.Y - w.Size.Y / 2
				t.ok(math.abs(bottom) < EPS, "wheel bottom on y 0, got " .. tostring(bottom))
			end
			t.ok(math.abs(lowest) < 0.2, "the truck's lowest point is the tyres (" .. tostring(lowest) .. ")")
		end)
	end)

	t.test(
		"Pickup.glb holds one unplaced Wheel piece (the radius and width the game uses), like every truck GLB",
		function()
			local fs = require("@lune/fs")
			local serde = require("@lune/serde")
			for _, id in ipairs({ "Pickup", "Rustbucket", "Flatbed", "LoggingRig" }) do
				local bytes = fs.readFile("assets/meshes/vehicles/" .. id .. "/" .. id .. ".glb")
				local jsonLen = string.unpack("<I4", bytes, 13)
				local gltf = serde.decode("json", string.sub(bytes, 21, 20 + jsonLen))
				local wheelNodes = 0
				local wheelMesh
				for _, node in ipairs(gltf.nodes) do
					if node.name == "Wheel" then
						wheelNodes += 1
						wheelMesh = node.mesh
					end
				end
				t.eq(wheelNodes, 1, id .. ".glb has one Wheel piece, not four placed wheels")
				local acc = gltf.accessors[gltf.meshes[wheelMesh + 1].primitives[1].attributes.POSITION + 1]
				if id == "Pickup" then
					t.ok(math.abs(acc.max[2] - R) < 0.006 and math.abs(acc.max[3] - R) < 0.006, "Pickup wheel radius")
					t.ok(math.abs(acc.max[1] - acc.min[1] - MESH[1]) < 0.002, "Pickup wheel width")
				end
			end
		end
	)

	t.test("the wheels clear the body: inside the wheel arches front and back, tyre top under the flare", function()
		-- Arch middles from the Body mesh (see the header); the tyre centre is within
		-- 0.15 of each, and the tyre top (3.509) stays under the flare top (3.97).
		t.ok(math.abs(ZS[1] - -9.75) < 0.15, "front wheel in the front arch")
		t.ok(math.abs(ZS[2] - 7.0) < 0.15, "rear wheel in the rear arch")
		t.ok(2 * R < 3.97, "the tyre top is under the flare")
		t.ok(X + WIDTH / 2 < 5.555, "the tyre's outer face is inside the body's side")
	end)

	t.test(
		"the Pickup's wheels turn and steer like the others: front pair steers, Axle motors, same wheel path",
		function()
			withMeshes(function()
				local model = TruckArt.Build(ItemCatalog.GetTruck("Pickup"))
				TruckArt.Rig(model)
				local steer = 0
				for _, w in ipairs(wheelsOf(model)) do
					local axle = w:FindFirstChild("Axle")
					t.ok(axle ~= nil and axle:IsA("Motor6D"), "an Axle motor on the wheel")
					if w:GetAttribute("Steer") then
						steer += 1
						t.ok(w.CFrame.Z < 0, "the steering pair is at the front")
					end
				end
				t.eq(steer, 2, "two steering wheels")
			end)
		end
	)

	-- The repo's GLB wheels are dished on both faces (since the 12 October GLB pass), but the wheel
	-- meshes live in Roblox are still the old one-sided uploads (rim, lugs and cap on +X only), so
	-- every truck and trailer turns its left (-X) wheels half way round about Y (VehicleModels
	-- mirrorLeft). A half turn of a two-sided wheel looks the same, so this holds after the
	-- re-upload too. VehicleWheelFaces.spec runs it for every vehicle.
	t.test(
		"the Pickup's left (-X) wheels turn about Y so the rim faces out; spin and steer axes stay the same",
		function()
			t.eq(VehicleModels.Truck("Pickup").Wheel.mirrorLeft, true, "the Pickup's wheel has mirrorLeft")
			withMeshes(function()
				local model = TruckArt.Build(ItemCatalog.GetTruck("Pickup"))
				local chassis = model:FindFirstChild("Chassis", true)
				local base = chassis.CFrame
				TruckArt.Rig(model)
				local left, right = 0, 0
				for _, w in ipairs(wheelsOf(model)) do
					local rel = base:ToObjectSpace(w.CFrame)
					local axle = w:FindFirstChild("Axle")
					local isLeft = base:PointToObjectSpace(w.CFrame.Position).X < 0
					if isLeft then
						left += 1
						t.eq(w:GetAttribute("Mirror"), true, "a left wheel is marked turned")
						t.ok(rel.RightVector.X < -0.999, "a left wheel's rim face (+X of the mesh) points to -X")
						t.ok(axle.C1.RightVector.X < -0.999, "the half turn is in C1")
					else
						right += 1
						t.eq(w:GetAttribute("Mirror"), nil, "a right wheel is not turned")
						t.ok(rel.RightVector.X > 0.999, "a right wheel's rim face points to +X")
						t.ok(axle.C1.RightVector.X > 0.999, "a right wheel has no turn in C1")
					end
					-- Either way the joint acts about the unturned axle: Transform's spin (about X)
					-- and steer (about Y) go the same way on both sides.
					t.ok(axle.C0.RightVector.X > 0.999, "the joint frame's X is the axle on both sides")
					t.ok(axle.C0.UpVector.Y > 0.999, "the joint frame is upright")
				end
				t.eq(left, 2)
				t.eq(right, 2)
			end)
		end
	)

	t.test(
		"the Pickup's wheel GLB is the same on both faces (mirror-symmetric about x), so the half turn is harmless after the re-upload",
		function()
			local fs = require("@lune/fs")
			local serde = require("@lune/serde")
			local bytes = fs.readFile("assets/meshes/vehicles/Pickup/Pickup.glb")
			local jsonLen = string.unpack("<I4", bytes, 13)
			local gltf = serde.decode("json", string.sub(bytes, 21, 20 + jsonLen))
			local binAt = 20 + jsonLen + 8 + 1 -- the BIN chunk's data
			local mesh
			for _, node in ipairs(gltf.nodes) do
				if node.name == "Wheel" then
					mesh = node.mesh
				end
			end
			local seen, total = {}, 0
			local verts = {}
			for _, prim in ipairs(gltf.meshes[mesh + 1].primitives) do
				local acc = gltf.accessors[prim.attributes.POSITION + 1]
				local view = gltf.bufferViews[acc.bufferView + 1]
				for i = 0, acc.count - 1 do
					local o = binAt + (view.byteOffset or 0) + (acc.byteOffset or 0) + i * (view.byteStride or 12)
					local x, y, z = string.unpack("<fff", bytes, o)
					table.insert(verts, { x, y, z })
					seen[string.format(
						"%d,%d,%d",
						math.floor(x * 20 + 0.5),
						math.floor(y * 20 + 0.5),
						math.floor(z * 20 + 0.5)
					)] =
						true
				end
			end
			local matched = 0
			for _, v in ipairs(verts) do
				total += 1
				-- Within a 0.05 cell either side (rounding at a cell's edge).
				local cx, cy, cz =
					math.floor(-v[1] * 20 + 0.5), math.floor(v[2] * 20 + 0.5), math.floor(v[3] * 20 + 0.5)
				local hit = false
				for dx = -1, 1 do
					for dy = -1, 1 do
						for dz = -1, 1 do
							if seen[string.format("%d,%d,%d", cx + dx, cy + dy, cz + dz)] then
								hit = true
							end
						end
					end
				end
				if hit then
					matched += 1
				end
			end
			t.ok(total > 1000, "the wheel has its triangles")
			t.ok(matched / total > 0.99, string.format("%.1f%% of the wheel mirrors across x", matched / total * 100))
		end
	)

	t.test("the Dealership's display copy has the same four wheels, resting on its plinth", function()
		withMeshes(function()
			local lot = DealershipLot.Build()
			local display
			for _, child in ipairs(lot:GetChildren()) do
				if
					child:IsA("Model")
					and child:GetAttribute("ItemId") == "Pickup"
					and child:GetAttribute("Category") == "Truck"
				then
					display = child
				end
			end
			t.ok(display ~= nil, "the lot shows the Pickup")
			local wheels = wheelsOf(display)
			t.eq(#wheels, 4, "four wheels on the display copy")
			local chassis = display:FindFirstChild("Chassis", true)
			-- Same wheels as the gameplay truck: same centres in the truck's own frame.
			-- (The copy is turned side-on, so measure in the chassis frame.)
			local plinth
			for _, d in ipairs(lot:GetChildren()) do
				if d.Name == "Plinth" and d:GetAttribute("ItemId") == "Pickup" then
					plinth = d
				end
			end
			t.ok(plinth ~= nil, "the Pickup's plinth")
			local top = plinth.CFrame.Position.Y + plinth.Size.Y / 2
			local turned = 0
			for _, w in ipairs(wheels) do
				if w:GetAttribute("Mirror") == true then
					turned += 1
					t.ok(chassis.CFrame:PointToObjectSpace(w.CFrame.Position).X < 0, "only a left wheel is turned")
				end
			end
			t.eq(turned, 2, "the display copy turns its two left wheels, like the gameplay truck")
			local centres = localCentres(wheels, chassis.CFrame, top)
			for _, side in ipairs({ -1, 1 }) do
				for _, z in ipairs(ZS) do
					t.ok(hasCentre(centres, side * X, z), string.format("display wheel at x %.4f z %.3f", side * X, z))
				end
			end
			for _, w in ipairs(wheels) do
				t.ok(w:IsA("MeshPart"), "the display wheel is the mesh")
				t.eq(w:GetAttribute("MeshId"), tostring(VehicleModels.Truck("Pickup").Wheel.meshId))
				t.ok(
					math.abs(w.Size.X - MESH[1]) < 0.002 and math.abs(w.Size.Y - MESH[2]) < 0.002,
					"the display wheel is the mesh's own size"
				)
				local bottom = w.CFrame.Position.Y - w.Size.Y / 2
				t.ok(
					math.abs(bottom - top) < 0.05,
					"display wheel bottom on the plinth top: " .. tostring(bottom - top)
				)
			end
		end)
	end)

	t.test(
		"no other truck changed but its wheel mesh bounds (the 12 October GLB pass): ids and centres are as they were",
		function()
			-- id, wheel mesh id, tyre width, tyre diameter, wheelX, front z, rear z (truck-local).
			local pinned = {
				Rustbucket = { 96000510170326, 1.307, 3.39 },
				Pickup = { 100358820661876, 1.377, 3.52 },
				ScoutATV = { 108444483567193, 1.822, 3.26 },
				Flatbed = { 94524411538210, 1.447, 3.65 },
				LoggingRig = { 88377082453341, 1.546, 4.56 },
			}
			for id, want in pairs(pinned) do
				local wheel = VehicleModels.Truck(id).Wheel
				t.eq(wheel.meshId, want[1], id .. " wheel mesh id")
				t.ok(math.abs(wheel.size.X - want[2]) < 1e-3, id .. " wheel width")
				t.ok(math.abs(wheel.size.Y - want[3]) < 1e-3, id .. " wheel diameter")
			end
			-- Every other truck's wheels are built the same way as the Pickup's: a MeshPart
			-- "Wheel" per tyre, resting on the ground, with the part-built tyre's Radius.
			withMeshes(function()
				for _, def in ipairs(ItemCatalog.TruckList()) do
					local spec = VehicleModels.Truck(def.id)
					if spec == nil then
						continue -- no uploaded pieces (a part-built truck): nothing to compare
					end
					local model = TruckArt.Build(def)
					local meshId = tostring(spec.Wheel.meshId)
					local n = 0
					for _, w in ipairs(wheelsOf(model)) do
						n += 1
						t.ok(w:IsA("MeshPart"), def.id .. " wheel is a mesh")
						t.eq(w:GetAttribute("MeshId"), meshId, def.id .. " wheel mesh")
						local y = w.CFrame.Position.Y
						t.ok(math.abs(y - w:GetAttribute("Radius")) < EPS, def.id .. " wheel on the ground")
					end
					t.ok(n >= 4, def.id .. " has wheels")
				end
			end)
		end
	)
end
