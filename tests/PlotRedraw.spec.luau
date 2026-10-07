--!nocheck
-- PlotRedraw: a pad is not rebuilt under a player's feet when the plot kit's
-- meshes land late, and the picker's data (plain numbers) is not touched.
return function(t)
	local PlotRedraw = t.shared("PlotRedraw")
	local fs = require("@lune/fs")

	local pads = {
		{ index = 1, x = 0, z = 0 },
		{ index = 2, x = 300, z = 0 },
		{ index = 3, x = 600, z = 0 },
	}

	t.test("a pad with a player near it waits; the rest are redrawn now", function()
		local now, later = PlotRedraw.Split(pads, { { x = 10, z = 10 } })
		t.eq(now, { 2, 3 })
		t.eq(later, { 1 })
	end)

	t.test("nobody around: everything now; everyone around: everything waits", function()
		local now, later = PlotRedraw.Split(pads, {})
		t.eq(now, { 1, 2, 3 })
		t.eq(later, {})
		now, later = PlotRedraw.Split(pads, { { x = 0, z = 0 }, { x = 300, z = 0 }, { x = 600, z = 0 } })
		t.eq(now, {})
		t.eq(later, { 1, 2, 3 })
	end)

	t.test("the radius is flat distance, edge inclusive", function()
		local r = PlotRedraw.NearRadius
		local _, later = PlotRedraw.Split(pads, { { x = r, z = 0 } })
		t.eq(later, { 1 })
		_, later = PlotRedraw.Split(pads, { { x = r + 0.5, z = 0 } })
		t.eq(later, {})
		_, later = PlotRedraw.Split(pads, { { x = 5, z = 5 } }, 2)
		t.eq(later, {}, "a smaller radius")
	end)

	t.test("regression: the late redraw asks PlotRedraw instead of rebuilding every pad at once", function()
		local source = fs.readFile("src/ServerScriptService/PlotService.luau")
		t.ok(string.find(source, "PlotRedraw.Split(pads, players)", 1, true))
		t.ok(string.find(source, "function PlotService.RedrawLate", 1, true))
		-- The old code redrew every slot in one loop in the meshes' callback.
		local init = string.match(source, "ItemMeshes.LoadAsync%(%).-end%)\n")
		t.ok(init and string.find(init, "PlotService.RedrawLate()", 1, true))
		t.ok(init and string.find(init, "redrawSlot(slot)", 1, true) == nil, "no bare loop over every pad")
	end)
end
