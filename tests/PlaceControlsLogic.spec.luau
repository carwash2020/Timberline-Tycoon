--!nocheck
-- Lane F, Step 8 / QA BL1: placement controls on PC, phone and Xbox. The
-- bindings never include the right trigger; every action is reachable on every
-- device; the on-screen buttons are 44 px or more with 8 px between and, on a
-- phone, stay out of the thumbstick and jump zones at the test sizes.
return function(t)
	local Controls = t.shared("PlaceControlsLogic")

	t.test("the bindings are valid: no right trigger, no key doing two jobs, everything reachable", function()
		t.eq({ Controls.Validate() }, { true, nil })
		t.eq(table.find(Controls.AllKeys(), "ButtonR2"), nil, "ButtonR2 is never bound")
		for _, device in ipairs({ "desktop", "console", "phone" }) do
			t.eq(Controls.Unreachable(device), {}, device .. " reaches every action")
		end
	end)

	t.test("the brief's table, exactly", function()
		t.eq(Controls.KeysFor("desktop", "rotate"), { "R" })
		t.eq(Controls.KeysFor("desktop", "cancel"), { "Q" })
		t.eq(Controls.KeysFor("desktop", "raise"), { "PageUp", "E" }, "PageUp, and the old E stays")
		t.eq(Controls.KeysFor("desktop", "lower"), { "PageDown", "C" })
		t.eq(Controls.KeysFor("desktop", "place"), {}, "a PC places with the left mouse button")
		t.eq(Controls.PlaceMouse, "MouseButton1")
		t.eq(Controls.KeysFor("console", "place"), { "ButtonA" }, "A places, not the right trigger")
		t.eq(Controls.KeysFor("console", "rotate"), { "DPadRight" })
		t.eq(Controls.KeysFor("console", "raise"), { "DPadUp" })
		t.eq(Controls.KeysFor("console", "lower"), { "DPadDown" })
		t.eq(Controls.KeysFor("console", "cancel"), { "ButtonB" }, "B closes")
		t.eq(Controls.GamepadExtras.lock, "ButtonL2", "LT locks")
		t.eq(Controls.GamepadExtras.pushOut, "ButtonR1")
		t.eq(Controls.GamepadExtras.pushIn, "ButtonL1")
		t.eq(Controls.GamepadExtras.stick, "Thumbstick1")
		for _, action in ipairs(Controls.Actions) do
			t.eq(Controls.KeysFor("phone", action), {}, "a phone has buttons, not keys")
		end
	end)

	local sizes = {
		{ "phone", 667, 375, 0.78 }, -- UITheme.ScaleFor on a 375-tall phone
		{ "phone", 667, 375, 1 },
		{ "phone", 812, 375, 0.78 },
		{ "desktop", 1920, 1080, 1.25 },
		{ "desktop", 1280, 720, 1 },
	}

	t.test("every button is at least 44 x 44 UI units with 8 between, and inside the screen", function()
		for _, row in ipairs(sizes) do
			local device, w, h, scale = row[1], row[2], row[3], row[4]
			local layout = Controls.Layout(device, { x = w, y = h }, 70, scale)
			local rects = {}
			for _, action in ipairs(Controls.Actions) do
				local rect = layout.buttons[action]
				local label = string.format("%s %dx%d@%.2f %s", device, w, h, scale, action)
				t.ok(rect ~= nil, label .. " exists")
				t.ok(rect.w >= 44 and rect.h >= 44, label .. " is " .. rect.w .. "x" .. rect.h)
				local px = Controls.ScreenRect(layout, action)
				t.ok(px.x >= 0 and px.y >= 0 and px.x + px.w <= w and px.y + px.h <= h, label .. " is on screen")
				table.insert(rects, rect)
			end
			for i = 1, #rects do
				for j = i + 1, #rects do
					local a, b = rects[i], rects[j]
					t.eq(Controls.Overlaps(a, b), false, "buttons do not overlap")
					local gapX = math.max(b.x - (a.x + a.w), a.x - (b.x + b.w))
					local gapY = math.max(b.y - (a.y + a.h), a.y - (b.y + b.h))
					t.ok(math.max(gapX, gapY) >= 8 - 1e-6, string.format("%s %dx%d: 8 between buttons", device, w, h))
				end
			end
		end
	end)

	t.test("on a phone nothing sits in the thumbstick or jump zones (the label line included)", function()
		for _, row in ipairs(sizes) do
			local device, w, h, scale = row[1], row[2], row[3], row[4]
			if device == "phone" then
				local layout = Controls.Layout(device, { x = w, y = h }, 70, scale)
				local zones = Controls.Zones({ x = w, y = h })
				local at = string.format("%dx%d@%.2f", w, h, scale)
				t.eq(Controls.Overlaps(layout.bar, zones.thumb), false, at .. " bar clear of the thumbstick")
				t.eq(Controls.Overlaps(layout.bar, zones.jump), false, at .. " bar clear of jump")
				for _, action in ipairs(Controls.Actions) do
					local rect = Controls.ScreenRect(layout, action)
					t.eq(Controls.Overlaps(rect, zones.thumb), false, action .. " clear of the thumbstick")
					t.eq(Controls.Overlaps(rect, zones.jump), false, action .. " clear of jump")
				end
			end
		end
	end)

	t.test("the phone grid keeps every action in the brief's order and PLACE and CANCEL apart", function()
		local layout = Controls.Layout("phone", { x = 667, y = 375 }, 70)
		t.eq({ layout.columns, layout.rows }, { 2, 3 })
		local place, cancel = layout.buttons.place, layout.buttons.cancel
		t.eq(
			Controls.Overlaps(
				{ x = place.x, y = place.y, w = place.w, h = place.h },
				{ x = cancel.x, y = cancel.y, w = cancel.w, h = cancel.h }
			),
			false
		)
		t.ok(cancel.y - (place.y + place.h) >= 8, "an accidental tap on CANCEL does not land on PLACE")
		for _, action in ipairs(Controls.Actions) do
			t.ok(Controls.Labels[action] ~= nil)
		end
	end)

	t.test("an Xbox bar has no buttons: the pad has every action, the hint line says how", function()
		local layout = Controls.Layout("console", { x = 1920, y = 1080 }, 70)
		t.eq(next(layout.buttons), nil)
		t.ok(Controls.Hints.console:find("A place") ~= nil and Controls.Hints.console:find("B stop") ~= nil)
		t.ok(Controls.Hints.phone:find("PLACE") ~= nil)
		t.ok(Controls.Hints.desktop:find("R to turn") ~= nil)
		t.eq(Controls.Hints.console:find("RT"), nil, "no mention of the right trigger")
	end)

	t.test("a drag starts only on or next to the ghost; elsewhere a touch is the camera's", function()
		local ghost = { x = 300, y = 200 }
		t.eq(Controls.StartsDrag({ x = 310, y = 210 }, ghost), true)
		t.eq(Controls.StartsDrag({ x = 300 + Controls.DragGrab, y = 200 }, ghost), true)
		t.eq(Controls.StartsDrag({ x = 300 + Controls.DragGrab + 1, y = 200 }, ghost), false)
		t.eq(Controls.StartsDrag({ x = 10, y = 10 }, ghost), false)
		t.eq(Controls.StartsDrag({ x = 300, y = 200 }, nil), false, "no ghost on screen")
	end)
end
