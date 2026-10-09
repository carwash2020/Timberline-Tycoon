--!nocheck
-- UI round 3 (GAD): the code-built plaque, panel and button skins, the
-- phone HUD's three 44 x 44 icon buttons (MENU, HAMMER, Sell here), and the
-- contrast of the colours they use. The icon ids are the uploaded IMAGE
-- ids; SAVES and Send truck home move into MENU on a phone only.
return function(t)
	local roblox = t.roblox
	local Instance, Vector2, Rect, Enum = roblox.Instance, roblox.Vector2, roblox.Rect, roblox.Enum

	local function signal()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end
	for _, prop in ipairs({ "InputBegan", "InputEnded", "SelectionLost", "Activated" }) do
		pcall(roblox.implementProperty, "TextButton", prop, signal)
	end

	local function theme(phone)
		local playerGui = Instance.new("Folder")
		playerGui.Name = "PlayerGui"
		local loader = t.loader({
			services = {
				GuiService = {
					IsTenFootInterface = function()
						return false
					end,
					TopbarInset = Rect.new(0, 0, 0, 0),
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
				ContentProvider = {
					PreloadAsync = function(_, _, callback)
						if callback then
							callback("", Enum.AssetFetchStatus.Success)
						end
					end,
				},
				UserInputService = { TouchEnabled = phone, KeyboardEnabled = not phone },
			},
			globals = {
				workspace = {
					CurrentCamera = if phone then { ViewportSize = Vector2.new(667, 375) } else nil,
				},
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
				},
			},
		})
		return loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
	end

	local function hex(color)
		return string.format(
			"#%02X%02X%02X",
			math.floor(color.R * 255 + 0.5),
			math.floor(color.G * 255 + 0.5),
			math.floor(color.B * 255 + 0.5)
		)
	end
	local function lin(c)
		return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
	end
	local function lum(color)
		return 0.2126 * lin(color.R) + 0.7152 * lin(color.G) + 0.0722 * lin(color.B)
	end
	local function ratio(a, b)
		local hi, lo = lum(a), lum(b)
		if hi < lo then
			hi, lo = lo, hi
		end
		return (hi + 0.05) / (lo + 0.05)
	end

	t.test("the GAD tokens are the final hex values", function()
		local C = theme(false).Colors
		t.eq(hex(C.Paper), "#F0E1C3")
		t.eq(hex(C.PaperDark), "#E2CFAA")
		t.eq(hex(C.Cream), "#F5EBD7")
		t.eq(hex(C.Bark), "#583A22")
		t.eq(hex(C.Ink), "#3C2814")
		t.eq(hex(C.MutedStroke), "#A09178")
	end)

	t.test("the three phone icons are the uploaded Image ids, 44 x 44 buttons with a 28 px icon", function()
		local UITheme = theme(true)
		t.eq(UITheme.HudIcons.Menu, 76852120099119)
		t.eq(UITheme.HudIcons.Hammer, 129127727779001)
		t.eq(UITheme.HudIcons.SellHere, 96932580819074)
		t.eq(UITheme.HudIconImage("Menu"), "rbxassetid://76852120099119")
		t.eq(UITheme.HudIconImage("Hammer"), "rbxassetid://129127727779001")
		t.eq(UITheme.HudIconImage("SellHere"), "rbxassetid://96932580819074")
		t.eq(UITheme.HudIconImage("Nothing"), nil)
		t.eq(UITheme.IconButton, 44)
		t.eq(UITheme.IconSize, 28)
		-- About 8 px of padding round the icon.
		t.eq((UITheme.IconButton - UITheme.IconSize) / 2, 8)
	end)

	t.test(
		"a phone's icon buttons are squares showing the image; the text only when the id is 0 or the load fails",
		function()
			local UITheme = theme(true)
			for _, name in ipairs({ "Menu", "Hammer", "SellHere" }) do
				local look = UITheme.SideLook(true, name, nil, "Text", "buy")
				t.ok(look.square and look.showImage, name .. ": the real icon")
				t.eq(look.text, "", name .. ": no text beside the icon")
				local pending = UITheme.SideLook(true, name, "Pending", "Text", "buy")
				t.ok(pending.showImage, name .. ": still pending shows the image")
				local failed = UITheme.SideLook(true, name, "Failure", "Text", "buy")
				t.ok(failed.square and not failed.showImage, name .. ": a failed load")
				t.eq(failed.text, UITheme.IconFallbackText[name], name .. ": falls back to its short text")
			end
			t.eq(UITheme.IconFallbackText, { Menu = "MENU", Hammer = "BUILD", SellHere = "SELL" })
			-- An id of 0 is the same as a failed load.
			UITheme.HudIcons.Hammer = 0
			local zero = UITheme.SideLook(true, "Hammer", nil, "HAMMER", "buy")
			t.ok(zero.square and not zero.showImage)
			t.eq(zero.text, "BUILD")
		end
	)

	t.test("MENU is amber; HAMMER and Sell here sit on the deeper green", function()
		local UITheme = theme(true)
		t.eq(UITheme.SideLook(true, "Menu", nil, "MENU", "amber").style, "amber")
		t.eq(UITheme.SideLook(true, "Hammer", nil, "HAMMER", "buy").style, "iconGreen")
		t.eq(UITheme.SideLook(true, "SellHere", nil, "Sell here", "buy").style, "iconGreen")
		local C = UITheme.Colors
		t.eq(UITheme.Styles.iconGreen.fill, C.Green)
		t.eq(UITheme.Styles.iconGreen.ink, C.Cream)
	end)

	t.test("off a phone, or with no icon, a side button is the text button it was", function()
		local UITheme = theme(false)
		for _, name in ipairs({ "Menu", "Hammer", "SellHere" }) do
			local look = UITheme.SideLook(false, name, nil, "Sell here", "buy")
			t.eq(look, { square = false, showImage = false, text = "Sell here", style = "buy" })
		end
		local plain = UITheme.SideLook(true, nil, nil, "SAVES", "bark")
		t.eq(plain, { square = false, showImage = false, text = "SAVES", style = "bark" })
		t.eq(UITheme.Sized("SideButton").size.X, 110, "PC and Xbox keep the 110 x 40 button")
		t.eq(theme(true).Sized("SideButton").size.X, 116, "and a phone's other buttons stay 116 x 44")
	end)

	t.test("MENU, HAMMER and Sell here stack in one column, 44 apart by 8, 12 from the edge", function()
		local HudLayout = t.load("StarterPlayer/StarterPlayerScripts/HudLayout")
		local UITheme = theme(true)
		-- 667 x 375: the jump box is 70 px, top-left 95 from the right and 90 up.
		local jump = { left = 667 - 95, top = 375 - 90, right = 667 - 25, bottom = 375 - 20 }
		local corner, room = HudLayout.SideColumn(Vector2.new(667, 375), 100, jump, 12, 8, 24, 44)
		t.ok(corner.X <= 667 - 12, "no nearer the edge than the 12 px margin")
		local face = UITheme.IconButton
		local sizes = { Vector2.new(face, face), Vector2.new(face, face), Vector2.new(face, face) }
		-- A phone never wraps (HUD.arrangeSide lifts the room to the column's height).
		local height = 3 * face + 3 * 8
		local spots = HudLayout.Stack(sizes, math.max(room, height), 8)
		for i = 1, 3 do
			t.eq(spots[i].X, 0, "button " .. i .. " is in the one column")
		end
		t.eq(spots[2].Y - spots[3].Y, face + 8, "8 px between faces")
		t.eq(spots[1].Y - spots[2].Y, face + 8, "8 px between faces")
	end)

	t.test(
		"a plaque and a panel are code-built: Paper face, Bark stroke and 4 px drop edge, gradient, corner 12",
		function()
			local UITheme = theme(false)
			local C = UITheme.Colors
			for kind, inset in pairs({ Plaque = 4, Panel = 12 }) do
				local card = UITheme.Plate(kind)
				t.eq(card.outer.BackgroundColor3, C.Bark, kind .. ": the drop edge is Bark")
				t.eq(card.face.Size.Y.Offset, -4, kind .. ": the face stops 4 px short of the edge")
				t.eq(card.face.Image, "", kind .. ": no image, so no image shadow")
				t.eq(card.face:FindFirstChildOfClass("UICorner").CornerRadius.Offset, 12)
				local stroke = card.face:FindFirstChildOfClass("UIStroke")
				t.eq(stroke.Thickness, 2)
				t.eq(stroke.Color, C.Bark)
				local pad = card.face:FindFirstChildOfClass("UIPadding")
				t.eq(pad.PaddingTop.Offset, inset, kind .. ": content inset")
				t.eq(pad.PaddingLeft.Offset, inset)
				local shade = card.face:FindFirstChildOfClass("UIGradient")
				t.eq(shade.Rotation, 90)
				local keys = shade.Color.Keypoints
				t.ok(math.abs(keys[2].Time - 0.18) < 1e-6, "Paper at 0.18")
				t.eq(hex(keys[1].Value), "#F5EBD7", "Cream at the top")
				t.eq(hex(keys[2].Value), "#F0E1C3", "Paper")
				t.eq(hex(keys[3].Value), "#E2CFAA", "PaperDark at the bottom")
				t.eq(card.face.BackgroundColor3, roblox.Color3.new(1, 1, 1), "white, so the gradient shows as written")
			end
		end
	)

	t.test(
		"a button: corner 10, a 3 px drop edge in its edge colour, a shine, a 2 px stroke only on starter",
		function()
			local UITheme = theme(false)
			local C = UITheme.Colors
			t.eq(UITheme.ButtonRadius, 10)
			t.eq(UITheme.ButtonDrop, 3)
			for name, style in pairs(UITheme.Styles) do
				local button = UITheme.Button({ text = "X", size = Vector2.new(100, 44), style = name })
				t.eq(button.root.Size.Y.Offset, 44 + 3, name .. ": the face and its 3 px edge")
				t.eq(button.face.Size.Y.Offset, -3, name .. ": the face stops 3 px short")
				t.eq(button.face:FindFirstChildOfClass("UICorner").CornerRadius.Offset, 10, name .. ": corner 10")
				local stroke = button.face:FindFirstChildOfClass("UIStroke")
				t.eq(stroke.Enabled, name == "starter", name .. ": the stroke is on starter only")
				if name == "starter" then
					t.eq(stroke.Color, C.MutedStroke)
					t.eq(stroke.Thickness, 2)
				else
					t.eq(button.root.BackgroundColor3, style.edge, name .. ": the drop edge is its edge colour")
					t.eq(button.root.BackgroundTransparency, 0, name .. ": the edge shows at rest")
				end
				t.eq(button.face.Position.Y.Offset, 0, name .. ": at rest the face sits on top")
				local shine = button.face:FindFirstChildOfClass("UIGradient")
				t.eq(shine.Rotation, 90)
				local keys = shine.Color.Keypoints
				t.eq(#keys, 3)
				t.eq(hex(keys[1].Value), "#FFFFFF", name .. ": white at 0")
				t.ok(math.abs(keys[2].Time - 0.12) < 1e-6, name .. ": grey from 0.12")
				t.eq(hex(keys[2].Value), hex(keys[3].Value))
				t.ok(math.abs(keys[3].Value.R - 0.9) < 0.005, name .. ": 0.9 grey")
			end
		end
	)

	t.test("the colours of the new skins have the contrast the brief asks for", function()
		local C = theme(false).Colors
		t.ok(ratio(C.Ink, C.Paper) >= 4.5, "Ink on Paper")
		t.ok(ratio(C.Bark, C.Paper) >= 4.5, "Bark on Paper")
		t.ok(ratio(C.Ink, C.PaperDark) >= 4.5, "Ink on PaperDark")
		t.ok(ratio(C.Bark, C.PaperDark) >= 4.5, "Bark on PaperDark")
		t.ok(ratio(C.Bark, C.Cream) >= 4.5, "Bark on Cream")
		t.ok(ratio(C.Cream, C.Green) >= 3, "Cream on the icon green")
		t.ok(ratio(C.Ink, C.Amber) >= 3, "Ink on amber")
		t.ok(ratio(C.Cream, C.Bark) >= 4.5, "Cream on Bark")
	end)

	t.test("the loading card's colours and numbers are the GAD ones", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/ReplicatedFirst/LoadingScreen.client.luau")
		for _, needle in ipairs({
			'"#3C2814"',
			'"#F5EBD7"',
			'"#F0E1C3"',
			'"#E2CFAA"',
			'"#583A22"',
			"CARD_WIDTH = 280",
			"CARD_HEIGHT = 132",
			"CARD_SHARE = 0.72",
			"BACKDROP_TRANSPARENCY = 0.45",
			"Enum.Font.FredokaOne",
			"Enum.Font.GothamMedium",
		}) do
			t.ok(string.find(source, needle, 1, true), "LoadingScreen has " .. needle)
		end
	end)

	t.test("on a phone SAVES, Send truck home and OWNER are rows in MENU; the rest of the HUD is as it was", function()
		local fs = require("@lune/fs")
		local dir = "src/StarterPlayer/StarterPlayerScripts/"
		local function has(file, needle)
			t.ok(string.find(fs.readFile(dir .. file), needle, 1, true), file .. ": " .. needle)
		end
		has("SaveSlotUI.luau", "phoneMenu = true")
		has("VehicleController.luau", "phoneMenu = true")
		has("AdminUI.luau", "phoneMenu = true")
		has("StoreUI.luau", 'icon = "SellHere"')
		has("PlotUI.luau", 'icon = "Hammer"')
		has("QuickMenuUI.luau", 'icon = "Menu"')
		has("QuickMenuUI.luau", "HUD.MenuRows()")
		has("QuickMenuUI.luau", 'device == "phone"')
		-- Nothing in this lane binds the Xbox chop button.
		for _, file in ipairs({
			"HUD.luau",
			"QuickMenuUI.luau",
			"NewsUI.luau",
			"UITheme.luau",
			"MenuPad.luau",
		}) do
			t.eq(string.find(fs.readFile(dir .. file), "ButtonR2", 1, true), nil, file .. " never touches ButtonR2")
		end
	end)

	t.test(
		"What's New: Close is a 44 x 44 square at the top right of the title strip, clear of title and rows",
		function()
			local fs = require("@lune/fs")
			local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/NewsUI.luau")
			local function has(needle, message)
				t.ok(string.find(source, needle, 1, true), message)
			end
			has("size = Vector2.new(UITheme.Size.Tap, UITheme.Size.Tap)", "44 x 44")
			has("close.root.Size = UDim2.fromOffset(tap, tap + UITheme.ButtonDrop)", "the face is tap x tap")
			has("close.root.Parent = hero", "in the title strip")
			has("local margin = math.ceil(8 / scale)", "8 px on screen")
			has("hero.Size = UDim2.new(1, 0, 0, tap + 2 * margin)", "the strip is 8 + 44 + 8")
			has("word.Size = UDim2.new(1, -(tap + 3 * margin)", "the title stops short of Close")
			has("row.LayoutOrder = 1 + i", "the rows come after the strip")
			t.eq(string.find(source, "CloseRow", 1, true), nil, "no separate Close row")
		end
	)
end
