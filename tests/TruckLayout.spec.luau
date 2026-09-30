--!nocheck
-- Every truck's parts and bed logs fit where they should.
return function(t)
	local ItemCatalog = t.shared("ItemCatalog")
	local TruckLayout = t.shared("TruckLayout")

	t.test("one log slot per bed space, all inside the bed", function()
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			t.eq(#layout.logSlots, truck.bedCapacity, id .. " slots")
			for i, slot in ipairs(layout.logSlots) do
				local r = TruckLayout.LogDiameter / 2
				t.ok(
					math.abs(slot.Z) + r <= layout.bedLength / 2,
					string.format("%s log %d sticks out of the bed", id, i)
				)
				t.ok(slot.Y > 0, id .. " logs sit on the bed")
			end
			t.ok(layout.logLength < layout.width, id .. " logs fit across the bed")
		end
	end)

	t.test("the bed starts behind the cab and ends at the back", function()
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			t.eq(layout.front, -layout.length / 2, id)
			t.ok(layout.bedStart >= layout.front + TruckLayout.CabLength - 1e-6, id .. " bed overlaps the cab")
			t.ok(layout.bedStart + layout.bedLength <= layout.length / 2, id .. " bed runs off the back")
		end
	end)

	t.test("wheels sit under the truck; long beds get an extra axle", function()
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			for _, z in ipairs(layout.wheelZ) do
				t.ok(math.abs(z) < layout.length / 2, id .. " wheel off the end")
			end
		end
		t.eq(#TruckLayout.For(ItemCatalog.GetTruck("Rustbucket")).wheelZ, 2)
		t.eq(#TruckLayout.For(ItemCatalog.GetTruck("LoggingRig")).wheelZ, 3)
	end)

	t.test("every rig fits a parking slot (6.5 x 37 studs), trailer and all", function()
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			t.ok(2 * layout.wheelX + 0.8 <= 6.5 + 0.5, id .. " too wide")
			t.ok(layout.length <= 37, id .. " too long")
			for trailerId, trailer in pairs(ItemCatalog.Trailers) do
				local tl = TruckLayout.ForTrailer(trailer, layout)
				t.ok(layout.length + tl.length <= 37, id .. " + " .. trailerId .. " too long")
			end
		end
	end)

	t.test("trailer beds hold their extra capacity, behind the truck", function()
		local truck = TruckLayout.For(ItemCatalog.GetTruck("Pickup"))
		for id, trailer in pairs(ItemCatalog.Trailers) do
			local tl = TruckLayout.ForTrailer(trailer, truck)
			t.eq(#tl.logSlots, trailer.extraCapacity, id .. " slots")
			t.ok(tl.bedCenterZ - tl.bedLength / 2 > truck.length / 2, id .. " overlaps the truck")
			for _, slot in ipairs(tl.logSlots) do
				t.ok(math.abs(slot.Z) + TruckLayout.LogDiameter / 2 <= tl.bedLength / 2, id .. " log sticks out")
			end
			t.ok(math.abs(tl.wheelZ - tl.bedCenterZ) < tl.bedLength / 2, id .. " axle under the bed")
		end
	end)

	t.test("the Scout ATV has no bed", function()
		local layout = TruckLayout.For(ItemCatalog.GetTruck("ScoutATV"))
		t.eq(layout.bedLength, 0)
		t.eq(#layout.logSlots, 0)
	end)
end
