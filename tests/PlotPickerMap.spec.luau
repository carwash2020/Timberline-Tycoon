--!nocheck
-- The plot picker's map card and shot maths (Shared/PlotPickerMap).
return function(t)
	local Map = t.shared("PlotPickerMap")

	local function near(a, b)
		t.ok(math.abs(a - b) < 1e-9, tostring(a) .. " vs " .. tostring(b))
	end

	local function plots()
		return {
			{ x = 0, z = 0, taken = false },
			{ x = 100, z = 0, taken = true },
			{ x = 100, z = 50, taken = false },
		}
	end

	t.test("the chosen pad is selected, taken ones grey, open ones green", function()
		t.eq(Map.State(false, true), "selected")
		t.eq(Map.State(true, true), "selected")
		t.eq(Map.State(true, false), "taken")
		t.eq(Map.State(false, false), "open")
		local dots = Map.Layout(plots(), 2)
		t.eq(dots[1].state, "open")
		t.eq(dots[2].state, "selected")
		t.eq(dots[3].state, "open")
		dots = Map.Layout(plots(), 3)
		t.eq(dots[2].state, "taken")
	end)

	t.test("every dot sits inside the card with the margin kept", function()
		for _, dot in ipairs(Map.Layout(plots(), 1)) do
			t.ok(dot.fx >= Map.Margin - 1e-9 and dot.fx <= 1 - Map.Margin + 1e-9, "x in range")
			t.ok(dot.fy >= Map.Margin - 1e-9 and dot.fy <= 1 - Map.Margin + 1e-9, "y in range")
		end
	end)

	t.test("north is up, east is right, and the shape is not stretched", function()
		local dots = Map.Layout(plots(), 1)
		t.ok(dots[2].fx > dots[1].fx, "larger x is further right")
		near(dots[2].fy, dots[1].fy)
		t.ok(dots[3].fy > dots[2].fy, "larger z is lower")
		near(dots[3].fy - dots[2].fy, (dots[2].fx - dots[1].fx) / 2)
	end)

	t.test("one pad, or none, does not break the layout", function()
		t.eq(#Map.Layout({}, 1), 0)
		local one = Map.Layout({ { x = 40, z = -9, taken = false } }, 1)
		near(one[1].fx, 0.5)
		near(one[1].fy, 0.5)
		local line = Map.Layout({ { x = 0, z = 5, taken = false }, { x = 10, z = 5, taken = false } }, 1)
		near(line[1].fy, 0.5)
	end)

	t.test("a tap picks the nearest pad", function()
		local dots = Map.Layout(plots(), 1)
		t.eq(Map.Nearest(dots, dots[3].fx, dots[3].fy), 3)
		t.eq(Map.Nearest(dots, 0, 0), 1)
		t.eq(Map.Nearest({}, 0.5, 0.5), nil)
	end)

	t.test("the shot looks at the pad from up and behind", function()
		local shot = Map.Shot({ x = 10, y = 2, z = 20 })
		t.eq(shot.atX, 10)
		t.eq(shot.atY, 2 + Map.FocusUp)
		t.eq(shot.atZ, 20)
		t.eq(shot.fromX, 10 + Map.CameraBack.x)
		t.eq(shot.fromY, 2 + Map.CameraBack.y)
		t.eq(shot.fromZ, 20 + Map.CameraBack.z)
	end)

	t.test("the glide is frame-rate independent and never overshoots", function()
		t.eq(Map.Ease(0, 8), 0)
		t.ok(Map.Ease(1 / 60, 8) > 0 and Map.Ease(1 / 60, 8) < 1)
		near(1 - (1 - Map.Ease(1 / 60, 8)) ^ 2, Map.Ease(2 / 60, 8))
		t.ok(Map.Ease(10, 8) <= 1)
	end)

	t.test("the words", function()
		t.eq(Map.ClaimedText("Pine Ridge"), "Claimed Pine Ridge!")
		t.eq(Map.LoadingText(true), "Loading view…")
		t.eq(Map.LoadingText(false), "")
		t.eq(Map.FadeSeconds, 0.4)
	end)
end
