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
		t.eq(table.find(Controls.AllKeys(), "ButtonA"), nil, "A only jumps")
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
		t.eq(Controls.KeysFor("console", "place"), {}, "RT places through the hammer; A only jumps")
		t.eq(Controls.HammerPlaces, true)
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
		t.eq(
			Controls.Hints.console,
			"RT place · D-pad right turn · D-pad up/down raise · LT lock · B stop",
			"RT places now, and the hint says so"
		)
		t.ok(Controls.Hints.phone:find("PLACE") ~= nil)
		t.ok(Controls.Hints.desktop:find("R rotate") ~= nil)
		t.eq(Controls.Hints.console:find("A place"), nil, "A no longer places")
	end)

	t.test("each device's hint names every action bound for that device, and no other", function()
		for _, device in ipairs({ "desktop", "console", "phone" }) do
			local bound = {}
			for _, action in ipairs(Controls.BoundActions(device)) do
				bound[action] = true
			end
			local named = {}
			for _, part in ipairs(Controls.HintParts[device]) do
				t.ok(Controls.Hints[device]:find(part.text, 1, true) ~= nil, device .. " hint holds " .. part.text)
				for _, action in ipairs(part.actions) do
					t.ok(bound[action], device .. " hint names " .. action .. ", which it cannot do")
					named[action] = true
				end
			end
			for action in pairs(bound) do
				t.ok(named[action], device .. " hint leaves out " .. action)
			end
		end
		-- No device's hint borrows another's controls.
		t.eq(Controls.Hints.desktop:find("RT"), nil)
		t.eq(Controls.Hints.desktop:find("D-pad"), nil)
		t.eq(Controls.Hints.phone:find("Click"), nil)
		t.eq(Controls.Hints.phone:find("D-pad"), nil)
		t.eq(Controls.Hints.console:find("Click"), nil)
		t.eq(Controls.Hints.console:find("PgUp"), nil)
		-- The pad's lock is the one extra action, and only the pad has it.
		t.eq(table.find(Controls.BoundActions("console"), "lock") ~= nil, true)
		t.eq(table.find(Controls.BoundActions("desktop"), "lock"), nil)
	end)

	t.test("the hint pill: Scale only, inside the 5 percent safe area, above the bar on a phone", function()
		local fs = require("@lune/fs")
		local sizes = {
			{ "console", 1920, 1080, 1.25 },
			{ "console", 1280, 720, 1 },
			{ "desktop", 1920, 1080, 1.25 },
			{ "desktop", 1280, 720, 1 },
			{ "phone", 667, 375, 0.78 },
			{ "phone", 812, 375, 0.78 },
		}
		t.eq(Controls.PillMin, { w = 260, h = 40 })
		t.eq(Controls.PillMax, { w = 520, h = 64 })
		for _, row in ipairs(sizes) do
			local device, w, h, scale = row[1], row[2], row[3], row[4]
			local at = string.format("%s %dx%d", device, w, h)
			local bottom = (if device == "console" then 36 else 12) + (if device == "phone" then 58 else 70)
			local pill = Controls.Pill(device, { x = w, y = h }, bottom * scale, scale)
			t.eq(pill.x, 0.5, at)
			t.ok(pill.w > 0 and pill.w <= 1 and pill.h > 0 and pill.h <= 1, at .. ": scale sizes")
			local r = pill.rect
			t.ok(r.x >= w * 0.05 - 1e-6 and r.x + r.w <= w * 0.95 + 1e-6, at .. ": inside the side safe area")
			t.ok(r.y >= h * 0.05 - 1e-6 and r.y + r.h <= h * 0.95 + 1e-6, at .. ": inside the top and bottom safe area")
			t.ok(r.w >= 260 * scale - 1e-6 or r.w >= w * 0.9, at .. ": at least the minimum width")
			-- Clear of the build bar and the hotbar.
			local bar = Controls.Layout(device, { x = w, y = h }, bottom * scale, scale).bar
			t.ok(r.y + r.h <= bar.y - Controls.PillGap + 1e-6, at .. ": above the build bar")
			t.ok(r.y + r.h <= h - bottom * scale - Controls.PillAboveHotbar + 1e-6, at .. ": 24 px above the hotbar")
		end
		-- The label is Scale only in the HUD: no offset size or position for the pill.
		local hud = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HUD.luau")
		t.ok(hud:find("hint.Position = UDim2.fromScale(pill.x, pill.y)", 1, true), "Scale-only Position")
		t.ok(hud:find("hint.Size = UDim2.fromScale(pill.w, pill.h)", 1, true), "Scale-only Size")
		t.ok(hud:find("PlaceControlsLogic.PillMin.w", 1, true) and hud:find("PlaceControlsLogic.PillMax.h", 1, true))
	end)

	t.test("a drag starts only on or next to the ghost; elsewhere a touch is the camera's", function()
		local ghost = { x = 300, y = 200 }
		t.eq(Controls.StartsDrag({ x = 310, y = 210 }, ghost), true)
		t.eq(Controls.StartsDrag({ x = 300 + Controls.DragGrab, y = 200 }, ghost), true)
		t.eq(Controls.StartsDrag({ x = 300 + Controls.DragGrab + 1, y = 200 }, ghost), false)
		t.eq(Controls.StartsDrag({ x = 10, y = 10 }, ghost), false)
		t.eq(Controls.StartsDrag({ x = 300, y = 200 }, nil), false, "no ghost on screen")
	end)

	t.test("the left stick turns the ghost, the camera's right stick is never bound, ButtonR2 is nowhere", function()
		local fs = require("@lune/fs")
		local dir = "src/StarterPlayer/StarterPlayerScripts/"
		local placeSrc = fs.readFile(dir .. "PlaceControls.luau")
		local placerSrc = fs.readFile(dir .. "BlueprintPlacer.luau")
		local logicSrc = fs.readFile("src/ReplicatedStorage/Shared/PlaceControlsLogic.luau")
		-- The stick the placer turns with is the LEFT one (Thumbstick1), with LT held.
		t.eq(Controls.GamepadExtras.stick, "Thumbstick1")
		t.ok(string.find(logicSrc, '"Thumbstick1"', 1, true), "the logic names the left stick")
		t.ok(string.find(placeSrc, "extras.stick", 1, true), "PlaceControls binds it")
		t.ok(
			string.find(placeSrc, "GrabLogic.StickWalks(", 1, true)
				or string.find(placerSrc, "GrabLogic.StickWalks(", 1, true)
		)
		-- No source of the placer binds the right stick or the right trigger as an input.
		for name, src in pairs({ PlaceControls = placeSrc, BlueprintPlacer = placerSrc }) do
			t.eq(string.find(src, "Thumbstick2", 1, true), nil, name .. " never binds the right stick")
			t.eq(string.find(src, "KeyCode.ButtonR2", 1, true), nil, name .. " never binds ButtonR2")
		end
		for _, keys in pairs(Controls.AllKeys()) do
			t.ok(keys ~= "Thumbstick2" and keys ~= "ButtonR2", "AllKeys " .. tostring(keys))
		end
	end)
end
