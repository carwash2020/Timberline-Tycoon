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

	t.test("every truck fits a parking slot (6.5 x 25 studs)", function()
		for id, truck in pairs(ItemCatalog.Trucks) do
			local layout = TruckLayout.For(truck)
			t.ok(layout.length <= 25, id .. " too long")
			t.ok(2 * layout.wheelX + 0.8 <= 6.5 + 0.5, id .. " too wide")
		end
	end)

	t.test("the Scout ATV has no bed", function()
		local layout = TruckLayout.For(ItemCatalog.GetTruck("ScoutATV"))
		t.eq(layout.bedLength, 0)
		t.eq(#layout.logSlots, 0)
	end)
end
