--!nocheck
-- DropControls: how you drop the axe or plan in hand without an on-screen
-- button, and when B drops versus closes. Also source checks that the drop
-- is bound below every other B handler and that the Drop button is gone.
return function(t)
	local DropControls = t.shared("DropControls")
	local InputKit = t.shared("InputKit")
	local Enum = t.roblox.Enum
	local KeyCode = Enum.KeyCode

	local function state(over)
		local s = {
			holding = true,
			typing = false,
			menu = false,
			dialogue = false,
			placing = false,
			grabbing = false,
			seated = false,
		}
		for k, v in pairs(over or {}) do
			s[k] = v
		end
		return s
	end

	t.test("each device has its own drop key: B on a pad, Q and Backspace on a keyboard", function()
		t.eq(DropControls.PadKey, KeyCode.ButtonB)
		t.eq(DropControls.DeviceOf(KeyCode.ButtonB), "console")
		t.eq(DropControls.DeviceOf(KeyCode.Q), "desktop")
		t.eq(DropControls.DeviceOf(KeyCode.Backspace), "desktop")
		t.eq(DropControls.DeviceOf(KeyCode.E), nil)
		t.eq(DropControls.DeviceOf(KeyCode.DPadDown), nil, "the D-pad no longer drops")
		t.eq(InputKit.DropBind.gamepad, DropControls.PadKey)
		t.eq(InputKit.DropBind.keyboard, KeyCode.Q)
	end)

	t.test("with nothing open and an axe or plan in hand, every drop key drops", function()
		t.eq(DropControls.Decide(KeyCode.ButtonB, state()), "drop")
		t.eq(DropControls.Decide(KeyCode.Q, state()), "drop")
		t.eq(DropControls.Decide(KeyCode.Backspace, state()), "drop")
	end)

	t.test("with nothing to drop, a drop key does nothing", function()
		for _, key in ipairs({ KeyCode.ButtonB, KeyCode.Q, KeyCode.Backspace }) do
			t.eq(DropControls.Decide(key, state({ holding = false })), "ignore", key.Name)
		end
	end)

	t.test("B closes whatever is open; it never drops", function()
		for _, layer in ipairs({ "menu", "dialogue", "placing", "grabbing" }) do
			t.eq(DropControls.Decide(KeyCode.ButtonB, state({ [layer] = true })), "close", layer)
			t.eq(DropControls.Decide(KeyCode.ButtonB, state({ [layer] = true, holding = false })), "close", layer)
			-- Q and Backspace mean something else (or nothing) there: not the drop's.
			t.eq(DropControls.Decide(KeyCode.Q, state({ [layer] = true })), "ignore", layer)
			t.eq(DropControls.Decide(KeyCode.Backspace, state({ [layer] = true })), "ignore", layer)
		end
	end)

	t.test("seated, or typing in the chat: never a drop", function()
		for _, key in ipairs({ KeyCode.ButtonB, KeyCode.Q, KeyCode.Backspace }) do
			t.eq(DropControls.Decide(key, state({ seated = true })), "ignore", key.Name)
			t.eq(DropControls.Decide(key, state({ typing = true })), "ignore", key.Name)
		end
	end)

	t.test("a key that isn't a drop key is ignored whatever is going on", function()
		t.eq(DropControls.Decide(KeyCode.E, state()), "ignore")
		t.eq(DropControls.Decide(KeyCode.ButtonA, state({ menu = true })), "ignore")
		t.eq(DropControls.Decide(KeyCode.ButtonX, state()), "ignore")
	end)

	t.test("one press is never a close and a drop: closing leaves B with the menu", function()
		-- Press 1: a menu is open, B closes it (Decide says close, the drop passes).
		t.eq(DropControls.Decide(KeyCode.ButtonB, state({ menu = true })), "close")
		-- Press 2: it is shut, and only now does B drop.
		t.eq(DropControls.Decide(KeyCode.ButtonB, state({ menu = false })), "drop")
	end)

	t.test("a phone: a long press on the hotbar strip drops, anywhere else does not", function()
		local w, h = 667, 375
		t.ok(DropControls.InHotbarBand(333, 360, w, h), "the middle of the bottom edge")
		t.ok(not DropControls.InHotbarBand(333, 100, w, h), "up in the world")
		t.ok(not DropControls.InHotbarBand(40, 360, w, h), "under the thumbstick")
		t.ok(not DropControls.InHotbarBand(640, 360, w, h), "under the jump button")
		t.ok(not DropControls.InHotbarBand(1, 1, 0, 0), "no screen")
		t.ok(DropControls.TouchDrops(333, 360, w, h, state()))
		t.ok(not DropControls.TouchDrops(333, 100, w, h, state()))
		t.ok(not DropControls.TouchDrops(333, 360, w, h, state({ holding = false })))
		for _, layer in ipairs({ "menu", "dialogue", "placing", "grabbing", "seated", "typing" }) do
			t.ok(not DropControls.TouchDrops(333, 360, w, h, state({ [layer] = true })), layer)
		end
	end)

	t.test("the hints name the right control per device", function()
		t.ok(string.find(DropControls.Hint("console"), "B", 1, true))
		t.ok(string.find(DropControls.Hint("desktop"), "Q", 1, true))
		t.ok(string.find(DropControls.Hint("phone"), "Long-press", 1, true))
		t.eq(DropControls.Confirm("console", "Steel Axe"), "Press B again to drop the Steel Axe.")
		t.eq(DropControls.Confirm("desktop", "plan"), "Press Q again to drop the plan.")
		t.eq(DropControls.Confirm("phone", "plan"), "Long-press again to drop the plan.")
	end)

	-- The B audit, from the source: the drop sits under every other bind.
	t.test("the drop is bound below every menu's B, and the Drop button is gone", function()
		local fs = require("@lune/fs")
		local dir = "src/StarterPlayer/StarterPlayerScripts"
		t.ok(DropControls.Priority < Enum.ContextActionPriority.Medium.Value, "below a plain BindAction")
		local axe = fs.readFile(dir .. "/AxeController.luau")
		t.ok(string.find(axe, "DropControls.Priority", 1, true), "bound at DropControls.Priority")
		t.ok(string.find(axe, "DropControls.Decide", 1, true), "asks DropControls.Decide")
		t.ok(not string.find(axe, "SideButton", 1, true), "no side button")
		t.ok(not string.find(axe, "DPadDown", 1, true), "no D-pad bind")
		t.ok(not string.find(axe, "InputBegan", 1, true), "no unsunk InputBegan handler")
		for _, entry in ipairs(fs.readDir(dir)) do
			if string.match(entry, "%.luau$") and entry ~= "AxeController.luau" then
				local source = fs.readFile(dir .. "/" .. entry)
				t.ok(not string.find(source, 'name = "DropAxe"', 1, true), entry .. " names the old button")
				for call in string.gmatch(source, "BindActionAtPriority%b()") do
					if string.find(call, "ButtonB", 1, true) then
						t.ok(
							not string.find(call, "ContextActionPriority.Low", 1, true),
							entry .. " binds B below the drop"
						)
					end
				end
			end
		end
	end)
end
