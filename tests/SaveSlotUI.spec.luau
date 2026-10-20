--!nocheck
-- T393: the Saves list stays where the player scrolled. The 1 s loop used to
-- call fill(), which destroyed and rebuilt every row; the canvas shrank, the
-- engine put CanvasPosition back to 0 and the gamepad selection was lost.
-- Now the tick repaints in place, the rows are rebuilt only when the payload
-- changes, and a rebuild puts the scroll offset and the selected slot back.
--
-- The UI runs here against local fakes (a plain-table Instance, a mocked
-- UITheme); nothing is registered on Lune's Instance, so other specs are not
-- affected. The fake ScrollingFrame snaps CanvasPosition to 0 when a child is
-- destroyed, like the engine does when the canvas shrinks.
return function(t)
	local roblox = t.roblox
	local Vector2 = roblox.Vector2
	local fs = require("@lune/fs")

	local UI_PATH = "src/StarterPlayer/StarterPlayerScripts/SaveSlotUI.luau"

	local function noop() end

	-- A signal that keeps its handlers so a spec can fire them.
	local function newSignal()
		local handlers = {}
		return {
			Connect = function(_, fn)
				table.insert(handlers, fn)
				return { Disconnect = noop }
			end,
			Fire = function(_, ...)
				for _, fn in ipairs(table.clone(handlers)) do
					fn(...)
				end
			end,
		}
	end

	local FakeInstance = {}
	function FakeInstance.new(class)
		local data = { ClassName = class, Name = class, _children = {}, Destroyed = false }
		if class == "ScrollingFrame" then
			data.CanvasPosition = Vector2.new(0, 0)
			data.AbsoluteCanvasSize = Vector2.new(0, 0)
			data.AbsoluteWindowSize = Vector2.new(0, 0)
		end
		local inst
		inst = setmetatable({}, {
			__index = function(_, key)
				if key == "GetChildren" then
					return function()
						return table.clone(data._children)
					end
				elseif key == "IsA" then
					return function(_, what)
						return what == class or (what == "GuiObject" and class ~= "ScreenGui")
					end
				elseif key == "Destroy" then
					return function()
						data.Destroyed = true
						local parent = data.Parent
						if parent then
							local kids = parent._data._children
							local at = table.find(kids, inst)
							if at then
								table.remove(kids, at)
							end
							if parent.ClassName == "ScrollingFrame" then
								parent.CanvasPosition = Vector2.new(0, 0) -- the engine clamps a shrunk canvas
							end
						end
					end
				elseif key == "SetAttribute" then
					return function(_, name, value)
						data["attr_" .. name] = value
					end
				elseif key == "GetAttribute" then
					return function(_, name)
						return data["attr_" .. name]
					end
				elseif key == "_data" then
					return data
				elseif key == "Parent" then
					return data.Parent
				elseif key == "FocusLost" or key == "Activated" then
					data[key] = data[key] or newSignal()
					return data[key]
				elseif key == "FindFirstChild" then
					return function(_, name)
						for _, c in ipairs(data._children) do
							if c.Name == name then
								return c
							end
						end
						return nil
					end
				end
				return data[key]
			end,
			__newindex = function(_, key, value)
				if key == "Parent" then
					local old = data.Parent
					if old then
						local kids = old._data._children
						local at = table.find(kids, inst)
						if at then
							table.remove(kids, at)
						end
					end
					data.Parent = value
					if value then
						table.insert(value._data._children, inst)
					end
				else
					data[key] = value
				end
			end,
		})
		return inst
	end

	local queued = {}
	local loops = {}
	local attrs = {}
	local listeners = {}
	local player = {
		GetAttribute = function(_, name)
			return attrs[name]
		end,
		GetAttributeChangedSignal = function(_, name)
			listeners[name] = listeners[name] or newSignal()
			return listeners[name]
		end,
	}
	local guiService = { SelectedObject = nil }
	local slotState = newSignal()
	local device = "console"
	local madeScreen
	local openButtonPress

	local colors = setmetatable({}, {
		__index = function()
			return roblox.Color3.new(1, 1, 1)
		end,
	})
	local function fakeButton(opts)
		local root = FakeInstance.new("Frame")
		root.Size = roblox.UDim2.fromOffset(opts.size.X, opts.size.Y)
		local face = FakeInstance.new("TextButton")
		face.Name = "Face"
		face.Active = true
		face.Parent = root
		return { root = root, face = face, SetStyle = noop }
	end
	local uiTheme = {
		Colors = colors,
		Fonts = setmetatable({}, {
			__index = function()
				return roblox.Enum.Font.SourceSans
			end,
		}),
		Layers = setmetatable({}, {
			__index = function()
				return 1
			end,
		}),
		Size = { Tap = 44 },
		Screen = function(name)
			local gui = FakeInstance.new("ScreenGui")
			madeScreen = gui
			gui.Name = name
			gui.AbsoluteSize = Vector2.new(1280, 720)
			return gui
		end,
		PlayerGui = function()
			return FakeInstance.new("Folder")
		end,
		Button = fakeButton,
		corner = noop,
		stroke = noop,
		padding = noop,
		list = noop,
		HiddenSelection = function()
			return nil
		end,
		Scale = function()
			return 1
		end,
		Device = function()
			return device
		end,
		WatchLayout = noop,
	}

	local loader = t.loader({
		services = {
			ContextActionService = { BindActionAtPriority = noop, UnbindAction = noop },
			GuiService = guiService,
			Players = { LocalPlayer = player },
		},
		globals = {
			Instance = FakeInstance,
			task = {
				defer = function(fn)
					table.insert(queued, fn)
				end,
				spawn = function(fn)
					local co = coroutine.create(fn)
					coroutine.resume(co)
					table.insert(loops, co)
				end,
				wait = function()
					coroutine.yield()
				end,
				delay = noop,
			},
		},
		mocks = {
			UITheme = uiTheme,
			HUD = {
				HoldHint = noop,
				SideButton = function(opts)
					openButtonPress = opts.onPress
					return { root = FakeInstance.new("Frame") }
				end,
			},
			GamepadNav = {
				Restore = noop,
				Focus = function(first)
					guiService.SelectedObject = first
				end,
			},
			Net = {
				Remote = function(name)
					if name == "SlotState" then
						return { OnClientEvent = slotState, FireServer = noop }
					end
					return { OnClientEvent = newSignal(), FireServer = noop }
				end,
			},
		},
	})
	local ok, SaveSlotUI = pcall(function()
		return loader:load("StarterPlayer/StarterPlayerScripts/SaveSlotUI")
	end)
	if not ok then
		t.test("SaveSlotUI loads against the fakes", function()
			error(tostring(SaveSlotUI))
		end)
		return
	end

	local function flush()
		while #queued > 0 do
			local batch = queued
			queued = {}
			for _, fn in ipairs(batch) do
				fn()
			end
		end
	end

	local function payload(count, rename)
		local rows = {}
		for i = 1, count do
			table.insert(rows, {
				index = i,
				name = if rename and rename == i then "Renamed" else "Save " .. i,
				fresh = false,
				cash = 100 * i,
				axeId = "Starter",
				axeName = "Starter Axe",
				lastPlayed = 1000 + i,
				active = i == 1,
				hasPlot = true,
				pieces = i,
				tier = 1,
			})
		end
		return rows
	end

	-- Rooted at the ScreenGui the script made.
	local gui
	local function find(root, name)
		if root.Name == name then
			return root
		end
		for _, c in ipairs(root:GetChildren()) do
			local hit = find(c, name)
			if hit then
				return hit
			end
		end
		return nil
	end

	local started = false
	local rows, panel
	local function boot()
		if started then
			return
		end
		started = true
		SaveSlotUI.Start()
		gui = madeScreen
		panel = find(gui, "Saves")
		rows = find(gui, "Rows")
	end

	local function setup(count)
		boot()
		attrs.SlotCooldownUntil = nil
		if panel.Visible then
			openButtonPress() -- close it, so the next press opens it fresh
		end
		slotState:Fire(payload(count))
		openButtonPress()
		flush()
		rows.AbsoluteCanvasSize = Vector2.new(300, 900)
		rows.AbsoluteWindowSize = Vector2.new(300, 300)
		return rows
	end

	local function cards()
		local out = {}
		for _, c in ipairs(rows:GetChildren()) do
			if c.IsA(c, "Frame") then
				table.insert(out, c)
			end
		end
		return out
	end

	local function tick()
		for _, co in ipairs(loops) do
			if coroutine.status(co) == "suspended" then
				local ran, err = coroutine.resume(co)
				if not ran then
					error(err)
				end
			end
		end
		flush()
	end

	t.test("5 ticks and the same payload keep the scroll and replace no row", function()
		setup(8)
		rows.CanvasPosition = Vector2.new(0, 300)
		local before = cards()
		t.eq(#before, 8)
		for _ = 1, 5 do
			tick()
		end
		slotState:Fire(payload(8))
		flush()
		t.eq(rows.CanvasPosition.Y, 300)
		local after = cards()
		t.eq(#after, 8)
		for i, card in ipairs(after) do
			t.ok(card == before[i] and not card.Destroyed, "row " .. i .. " is the same instance")
		end
	end)

	t.test("the tick repaints the countdown and each row's enabled state in place", function()
		setup(3)
		local before = cards()
		attrs.SlotCooldownUntil = os.time() + 30
		tick()
		local loadFace = find(before[2], "Face")
		t.ok(loadFace.Active == false, "another save's LOAD is cooling down")
		t.ok(find(before[1], "Face") == nil, "the save being played has no button")
		for i, card in ipairs(cards()) do
			t.ok(card == before[i], "same row " .. i)
		end
		attrs.SlotCooldownUntil = nil
		tick()
		t.ok(find(before[2], "Face").Active == true, "ready again")
	end)

	t.test("a changed payload keeps Y valid and the same selected index", function()
		setup(8)
		rows.CanvasPosition = Vector2.new(0, 300)
		local before = cards()
		guiService.SelectedObject = find(before[5], "Face")
		slotState:Fire(payload(8, 3)) -- save 3 was renamed
		t.ok(cards()[3] ~= before[3], "the rows were rebuilt")
		t.eq(rows.CanvasPosition.Y, 0, "the rebuild snapped it (the engine's clamp)")
		flush()
		t.eq(rows.CanvasPosition.Y, 300)
		local selected = guiService.SelectedObject
		t.ok(selected == find(cards()[5], "Face"), "slot 5 stays selected")
		t.ok(not selected.Destroyed)
		-- a canvas that shrank: the offset is clamped, never past the end
		rows.CanvasPosition = Vector2.new(0, 600)
		rows.AbsoluteCanvasSize = Vector2.new(300, 450)
		slotState:Fire(payload(8, 4))
		flush()
		t.eq(rows.CanvasPosition.Y, 150)
	end)

	t.test("opening the panel puts the list at the top", function()
		setup(8)
		rows.CanvasPosition = Vector2.new(0, 300)
		openButtonPress() -- closes
		openButtonPress() -- opens again
		flush()
		t.eq(rows.CanvasPosition.Y, 0)
	end)

	t.test("CanvasPosition is written in one place, and only the open path passes 0", function()
		local src = fs.readFile(UI_PATH)
		local count = 0
		for _ in string.gmatch(src, "CanvasPosition%s*=[^=]") do
			count += 1
		end
		t.eq(count, 1, "one CanvasPosition assignment (placeCanvas)")
		t.ok(string.find(src, "placeCanvas(h, 0)", 1, true), "the open path sets 0")
		t.ok(
			not string.find(src, "while panel do%s+task.wait%(1%)%s+local p = panel%s+if p and p.Visible and confirm"),
			"the old loop is gone"
		)
	end)

	t.test("SummaryKey and ClampScroll", function()
		local Logic = t.shared("SaveSlotLogic")
		local a = payload(3)
		local b = payload(3)
		t.eq(Logic.SummaryKey(a, false), Logic.SummaryKey(b, false))
		b[2].name = "X"
		t.ok(Logic.SummaryKey(a, false) ~= Logic.SummaryKey(b, false), "name")
		b = payload(3)
		b[3].lastPlayed += 1
		t.ok(Logic.SummaryKey(a, false) ~= Logic.SummaryKey(b, false), "timestamp")
		t.ok(Logic.SummaryKey(a, false) ~= Logic.SummaryKey(a, true), "join pick")
		t.eq(Logic.ClampScroll(300, 900, 300), 300)
		t.eq(Logic.ClampScroll(900, 450, 300), 150)
		t.eq(Logic.ClampScroll(50, 200, 300), 0)
		t.eq(Logic.ClampScroll(-5, 900, 300), 0)
	end)
end
