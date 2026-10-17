--!nocheck
-- Rook's job board (playtest t351): talking to him opens the panel, and it
-- stays open. DailyUI.refresh used to hide the panel on every call, so
-- OpenForeman closed it the same frame and "Three jobs today." showed no jobs.
return function(t)
	local roblox = t.roblox
	local Instance, UDim2 = roblox.Instance, roblox.UDim2
	local DailyData = t.shared("DailyData")
	local ForemanData = t.shared("ForemanData")

	local attrs: { [string]: any } = {}
	local listeners: { [string]: { () -> () } } = {}
	local playerGui = Instance.new("Folder")
	local player = {
		UserId = 12345,
		GetAttribute = function(_, name)
			return attrs[name]
		end,
		GetAttributeChangedSignal = function(_, name)
			return {
				Connect = function(_, fn)
					listeners[name] = listeners[name] or {}
					table.insert(listeners[name], fn)
					return { Disconnect = function() end }
				end,
			}
		end,
		WaitForChild = function(_, name)
			return if name == "PlayerGui" then playerGui else nil
		end,
	}
	local function set(name, value)
		attrs[name] = value
		for _, fn in ipairs(listeners[name] or {}) do
			fn()
		end
	end
	local function noop() end
	local signal = {
		Connect = function()
			return { Disconnect = noop }
		end,
	}
	-- Lune's buttons have no Activated: an inert one will do (the Close handler is
	-- DailyUI._close, called below). The method is registered once for the whole
	-- run, so the Frame signals live on the table other specs share.
	pcall(roblox.implementProperty, "TextButton", "Activated", function()
		return {
			Connect = function()
				return { Disconnect = noop }
			end,
		}
	end)
	local watched = _G.__frameSignals or {}
	_G.__frameSignals = watched
	pcall(roblox.implementMethod, "Frame", "GetPropertyChangedSignal", function(self, prop)
		local listeners = {}
		local ev = {
			Connect = function(_, fn)
				table.insert(listeners, fn)
				return { Disconnect = noop }
			end,
			Fire = function()
				for _, fn in ipairs(listeners) do
					fn()
				end
			end,
		}
		watched[self] = watched[self] or {}
		watched[self][prop] = ev
		return ev
	end)
	local loader = t.loader({
		services = {
			GuiService = {
				SelectedObject = nil,
				IsTenFootInterface = function()
					return false
				end,
			},
			Players = { LocalPlayer = player },
			UserInputService = { TouchEnabled = true, KeyboardEnabled = false, InputBegan = signal },
			TextChatService = {},
		},
		globals = {
			workspace = {
				GetAttribute = function()
					return 2
				end,
				CurrentCamera = { ViewportSize = roblox.Vector2.new(667, 375) },
			},
			task = { spawn = noop, wait = noop, defer = noop, delay = noop },
		},
		mocks = {
			HUD = {
				Popup = noop,
				UnderCash = function()
					return nil
				end,
				PadShortcut = noop,
				PadGlyph = function()
					return Instance.new("Frame")
				end,
			},
			MenuPad = {
				Open = noop,
				Close = noop,
				Closes = function()
					return false
				end,
			},
			Net = {
				Remote = function()
					return { FireServer = noop }
				end,
			},
		},
	})
	local DailyUI = loader:load("StarterPlayer/StarterPlayerScripts/DailyUI")

	local goals = DailyData.Roll(12345, 20000, 1, 2)
	local function find(name)
		for _, gui in ipairs(playerGui:GetChildren()) do
			local hit = gui:FindFirstChild(name, true)
			if hit then
				return hit
			end
		end
		return nil
	end

	t.test("Rook's panel opens with the three jobs and stays open through a refresh", function()
		attrs.TutorialStep = 0
		attrs.DailyResetAt = os.time() + 3600
		attrs.DailyGoals = DailyData.Encode(goals)
		DailyUI.Start()
		local panel = find("Goals")
		t.ok(panel ~= nil, "panel built")
		t.ok(not panel.Visible, "closed until Rook opens it")
		DailyUI.OpenForeman()
		t.ok(panel.Visible, "the panel is visible straight after OpenForeman")
		local rows = 0
		for _, child in ipairs(panel:GetChildren()) do
			if child:IsA("Frame") and child.Visible and child.Name ~= "Actions" then
				for _, d in ipairs(child:GetChildren()) do
					if d:IsA("TextLabel") and string.find(d.Text, DailyData.GoalText(goals[rows + 1]), 1, true) then
						rows += 1
						break
					end
				end
			end
		end
		t.eq(rows, 3, "three job rows, each with its DailyData.GoalText")
		set("DailyGoals", DailyData.Encode(goals))
		t.ok(panel.Visible, "a DailyGoals change does not hide the open panel")
		set("DailyStreak", 2)
		t.ok(panel.Visible, "nor does a streak change")
	end)

	t.test("Close hides the panel, and Take shows only when Rook owes cash", function()
		local panel = find("Goals")
		local take = find("Take")
		local close = find("Close")
		DailyUI.OpenForeman()
		t.ok(not take.Visible, "nothing finished: no Take")
		t.ok(close.Size.X.Offset >= 44 and close.Size.Y.Offset >= 44, "Close is a tap target")
		t.ok(take.Size.Y.Offset >= 44, "Take is a tap target")
		local done = DailyData.Decode(DailyData.Encode(goals))
		done[1].done = true
		done[1].paid = false
		done[1].progress = done[1].target
		set("DailyGoals", DailyData.Encode(done))
		t.ok(ForemanData.Owed(done, 0) > 0)
		t.ok(panel.Visible and take.Visible, "owed cash: Take shows in the Foreman's panel")
		DailyUI._close() -- what Close's Activated does
		t.ok(not panel.Visible, "Close hides it")
		set("DailyGoals", DailyData.Encode(done))
		t.ok(not panel.Visible, "and a refresh does not reopen it")
	end)
end
