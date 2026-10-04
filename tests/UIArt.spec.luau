--!nocheck
-- HUD art (UIArt, UITheme.Card, the cash plaque, the top row, prompts).
-- The skins are sliced images; an empty id is today's flat card; the cash
-- text doesn't change; $1,999,999 fits; the top row stays in the bar or
-- just under it, clear of Roblox's buttons and the notch; a pressed
-- prompt button doesn't stay pressed.
return function(t)
	local roblox = t.roblox
	local Instance, Vector2, Rect, Enum = roblox.Instance, roblox.Vector2, roblox.Rect, roblox.Enum

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
	roblox.implementMethod("Frame", "GetPropertyChangedSignal", function()
		return signal()
	end)
	roblox.implementProperty("NumberValue", "Changed", function()
		return signal()
	end)

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
		return t.loader({
			services = {
				GuiService = {
					IsTenFootInterface = function()
						return false
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
				TextChatService = {},
				UserInputService = {
					TouchEnabled = extra.touch == true,
					KeyboardEnabled = if extra.keyboard == nil then true else extra.keyboard,
				},
				ContextActionService = {},
				ProximityPromptService = {},
				StarterGui = {},
				TweenService = extra.tween or {},
			},
			globals = {
				workspace = { CurrentCamera = extra.camera },
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

	local function cashAt(w, h)
		local parent = Instance.new("Folder")
		local loader = client({
			camera = { ViewportSize = Vector2.new(w, h) },
		})
		local HUD = loader:load("StarterPlayer/StarterPlayerScripts/HUD")
		HUD.BuildCash(parent)
		local screen = parent:FindFirstChild("TimberlineTop")
		local row = screen:FindFirstChild("TopRow")
		local plaque = row:FindFirstChild("CashPlaque")
		local face = plaque:FindFirstChild("Face")
		local paper = face:FindFirstChild("Paper")
		local label = paper:FindFirstChildWhichIsA("TextLabel")
		return {
			screen = screen,
			row = row,
			plaque = plaque,
			face = face,
			paper = paper,
			label = label,
			HUD = HUD,
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
			t.eq(built.screen:FindFirstChildOfClass("UIScale"), nil, "the top screen isn't scaled")
			local pad = paddingOf(built.face)
			for _, side in ipairs(pad) do
				t.ok(side >= 4, "plaque inset")
			end
		end
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
			-- A notch on each side, plus the 12 px right margin.
			local leftSafe, rightSafe = if math.min(w, h) < UITheme.CompactEdge then 44 else 0, 0
			local room = w - leftSafe - rightSafe - 12
			t.ok(plaqueW <= room, string.format("%dx%d plaque %d in %d", w, h, plaqueW, room))
			local barH = 36
			local place = HudLayout.TopRow(
				Vector2.new(w, h),
				Rect.new(math.min(160, w * 0.12), 0, w - 48, barH),
				Vector2.new(plaqueW, textH + inset * 2),
				textH,
				leftSafe,
				rightSafe,
				barH + 4
			)
			local left = place.right - plaqueW
			t.ok(left >= leftSafe, "not in the left notch")
			t.ok(place.right <= w - rightSafe, "not in the right notch")
			t.ok(place.inBar, "the plaque's own width fits the bar")
		end
	end)

	t.test("the top row clears Roblox's buttons and the notch", function()
		local HudLayout = t.load("StarterPlayer/StarterPlayerScripts/HudLayout")
		-- w, h, minX, minY, maxX, maxY, leftSafe, rightSafe, rowW, rowH, textH, fallback, inBar
		local cases = {
			{ 375, 667, 48, 0, 330, 36, 0, 0, 180, 28, 20, 40, true },
			{ 667, 375, 88, 0, 620, 36, 0, 0, 200, 28, 20, 40, true },
			{ 1024, 768, 150, 0, 980, 36, 0, 0, 220, 34, 26, 40, true },
			{ 1920, 1080, 160, 0, 1860, 36, 0, 0, 240, 34, 26, 40, true },
			{ 1920, 1080, 0, 0, 0, 0, 0, 0, 240, 34, 26, 62, false }, -- inset reads 0
			{ 667, 375, 48, 0, 640, 36, 80, 0, 100, 28, 20, 40, true }, -- left notch, still fits
			{ 667, 375, 48, 0, 300, 36, 80, 0, 230, 28, 20, 40, false }, -- left notch pushes it under
			{ 667, 375, 48, 0, 667, 36, 0, 44, 200, 28, 20, 40, true }, -- right notch
			{ 375, 667, 48, 0, 200, 36, 0, 0, 180, 28, 20, 40, false }, -- wider than the bar
			{ 1920, 1080, 160, 0, 1860, 24, 0, 0, 240, 34, 26, 28, false }, -- bar shorter than the text
			{ 800, 600, 48, 0, 248, 36, 0, 0, 184, 34, 26, 40, true }, -- exactly the bar's width minus 16
			{ 800, 600, 48, 0, 248, 36, 0, 0, 185, 34, 26, 40, false },
		}
		for _, c in ipairs(cases) do
			local w, h = c[1], c[2]
			local minX, minY, maxX, maxY = c[3], c[4], c[5], c[6]
			local leftSafe, rightSafe = c[7], c[8]
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

		began:Fire()
		t.eq(face.Image, UIArt.ButtonPressed.id, "pressed")
		ended:Fire()
		t.eq(face.Image, UIArt.Button.id, "release puts Button back")

		began:Fire()
		began:Fire()
		t.eq(face.Image, UIArt.ButtonPressed.id)
		triggered:Fire()
		t.eq(face.Image, UIArt.Button.id, "trigger puts Button back")
		ended:Fire()
		t.eq(face.Image, UIArt.Button.id, "a second release doesn't stick")
	end)
end
