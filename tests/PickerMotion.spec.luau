--!nocheck
-- PickerMotion (T420): the picker's motion is cheap (short tweens, no loops, a
-- cap on how many cards animate) and gives way to the player's "calm the screen"
-- setting: with it on, nothing slides, scales or fades in; the picker just
-- appears. UITheme.Tween is the one place a tween is made, and it honours it.
return function(t)
	local Motion = t.shared("PickerMotion")
	local roblox = t.roblox

	t.test("every effect is short and the whole open is under half a second", function()
		for _, name in ipairs({ "Open", "Close", "Hover", "Press", "Select", "CardIn", "TabIn" }) do
			local spec = Motion[name]
			t.ok(spec ~= nil, name .. " is defined")
			t.ok(spec.seconds > 0 and spec.seconds <= 0.3, name .. " is short: " .. tostring(spec.seconds))
		end
		t.ok(Motion.OpenTotal(false) <= 0.5, "slide plus the last card in: " .. Motion.OpenTotal(false))
	end)

	t.test("hover and press are small nudges, never a jump", function()
		t.ok(Motion.Hover.scale > 1 and Motion.Hover.scale <= 1.06)
		t.ok(Motion.Press.scale < 1 and Motion.Press.scale >= 0.94)
		t.eq(Motion.Scale(false, false, false), 1)
		t.eq(Motion.Scale(true, false, false), Motion.Hover.scale)
		t.eq(Motion.Scale(true, true, false), Motion.Press.scale, "press wins over hover")
	end)

	t.test("calm screen: no slide, no scale, no fade-in, no stagger; every duration is zero", function()
		t.eq(Motion.Seconds(Motion.Open, true), 0)
		t.eq(Motion.Seconds(Motion.Close, true), 0)
		t.eq(Motion.Slide(Motion.Open, true), 0)
		t.eq(Motion.Scale(true, false, true), 1)
		t.eq(Motion.Scale(true, true, true), 1)
		t.eq(Motion.Delay(5, true), 0)
		t.eq(Motion.OpenTotal(true), 0)
		t.ok(not Motion.Animates(1, true))
	end)

	t.test("only the first cards animate in, with a capped total stagger", function()
		t.ok(Motion.Animates(1, false))
		t.ok(Motion.Animates(Motion.MaxAnimated, false))
		t.ok(not Motion.Animates(Motion.MaxAnimated + 1, false), "a long tab does not start dozens of tweens")
		t.ok(Motion.Delay(Motion.MaxAnimated, false) <= Motion.MaxStagger + 1e-9)
		t.ok(Motion.Delay(2, false) > Motion.Delay(1, false))
		t.eq(Motion.Delay(1, false), 0)
	end)

	t.test("reduced motion is the existing calm-screen rule: the reduce flag, or shake switched off", function()
		t.ok(Motion.Reduced(true, nil))
		t.ok(Motion.Reduced(nil, false))
		t.ok(not Motion.Reduced(nil, nil))
		t.ok(not Motion.Reduced(false, true))
	end)

	t.test("UITheme.Tween plays a tween, or sets the end state at once when the screen is calm", function()
		local created, played = {}, 0
		local reduced = false
		local playerGui = roblox.Instance.new("Folder")
		local loader = t.loader({
			services = {
				GuiService = {
					IsTenFootInterface = function()
						return false
					end,
					TopbarInset = roblox.Rect.new(0, 0, 0, 0),
					GetGuiInset = function()
						return roblox.Vector2.new(0, 0), roblox.Vector2.zero
					end,
				},
				Players = {
					LocalPlayer = {
						WaitForChild = function()
							return playerGui
						end,
						GetAttribute = function(_, name)
							if name == "SettingReduceFlashing" then
								return reduced
							end
							return nil
						end,
					},
				},
				TextChatService = {},
				UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
				TweenService = {
					Create = function(_, obj, info, goal)
						table.insert(created, { obj = obj, info = info, goal = goal })
						return {
							Play = function()
								played += 1
							end,
							Cancel = function() end,
						}
					end,
				},
			},
			globals = {
				TweenInfo = {
					new = function(seconds)
						return { seconds = seconds }
					end,
				},
				workspace = { CurrentCamera = { ViewportSize = roblox.Vector2.new(1920, 1080) } },
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
				},
			},
		})
		local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
		local frame = roblox.Instance.new("Frame")
		UITheme.Tween(frame, 0.2, { BackgroundTransparency = 0.5 })
		t.eq(#created, 1)
		t.eq(played, 1)
		t.eq(created[1].goal.BackgroundTransparency, 0.5)
		reduced = true
		UITheme.Tween(frame, 0.2, { BackgroundTransparency = 0.25 })
		t.eq(#created, 1, "no tween is made while the screen is calm")
		t.eq(frame.BackgroundTransparency, 0.25, "the end state is set directly")
	end)
end
