--!nocheck
-- T421: the Timber Classic. It is the Pickup in its own paint: the same stats, bed and handling (copied, never
-- retyped), the brief's hitch, wheel centres and bed footprint, the Pickup's trailer variants, and visual meshes add no
-- mass. Its part sizes against TimberClassic/stats.json are an expected fail: that file is not in the repo.
return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local ItemCatalog = t.shared("ItemCatalog")
	local TruckLayout = t.shared("TruckLayout")
	local Handling = t.shared("Handling")
	local Gate = t.shared("VehicleMeshGate")
	local Data = t.shared("TimberClassicData")
	local VehicleModels = t.load("ReplicatedStorage/Shared/Art/VehicleModels")
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local fs = require("@lune/fs")

	local classic = ItemCatalog.Trucks.TimberClassic
	local pickup = ItemCatalog.Trucks.Pickup

	t.test("ItemCatalog.Trucks.TimberClassic exists and is a pass truck", function()
		t.ok(classic ~= nil)
		t.eq(classic.robux, true)
		t.eq(classic.sold, false)
	end)

	t.test("its stats, bed and handling EQUAL the Pickup's (they cannot drift)", function()
		for _, key in ipairs({ "bedCapacity", "topSpeed", "turnRate", "priceCash" }) do
			t.eq(classic[key], pickup[key], key)
		end
		t.eq(classic.v2, pickup.v2, "v2 stats")
		t.eq(classic.look.width, pickup.look.width)
		t.eq(classic.look.bedLength, pickup.look.bedLength)
		t.eq(classic.look.bedWalls, pickup.look.bedWalls)
		t.eq(TruckLayout.StyleOf(classic), TruckLayout.StyleOf(pickup))
		for _, key in ipairs({ "accel", "brake", "coast", "climb", "tipResist", "steerLow", "steerHigh", "suspension" }) do
			t.eq(Handling.For("TimberClassic")[key], Handling.For("Pickup")[key], key)
		end
	end)

	t.test("the hitch is at (0, 2.005, 12.875)", function()
		t.eq(Data.Hitch, Vector3.new(0, 2.005, 12.875))
		local at = VehicleModels.Truck("Pickup").Hitch.at
		t.ok((Data.Hitch - at).Magnitude < 1e-6, "the Pickup's hitch mesh sits at the same place")
	end)

	t.test(
		"the wheel centres are (+-4.713, 1.755, -9.685) and (+-4.713, 1.755, 7.085), as the layout builds them",
		function()
			local lay = TruckLayout.For(classic)
			local want = {
				{ -4.713, -9.685 },
				{ 4.713, -9.685 },
				{ -4.713, 7.085 },
				{ 4.713, 7.085 },
			}
			for i, c in ipairs(Data.WheelCentres) do
				t.eq(c, Vector3.new(want[i][1], 1.755, want[i][2]))
			end
			t.ok(math.abs(lay.wheelX - 4.713) < 0.01, "wheel X " .. lay.wheelX)
			t.ok(math.abs(lay.wheelZ[1] - -9.685) < 0.01, "front axle " .. lay.wheelZ[1])
			t.ok(math.abs(lay.wheelZ[2] - 7.085) < 0.01, "rear axle " .. lay.wheelZ[2])
			t.ok(math.abs(lay.wheelRadius - 1.755) < 0.01, "radius")
			local model = TruckArt.Build(classic, lay)
			local seen = 0
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and d.Name == "Wheel" and d:GetAttribute("TrailerBody") ~= true then
					seen += 1
					local p = d.CFrame.Position
					local ok = false
					for _, c in ipairs(Data.WheelCentres) do
						if (p - c).Magnitude < 0.01 then
							ok = true
						end
					end
					t.ok(ok, "a built wheel at " .. tostring(p) .. " is one of the four centres")
				end
			end
			t.eq(seen, 4)
		end
	)

	t.test("the bed footprint 7.22 x 15.5 is within the Pickup's 9 x 15.815", function()
		local bed = VehicleModels.Truck("Pickup").Bed.size
		t.ok(Data.BedFootprint.X <= bed.X and Data.BedFootprint.Y <= bed.Z, "inside")
		t.eq(Data.BedFootprint, roblox.Vector2.new(7.22, 15.5))
	end)

	t.test("it tows the Pickup's trailer variants", function()
		t.eq(Gate.VariantFor("TimberClassic"), "Pickup")
		t.eq(Data.TowVariant, "Pickup")
		for _, trailerId in ipairs(Gate.Trailers) do
			t.ok(VehicleModels.Trailer(trailerId, "Pickup") ~= nil, trailerId .. " has a Pickup variant")
		end
	end)

	-- What a mesh adds: nothing. Mass is the volume of every part that is not Massless; the visual meshes are Massless.
	local function mass(model)
		local sum = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and not d.Massless then
				sum += d.Size.X * d.Size.Y * d.Size.Z
			end
		end
		return sum
	end

	t.test("the assembly's mass is within 1% of its own hull's: visual meshes add none", function()
		local lay = TruckLayout.For(classic)
		local hull = TruckArt.Build(classic, lay)
		local before = mass(hull)
		local MeshKit = t.load("ReplicatedStorage/Shared/Art/MeshKit")
		for _, role in ipairs(Gate.ClassicParts) do
			local part = roblox.Instance.new("MeshPart")
			part.Name = "Mesh" .. role
			part.Size = Vector3.new(10, 5, 25)
			MeshKit.Visual(part, 123)
			part.Parent = hull
		end
		t.ok(math.abs(mass(hull) - before) / before < 0.01, "mass " .. mass(hull) .. " vs " .. before)
	end)

	local serde = require("@lune/serde")
	local stats = serde.decode("json", fs.readFile("assets/vehicles/t421/glb/TimberClassic/stats.json"))

	local function near(a, b)
		return math.abs(a - b) <= 0.01 * math.max(math.abs(b), 1)
	end

	t.test("its part sizes and offsets match TimberClassic/stats.json within 1%", function()
		local pieces = VehicleModels.Truck("TimberClassic")
		t.ok(pieces ~= nil, "VehicleModels has a piece table for it")
		for _, role in ipairs({ "Body", "Glass", "Lights", "Bed", "Hitch" }) do
			local want = stats[role]
			local got = pieces[role]
			t.ok(got ~= nil, role)
			for i, axis in ipairs({ "X", "Y", "Z" }) do
				t.ok(
					near(got.size[axis], want.size[i]),
					role .. " size " .. axis .. " " .. got.size[axis] .. " vs " .. want.size[i]
				)
				t.ok(math.abs(got.at[axis] - want.at[i]) <= 0.01, role .. " at " .. axis)
			end
		end
		local wheel = pieces.Wheel
		for i, axis in ipairs({ "X", "Y", "Z" }) do
			t.ok(near(wheel.size[axis], stats.Wheel.size[i]), "Wheel size " .. axis)
		end
		t.eq(wheel.mirrorLeft, true)
	end)

	t.test("bbox_check.md's Timber Classic bed row and the hitch agree with stats.json and the data module", function()
		local md = fs.readFile("assets/vehicles/t421/bbox_check.md")
		local x, y, z = string.match(md, "| TimberClassic Bed | ([%d%.]+) | ([%d%.]+) | ([%d%.]+) |")
		t.ok(x ~= nil, "found the bed row")
		t.ok(
			near(tonumber(x), stats.Bed.size[1])
				and near(tonumber(y), stats.Bed.size[2])
				and near(tonumber(z), stats.Bed.size[3])
		)
		t.eq(Data.BedFootprint, roblox.Vector2.new(tonumber(x), tonumber(z)))
		t.eq(Data.Hitch, Vector3.new(stats.Hitch.at[1], stats.Hitch.at[2], stats.Hitch.at[3]))
		for i, c in ipairs(stats.Wheel.wheelCentres) do
			t.eq(Data.WheelCentres[i], Vector3.new(c[1], c[2], c[3]))
		end
	end)

	t.test("with its meshes' ids in it is complete: only the ids decide (the stats are in)", function()
		Gate.SetIds(Gate.FakeIds())
		t.eq(Gate.Complete("Truck", "TimberClassic"), true)
		t.eq(#Gate.Missing("Truck", "TimberClassic"), 0)
		local empty = {}
		for _, part in ipairs(Gate.ClassicParts) do
			empty[Gate.TruckKey("TimberClassic", part)] = ""
		end
		Gate.SetIds(empty)
		t.eq(#Gate.Missing("Truck", "TimberClassic"), 6, "and with empty ids the six keys are missing")
		Gate.SetIds(nil)
	end)
end
