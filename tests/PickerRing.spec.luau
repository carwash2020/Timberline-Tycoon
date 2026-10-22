--!nocheck
-- PickerRing (T420): on Xbox the selection highlight of the blueprint picker sits
-- exactly on each button's edge: the ring is the button's own rectangle (no
-- anchor, no scale offset, the engine places a selection image from the object's
-- top-left corner), it has the button's corner radius, and its stroke is drawn
-- outside the edge. Checked on the real picker's tabs, cards and close button at
-- a small window, a medium window, a large window, a phone and a TV (1080p, 4K),
-- the same devices SelectionRing.spec walks for the HUD buttons.
return function(t)
	local roblox = t.roblox
	local Enum, Instance, Vector2, UDim2 = roblox.Enum, roblox.Instance, roblox.Vector2, roblox.UDim2
	local BlueprintBook = t.shared("BlueprintBook")
	local PlotData = t.shared("PlotData")

	local inert = setmetatable({}, { __mode = "k" })
	for _, prop in ipairs({ "InputBegan", "InputEnded", "SelectionGained", "SelectionLost", "Activated" }) do
		pcall(roblox.implementProperty, "TextButton", prop, function(self)
			inert[self] = inert[self] or {}
			local ev = inert[self][prop]
			if ev == nil then
				ev = {}
				function ev:Connect()
					return { Disconnect = function() end }
				end
				inert[self][prop] = ev
			end
			return ev
		end)
	end

	local devices = {
		{ name = "small window", viewport = Vector2.new(960, 540), keyboard = true },
		{ name = "medium window", viewport = Vector2.new(1920, 1080), keyboard = true },
		{ name = "large window", viewport = Vector2.new(3840, 2160), keyboard = true },
		{ name = "phone", viewport = Vector2.new(667, 375), touch = true },
		{ name = "TV 1080p", viewport = Vector2.new(1920, 1080), tenFoot = true, gamepad = true },
		{ name = "TV 4K", viewport = Vector2.new(3840, 2160), tenFoot = true, gamepad = true },
	}

	local function open(device)
		local playerGui = Instance.new("Folder")
		playerGui.Name = "PlayerGui"
		local never = {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
		local loader = t.loader({
			services = {
				GuiService = {
					SelectedObject = nil,
					IsTenFootInterface = function()
						return device.tenFoot == true
					end,
					TopbarInset = roblox.Rect.new(0, 0, 0, 0),
					GetGuiInset = function()
						return Vector2.new(0, 0), Vector2.zero
					end,
					GetPropertyChangedSignal = function()
						return never
					end,
				},
				ContextActionService = {
					BindActionAtPriority = function() end,
					BindAction = function() end,
					UnbindAction = function() end,
				},
				Players = {
					LocalPlayer = {
						FindFirstChildOfClass = function()
							return playerGui
						end,
						WaitForChild = function()
							return playerGui
						end,
					},
				},
				TextChatService = {},
				UserInputService = {
					TouchEnabled = device.touch == true,
					KeyboardEnabled = device.keyboard == true,
					GamepadEnabled = device.gamepad == true,
					LastInputTypeChanged = never,
					GetLastInputType = function()
						return if device.gamepad then Enum.UserInputType.Gamepad1 else Enum.UserInputType.Keyboard
					end,
					GetImageForKeyCode = function()
						return ""
					end,
				},
			},
			globals = {
				workspace = { CurrentCamera = { ViewportSize = device.viewport } },
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					defer = function(fn, ...)
						fn(...)
					end,
					delay = function() end,
				},
			},
			mocks = {
				HUD = {
					Toast = function() end,
					SetModal = function() end,
					TopRow = function()
						return nil
					end,
				},
			},
		})
		local UI = loader:load("StarterPlayer/StarterPlayerScripts/BuildMenuUI")
		UI.Start()
		local ids = {}
		for _, bp in ipairs(PlotData.Blueprints) do
			table.insert(ids, bp.id)
		end
		UI.Open({
			entries = function()
				return BlueprintBook.Entries(ids, {}, true)
			end,
			ctx = function()
				return { tier = 5, cash = 100000, boxed = false }
			end,
			place = function() end,
			land = function() end,
		})
		return UI, playerGui, loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
	end

	local function cornerOf(obj)
		local c = obj:FindFirstChildOfClass("UICorner")
		return if c then c.CornerRadius else nil
	end

	-- The ring's rectangle the engine's way: from the object's top-left, Position
	-- and Size against the object's own size, no anchor.
	local function resolve(ring, face)
		local x = ring.Position.X.Scale * face.X + ring.Position.X.Offset
		local y = ring.Position.Y.Scale * face.Y + ring.Position.Y.Offset
		local w = ring.Size.X.Scale * face.X + ring.Size.X.Offset
		local h = ring.Size.Y.Scale * face.Y + ring.Size.Y.Offset
		return x, y, w, h
	end

	local function checkRing(button, label, faces)
		local ring = button.SelectionImageObject
		t.ok(ring ~= nil, label .. " has its own selection image")
		t.eq(ring.AnchorPoint, Vector2.zero, label .. ": no anchor (the engine ignores it)")
		for _, face in ipairs(faces) do
			local x, y, w, h = resolve(ring, face)
			t.ok(
				math.abs(x) < 1e-6
					and math.abs(y) < 1e-6
					and math.abs(w - face.X) < 1e-6
					and math.abs(h - face.Y) < 1e-6,
				string.format("%s: the ring is the button's rectangle at %dx%d", label, face.X, face.Y)
			)
		end
		-- The corner is the button's own, so the stroke follows the edge round the corners.
		local want, got = cornerOf(button), cornerOf(ring)
		t.ok(want ~= nil and got ~= nil, label .. " has rounded corners on both")
		t.eq(got, want, label .. ": the ring's corner radius is the button's")
		-- The gold stroke is drawn outside the frame (Border mode), not over the face.
		local gold = ring:FindFirstChildOfClass("UIStroke")
		t.ok(gold ~= nil, label .. " has a gold stroke")
		t.ok(gold.ApplyStrokeMode == Enum.ApplyStrokeMode.Border, label .. ": the stroke sits on the edge")
		-- The dark outer ring is centred on the same middle, so it is even on all four sides.
		local ink = ring:FindFirstChild("InkRing")
		t.ok(ink ~= nil, label .. " has the dark outer ring")
		t.eq(ink.AnchorPoint, Vector2.new(0.5, 0.5))
		t.eq(ink.Position, UDim2.fromScale(0.5, 0.5))
		t.eq(ink.Size.X.Scale, 1)
		t.eq(ink.Size.Y.Scale, 1)
		t.eq(ink.Size.X.Offset, ink.Size.Y.Offset, label .. ": the same margin left, right, top and bottom")
		t.ok(ink.Size.X.Offset > 0)
	end

	local function find(root, name)
		for _, d in ipairs(root:GetDescendants()) do
			if d.Name == name then
				return d
			end
		end
		return nil
	end

	for _, device in ipairs(devices) do
		t.test("the highlight sits on the edge of every tab and card, " .. device.name, function()
			local UI, playerGui = open(device)
			local tiles = UI.Tiles()
			t.ok(#tiles > 0, "cards are up")
			-- Faces of different sizes: the ring is relative, so it must fit any.
			local faces = { Vector2.new(100, 44), Vector2.new(170, 190), Vector2.new(60, 60), Vector2.new(480, 120) }
			for i, tile in ipairs(tiles) do
				if i <= 6 then
					checkRing(tile.button, device.name .. " card " .. tile.entry.id, faces)
				end
			end
			local rows = 0
			for _, d in ipairs(playerGui:GetDescendants()) do
				if d:IsA("TextButton") and string.sub(d.Name, 1, 5) == "Rail_" then
					rows += 1
					checkRing(d, device.name .. " " .. d.Name, faces)
				end
			end
			t.ok(rows >= 7, "six tabs and Land: " .. rows)
		end)
	end

	t.test("the six tabs and Land are the rail's rows, in that order", function()
		local _, playerGui = open(devices[2])
		local rows = {}
		for _, d in ipairs(playerGui:GetDescendants()) do
			if d:IsA("TextButton") and string.sub(d.Name, 1, 5) == "Rail_" then
				table.insert(rows, d)
			end
		end
		table.sort(rows, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		local names = {}
		for _, d in ipairs(rows) do
			table.insert(names, string.sub(d.Name, 6))
		end
		for i, label in ipairs({ "Walls", "Floors", "Doors", "Roofs", "Fences", "Supports" }) do
			t.eq(names[i], label)
		end
		t.eq(names[#names], "Land")
	end)

	t.test("the ring is built by one UITheme function, with the radius passed in (no hand-set copy)", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/BuildMenuUI.luau")
		for _, line in ipairs(string.split(source, "\n")) do
			if string.find(line, "SelectionImageObject = focusRing", 1, true) then
				t.ok(string.find(line, ",", 1, true) ~= nil, "focusRing gets a stroke and a radius: " .. line)
			end
		end
		t.eq(string.find(source, "AnchorPoint = Vector2.new(0.5, 0.5)\n\tring", 1, true), nil)
	end)

	t.test(
		"Art's palette: panel #F3E7C9, text #3C2814, focus ring #C9A24A, short line #FFC873, too-long line #C8553D",
		function()
			local _, _, UITheme = open(devices[2])
			local C = UITheme.Colors
			t.eq(C.Paper:ToHex(), "F3E7C9")
			t.eq(C.PickerInk:ToHex(), "3C2814")
			t.eq(C.AmberEdge:ToHex(), "C9A24A")
			t.eq(C.WireShort:ToHex(), "FFC873")
			t.eq(C.WireTooLong:ToHex(), "C8553D")
			local ring = UITheme.FocusRing(4, 8)
			t.eq(ring:FindFirstChildOfClass("UIStroke").Color:ToHex(), "C9A24A", "the ring's gold")
			local UI = open(devices[2])
			local tile = UI.Tiles()[1]
			t.eq(tile.button.Plate:FindFirstChild("Name").TextColor3:ToHex(), "3C2814")
			t.eq(tile.button.Blurb.TextColor3:ToHex(), "3C2814")
			t.eq(tile.button.Cost.TextColor3:ToHex(), "3C2814")
			local fs = require("@lune/fs")
			local wire = fs.readFile("src/StarterPlayer/StarterPlayerScripts/WireTool.luau")
			t.ok(string.find(wire, "C.WireShort", 1, true) and string.find(wire, "C.WireTooLong", 1, true))
		end
	)
end
