--!strict
-- Per-tier driving feel. DriveMath's circle contracts stay put; this is
-- the layer VehicleController and the arcade fallback drive with.
return function(t)
	local Handling = t.shared("Handling")
	local ItemCatalog = t.shared("ItemCatalog")
	local TruckLayout = t.shared("TruckLayout")
	local PlotData = t.shared("PlotData")
	local Vector3 = t.roblox.Vector3

	local function tiltOf(up)
		return math.acos(math.clamp(up.Y, -1, 1))
	end

	t.test("catalog speeds and turns match the tier sheet", function()
		local function truck(id)
			return ItemCatalog.GetTruck(id)
		end
		t.eq(truck("Rustbucket").topSpeed, 26)
		t.eq(truck("Rustbucket").turnRate, 1.4)
		t.ok(truck("Pickup").topSpeed >= 30 and truck("Pickup").topSpeed <= 32, "Pickup 30 to 32")
		t.ok(truck("Pickup").turnRate >= truck("Rustbucket").turnRate, "Pickup turns at least as tight")
		t.ok(truck("ScoutATV").topSpeed > truck("Pickup").topSpeed, "the ATV is the fastest")
		t.ok(truck("ScoutATV").turnRate > truck("Pickup").turnRate, "the ATV turns tightest")
		t.eq(truck("ScoutATV").bedCapacity, 0, "no bed, so it can't be the hauler")
		t.eq(truck("Flatbed").turnRate, 1.2)
		t.eq(truck("LoggingRig").turnRate, 1)
		t.ok(truck("LoggingRig").topSpeed < truck("Rustbucket").topSpeed, "the rig is slow")
	end)

	t.test("climb, tip and steer follow the same order", function()
		local farm = Handling.For("Rustbucket")
		local pickup = Handling.For("Pickup")
		local atv = Handling.For("ScoutATV")
		local flat = Handling.For("Flatbed")
		local rig = Handling.For("LoggingRig")
		t.ok(farm.climb < pickup.climb and pickup.climb < atv.climb, "ATV climbs best, Rustbucket worst")
		t.ok(rig.climb > flat.climb and rig.climb > farm.climb, "the rig climbs a slope")
		t.ok(farm.tipResist > atv.tipResist, "the Rustbucket stays planted")
		t.ok(rig.tipResist > pickup.tipResist, "the rig is planted")
		t.ok(Handling.DriveForce(farm) < Handling.DriveForce(pickup), "the Pickup pulls harder")
		t.ok(Handling.DriveForce(atv) > Handling.DriveForce(pickup), "the ATV pulls hardest")
		t.ok(Handling.DriveForce(rig) > Handling.DriveForce(farm), "the rig out-climbs the Rustbucket")
		t.ok(Handling.DriveForce(farm) >= Handling.ForceFloor, "every tier still clears a kerb")
		-- Low speed: the Pickup steers harder than the Rustbucket, the ATV hardest.
		local function low(id, turnRate)
			return turnRate * Handling.SteerScale(4, ItemCatalog.GetTruck(id).topSpeed, Handling.For(id))
		end
		t.ok(low("Pickup", 1.4) > low("Rustbucket", 1.4), "Pickup turns tighter in a bay")
		t.ok(low("ScoutATV", 2) > low("Pickup", 1.4), "ATV turns tightest")
		t.ok(low("Flatbed", 1.2) < low("Pickup", 1.4), "Flatbed is the wider turn")
		t.ok(low("LoggingRig", 1) < low("Flatbed", 1.2), "the rig turns widest")
	end)

	t.test("a loaded truck does not tip on a normal slope", function()
		-- 12 degrees, a haul-road cross slope.
		local slope = Vector3.new(math.sin(math.rad(12)), math.cos(math.rad(12)), 0)
		local farm = tiltOf(Handling.Lean(slope, Handling.For("Rustbucket").tipResist, math.rad(30)))
		local atv = tiltOf(Handling.Lean(slope, Handling.For("ScoutATV").tipResist, math.rad(30)))
		local rig = tiltOf(Handling.Lean(slope, Handling.For("LoggingRig").tipResist, math.rad(30)))
		t.ok(farm < math.rad(6), string.format("Rustbucket leans %.1f deg", math.deg(farm)))
		t.ok(rig < math.rad(4), string.format("rig leans %.1f deg", math.deg(rig)))
		t.ok(atv > farm, "the ATV is allowed to lean more")
		t.ok(farm < math.rad(30) and rig < math.rad(30), "neither tips")
	end)

	t.test("a trailer widens the circle a little and swings without jackknifing", function()
		t.eq(Handling.TowRadius(10, false), 10)
		t.eq(Handling.TowRadius(nil, true), nil)
		local wider = Handling.TowRadius(10, true)
		t.ok(wider > 10 and wider < 12, "a small penalty")
		local angle = 0
		for _ = 1, 60 do
			angle = Handling.TrailerSwing(angle, 0.8, 20, 0.05)
		end
		t.ok(math.abs(angle) < 0.5, string.format("swing %.2f stays short of a jackknife", angle))
		t.ok(math.abs(angle) > 0.15, "the swing is visible")
	end)

	t.test("every truck is narrower than a plot lane", function()
		for id, def in pairs(ItemCatalog.Trucks) do
			local width = TruckLayout.For(def).width
			t.ok(width < PlotData.LaneWidth, string.format("%s is %.2f, lane is %d", id, width, PlotData.LaneWidth))
		end
	end)
end
