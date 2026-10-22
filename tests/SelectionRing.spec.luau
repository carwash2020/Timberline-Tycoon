--!nocheck
-- SelectionRing (T406): the gamepad selection box wraps its button exactly. The
-- engine places a SelectionImageObject from the selected object's top-left
-- corner and ignores AnchorPoint, so a ring that centred itself with
-- AnchorPoint (0.5, 0.5) and Position (0.5, 0.5) drew half a button right and
-- down (Xbox, BADGES / FIELD GUIDE / STORE). This resolves the ring's rectangle
-- the engine's way for every button size, at each UI scale and on a TV.
return function(t)
	local roblox = t.roblox
	local Instance, Vector2 = roblox.Instance, roblox.Vector2

	local function theme(device)
		local playerGui = Instance.new("Folder")
		playerGui.Name = "PlayerGui"
		local loader = t.loader({
			services = {
				GuiService = {
					IsTenFootInterface = function()
						return device.tenFoot == true
					end,
					TopbarInset = roblox.Rect.new(0, 0, 0, 0),
					GetGuiInset = function()
						return Vector2.new(0, 58), Vector2.zero
					end,
				},
				Players = {
					LocalPlayer = {
						WaitForChild = function()
							return playerGui
						end,
					},
				},
				TextChatService = {
					FindFirstChildOfClass = function()
						return nil
					end,
				},
				UserInputService = {
					TouchEnabled = device.touch,
					KeyboardEnabled = device.keyboard,
					GetLastInputType = function()
						return roblox.Enum.UserInputType.Keyboard
					end,
				},
			},
			globals = {
				workspace = { CurrentCamera = { ViewportSize = device.viewport } },
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
				},
			},
		})
		return loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
	end

	-- The ring's rectangle relative to the selected object's top-left, the way the
	-- engine lays it out: Position and Size against the object's size, no anchor.
	local function resolve(ring, face)
		local x = ring.Position.X.Scale * face.X + ring.Position.X.Offset
		local y = ring.Position.Y.Scale * face.Y + ring.Position.Y.Offset
		local w = ring.Size.X.Scale * face.X + ring.Size.X.Offset
		local h = ring.Size.Y.Scale * face.Y + ring.Size.Y.Offset
		return x, y, w, h
	end

	local devices = {
		{ name = "small window", viewport = Vector2.new(960, 540), keyboard = true },
		{ name = "medium window", viewport = Vector2.new(1920, 1080), keyboard = true },
		{ name = "large window", viewport = Vector2.new(3840, 2160), keyboard = true },
		{ name = "TV 1080p", viewport = Vector2.new(1920, 1080), tenFoot = true },
		{ name = "TV 4K", viewport = Vector2.new(3840, 2160), tenFoot = true },
	}

	t.test("the ring wraps every button: same centre, Ring px outside on each side, at every scale", function()
		for _, device in ipairs(devices) do
			local UITheme = theme(device)
			t.ok(not not UITheme.Ring)
			for _, size in ipairs({ Vector2.new(100, 44), Vector2.new(210, 56), Vector2.new(60, 60) }) do
				local ring = UITheme.SelectionRing()
				t.ok(ring ~= nil, device.name .. ": the button has a selection ring")
				t.eq(ring.AnchorPoint, Vector2.zero, device.name .. ": no anchor, the engine ignores it")
				t.eq(ring.Position.X.Scale, 0, device.name .. ": no scale in the position")
				t.eq(ring.Position.Y.Scale, 0, device.name .. ": no scale in the position")
				-- The face is the button's size without the drop edge (a scale of 1, offset -drop).
				local face = Vector2.new(size.X, size.Y)
				local x, y, w, h = resolve(ring, face)
				local ringPx = UITheme.Ring
				t.ok(
					math.abs(x + ringPx) < 1e-6 and math.abs(y + ringPx) < 1e-6,
					device.name .. ": starts Ring px up and left of the button"
				)
				t.ok(
					math.abs(w - (face.X + 2 * ringPx)) < 1e-6 and math.abs(h - (face.Y + 2 * ringPx)) < 1e-6,
					device.name .. ": Ring px larger on every side"
				)
				t.ok(
					math.abs((x + w / 2) - face.X / 2) < 1e-6 and math.abs((y + h / 2) - face.Y / 2) < 1e-6,
					device.name .. ": centred on the button"
				)
			end
		end
	end)

	t.test("no selection ring in the HUD code is placed by an anchor or a scale position", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/UITheme.luau")
		local from = string.find(source, "function selectionRing()", 1, true)
		local to = string.find(source, "-- A selection image that draws nothing", 1, true)
		t.ok(from ~= nil and to ~= nil and to > from, "found selectionRing")
		local body = string.sub(source, from, to)
		t.eq(string.find(body, "AnchorPoint = Vector2.new(0.5", 1, true), nil, "no centre anchor")
		t.eq(string.find(body, "Position = UDim2.fromScale", 1, true), nil, "no scale position")
	end)
end
