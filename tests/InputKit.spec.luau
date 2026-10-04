--!nocheck
-- InputKit: touch size, the per-context key map, and the Open/Forest proof.
return function(t)
	local InputKit = t.shared("InputKit")
	local ForestData = t.shared("ForestData")
	local Enum = t.roblox.Enum
	local Instance = t.roblox.Instance

	local function bind(action, gamepad, keyboard)
		return { action = action, gamepad = gamepad, keyboard = keyboard }
	end

	t.test("touch targets are 44 px and tags are 14 px at 667x375", function()
		t.eq(InputKit.MinTouchPx, 44)
		t.eq(InputKit.MinTagPx, 14)
		t.eq(InputKit.PhoneWidth, 667)
		t.eq(InputKit.PhoneHeight, 375)
		t.ok(InputKit.TouchOk(44))
		t.ok(not InputKit.TouchOk(43))
		t.ok(InputKit.TagOk(14))
		t.ok(not InputKit.TagOk(13))
	end)

	t.test("the safe area is CoreUISafeInsets", function()
		t.eq(InputKit.SafeInsets, Enum.ScreenInsets.CoreUISafeInsets)
		t.ok(InputKit.UsesCoreSafeInsets(Enum.ScreenInsets.CoreUISafeInsets))
		t.ok(not InputKit.UsesCoreSafeInsets(Enum.ScreenInsets.DeviceSafeInsets))
		t.ok(not InputKit.UsesCoreSafeInsets(Enum.ScreenInsets.None))
	end)

	t.test("ButtonX is Interact, Talk, and Buy", function()
		t.eq(#InputKit.ButtonXActions, 3)
		for _, name in ipairs(InputKit.ButtonXActions) do
			t.ok(InputKit.IsButtonXAction(name), name)
			t.eq(InputKit.Actions[name].gamepad, Enum.KeyCode.ButtonX)
			t.eq(InputKit.Actions[name].keyboard, Enum.KeyCode.E)
		end
		t.eq(InputKit.Actions.Open.gamepad, Enum.KeyCode.ButtonY)
		t.eq(InputKit.Actions.Open.keyboard, Enum.KeyCode.F)
		t.eq(InputKit.Actions.Forest.gamepad, Enum.KeyCode.ButtonY)
		t.eq(InputKit.Actions.Forest.keyboard, Enum.KeyCode.F)
		t.eq(InputKit.Actions.Cancel.gamepad, Enum.KeyCode.ButtonB)
		for _, context in ipairs(InputKit.ContextNames) do
			for _, row in ipairs(InputKit.Target[context]) do
				if row.gamepad == Enum.KeyCode.ButtonX then
					t.ok(InputKit.IsButtonXAction(row.action), context .. " " .. row.action)
				end
			end
		end
	end)

	t.test("keys are unique inside each context", function()
		t.eq(#InputKit.ContextNames, 4)
		-- Open and Forest share ButtonY only with the apart proof.
		t.ok(InputKit.KeysUnique(InputKit.Target.world, true))
		t.ok(not InputKit.KeysUnique(InputKit.Target.world, false))
		t.ok(not InputKit.KeysUnique(InputKit.Target.world, nil))
		for _, context in ipairs({ "placer", "drag", "menu" }) do
			t.ok(InputKit.KeysUnique(InputKit.Target[context], false), context)
		end
		-- Two different drag actions on one pad button.
		local clash = {
			bind("Further", Enum.KeyCode.DPadUp, nil),
			bind("Yaw", Enum.KeyCode.DPadUp, nil),
		}
		t.ok(not InputKit.KeysUnique(clash, true))
		-- ButtonX is not a free key for some other action.
		local honk = { bind("Honk", Enum.KeyCode.ButtonX, Enum.KeyCode.H) }
		t.ok(not InputKit.KeysUnique(honk, true))
	end)

	t.test("Open and Forest share ButtonY only when no spot is in both ranges", function()
		t.eq(InputKit.OpenRange, 10)
		t.eq(InputKit.ForestRange, ForestData.PlantRange - 2)
		local pad = { x = 0, z = 0, half = 100 }
		-- On the boundary (gap == 20) a point is still inside both discs.
		local edge = { { x = 100 + InputKit.OpenRange + InputKit.ForestRange, z = 0 } }
		t.ok(not InputKit.OpenForestApart(edge, { pad }, InputKit.OpenRange, InputKit.ForestRange))
		local clear = { { x = 100 + InputKit.OpenRange + InputKit.ForestRange + 0.1, z = 0 } }
		t.ok(InputKit.OpenForestApart(clear, { pad }, InputKit.OpenRange, InputKit.ForestRange))
		local inside = { { x = 10, z = 10 } }
		t.ok(not InputKit.OpenForestApart(inside, { pad }, InputKit.OpenRange, InputKit.ForestRange))
		-- The world binds are unique with that clear pair, and not with the overlap.
		t.ok(InputKit.KeysUnique(InputKit.Target.world, true))
		t.ok(not InputKit.KeysUnique(InputKit.Target.world, false))
	end)

	t.test("the placer target uses no ButtonX, and E or ButtonX needs prompts off", function()
		for _, row in ipairs(InputKit.Target.placer) do
			t.ok(row.gamepad ~= Enum.KeyCode.ButtonX, row.action)
		end
		local rotate = InputKit.Target.placer[1]
		t.eq(rotate.action, "Rotate")
		t.eq(rotate.keyboard, Enum.KeyCode.R)
		t.eq(rotate.gamepad, Enum.KeyCode.DPadRight)
		-- Raise is still E, which is world Interact. Safe only with prompts off.
		t.ok(not InputKit.PlacerSafe(InputKit.Target.placer, true))
		t.ok(InputKit.PlacerSafe(InputKit.Target.placer, false))
		local raise = { bind("Raise", Enum.KeyCode.ButtonR1, Enum.KeyCode.E) }
		t.ok(not InputKit.PlacerSafe(raise, true))
		t.ok(InputKit.PlacerSafe(raise, false))
	end)

	t.test("today's placer binds fail while prompts are on and pass when they are off", function()
		-- BlueprintPlacer.luau:360-388. Rotate is still ButtonX. Raise is E.
		local today = {
			bind("Rotate", Enum.KeyCode.ButtonX, Enum.KeyCode.R),
			bind("Place", Enum.KeyCode.ButtonR2, nil),
			bind("Cancel", Enum.KeyCode.ButtonB, Enum.KeyCode.Q),
			bind("Raise", Enum.KeyCode.ButtonR1, Enum.KeyCode.E),
			bind("Lower", Enum.KeyCode.ButtonL1, Enum.KeyCode.C),
		}
		t.ok(not InputKit.PlacerSafe(today, true))
		t.ok(InputKit.PlacerSafe(today, false))
	end)

	t.test("PromptDefaults sets the mapped keys and line of sight, and is idempotent", function()
		local prompt = Instance.new("ProximityPrompt")
		prompt.KeyboardKeyCode = Enum.KeyCode.G
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonL3
		prompt.RequiresLineOfSight = true
		InputKit.PromptDefaults(prompt)
		t.eq(prompt.KeyboardKeyCode, Enum.KeyCode.E)
		t.eq(prompt.GamepadKeyCode, Enum.KeyCode.ButtonX)
		t.eq(prompt.RequiresLineOfSight, false)
		prompt.KeyboardKeyCode = Enum.KeyCode.G
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonL3
		prompt.RequiresLineOfSight = true
		InputKit.PromptDefaults(prompt, "Interact")
		local keyboard, gamepad, sight = prompt.KeyboardKeyCode, prompt.GamepadKeyCode, prompt.RequiresLineOfSight
		InputKit.PromptDefaults(prompt, "Interact")
		t.eq(prompt.KeyboardKeyCode, keyboard)
		t.eq(prompt.GamepadKeyCode, gamepad)
		t.eq(prompt.RequiresLineOfSight, sight)

		InputKit.PromptDefaults(prompt, "Open")
		t.eq(prompt.KeyboardKeyCode, Enum.KeyCode.F)
		t.eq(prompt.GamepadKeyCode, Enum.KeyCode.ButtonY)
		t.eq(prompt.RequiresLineOfSight, false)
		InputKit.PromptDefaults(prompt, "Open")
		t.eq(prompt.KeyboardKeyCode, Enum.KeyCode.F)
		t.eq(prompt.GamepadKeyCode, Enum.KeyCode.ButtonY)

		InputKit.PromptDefaults(prompt, "Forest")
		t.eq(prompt.GamepadKeyCode, Enum.KeyCode.ButtonY)
		InputKit.PromptDefaults(prompt, "Talk")
		t.eq(prompt.GamepadKeyCode, Enum.KeyCode.ButtonX)
		InputKit.PromptDefaults(prompt, "Buy")
		t.eq(prompt.KeyboardKeyCode, Enum.KeyCode.E)
		t.fails(function()
			InputKit.PromptDefaults(prompt, "Honk")
		end, "unknown action")
	end)
end
