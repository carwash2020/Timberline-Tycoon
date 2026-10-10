--!nocheck
-- Lane P previews: the REAL store GUI, laid out from the Instances the game
-- builds (StoreUI.Start's panel, StoreBoard's poster canvas), written as
-- HTML for Playwright to screenshot. It resolves UDim2 sizes and positions,
-- AnchorPoint, UIPadding, UIGridLayout, UIListLayout, UIScale, UICorner,
-- UIStroke, UIGradient (the button shine), TextScaled with its size
-- constraint, wrapping and truncation, and draws the gamepad ring
-- (SelectionImageObject) round GuiService.SelectedObject. Montserrat stands
-- in for Gotham and Fredoka for FredokaOne (neither Roblox face is here).
--
--   lune run tools/preview/v1p_gui <out-dir>
-- Writes <out-dir>/*.html; tools/preview/v1p_shots.mjs turns them into PNGs.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

assert(fs.isFile("rokit.toml"), "Run this from the repo root")
local OUT = process.args[1] or "preview/v1-p"
fs.writeDir(OUT)

local Vector2, UDim2, Instance, Enum = roblox.Vector2, roblox.UDim2, roblox.Instance, roblox.Enum

-- Activated as a real signal, so a preview can press the store's tabs.
local handlers = {}
pcall(roblox.implementProperty, "TextButton", "Activated", function(inst)
	return {
		Connect = function(_, fn)
			handlers[inst] = handlers[inst] or {}
			table.insert(handlers[inst], fn)
			return { Disconnect = function() end }
		end,
	}
end)
for _, class in ipairs({ "TextButton", "Frame", "TextLabel", "ImageLabel", "ImageButton", "ScrollingFrame" }) do
	for _, prop in ipairs({
		"MouseEnter",
		"MouseLeave",
		"SelectionGained",
		"SelectionLost",
		"InputBegan",
		"InputEnded",
		"MouseButton1Down",
		"MouseButton1Up",
	}) do
		pcall(roblox.implementProperty, class, prop, function()
			return {
				Connect = function()
					return { Disconnect = function() end }
				end,
			}
		end)
	end
end
for _, class in ipairs({
	"TextButton",
	"Frame",
	"TextLabel",
	"ImageLabel",
	"ImageButton",
	"ScrollingFrame",
	"ScreenGui",
	"Folder",
	"UIScale",
	"UIStroke",
}) do
	pcall(roblox.implementMethod, class, "GetPropertyChangedSignal", function()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end)
end
local screenAbs = Vector2.new(1280, 684)
pcall(roblox.implementProperty, "ScreenGui", "AbsoluteSize", function()
	return screenAbs
end)
for _, class in ipairs({ "TextButton", "Frame", "TextLabel", "ImageLabel", "ImageButton", "ScrollingFrame" }) do
	pcall(roblox.implementProperty, class, "AbsoluteSize", function(inst)
		return Vector2.new(inst.Size.X.Offset, inst.Size.Y.Offset)
	end)
	pcall(roblox.implementProperty, class, "AbsolutePosition", function()
		return Vector2.zero
	end)
end
local function press(button)
	for _, fn in ipairs(handlers[button] or {}) do
		fn()
	end
end

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()

local function hex(c, mul)
	mul = mul or 1
	return string.format(
		"#%02X%02X%02X",
		math.clamp(math.floor(c.R * mul * 255 + 0.5), 0, 255),
		math.clamp(math.floor(c.G * mul * 255 + 0.5), 0, 255),
		math.clamp(math.floor(c.B * mul * 255 + 0.5), 0, 255)
	)
end
local function rgba(c, transparency)
	return string.format(
		"rgba(%d,%d,%d,%.3f)",
		math.floor(c.R * 255 + 0.5),
		math.floor(c.G * 255 + 0.5),
		math.floor(c.B * 255 + 0.5),
		1 - (transparency or 0)
	)
end
local function esc(text)
	text = tostring(text or "")
	text = string.gsub(text, "&", "&amp;")
	text = string.gsub(text, "<", "&lt;")
	return (string.gsub(text, ">", "&gt;"))
end

local FONTS = {
	GothamBlack = { "Montserrat", 900 },
	GothamBold = { "Montserrat", 700 },
	GothamMedium = { "Montserrat", 600 },
	GothamSemibold = { "Montserrat", 600 },
	Gotham = { "Montserrat", 500 },
	FredokaOne = { "Fredoka", 600 },
	SourceSansBold = { "Montserrat", 700 },
	SourceSans = { "Montserrat", 500 },
}

local function child(inst, class)
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA(class) then
			return c
		end
	end
	return nil
end

local function resolve(u, size)
	return Vector2.new(u.X.Scale * size.X + u.X.Offset, u.Y.Scale * size.Y + u.Y.Offset)
end

-- Content box of a container: its size less UIPadding.
local function content(inst, size)
	local pad = child(inst, "UIPadding")
	if not pad then
		return Vector2.new(0, 0), size
	end
	local l = pad.PaddingLeft.Scale * size.X + pad.PaddingLeft.Offset
	local r = pad.PaddingRight.Scale * size.X + pad.PaddingRight.Offset
	local t = pad.PaddingTop.Scale * size.Y + pad.PaddingTop.Offset
	local b = pad.PaddingBottom.Scale * size.Y + pad.PaddingBottom.Offset
	return Vector2.new(l, t), Vector2.new(size.X - l - r, size.Y - t - b)
end

local function visibleKids(inst)
	local kids = {}
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible then
			table.insert(kids, c)
		end
	end
	table.sort(kids, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.Name < b.Name
	end)
	return kids
end

-- Where each child goes when a layout places them: { [child] = {pos, size} }.
local function layoutPlaces(inst, origin, area)
	local places = {}
	local grid = child(inst, "UIGridLayout")
	local list = child(inst, "UIListLayout")
	if grid then
		local cell = resolve(grid.CellSize, area)
		local gap = resolve(grid.CellPadding, area)
		local kids = visibleKids(inst)
		local cols = math.max(1, math.floor((area.X + gap.X) / (cell.X + gap.X)))
		if grid.FillDirectionMaxCells > 0 then
			cols = math.min(cols, grid.FillDirectionMaxCells)
		end
		local used = math.min(cols, #kids)
		local rowW = used * cell.X + (used - 1) * gap.X
		local x0 = 0
		if grid.HorizontalAlignment == Enum.HorizontalAlignment.Center then
			x0 = (area.X - rowW) / 2
		elseif grid.HorizontalAlignment == Enum.HorizontalAlignment.Right then
			x0 = area.X - rowW
		end
		for i, k in ipairs(kids) do
			local c = (i - 1) % cols
			local r = (i - 1) // cols
			places[k] = { origin + Vector2.new(x0 + c * (cell.X + gap.X), r * (cell.Y + gap.Y)), cell }
		end
	elseif list then
		local kids = visibleKids(inst)
		local pad = list.Padding.Offset
		local horiz = list.FillDirection == Enum.FillDirection.Horizontal
		local sizes, total = {}, 0
		for i, k in ipairs(kids) do
			sizes[i] = resolve(k.Size, area)
			total += if horiz then sizes[i].X else sizes[i].Y
		end
		total += math.max(0, #kids - 1) * pad
		local cursor = 0
		if horiz and list.HorizontalAlignment == Enum.HorizontalAlignment.Center then
			cursor = (area.X - total) / 2
		elseif not horiz and list.VerticalAlignment == Enum.VerticalAlignment.Center then
			cursor = (area.Y - total) / 2
		end
		for i, k in ipairs(kids) do
			local s = sizes[i]
			local p
			if horiz then
				local y = 0
				if list.VerticalAlignment == Enum.VerticalAlignment.Center then
					y = (area.Y - s.Y) / 2
				end
				p = Vector2.new(cursor, y)
				cursor += s.X + pad
			else
				local x = 0
				if list.HorizontalAlignment == Enum.HorizontalAlignment.Center then
					x = (area.X - s.X) / 2
				end
				p = Vector2.new(x, cursor)
				cursor += s.Y + pad
			end
			places[k] = { origin + p, s }
		end
	end
	return places
end

local function cornerCss(inst, size)
	local c = child(inst, "UICorner")
	if not c then
		return ""
	end
	local r = c.CornerRadius.Scale * math.min(size.X, size.Y) + c.CornerRadius.Offset
	return string.format("border-radius:%.1fpx;", r)
end

local function strokeCss(inst, isText)
	for _, s in ipairs(inst:GetChildren()) do
		if s:IsA("UIStroke") and s.Enabled then
			local contextual = s.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual
			if isText and contextual then
				return string.format(
					"-webkit-text-stroke:%.1fpx %s;paint-order:stroke fill;",
					s.Thickness * 2,
					rgba(s.Color, s.Transparency)
				),
					false
			end
			return string.format("box-shadow:0 0 0 %.1fpx %s;", s.Thickness, rgba(s.Color, s.Transparency)), true
		end
	end
	return "", false
end

local function backgroundCss(inst)
	if inst.BackgroundTransparency >= 1 then
		return ""
	end
	local g = child(inst, "UIGradient")
	if g and g.Enabled then
		local stops = {}
		for _, kp in ipairs(g.Color.Keypoints) do
			local c = inst.BackgroundColor3
			local m = kp.Value
			local mixed = roblox.Color3.new(c.R * m.R, c.G * m.G, c.B * m.B)
			table.insert(stops, string.format("%s %.1f%%", rgba(mixed, inst.BackgroundTransparency), kp.Time * 100))
		end
		return string.format("background:linear-gradient(%ddeg,%s);", g.Rotation + 90, table.concat(stops, ","))
	end
	return "background:" .. rgba(inst.BackgroundColor3, inst.BackgroundTransparency) .. ";"
end

local function textCss(inst, size)
	local font = FONTS[inst.Font.Name] or { "Montserrat", 600 }
	local px = inst.TextSize
	if inst.TextScaled then
		local cap = child(inst, "UITextSizeConstraint")
		local _, area = content(inst, size)
		local len = math.max(1, utf8.len(inst.Text) or #inst.Text)
		px = math.min(area.Y * 0.9, area.X / (len * 0.62))
		if cap then
			px = math.clamp(px, cap.MinTextSize, cap.MaxTextSize)
		end
		px = math.floor(px)
	end
	local justify = "flex-start"
	if inst.TextXAlignment == Enum.TextXAlignment.Center then
		justify = "center"
	elseif inst.TextXAlignment == Enum.TextXAlignment.Right then
		justify = "flex-end"
	end
	local align = "center"
	if inst.TextYAlignment == Enum.TextYAlignment.Top then
		align = "flex-start"
	elseif inst.TextYAlignment == Enum.TextYAlignment.Bottom then
		align = "flex-end"
	end
	local textAlign = if justify == "center" then "center" elseif justify == "flex-end" then "right" else "left"
	local lines = math.max(1, math.floor(size.Y / (px * 1.18)))
	local wrap
	if inst.TextWrapped then
		wrap = string.format(
			"display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:%d;overflow:hidden;white-space:normal;",
			lines
		)
	else
		wrap = "white-space:nowrap;overflow:hidden;text-overflow:"
			.. (if inst.TextTruncate == Enum.TextTruncate.AtEnd then "ellipsis" else "clip")
			.. ";"
	end
	local stroke = ""
	if inst.TextStrokeTransparency < 1 then
		stroke = string.format(
			"-webkit-text-stroke:1.5px %s;paint-order:stroke fill;",
			rgba(inst.TextStrokeColor3, inst.TextStrokeTransparency)
		)
	end
	local textStroke = strokeCss(inst, true)
	return string.format(
		"display:flex;justify-content:%s;align-items:%s;font-family:'%s';font-weight:%d;font-size:%dpx;line-height:1.15;color:%s;",
		justify,
		align,
		font[1],
		font[2],
		px,
		rgba(inst.TextColor3, inst.TextTransparency)
	),
		string.format(
			'<span style="%s%s%stext-align:%s;max-width:100%%;">%s</span>',
			wrap,
			stroke,
			if string.find(textStroke, "text%-stroke") then textStroke else "",
			textAlign,
			esc(inst.Text)
		)
end

local selected = nil
local out = {}

local function render(inst, pos, size, depth)
	if not inst:IsA("GuiObject") or not inst.Visible then
		return
	end
	local isText = inst:IsA("TextLabel") or inst:IsA("TextButton")
	local style = string.format(
		"position:absolute;left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;box-sizing:border-box;",
		pos.X,
		pos.Y,
		size.X,
		size.Y
	)
	style ..= backgroundCss(inst) .. cornerCss(inst, size)
	local stroke = strokeCss(inst, isText)
	if not string.find(stroke, "text%-stroke") then
		style ..= stroke
	end
	if inst.ClipsDescendants or inst:IsA("ScrollingFrame") then
		style ..= "overflow:hidden;"
	end
	local inner = ""
	if (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) and inst.Image ~= "" then
		-- The art Roblox already has (public thumbnails, fetched once for the preview).
		local id = string.match(inst.Image, "(%d+)")
		if id and fs.isFile(OUT .. "/img-" .. id .. ".png") then
			inner = string.format(
				'<img src="img-%s.png" style="position:absolute;left:0;top:0;width:100%%;height:100%%;object-fit:contain;%s">',
				id,
				cornerCss(inst, size)
			)
		end
	end
	if isText and inst.Text ~= "" then
		local origin, area = content(inst, size)
		local css, span = textCss(inst, size)
		inner = string.format(
			'<div style="position:absolute;left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;%s">%s</div>',
			origin.X,
			origin.Y,
			area.X,
			area.Y,
			css,
			span
		)
	end
	table.insert(out, string.format('<div data-name="%s" style="%s">%s', esc(inst.Name), style, inner))
	local origin, area = content(inst, size)
	local places = layoutPlaces(inst, origin, area)
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("GuiObject") then
			local place = places[c]
			local cpos, csize
			if place then
				cpos, csize = place[1], place[2]
			else
				csize = resolve(c.Size, area)
				cpos = origin
					+ resolve(c.Position, area)
					- Vector2.new(c.AnchorPoint.X * csize.X, c.AnchorPoint.Y * csize.Y)
			end
			render(c, cpos, csize, depth + 1)
		end
	end
	if inst == selected and inst.SelectionImageObject then
		-- The ring, laid out against the selected object as Roblox does.
		render(
			inst.SelectionImageObject,
			(function()
				local ring = inst.SelectionImageObject
				local rs = resolve(ring.Size, size)
				return resolve(ring.Position, size) - Vector2.new(ring.AnchorPoint.X * rs.X, ring.AnchorPoint.Y * rs.Y)
			end)(),
			resolve(inst.SelectionImageObject.Size, size),
			depth + 1
		)
	end
	table.insert(out, "</div>")
end

local PAGE_HEAD = [[<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;}
body{width:%dpx;height:%dpx;overflow:hidden;position:relative;background:%s;}
</style></head><body>]]

-- A whole screen: the ScreenGui at its UIScale, under a 36 px top bar strip
-- (the Roblox core UI inset), over `backdrop` (an image path or a colour).
local function screenHtml(gui, w, h, backdrop, inset)
	inset = inset or 36
	out = {}
	local scale = 1
	local s = child(gui, "UIScale")
	if s then
		scale = s.Scale
	end
	local design = Vector2.new(w / scale, (h - inset) / scale)
	table.insert(out, string.format(PAGE_HEAD, w, h, "#000"))
	if backdrop then
		table.insert(
			out,
			string.format(
				'<img src="%s" style="position:absolute;left:0;top:0;width:%dpx;height:%dpx;object-fit:cover;">',
				backdrop,
				w,
				h
			)
		)
	end
	table.insert(
		out,
		string.format(
			'<div style="position:absolute;left:0;top:%dpx;width:%.1fpx;height:%.1fpx;transform:scale(%.4f);transform-origin:0 0;">',
			inset,
			design.X,
			design.Y,
			scale
		)
	)
	for _, c in ipairs(gui:GetChildren()) do
		if c:IsA("GuiObject") then
			local cs = resolve(c.Size, design)
			local cp = resolve(c.Position, design) - Vector2.new(c.AnchorPoint.X * cs.X, c.AnchorPoint.Y * cs.Y)
			render(c, cp, cs, 0)
		end
	end
	table.insert(out, "</div>")
	-- The Roblox top bar's strip (core UI), drawn as Roblox does over the scene.
	table.insert(
		out,
		string.format(
			'<div style="position:absolute;left:12px;top:4px;width:%dpx;height:%dpx;border-radius:%dpx;background:rgba(0,0,0,0.5)"></div>',
			inset - 8,
			inset - 8,
			(inset - 8) // 2
		)
	)
	table.insert(out, "</body></html>")
	return table.concat(out, "\n")
end

-- A SurfaceGui's canvas on its own, at its CanvasSize.
local function canvasHtml(surface, background)
	out = {}
	local size = surface.CanvasSize
	table.insert(out, string.format(PAGE_HEAD, size.X, size.Y, background))
	for _, c in ipairs(surface:GetChildren()) do
		if c:IsA("GuiObject") then
			local cs = resolve(c.Size, size)
			local cp = resolve(c.Position, size) - Vector2.new(c.AnchorPoint.X * cs.X, c.AnchorPoint.Y * cs.Y)
			render(c, cp, cs, 0)
		end
	end
	table.insert(out, "</body></html>")
	return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------
-- The store panel, from StoreUI.Start, at a viewport.

local PRICES = { -- Connor's prices (8 Oct 2026), standing in for Roblox's answer in the preview only
	[2005256811] = 499,
	[2005226878] = 300,
	[2006186967] = 99,
	[2006912886] = 199,
	[2006456926] = 149,
	[3716312861] = 49,
	[3716312899] = 299,
	[3717310556] = 299,
	[3717310577] = 35,
}

local function signal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
		Wait = function() end,
	}
end

local function bootStore(w, h, opts)
	opts = opts or {}
	local phone = math.min(w, h) < 500
	screenAbs = Vector2.new(w, h - 36)
	local playerGui = Instance.new("PlayerGui")
	playerGui.Name = "PlayerGui"
	local attrs = opts.attrs or {}
	local player = {
		Name = "Connor",
		UserId = 1,
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		GetAttributeChangedSignal = function()
			return signal()
		end,
		WaitForChild = function()
			return playerGui
		end,
		FindFirstChild = function()
			return playerGui
		end,
		FindFirstChildOfClass = function()
			return playerGui
		end,
	}
	local opener = nil
	-- Roblox's top bar: 36 px tall, as GetGuiInset reports it.
	local gui: any = { SelectedObject = nil, TopbarInset = { Max = Vector2.new(0, 36) } }
	gui.GetPropertyChangedSignal = function()
		return signal()
	end
	gui.IsTenFootInterface = function()
		return opts.tenFoot == true
	end
	gui.GetGuiInset = function()
		return Vector2.zero, Vector2.new(0, 36)
	end
	local loader = Loader.new({
		services = {
			GuiService = gui,
			-- No chat window in these shots.
			TextChatService = {
				FindFirstChildOfClass = function()
					return nil
				end,
				WaitForChild = function()
					return nil
				end,
				ChildAdded = signal(),
				DescendantAdded = signal(),
			},
			Players = { LocalPlayer = player },
			UserInputService = {
				TouchEnabled = phone,
				KeyboardEnabled = not phone,
				GamepadEnabled = opts.tenFoot == true,
				InputBegan = signal(),
				GetLastInputType = function()
					return if phone then Enum.UserInputType.Touch else Enum.UserInputType.Keyboard
				end,
			},
			MarketplaceService = {
				GetProductInfo = function(_, id)
					return { IsForSale = opts.offSale == nil or not opts.offSale[id], PriceInRobux = PRICES[id] }
				end,
			},
			CollectionService = {
				GetTagged = function()
					return {}
				end,
				GetInstanceAddedSignal = function()
					return signal()
				end,
			},
		},
		globals = {
			Instance = {
				new = function(class, parent)
					local inst = Instance.new(class)
					if inst:IsA("GuiBase2d") then
						inst.AbsoluteSize = if class == "ScreenGui" then screenAbs else Vector2.zero
						inst.AbsolutePosition = Vector2.zero
					end
					if parent then
						inst.Parent = parent
					end
					return inst
				end,
				fromExisting = Instance.fromExisting,
			},
			workspace = {
				GetPropertyChangedSignal = function()
					return signal()
				end,
				CurrentCamera = {
					ViewportSize = Vector2.new(w, h),
					GetPropertyChangedSignal = function()
						return signal()
					end,
				},
			},
			task = {
				spawn = function(fn, ...)
					local co = coroutine.create(fn)
					coroutine.resume(co, ...)
				end,
				defer = function() end,
				delay = function() end,
				wait = function()
					coroutine.yield()
				end,
			},
		},
		mocks = {
			HUD = {
				SetModal = function() end,
				BesideCash = function()
					return Instance.new("Frame")
				end,
				UnderCash = function()
					return Instance.new("Frame")
				end,
				SideButton = function()
					return { root = Instance.new("Frame"), face = Instance.new("TextButton"), SetText = function() end }
				end,
				Toast = function() end,
			},
			HudNav = { Add = function() end },
			ShopUI = {
				SetStoreOpener = function(fn)
					opener = fn
				end,
			},
			Net = {
				Remote = function()
					return { FireServer = function() end, OnClientEvent = signal() }
				end,
			},
		},
	})
	local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
	local okStart, why = pcall(function()
		UITheme.Start()
	end)
	if not okStart then
		print("  UITheme.Start: " .. tostring(why))
	end
	print("  UITheme.Scale() = " .. UITheme.Scale())
	local StorePrices = loader:load("StarterPlayer/StarterPlayerScripts/StorePrices")
	local StoreUI = loader:load("StarterPlayer/StarterPlayerScripts/StoreUI")
	StoreUI.Start()
	pcall(function()
		StorePrices.Load()
	end)
	local screen = playerGui:FindFirstChild("StoreUI")
	assert(screen, "StoreUI made no screen")
	local scale = child(screen, "UIScale")
	print(string.format("  %dx%d UIScale %.3f", w, h, scale and scale.Scale or 1))
	opener()
	print("  panel", screen.StorePanel.Size, "abs", screen.AbsoluteSize, "scale", UITheme.Scale())
	if opts.tab == "Products" then
		press(screen:FindFirstChild("Products", true):FindFirstChild("Face"))
	end
	return screen, gui
end

local function storeShots()
	-- The real HUD behind the store: lane U's in-context HUD renders
	-- (previews/v1-u/r3-hud-*), copied into OUT as _hud-phone/_hud-pc.png.
	local function hud(w: number): string?
		local name = if w < 1000 then "_hud-phone.png" else "_hud-pc.png"
		return if fs.isFile(OUT .. "/" .. name) then name else nil
	end
	local backdrop = hud(1920)
	for _, view in ipairs({
		{ "store-passes", "Passes", 667, 375 },
		{ "store-passes", "Passes", 1280, 720 },
		{ "store-passes", "Passes", 1920, 1080 },
		{ "store-products", "Products", 667, 375 },
		{ "store-products", "Products", 1280, 720 },
		{ "store-products", "Products", 1920, 1080 },
	}) do
		local screen = bootStore(view[3], view[4], {
			tab = view[2],
			attrs = { Cash = 12400, StoreStage = 3, Pass_LuxAxe = true },
		})
		local html = screenHtml(screen, view[3], view[4], hud(view[3]), 36)
		fs.writeFile(string.format("%s/%s-%dx%d.html", OUT, view[1], view[3], view[4]), html)
	end
	-- Xbox: a TV at 1920x1080, the ring on the first Buy pill.
	local screen, gui = bootStore(1920, 1080, { tenFoot = true, attrs = { Cash = 12400, StoreStage = 3 } })
	selected = gui.SelectedObject
	print("  gamepad selection: " .. (if selected then selected:GetFullName() else "none"))
	fs.writeFile(OUT .. "/store-gamepad-1920x1080.html", screenHtml(screen, 1920, 1080, backdrop, 36))
	selected = nil
	-- Purchase flow: one card off sale (Coming soon), one owned, a wallet-full pack.
	local flow = bootStore(1920, 1080, {
		tab = "Products",
		attrs = { Cash = 1_999_000, StoreStage = 6 },
		offSale = { [3717310577] = true },
	})
	fs.writeFile(OUT .. "/purchase-flow-states-1920x1080.html", screenHtml(flow, 1920, 1080, backdrop, 36))
end

local function boardShots()
	local loader = Loader.new({})
	local StoreBoard = loader:shared("StoreBoard")
	local StoreCopy = loader:shared("Store/StoreCopy")
	for _, view in ipairs({
		{ "board-canvas-page1", nil, 1 },
		{ "board-canvas-page2", nil, 2 },
		{ "board-canvas-page3", nil, 3 },
		{ "board-canvas-soon", { InstantDelivery = true, TimberClassic = true }, 1 },
	}) do
		local off = view[2]
		local model = StoreBoard.Build(if off
			then function(_, key)
				return not off[key]
			end
			else nil)
		local surface = model:FindFirstChild("Posters", true)
		local list = surface:FindFirstChild("List")
		StoreBoard.ShowPage(list, view[3])
		-- What each client paints on the pills: their own price.
		for _, d in ipairs(surface:GetDescendants()) do
			if d:IsA("TextLabel") and d.Name == "Price" then
				local loaderData = loader:shared("StoreData")
				local id = loaderData.IdOf(d:GetAttribute("RobuxKind"), d:GetAttribute("RobuxKey"))
				d.Text = StoreCopy.Price(PRICES[id])
			end
		end
		fs.writeFile(OUT .. "/" .. view[1] .. ".html", canvasHtml(surface, "#" .. surface.Parent.Color:ToHex()))
		-- The same canvas with no cork behind it, for pasting onto the 3D render.
		fs.writeFile(OUT .. "/" .. view[1] .. "-alpha.html", canvasHtml(surface, "transparent"))
	end
end

local which = process.args[2] or "all"
if which == "all" or which == "board" then
	print("== board canvas")
	boardShots()
end
if which == "all" or which == "store" then
	print("== store panel")
	storeShots()
end
