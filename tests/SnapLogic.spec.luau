--!nocheck
-- Lane F: the ghost snaps wall ends together and sits on the floor top
-- below; the same placements then pass PlotLogic.Check (QA BL8).
return function(t)
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local Snap = t.shared("SnapLogic")

	local function bp(id)
		return PlotData.Blueprint(id)
	end
	local function near(a, b, msg)
		t.ok(math.abs(a - b) < 1e-4, (msg or "") .. ": " .. tostring(a) .. " vs " .. tostring(b))
	end
	local function at(id, x, z, rot, y, uid)
		return { uid = uid or id, blueprintId = id, x = x, z = z, rot = rot or 0, y = y }
	end

	t.test("a wall end within 1 stud snaps onto another wall's end, then the server agrees", function()
		local placed = { at("Wall4", 0, 0, 0, nil, "a") } -- ends at x -2 and 2
		-- Aimed 0.8 short of a straight join: centre 5.2 rounds to 6 on the grid
		-- (end at 4, two studs off), so ends snap back to x = 2 -> centre 4.
		local x, z, y = Snap.Place(bp("Wall4"), 4.6, 0, 0, 0, placed)
		t.eq({ x, z, y }, { 4, 0, 0 })
		t.eq(PlotLogic.Check(bp("Wall4"), x, z, 0, 1, placed, nil, y), true, "the server takes it")
	end)

	t.test("an end further than 1 stud away does not snap", function()
		local placed = { at("Wall4", 0, 0, 0, nil, "a") }
		local x, z = Snap.Place(bp("Wall4"), 10, 0, 0, 0, placed)
		t.eq({ x, z }, { 10, 0 })
	end)

	t.test("an L corner: a turned wall's end meets the first wall's end", function()
		local placed = { at("Wall4", 0, 0, 0, nil, "a") } -- end at (2, 0)
		local x, z, y = Snap.Place(bp("Wall4"), 2.4, 2.6, 1, 0, placed)
		t.eq({ x, z }, { 2, 2 }, "turned wall from (2,0) to (2,4)")
		t.eq(PlotLogic.Check(bp("Wall4"), x, z, 1, 1, placed, nil, y), true)
	end)

	t.test("a base snaps to the floor, foundation or tall wall top below", function()
		near(Snap.TopOf(bp("Floor4")), 0.4)
		t.eq(Snap.TopOf(bp("Foundation8")), 2)
		t.eq(Snap.TopOf(bp("TallWall8")), 10)
		local placed = { at("Foundation8", 0, 0, 0, nil, "f") }
		local _, _, y = Snap.Place(bp("Wall4"), 0, 0, 0, 0.5, placed)
		near(y, 2, "a wall on a foundation sits on its top")
		t.eq(PlotLogic.Check(bp("Wall4"), 0, 0, 0, 1, placed, nil, y), true)
		local storey = { at("TallWall8", 0, 0, 0, 2, "w") }
		local _, _, y2 = Snap.Place(bp("Floor4"), 0, 0, 0, 11.5, storey)
		near(y2, 12, "the next storey's floor on the tall wall top")
	end)

	t.test("with nothing below, the height stays on the 0.2 grid and in bounds", function()
		local _, _, y = Snap.Place(bp("Wall4"), 0, 0, 0, 3.33, {})
		near(y, 3.4)
		local _, _, top = Snap.Place(bp("Wall4"), 0, 0, 0, 999, {})
		t.eq(top, PlotData.MaxBuildY)
		local _, _, low = Snap.Place(bp("Wall4"), 0, 0, 0, -5, {})
		t.eq(low, 0)
	end)

	t.test("four storeys of tall walls and floors fit under MaxBuildY", function()
		local placed = {}
		local y = 0
		for i = 1, 3 do
			table.insert(placed, at("TallWall8", 0, 0, 0, y, "w" .. i))
			local _, _, fy = Snap.Place(bp("Floor4"), 0, 0, 0, y + 10.5, placed)
			near(fy, y + 10, "storey " .. i)
			table.insert(placed, at("Floor4", 0, 0, 0, fy, "f" .. i))
			y = fy + 0.4
		end
		t.ok(y <= PlotData.MaxBuildY, "the fourth storey's base is under the cap")
		t.eq(PlotLogic.HeightOk(PlotLogic.SnapY(y)), true)
	end)
end
