--!nocheck
-- HUD art (UIArt, UITheme.Card, the cash plaque, the top row, prompts).
-- The skins are sliced images; an empty id is today's flat card; the cash
-- text doesn't change; $1,999,999 fits; the top row stays in the bar or
-- just under it, clear of Roblox's buttons and the notch; a pressed
-- prompt button doesn't stay pressed.
return function(t)
	local roblox = t.roblox
	local Instance, Vector2, Rect, UDim, UDim2, Enum =
		roblox.Instance, roblox.Vector2, roblox.Rect, roblox.UDim, roblox.UDim2, roblox.Enum

	-- Lune's instances have no property signals. The cash row connects
	-- them; a no-op signal lets the build run here.
	local function signal()
		local fns = {}
		local ev = {}
		function ev:Connect(fn)
			table.insert(fns, fn)
			return {
				Disconnect = function()
					local i = table.find(fns, fn)
					if i then
						table.remove(fns, i)
					end
				end,
			}
		end
		function ev:Once(fn)
			return ev:Connect(fn)
		end
		function ev:Fire(...)
			for _, fn in ipairs(table.clone(fns)) do
				fn(...)
			end
		end
		return ev
	end
	-- Remembered so a spec can fire the safe probe's AbsoluteSize and
	-- re-place the row the way a real layout change does.
	local watched = {}
	roblox.implementMethod("Frame", "GetPropertyChangedSignal", function(self, prop)
		local ev = signal()
		watched[self] = watched[self] or {}
		watched[self][prop] = ev
		return ev
	end)
	roblox.implementProperty("NumberValue", "Changed", function()
		return signal()
	end)
	-- Lune's buttons have no input signals. Quest's Skip button connects them.
	for _, prop in ipairs({ "InputBegan", "InputEnded", "SelectionLost", "Activated" }) do
		roblox.implementProperty("TextButton", prop, function()
			return signal()
		end)
	end

	local PLAQUE = "rbxassetid://139841387610705"
	local PANEL = "rbxassetid://90740664574742"
	local BUTTON = "rbxassetid://72427678124813"
	local PRESSED = "rbxassetid://74100852047057"
	-- Fredoka One advance of "$1,999,999", measured from the font and
	-- rounded up (20 px: 94.4, 26 px: 122.7).
	local ADVANCE = { [20] = 95, [26] = 123 }
	local PAPER_PAD = 14 -- the plaque's paper, each side
	local SCREENS = {
		{ 375, 667 },
		{ 667, 375 },
		{ 1024, 768 },
		{ 1920, 1080 },
	}

	local function client(extra)
		extra = extra or {}
		local watch = extra.watch
		local camera = extra.camera
		if type(camera) == "table" and camera.GetPropertyChangedSignal == nil then
			camera.GetPropertyChangedSignal = function()
				return signal()
			end
		end
		return t.loader({
			services = {
				GuiService = {
					IsTenFootInterface = function()
						return extra.tenFoot == true
					end,
					TopbarInset = extra.topbar or Rect.new(0, 0, 0, 0),
					GetGuiInset = function()
						return extra.guiInset or Vector2.new(0, 58), extra.guiInsetBR or Vector2.zero
					end,
					GetPropertyChangedSignal = function()
						return {
							Connect = function(_, fn)
								if watch then
									table.insert(watch, fn)
								end
								return { Disconnect = function() end }
							end,
						}
					end,
				},
				Players = { LocalPlayer = extra.player or {} },
				TextChatService = {
					WaitForChild = function()
						return nil
					end,
					FindFirstChildOfClass = function()
						return nil
					end,
				},
				ContentProvider = {
					PreloadAsync = extra.preload or function(_, _, callback)
						if callback then
							callback("", Enum.AssetFetchStatus.Success)
						end
					end,
				},
				UserInputService = {
					TouchEnabled = extra.touch == true,
					KeyboardEnabled = if extra.keyboard == nil then true else extra.keyboard,
					LastInputTypeChanged = signal(),
					GetLastInputType = function()
						return Enum.UserInputType.Keyboard
					end,
				},
				ContextActionService = {},
				ProximityPromptService = {},
				StarterGui = {},
				TweenService = extra.tween or {},
			},
			globals = {
				workspace = {
					CurrentCamera = extra.camera,
					GetPropertyChangedSignal = function()
						return signal()
					end,
					WaitForChild = function()
						return nil
					end,
				},
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
				},
				-- Lune has no TweenInfo. PromptUI only needs a value to hand
				-- to the (stubbed) TweenService.
				TweenInfo = {
					new = function()
						return {}
					end,
				},
				-- AbsoluteSize has no default until something writes it.
				-- Real clients always have one; give new gui objects zero.
				Instance = setmetatable({
					new = function(className, parent)
						local inst = Instance.new(className)
						if inst:IsA("GuiObject") then
							inst.AbsoluteSize = Vector2.zero
							inst.AbsolutePosition = Vector2.zero
						end
						if parent ~= nil then
							inst.Parent = parent
						end
						return inst
					end,
				}, { __index = Instance }),
			},
		})
	end

	local function theme()
		local loader = client()
		return loader:load("StarterPlayer/StarterPlayerScripts/UITheme"),
			loader:load("StarterPlayer/StarterPlayerScripts/UIArt")
	end

	local function cornerOffset(inst)
		local c = inst:FindFirstChildOfClass("UICorner")
		return if c then c.CornerRadius.Offset else nil
	end

	local function paddingOf(inst)
		local p = inst:FindFirstChildOfClass("UIPadding")
		if not p then
			return nil
		end
		return { p.PaddingTop.Offset, p.PaddingRight.Offset, p.PaddingBottom.Offset, p.PaddingLeft.Offset }
	end

	-- The flat card's properties, so an empty id can be checked against one.
	local function snap(card)
		local outer, face = card.outer, card.face
		return {
			faceParent = face.Parent == outer,
			faceName = face.Name,
			outerTrans = outer.BackgroundTransparency,
			outerBorder = outer.BorderSizePixel,
			outerSize = tostring(outer.Size),
			outerAuto = tostring(outer.AutomaticSize),
			outerCorner = cornerOffset(outer),
			outerPad = paddingOf(outer),
			outerColor = tostring(outer.BackgroundColor3),
			faceImage = face.Image,
			faceTrans = face.BackgroundTransparency,
			faceBorder = face.BorderSizePixel,
			faceSize = tostring(face.Size),
			faceAuto = tostring(face.AutomaticSize),
			faceScale = tostring(face.ScaleType),
			faceSlice = tostring(face.SliceCenter),
			faceSliceScale = face.SliceScale,
			faceCorner = cornerOffset(face),
			facePad = paddingOf(face),
			faceColor = tostring(face.BackgroundColor3),
			faceArt = face:GetAttribute("UIArt"),
			children = #face:GetChildren(),
		}
	end

	t.test("every UIArt skin returns an outer frame and a face", function()
		local UITheme, UIArt = theme()
		local fill, edge = UITheme.Colors.Paper, UITheme.Colors.Ink
		for _, name in ipairs(UIArt.Names) do
			local card = UITheme.Card(fill, edge, 3, 12, true, name)
			t.eq(card.outer.ClassName, "Frame", name)
			t.eq(card.face.ClassName, "ImageLabel", name)
			t.eq(card.face.Name, "Face", name)
			t.ok(card.face.Parent == card.outer, name .. " face sits in the outer")
		end
		t.eq(UIArt.Plaque.id, PLAQUE)
		t.eq(UIArt.Panel.id, PANEL)
		t.eq(UIArt.Button.id, BUTTON)
		t.eq(UIArt.ButtonPressed.id, PRESSED)
		t.eq(UIArt.Plaque.sliceScale, 1 / 6)
		t.eq(UIArt.Panel.sliceScale, 0.25)
		t.eq({ UIArt.Plaque.sliceCenter.Min.X, UIArt.Plaque.sliceCenter.Max.X }, { 24, 232 })
		t.eq({ UIArt.Panel.sliceCenter.Min.Y, UIArt.Panel.sliceCenter.Max.Y }, { 48, 208 })
	end)

	t.test("a skinned face is sliced, transparent, and has no corner", function()
		local UITheme, UIArt = theme()
		local fill, edge = UITheme.Colors.Bark, UITheme.Colors.Ink
		for _, name in ipairs(UIArt.Names) do
			local art = UIArt.Get(name)
			local card = UITheme.Card(fill, edge, 3, 14, false, name)
			local face = card.face
			t.eq(face.Image, art.id, name)
			t.eq(face.ScaleType, Enum.ScaleType.Slice, name)
			t.eq(face.SliceCenter, art.sliceCenter, name)
			-- SliceScale is stored as a float32, so 1/6 doesn't compare equal.
			t.ok(math.abs(face.SliceScale - art.sliceScale) < 1e-6, name .. " slice scale")
			t.eq(face.BackgroundTransparency, 1, name)
			t.eq(face:FindFirstChildOfClass("UICorner"), nil, name .. " has no corner")
			t.eq(card.outer.BackgroundTransparency, 1, name .. " outer is clear")
		end
	end)

	t.test("texture() leaves a skinned face alone", function()
		local UITheme = theme()
		UITheme.Textures.Wood = "rbxassetid://123"
		local skinned = UITheme.Card(UITheme.Colors.Bark, UITheme.Colors.Ink, 3, 12, true, "Panel")
		local image, scale, n = skinned.face.Image, skinned.face.ScaleType, #skinned.face:GetChildren()
		UITheme.texture(skinned.face, "Wood", 12)
		t.eq(skinned.face.Image, image)
		t.eq(skinned.face.ScaleType, scale)
		t.eq(skinned.face.BackgroundTransparency, 1)
		t.eq(#skinned.face:GetChildren(), n, "no tiled image added")

		local plain = UITheme.Card(UITheme.Colors.Bark, UITheme.Colors.Ink, 3, 12, true)
		UITheme.texture(plain.face, "Wood", 12)
		t.eq(plain.face.Image, "rbxassetid://123", "a flat face still takes a texture")
		t.eq(plain.face.ScaleType, Enum.ScaleType.Tile)
	end)

	t.test("an empty id builds today's flat card", function()
		local UITheme, UIArt = theme()
		local fill, edge = UITheme.Colors.Paper, UITheme.Colors.Bark
		for _, auto in ipairs({ true, false }) do
			UIArt.Plaque.id = ""
			local empty = UITheme.Card(fill, edge, 3, 14, auto, "Plaque")
			UIArt.Plaque.id = PLAQUE
			local plain = UITheme.Card(fill, edge, 3, 14, auto)
			local missing = UITheme.Card(fill, edge, 3, 14, auto, "NoSuchSkin")
			t.eq(snap(empty), snap(plain), if auto then "auto" else "fixed")
			t.eq(snap(missing), snap(plain), "a missing skin")
		end
		-- And with the id restored, the plaque is skinned again.
		local again = UITheme.Card(fill, edge, 3, 14, true, "Plaque")
		t.eq(again.face.Image, PLAQUE)
	end)

	t.test("the plaque's center inset is at least 4 px", function()
		local UITheme = theme()
		local card = UITheme.Card(UITheme.Colors.Bark, UITheme.Colors.Ink, 3, 14, true, "Plaque")
		local pad = paddingOf(card.face)
		t.ok(pad, "an auto plaque pads its face")
		for _, side in ipairs(pad) do
			t.ok(side >= 4, "inset " .. side)
		end
		t.eq(UITheme.SkinInset("Plaque"), 4)
	end)

	local function cashAt(w, h, extra)
		extra = extra or {}
		local parent = Instance.new("Folder")
		local camera = extra.camera or { ViewportSize = Vector2.new(w, h) }
		camera.ViewportSize = camera.ViewportSize or Vector2.new(w, h)
		extra.camera = camera
		local loader = client(extra)
		local HUD = loader:load("StarterPlayer/StarterPlayerScripts/HUD")
		local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
		HUD.BuildCash(parent)
		local screen = parent:FindFirstChild("TimberlineTop")
		local row = screen:FindFirstChild("TopRow")
		local plaque = row:FindFirstChild("CashPlaque")
		local face = plaque:FindFirstChild("Face")
		local paper = face:FindFirstChild("Paper")
		local label = paper:FindFirstChildWhichIsA("TextLabel")
		local probeGui = parent:FindFirstChild("TimberlineSafeProbe")
		return {
			screen = screen,
			row = row,
			plaque = plaque,
			face = face,
			paper = paper,
			label = label,
			HUD = HUD,
			theme = UITheme,
			probe = probeGui:FindFirstChild("SafeArea"),
			probeGui = probeGui,
		}
	end

	t.test("cash text stays a live heading with no stroke", function()
		local desk = cashAt(1920, 1080)
		local phone = cashAt(375, 667)
		t.eq(desk.label.TextSize, 26)
		t.eq(phone.label.TextSize, 20)
		for _, built in ipairs({ desk, phone }) do
			local label = built.label
			t.eq(label.Font, Enum.Font.FredokaOne)
			t.eq(label.TextScaled, false)
			t.eq(label.TextTruncate, Enum.TextTruncate.None)
			t.eq(label.TextStrokeTransparency, 1)
			t.eq(label.AutomaticSize, Enum.AutomaticSize.X)
			t.eq(label:FindFirstChildOfClass("UIStroke"), nil, "no stroke on the digits")
			t.eq(label:FindFirstChildOfClass("UITextSizeConstraint"), nil, "the text never shrinks")
			t.eq(label.Text, "$0")
			local glow = built.plaque:FindFirstChildOfClass("UIStroke")
			t.ok(glow and glow.Parent == built.plaque, "the glow is on the plaque, outside the digits")
			t.eq(glow.Enabled, false)
			t.eq(built.face.BackgroundTransparency, 1)
			t.eq(built.face.Image, PLAQUE)
			t.eq(built.screen.ScreenInsets, Enum.ScreenInsets.None)
			local uiScale = built.screen:FindFirstChildOfClass("UIScale")
			t.ok(uiScale and uiScale.Scale >= 1, "the top screen scales up, never down")
			local pad = paddingOf(built.face)
			for _, side in ipairs(pad) do
				t.ok(side >= 4, "plaque inset")
			end
		end
		-- Paper is the text plus 8; the plaque adds the border on each side.
		t.eq(desk.paper.Size.Y.Offset, 26 + 8)
		t.eq(phone.paper.Size.Y.Offset, 20 + 8)
		t.eq(desk.plaque:FindFirstChildOfClass("UISizeConstraint").MinSize.Y, 26 + 8 + 8)
		t.eq(phone.plaque:FindFirstChildOfClass("UISizeConstraint").MinSize.Y, 20 + 8 + 8)
		-- The widest desktop label is reserved wide enough for the string.
		local reserve = desk.label:FindFirstChildOfClass("UISizeConstraint")
		t.ok(reserve.MinSize.X >= ADVANCE[26], "desktop reserves the widest string")
		local HUD = desk.HUD
		t.eq(HUD.CashText(0), "$0")
		t.eq(HUD.CashText(1999999), "$1,999,999")
		t.eq(HUD.CashText(2000000), "MAX")
		t.eq(HUD.CashText(2000001), "MAX")
		local fs = require("@lune/fs")
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HUD.luau")
		t.ok(string.find(src, 'pop.Name = "CashPop"', 1, true), "CashPop is unchanged")
	end)

	t.test("$1,999,999 fits on the four screens", function()
		local UITheme = theme()
		local HudLayout = t.load("StarterPlayer/StarterPlayerScripts/HudLayout")
		local inset = UITheme.SkinInset("Plaque")
		t.eq(inset, 4)
		for _, screen in ipairs(SCREENS) do
			local w, h = screen[1], screen[2]
			local textH = if math.min(w, h) < UITheme.CompactEdge then 20 else 26
			local plaqueW = ADVANCE[textH] + PAPER_PAD * 2 + inset * 2
			local plaqueH = textH + 8 + inset * 2
			-- A notch, read the way the probe reports it, plus the 12 px margin.
			local probeX = if math.min(w, h) < UITheme.CompactEdge then 44 else 0
			local probeW = w - probeX
			local leftSafe, rightSafe = probeX, w - (probeX + probeW)
			local room = w - leftSafe - rightSafe - 12
			t.ok(plaqueW <= room, string.format("%dx%d plaque %d in %d", w, h, plaqueW, room))
			local barH = 36
			local place = HudLayout.TopRow(
				Vector2.new(w, h),
				Rect.new(math.min(160, w * 0.12), 0, w - 48, barH),
				Vector2.new(plaqueW, plaqueH),
				textH,
				leftSafe,
				rightSafe,
				barH + 4
			)
			local left = place.right - plaqueW
			t.ok(left >= leftSafe, "not in the left notch")
			t.ok(place.right <= w - rightSafe, "not in the right notch")
			-- The plaque is the text plus 8 plus the border, so a 36 px bar
			-- is too short for the row. The width still clears the notch.
			local rowBand = plaqueH + 8
			t.eq(place.inBar, rowBand <= barH and textH + 8 <= barH, "in the bar only when the row fits")
		end
	end)

	t.test("the top row clears Roblox's buttons and the notch", function()
		local HudLayout = t.load("StarterPlayer/StarterPlayerScripts/HudLayout")
		-- w, h, minX, minY, maxX, maxY, probeX, probeW, rowW, rowH, textH, fallback, inBar
		-- probeX / probeW are the safe frame's AbsolutePosition.X and AbsoluteSize.X.
		local cases = {
			{ 375, 667, 48, 0, 330, 36, 0, 375, 180, 28, 20, 40, true },
			{ 667, 375, 88, 0, 620, 36, 0, 667, 200, 28, 20, 40, true },
			{ 1024, 768, 150, 0, 980, 36, 0, 1024, 220, 34, 26, 40, false }, -- row + pad taller than the bar
			{ 1920, 1080, 160, 0, 1860, 36, 0, 1920, 240, 34, 26, 40, false },
			{ 1920, 1080, 0, 0, 0, 0, 0, 1920, 240, 34, 26, 62, false }, -- inset reads 0
			{ 667, 375, 48, 0, 640, 36, 80, 587, 100, 28, 20, 40, true }, -- left notch, still fits
			{ 667, 375, 48, 0, 300, 36, 80, 587, 230, 28, 20, 40, false }, -- left notch pushes it under
			{ 667, 375, 48, 0, 667, 36, 0, 623, 200, 28, 20, 40, true }, -- right notch of 44
			{ 375, 667, 48, 0, 200, 36, 0, 375, 180, 28, 20, 40, false }, -- wider than the bar
			{ 1920, 1080, 160, 0, 1860, 24, 0, 1920, 240, 34, 26, 28, false }, -- bar shorter than the text
			{ 800, 600, 48, 0, 248, 48, 0, 800, 184, 34, 26, 52, true }, -- exactly the bar's width minus 16
			{ 800, 600, 48, 0, 248, 48, 0, 800, 185, 34, 26, 52, false },
			{ 1920, 1080, 160, 0, 1860, 58, 0, 1920, 240, 63, 26, 62, false }, -- 58 px bar, 63 px row
		}
		for _, c in ipairs(cases) do
			local w, h = c[1], c[2]
			local minX, minY, maxX, maxY = c[3], c[4], c[5], c[6]
			local probeX, probeW = c[7], c[8]
			local leftSafe, rightSafe = probeX, w - (probeX + probeW)
			local rowW, rowH, textH, fallback, wantBar = c[9], c[10], c[11], c[12], c[13]
			local topbar = Rect.new(minX, minY, maxX, maxY)
			local place = HudLayout.TopRow(
				Vector2.new(w, h),
				topbar,
				Vector2.new(rowW, rowH),
				textH,
				leftSafe,
				rightSafe,
				fallback
			)
			local left, right = place.right - rowW, place.right
			local top, bottom = place.top, place.top + rowH
			local where = string.format("%dx%d row %d inBar=%s", w, h, rowW, tostring(place.inBar))
			t.eq(place.inBar, wantBar, where)
			-- Left of TopbarInset.Min.X is Roblox's buttons. Overlap only counts
			-- while the row is actually in the bar's vertical band.
			local inBand = top < maxY and bottom > minY and maxY > minY
			if inBand then
				t.ok(left >= minX, where .. " overlaps a left button")
				t.ok(right <= maxX, where .. " overlaps a right button")
			end
			local fitsSafe = rowW <= (w - rightSafe) - leftSafe
			if fitsSafe then
				t.ok(left >= leftSafe - 1e-6, where .. " enters the left notch")
				t.ok(right <= w - rightSafe + 1e-6, where .. " enters the right notch")
			end
			if place.inBar then
				local center = top + rowH / 2
				local barCenter = (minY + maxY) / 2
				t.ok(math.abs(center - barCenter) < 1e-6, where .. " isn't centred in the bar")
				t.ok(right <= math.min(maxX, w - rightSafe) - 12 + 1e-6, where .. " right edge")
			else
				t.eq(place.top, fallback, where .. " under-bar y")
			end
		end
	end)

	t.test("a pressed prompt button doesn't stick", function()
		local player = Instance.new("Folder")
		local gui = Instance.new("Folder")
		gui.Name = "PlayerGui"
		gui.Parent = player
		local began, ended, triggered = signal(), signal(), signal()
		local prompt = {
			Parent = Instance.new("Part"),
			ActionText = "Chop",
			ObjectText = "Oak",
			HoldDuration = 1,
			ClickablePrompt = false,
			KeyboardKeyCode = Enum.KeyCode.E,
			GamepadKeyCode = Enum.KeyCode.ButtonX,
			UIOffset = Vector2.zero,
			PromptButtonHoldBegan = began,
			PromptButtonHoldEnded = ended,
			Triggered = triggered,
			PromptHidden = signal(),
			Destroying = signal(),
			GetPropertyChangedSignal = function()
				return signal()
			end,
			InputHoldBegin = function() end,
			InputHoldEnd = function() end,
		}
		local loader = client({
			player = player,
			tween = {
				Create = function()
					return {
						Play = function() end,
						Cancel = function() end,
					}
				end,
			},
		})
		local PromptUI = loader:load("StarterPlayer/StarterPlayerScripts/PromptUI")
		local UIArt = loader:load("StarterPlayer/StarterPlayerScripts/UIArt")
		PromptUI.Show(prompt, Enum.ProximityPromptInputType.Keyboard)
		local key = gui:FindFirstChild("Key", true)
		local face = key:FindFirstChild("Face")
		t.eq(face.Image, UIArt.Button.id, "starts on Button")
		t.eq(face.ScaleType, Enum.ScaleType.Slice)
		t.eq(face:FindFirstChildOfClass("UICorner"), nil)

		t.eq(face.BackgroundTransparency, 1, "a cached success is skinned before the hold")
		t.eq(face.ScaleType, Enum.ScaleType.Slice)
		began:Fire()
		t.eq(face.Image, UIArt.ButtonPressed.id, "pressed")
		t.eq(face.BackgroundTransparency, 1, "holding a loaded skin doesn't flash flat")
		t.eq(face.ScaleType, Enum.ScaleType.Slice)
		ended:Fire()
		t.eq(face.Image, UIArt.Button.id, "release puts Button back")
		t.eq(face.BackgroundTransparency, 1)

		began:Fire()
		began:Fire()
		t.eq(face.Image, UIArt.ButtonPressed.id)
		triggered:Fire()
		t.eq(face.Image, UIArt.Button.id, "trigger puts Button back")
		ended:Fire()
		t.eq(face.Image, UIArt.Button.id, "a second release doesn't stick")
	end)

	t.test("drawn cash text is never smaller than before", function()
		local function draw(w, h, tenFoot)
			local player = Instance.new("Folder")
			local pg = Instance.new("PlayerGui")
			pg.Parent = player
			local loader = client({
				player = player,
				camera = { ViewportSize = Vector2.new(w, h) },
				tenFoot = tenFoot,
				keyboard = true,
				touch = false,
			})
			local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
			local HUD = loader:load("StarterPlayer/StarterPlayerScripts/HUD")
			UITheme.Start()
			HUD.BuildCash(pg)
			local screen = pg:FindFirstChild("TimberlineTop")
			local label = screen
				:FindFirstChild("TopRow")
				:FindFirstChild("CashPlaque")
				:FindFirstChild("Face")
				:FindFirstChild("Paper")
				:FindFirstChildWhichIsA("TextLabel")
			local uiScale = screen:FindFirstChildOfClass("UIScale")
			local drawn = label.TextSize * uiScale.Scale
			local scaleFor = UITheme.ScaleFor(Vector2.new(w, h), false, tenFoot == true)
			local least = if math.min(w, h) < UITheme.CompactEdge then 20 else 26 * scaleFor
			t.ok(uiScale.Scale >= 1, string.format("%dx%d scale", w, h))
			t.ok(
				drawn + 1e-6 >= least,
				string.format("%dx%d drawn %s least %s", w, h, tostring(drawn), tostring(least))
			)
		end
		draw(1920, 1080, false)
		draw(1920, 1080, true) -- a TV
		draw(1024, 768, false)
		draw(375, 667, false)
	end)

	t.test("a zero top bar inset sits the row at TopBar() + 4", function()
		local built = cashAt(1920, 1080)
		t.eq(built.probeGui.ScreenInsets, Enum.ScreenInsets.DeviceSafeInsets)
		t.eq(built.row.Position.Y.Offset, built.theme.TopBar() + 4)
	end)

	t.test("notch insets come from the safe probe, not GetGuiInset", function()
		-- GetGuiInset's X is 0. The probe says the notch is 80. A row that
		-- would clear 0 but not 80 has to drop under the bar.
		local built = cashAt(667, 375, {
			topbar = Rect.new(48, 0, 300, 36),
			guiInset = Vector2.new(0, 36),
		})
		local probe = built.probe
		probe.AbsolutePosition = Vector2.new(80, 0)
		probe.AbsoluteSize = Vector2.new(667 - 80, 375)
		built.row.AbsoluteSize = Vector2.new(230, 28)
		local ev = watched[probe] and watched[probe].AbsoluteSize
		t.ok(ev, "re-places when the probe's size changes")
		ev:Fire()
		t.eq(built.row.Position.Y.Offset, built.theme.TopBar() + 4, "under the bar, clear of the notch")
	end)

	-- PreloadAsync holds its callback until `finish`, so a card can return
	-- while the image is still pending. Replaces the old immediate callback.
	local function holdPreload()
		local pending = {}
		return {
			preload = function(_, ids, callback)
				local id = ids[1]
				pending[id] = pending[id] or {}
				table.insert(pending[id], callback)
			end,
			finish = function(id, status)
				local list = pending[id] or {}
				pending[id] = nil
				for _, callback in ipairs(list) do
					callback(id, status)
				end
			end,
		}
	end

	t.test("held preload: Card returns at once, then slices on success", function()
		local held = holdPreload()
		local loader = client({ preload = held.preload })
		local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
		local UIArt = loader:load("StarterPlayer/StarterPlayerScripts/UIArt")
		t.eq(UIArt.Status(UIArt.Panel.id), "Pending")
		local card = UITheme.Card(UITheme.Colors.Paper, UITheme.Colors.Bark, 3, 12, false, "Panel")
		local face = card.face
		t.eq(face.BackgroundTransparency, 0, "flat until the image arrives")
		t.eq(face.Image, "")
		t.eq(face.ScaleType, Enum.ScaleType.Stretch)
		t.ok(face:FindFirstChildOfClass("UICorner"), "a flat card keeps its corner")
		t.eq(card.outer.BackgroundTransparency, 0)
		for _, side in ipairs(paddingOf(face)) do
			t.ok(side >= 12, "Panel inset from the start")
		end
		-- A side already past the inset stays; a short side is raised to it.
		local pad = face:FindFirstChildOfClass("UIPadding")
		pad.PaddingTop = UDim.new(0, 2)
		pad.PaddingLeft = UDim.new(0, 20)
		held.finish(UIArt.Panel.id, Enum.AssetFetchStatus.Success)
		t.eq(face.ScaleType, Enum.ScaleType.Slice)
		t.eq(face.Image, UIArt.Panel.id)
		t.eq(face.BackgroundTransparency, 1)
		t.eq(face:FindFirstChildOfClass("UICorner"), nil)
		t.eq(card.outer.BackgroundTransparency, 1)
		t.eq(paddingOf(face), { 12, 12, 12, 20 })
	end)

	t.test("held preload then failure stays flat and opaque", function()
		local held = holdPreload()
		local loader = client({ preload = held.preload })
		local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
		local UIArt = loader:load("StarterPlayer/StarterPlayerScripts/UIArt")
		local card = UITheme.Card(UITheme.Colors.Paper, UITheme.Colors.Bark, 3, 12, true, "Panel")
		held.finish(UIArt.Panel.id, Enum.AssetFetchStatus.Failure)
		t.eq(card.face.BackgroundTransparency, 0)
		t.eq(card.face.Image, "")
		t.eq(card.face.ScaleType, Enum.ScaleType.Stretch)
		t.ok(card.face:FindFirstChildOfClass("UICorner"))
		t.eq(card.outer.BackgroundTransparency, 0)
		t.eq(card.face:GetAttribute("UIArt"), nil)
		for _, side in ipairs(paddingOf(card.face)) do
			t.ok(side >= 12, "still the Panel inset")
		end
	end)

	t.test("a Murph bubble keeps its height and padding across the skin swap", function()
		local function bubbleOf(preload)
			local loader = client({ preload = preload })
			local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
			local UIArt = loader:load("StarterPlayer/StarterPlayerScripts/UIArt")
			-- QuestUI's speech card: fixed width, height from the words.
			local bubble = UITheme.Card(UITheme.Colors.Bark, UITheme.Colors.Ink, 3, 12, false, "Panel")
			bubble.outer.Name = "Card"
			bubble.outer.Size = UDim2.fromOffset(280, 0)
			bubble.outer.AutomaticSize = Enum.AutomaticSize.Y
			bubble.face.Size = UDim2.fromScale(1, 0)
			bubble.face.AutomaticSize = Enum.AutomaticSize.Y
			UITheme.padding(bubble.outer, 0, 0, 3, 0)
			UITheme.padding(bubble.face, 8, 10, 8, 8)
			bubble.outer.AbsoluteSize = Vector2.new(280, 64)
			bubble.face.AbsoluteSize = Vector2.new(280, 48)
			return bubble, UIArt
		end
		local function settled(status)
			local held = holdPreload()
			local bubble, UIArt = bubbleOf(held.preload)
			local outer, face = bubble.outer, bubble.face
			local size, auto = outer.Size, outer.AutomaticSize
			local faceSize, faceAuto = face.Size, face.AutomaticSize
			local outerPad, facePad = paddingOf(outer), paddingOf(face)
			local outerAbs, faceAbs = outer.AbsoluteSize, face.AbsoluteSize
			t.ok(outerAbs.Y > 0, "the bubble has a height before the image")
			held.finish(UIArt.Panel.id, status)
			t.ok(outer.AbsoluteSize.Y > 0, "height stays after " .. tostring(status))
			t.eq(outer.AbsoluteSize, outerAbs)
			t.eq(face.AbsoluteSize, faceAbs)
			t.eq(paddingOf(outer), outerPad, "outer padding")
			t.eq(paddingOf(face), facePad, "face padding")
			t.eq(outer.AutomaticSize, auto)
			t.eq(face.AutomaticSize, faceAuto)
			t.eq(tostring(outer.Size), tostring(size))
			t.eq(tostring(face.Size), tostring(faceSize))
		end
		settled(Enum.AssetFetchStatus.Success)
		settled(Enum.AssetFetchStatus.Failure)
	end)

	t.test("cached success builds the skinned card with no flat step", function()
		local UITheme, UIArt = theme()
		t.eq(UIArt.Status(UIArt.Panel.id), "Success")
		local card = UITheme.Card(UITheme.Colors.Paper, UITheme.Colors.Ink, 3, 12, false, "Panel")
		t.eq(card.face.Image, UIArt.Panel.id)
		t.eq(card.face.ScaleType, Enum.ScaleType.Slice)
		t.eq(card.face.BackgroundTransparency, 1)
		t.eq(card.face:FindFirstChildOfClass("UICorner"), nil, "never a flat corner")
		t.eq(card.outer.BackgroundTransparency, 1)
		t.eq(card.outer:FindFirstChildOfClass("UICorner"), nil)
	end)

	t.test("a held preload doesn't block the prompt hold swap", function()
		local held = holdPreload()
		local player = Instance.new("Folder")
		local gui = Instance.new("Folder")
		gui.Name = "PlayerGui"
		gui.Parent = player
		local began, ended = signal(), signal()
		local prompt = {
			Parent = Instance.new("Part"),
			ActionText = "Chop",
			ObjectText = "Oak",
			HoldDuration = 1,
			ClickablePrompt = false,
			KeyboardKeyCode = Enum.KeyCode.E,
			GamepadKeyCode = Enum.KeyCode.ButtonX,
			UIOffset = Vector2.zero,
			PromptButtonHoldBegan = began,
			PromptButtonHoldEnded = ended,
			Triggered = signal(),
			PromptHidden = signal(),
			Destroying = signal(),
			GetPropertyChangedSignal = function()
				return signal()
			end,
			InputHoldBegin = function() end,
			InputHoldEnd = function() end,
		}
		local loader = client({
			player = player,
			preload = held.preload,
			tween = {
				Create = function()
					return { Play = function() end, Cancel = function() end }
				end,
			},
		})
		local PromptUI = loader:load("StarterPlayer/StarterPlayerScripts/PromptUI")
		local UIArt = loader:load("StarterPlayer/StarterPlayerScripts/UIArt")
		PromptUI.Show(prompt, Enum.ProximityPromptInputType.Keyboard)
		local face = gui:FindFirstChild("Key", true):FindFirstChild("Face")
		t.eq(face.BackgroundTransparency, 0, "Show returned before the image")
		t.eq(face.Image, "")
		began:Fire()
		t.eq(face.BackgroundTransparency, 0, "the hold returns without a blank slice")
		t.eq(face.ScaleType, Enum.ScaleType.Stretch)
		held.finish(UIArt.Button.id, Enum.AssetFetchStatus.Success)
		-- The hold asked for ButtonPressed, which is still pending, so the
		-- resting Button skin must not paint over that request.
		t.eq(face.Image, "")
		t.eq(face.BackgroundTransparency, 0)
		held.finish(UIArt.ButtonPressed.id, Enum.AssetFetchStatus.Success)
		t.eq(face.Image, UIArt.ButtonPressed.id)
		t.eq(face.BackgroundTransparency, 1)
		t.eq(face.ScaleType, Enum.ScaleType.Slice)
		ended:Fire()
		t.eq(face.Image, UIArt.Button.id, "release puts Button back")
		t.eq(face.BackgroundTransparency, 1)
	end)

	t.test("at 1.5 scale on 1920x1080 the top row position is the layout divided by the scale", function()
		local w, h = 1920, 1080
		local player = Instance.new("Folder")
		local pg = Instance.new("PlayerGui")
		pg.Parent = player
		-- 56 px bar and a 42 px right notch: at s = 1.5 the layout's right and
		-- top land on whole offsets (lune stores UDim offsets as integers).
		local topbar = Rect.new(160, 0, 1860, 56)
		local loader = client({
			player = player,
			tenFoot = true,
			topbar = topbar,
			camera = { ViewportSize = Vector2.new(w, h) },
			keyboard = true,
			touch = false,
		})
		local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
		local HUD = loader:load("StarterPlayer/StarterPlayerScripts/HUD")
		local HudLayout = t.load("StarterPlayer/StarterPlayerScripts/HudLayout")
		UITheme.Start()
		HUD.BuildCash(pg)
		local screen = pg:FindFirstChild("TimberlineTop")
		local row = screen:FindFirstChild("TopRow")
		local uiScale = screen:FindFirstChildOfClass("UIScale")
		local s = uiScale.Scale
		t.eq(s, 1.5)
		local rightSafe = 42
		local probe = pg:FindFirstChild("TimberlineSafeProbe"):FindFirstChild("SafeArea")
		probe.AbsolutePosition = Vector2.zero
		probe.AbsoluteSize = Vector2.new(w - rightSafe, h)
		local function place(rowW, rowH)
			row.AbsoluteSize = Vector2.new(rowW, rowH)
			local ev = watched[row] and watched[row].AbsoluteSize
			t.ok(ev, "re-places from the row's size")
			ev:Fire()
			local expected = HudLayout.TopRow(
				Vector2.new(w, h),
				topbar,
				Vector2.new(rowW, rowH),
				26 * s,
				0,
				rightSafe,
				UITheme.TopBar() + 4
			)
			local rx = row.Position.X.Offset * s
			local ry = row.Position.Y.Offset * s
			t.ok(
				math.abs(rx - expected.right) < 1e-3,
				string.format("right %s vs %s", tostring(rx), tostring(expected.right))
			)
			t.ok(
				math.abs(ry - expected.top) < 1e-3,
				string.format("top %s vs %s", tostring(ry), tostring(expected.top))
			)
			t.ok(rx <= w - rightSafe - 12 + 1e-3, "right edge " .. tostring(rx))
			return expected
		end
		-- The $1,999,999 plaque, in screen pixels at this scale, and a short
		-- row that still fits the bar. Both go through placeTopRow.
		local plaqueW = (ADVANCE[26] + PAPER_PAD * 2 + 4 * 2) * s
		local plaqueH = (26 + 8 + 4 * 2) * s
		t.ok(plaqueW <= w - rightSafe - 12, "the scaled $1,999,999 plaque fits")
		local fitted = place(plaqueW, plaqueH)
		t.eq(fitted.inBar, false, "42 px of plaque is 63 px on screen, past the bar")
		local inBar = place(240, 32)
		t.eq(inBar.inBar, true, "a short row still sits in the bar")
	end)

	t.test("every skinned face pads to its inset and has no stroke", function()
		local UITheme, UIArt = theme()
		for _, name in ipairs(UIArt.Names) do
			for _, auto in ipairs({ true, false }) do
				local card = UITheme.Card(UITheme.Colors.Paper, UITheme.Colors.Ink, 3, 12, auto, name)
				t.eq(card.face:FindFirstChildOfClass("UIStroke"), nil, name)
				local inset = card.face:GetAttribute("SkinInset")
				local pad = paddingOf(card.face)
				t.ok(type(inset) == "number" and pad, name)
				for _, side in ipairs(pad) do
					t.ok(side >= inset, name .. " pad " .. side)
				end
			end
		end
		-- The speech bubble pads 8 inside a 12 px border; the floor lifts it.
		local bubble = UITheme.Card(UITheme.Colors.Bark, UITheme.Colors.Ink, 3, 12, false, "Panel")
		UITheme.padding(bubble.face, 8, 10, 8, 8)
		for _, side in ipairs(paddingOf(bubble.face)) do
			t.ok(side >= 12, "bubble pad " .. side)
		end
	end)

	t.test("skinned card text clears 7:1 on Paper", function()
		local function channel(c)
			return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
		end
		local function contrast(a, b)
			local function lum(color)
				return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
			end
			local hi, lo = math.max(lum(a), lum(b)), math.min(lum(a), lum(b))
			return (hi + 0.05) / (lo + 0.05)
		end
		local function onPaper(label, face, paper)
			if label.BackgroundTransparency < 1 or label.Text == "" then
				return false
			end
			local p = label.Parent
			while p and p ~= face do
				if p:IsA("GuiObject") and p.BackgroundTransparency < 1 then
					local c = p.BackgroundColor3
					local same = math.abs(c.R - paper.R) < 1e-3
						and math.abs(c.G - paper.G) < 1e-3
						and math.abs(c.B - paper.B) < 1e-3
					if not same then
						return false
					end
				end
				p = p.Parent
			end
			return true
		end
		local function check(root, paper, where)
			local n = 0
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("TextLabel") or d:IsA("TextButton") then
					local face = d.Parent
					while face and not (face:IsA("ImageLabel") and face:GetAttribute("UIArt") ~= nil) do
						face = face.Parent
					end
					if face and onPaper(d, face, paper) then
						n += 1
						t.ok(
							contrast(d.TextColor3, paper) >= 7,
							where .. " " .. d.Text .. " " .. tostring(d.TextColor3)
						)
					end
				end
			end
			t.ok(n > 0, where .. " has text on the paper")
			return n
		end

		local UITheme = theme()
		local paper = UITheme.Colors.Paper
		local bar = UITheme.Bar(Instance.new("Folder"), "BuildMode")
		bar.label.Text = "Build"
		check(bar.outer, paper, "bar")

		local built = cashAt(1920, 1080)
		check(built.plaque, paper, "cash")

		local player = Instance.new("Folder")
		local pg = Instance.new("PlayerGui")
		pg.Name = "PlayerGui"
		pg.Parent = player
		local began = signal()
		local prompt = {
			Parent = Instance.new("Part"),
			ActionText = "Chop",
			ObjectText = "Oak",
			HoldDuration = 0,
			ClickablePrompt = false,
			KeyboardKeyCode = Enum.KeyCode.E,
			GamepadKeyCode = Enum.KeyCode.ButtonX,
			UIOffset = Vector2.zero,
			PromptButtonHoldBegan = began,
			PromptButtonHoldEnded = signal(),
			Triggered = signal(),
			PromptHidden = signal(),
			Destroying = signal(),
			GetPropertyChangedSignal = function()
				return signal()
			end,
			InputHoldBegin = function() end,
			InputHoldEnd = function() end,
		}
		local loader = client({
			player = player,
			tween = {
				Create = function()
					return { Play = function() end, Cancel = function() end }
				end,
			},
		})
		loader:load("StarterPlayer/StarterPlayerScripts/PromptUI").Show(prompt, Enum.ProximityPromptInputType.Keyboard)
		check(pg, paper, "prompt")

		-- Murph's card. Start wires signals after the card exists; a missing
		-- one must not hide the text we came to read.
		local qPlayer = Instance.new("Folder")
		local qGui = Instance.new("PlayerGui")
		qGui.Parent = qPlayer
		local qLoader = client({
			player = qPlayer,
			tween = {
				Create = function()
					return { Play = function() end, Cancel = function() end }
				end,
			},
			servicesExtra = true,
		})
		local QuestUI = qLoader:load("StarterPlayer/StarterPlayerScripts/QuestUI")
		local started, startErr = pcall(function()
			QuestUI.Start()
		end)
		local speech = qGui:FindFirstChild("Card", true)
		t.ok(speech, "Murph's card: " .. tostring(startErr) .. " started=" .. tostring(started))
		if speech then
			check(speech, paper, "speech")
		end
	end)
end
