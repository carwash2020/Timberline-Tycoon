--!nocheck
-- The grey box (Xbox join, 13 October): once the loading card hands over to
-- the game, no big translucent veil may be left on screen. Each full-screen
-- overlay is built by its real module against the Instance stand-ins, put in
-- its idle (closed) state with the save loaded, and then every GuiObject
-- that is visible, covers more than 35% of the viewport and is not
-- (nearly) transparent must be on an explicit allow-list of modals that are
-- actually open. Big gamepad-selectable objects must carry a transparent
-- SelectionImageObject (or be Selectable = false), so the engine's default
-- grey selection box never draws over them. Run at a PC and a phone size.
return function(t)
	local roblox = t.roblox
	local Instance, Vector2, Enum, UDim2 = roblox.Instance, roblox.Vector2, roblox.Enum, roblox.UDim2
	local fs = require("@lune/fs")

	local BIG = 0.35
	local OPAQUE = 0.95 -- BackgroundTransparency at or above this is not a veil
	local SIZES = { Vector2.new(1920, 1080), Vector2.new(667, 375) }

	-- Pixel size of a GuiObject from its Size (UIScale / constraints ignored:
	-- scales of 1 or more only make an overlay bigger, never smaller).
	local function pixels(obj, parent)
		local sz = obj.Size
		return sz.X.Scale * parent.X + sz.X.Offset, sz.Y.Scale * parent.Y + sz.Y.Offset
	end

	-- Every offender under `root` (a ScreenGui or any container) at `viewport`.
	-- allow: { [name] = true } for the open modals.
	local function offenders(root, viewport, allow)
		local out = {}
		local function walk(node, parent, shown)
			for _, child in ipairs(node:GetChildren()) do
				if child:IsA("GuiObject") then
					local w, h = pixels(child, parent)
					local visible = shown and child.Visible
					local area = (w * h) / (viewport.X * viewport.Y)
					if visible and area > BIG and not allow[child.Name] then
						if child.BackgroundTransparency < OPAQUE then
							table.insert(out, child.Name .. " (translucent veil)")
						end
						if child.Selectable and child.SelectionImageObject == nil and child:IsA("GuiButton") then
							table.insert(out, child.Name .. " (big selectable, no SelectionImageObject)")
						end
					end
					walk(child, Vector2.new(w, h), visible)
				elseif child:IsA("ScreenGui") then
					walk(child, viewport, shown and child.Enabled)
				else
					walk(child, parent, shown)
				end
			end
		end
		walk(root, viewport, true)
		return out
	end

	-- Lune's buttons have no input signals: give each its own inert ones.
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

	local function describe(list)
		return table.concat(list, "; ")
	end

	local function signals()
		local function ev()
			local fns = {}
			return {
				Connect = function(_, fn)
					table.insert(fns, fn)
					return { Disconnect = function() end }
				end,
				Fire = function(_, ...)
					for _, fn in ipairs(table.clone(fns)) do
						fn(...)
					end
				end,
			}
		end
		return ev
	end

	-- A client: PlayerGui, a player whose attributes are set here, the
	-- services the overlays touch.
	local function client(viewport, attrs)
		local c = { attributes = table.clone(attrs or {}), listeners = {} }
		local playerGui = Instance.new("Folder")
		playerGui.Name = "PlayerGui"
		c.playerGui = playerGui
		local player = {
			Name = "Tester",
			GetAttribute = function(_, name)
				return c.attributes[name]
			end,
			SetAttribute = function(_, name, value)
				c.attributes[name] = value
				for _, fn in ipairs(c.listeners[name] or {}) do
					fn()
				end
			end,
			GetAttributeChangedSignal = function(_, name)
				return {
					Connect = function(_, fn)
						c.listeners[name] = c.listeners[name] or {}
						table.insert(c.listeners[name], fn)
						return { Disconnect = function() end }
					end,
				}
			end,
			WaitForChild = function(_, name)
				return if name == "PlayerGui" then playerGui else nil
			end,
			FindFirstChild = function()
				return nil
			end,
			FindFirstChildOfClass = function(_, class)
				return if class == "PlayerGui" then playerGui else nil
			end,
			CharacterRemoving = { Connect = function() end },
		}
		c.player = player
		local ev = signals()
		c.services = {
			GuiService = {
				SelectedObject = nil,
				IsTenFootInterface = function()
					return false
				end,
				GetPropertyChangedSignal = function()
					return ev()
				end,
				MenuOpened = ev(),
			},
			Players = { LocalPlayer = player },
			UserInputService = {
				TouchEnabled = viewport.X < 1000,
				KeyboardEnabled = viewport.X >= 1000,
				InputBegan = ev(),
				LastInputTypeChanged = ev(),
				WindowFocusReleased = ev(),
				GetLastInputType = function()
					return Enum.UserInputType.MouseMovement
				end,
			},
			TextChatService = {},
			ContextActionService = {
				BindActionAtPriority = function() end,
				UnbindAction = function() end,
			},
		}
		c.globals = {
			workspace = { CurrentCamera = { ViewportSize = viewport } },
			task = {
				defer = function() end,
				delay = function() end,
				spawn = function(fn, ...)
					fn(...)
				end,
			},
		}
		return c
	end

	-- NewsUI reads AbsolutePosition (Lune has no layout), so its Start stops
	-- in placeCard; every Instance it made is captured, and its ScreenGui is
	-- put in PlayerGui as Start would, which is its idle state at join.
	local function news(c)
		local made = {}
		local globals = table.clone(c.globals)
		globals.Instance = {
			new = function(class)
				local inst = Instance.new(class)
				table.insert(made, inst)
				return inst
			end,
		}
		local loader = t.loader({
			services = c.services,
			globals = globals,
			mocks = {
				Net = {
					Remote = function()
						return { FireServer = function() end }
					end,
				},
				MenuPad = {
					Open = function() end,
					Close = function() end,
					Closes = function()
						return false
					end,
				},
			},
		})
		local UI = loader:load("StarterPlayer/StarterPlayerScripts/NewsUI")
		pcall(UI.Start)
		for _, inst in ipairs(made) do
			if inst:IsA("ScreenGui") and inst.Name == "NewsUI" then
				inst.Parent = c.playerGui
			end
		end
		return UI
	end

	-- What's new: no scrim at all (13-14 October: the full-screen Scrim
	-- TextButton was the grey box behind the card), and the card is dead
	-- centre. Lune has no layout engine, so the card's bounds are computed
	-- from its properties: the ScreenGui area (viewport less insets) over
	-- the UIScale gives the space the card's scale resolves against; its
	-- height is its padding plus the visible rows of its list.
	local CENTRE_SIZES = {
		{ name = "1920x1080 Xbox/PC", vp = Vector2.new(1920, 1080), inset = { 0, 0, 0, 0 } },
		{ name = "667x375 phone", vp = Vector2.new(667, 375), inset = { 0, 0, 0, 0 } },
		{ name = "812x375 notched phone", vp = Vector2.new(812, 375), inset = { 44, 0, 44, 21 } },
		{ name = "1920x1080 TV-safe margin", vp = Vector2.new(1920, 1080), inset = { 48, 27, 48, 27 } },
	}

	local function cardHeight(card)
		local face = card.Face
		local pad = face:FindFirstChildOfClass("UIPadding")
		local list = face:FindFirstChildOfClass("UIListLayout")
		local h = pad.PaddingTop.Offset + pad.PaddingBottom.Offset
		local n = 0
		for _, child in ipairs(face:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible then
				h += child.Size.Y.Offset
				n += 1
			end
		end
		return h + list.Padding.Offset * math.max(n - 1, 0)
	end

	for _, case in ipairs(CENTRE_SIZES) do
		for _, open in ipairs({ false, true }) do
			t.test(
				"What's new is centred with no backing at " .. case.name .. (open and " (open)" or " (closed)"),
				function()
					local viewport = case.vp
					local c = client(viewport, { ProfileLoaded = true, NewsV1Seen = true, TutorialStep = 99 })
					local UI = news(c)
					if open then
						UI.Open()
					end
					local gui = c.playerGui:FindFirstChild("NewsUI")
					t.ok(gui ~= nil, "the screen exists")
					local card = gui:FindFirstChild("WhatsNew")
					t.ok(card ~= nil, "the card exists")
					t.eq(card.Visible, open)
					t.eq(card.AnchorPoint, Vector2.new(0.5, 0.5))
					t.eq(card.Position, UDim2.new(0.5, 0, 0.5, 0))
					-- Nothing between the card and the ScreenGui paints.
					local node = card.Parent
					while node ~= nil and not node:IsA("ScreenGui") do
						t.ok(
							not (node:IsA("GuiObject") and node.Visible and node.BackgroundTransparency < 1),
							"ancestor " .. node.Name .. " paints a backing"
						)
						node = node.Parent
					end
					t.ok(node == gui, "the card is under the NewsUI screen")
					t.eq(gui:FindFirstChild("Scrim"), nil, "no scrim")
					-- The ScreenGui holds the card and no other GuiObject (no
					-- full-screen frame, button or dim behind it).
					for _, child in ipairs(gui:GetChildren()) do
						if child:IsA("GuiObject") then
							t.eq(child.Name, "WhatsNew", "stray GuiObject in the screen: " .. child.Name)
						end
					end
					-- Nothing else in the PlayerGui is a veil either.
					t.eq(#offenders(c.playerGui, viewport, { WhatsNew = true }), 0)
					-- Computed bounds.
					local scale = gui:FindFirstChildOfClass("UIScale").Scale
					local areaW = viewport.X - case.inset[1] - case.inset[3]
					local areaH = viewport.Y - case.inset[2] - case.inset[4]
					local logicW, logicH = areaW / scale, areaH / scale
					local limit = card:FindFirstChildOfClass("UISizeConstraint")
					local w = math.min(card.Size.X.Scale * logicW + card.Size.X.Offset, limit.MaxSize.X)
					local h = cardHeight(card)
					local px, py = w * scale, h * scale
					local cx = case.inset[1] + areaW * card.Position.X.Scale + card.Position.X.Offset * scale
					local cy = case.inset[2] + areaH * card.Position.Y.Scale + card.Position.Y.Offset * scale
					local left, top = cx - px * card.AnchorPoint.X, cy - py * card.AnchorPoint.Y
					t.ok(left >= 0 and top >= 0, "card starts on screen")
					t.ok(left + px <= viewport.X and top + py <= viewport.Y, "card ends on screen")
					t.ok(left >= case.inset[1] and top >= case.inset[2], "inside the safe area (top left)")
					t.ok(
						left + px <= viewport.X - case.inset[3] and top + py <= viewport.Y - case.inset[4],
						"inside the safe area (bottom right)"
					)
					t.ok(math.abs((left + px / 2) - (case.inset[1] + areaW / 2)) <= 1, "centred across")
					t.ok(math.abs((top + py / 2) - (case.inset[2] + areaH / 2)) <= 1, "centred down")
				end
			)
		end
	end

	t.test("the news source has no scrim and no offset placement", function()
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/NewsUI.luau")
		t.eq(string.find(src, 'Instance.new("TextButton")', 1, true), nil, "no full-screen button")
		t.eq(string.find(src, "scrimBack", 1, true), nil)
		t.eq(string.find(src, "AbsolutePosition", 1, true), nil, "placement ignores the screen's offset")
		t.ok(string.find(src, "UDim2.fromScale(0.5, 0.5)", 1, true), "centred")
	end)

	for _, viewport in ipairs(SIZES) do
		local label = string.format("%dx%d", viewport.X, viewport.Y)

		t.test(
			"the quality picker is no veil once a choice is saved, and is the only modal while open (" .. label .. ")",
			function()
				for _, saved in ipairs({ "low", "high" }) do
					local c = client(viewport, { ProfileLoaded = true, SettingQuality = saved })
					local loader = t.loader({
						services = c.services,
						globals = c.globals,
						mocks = {
							Net = {
								Remote = function()
									return { FireServer = function() end }
								end,
							},
							Quality = {
								TouchOnly = function()
									return false
								end,
								Refresh = function() end,
							},
						},
					})
					local UI = loader:load("StarterPlayer/StarterPlayerScripts/QualityPickerUI")
					UI.Start()
					local list = offenders(c.playerGui, viewport, {})
					t.eq(#list, 0, saved .. ": " .. describe(list))
				end
			end
		)
	end

	-- The loading card (ReplicatedFirst) is exercised by LoadingScreen.spec;
	-- here only the hand-over contract: it never outlives its fade, and the
	-- failsafe sweeps a leftover one.
	t.test("the loading card has a bounded failsafe that names a leftover card", function()
		local src = fs.readFile("src/ReplicatedFirst/LoadingScreen.client.luau")
		t.ok(string.find(src, "task.delay(FAILSAFE_SECONDS, sweep, playerGui)", 1, true), "after the hand-over")
		t.ok(string.find(src, "failsafe: leftover loading card", 1, true), "it warns, naming the card")
		local hud = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HUD.luau")
		t.ok(string.find(hud, "failsafe: the loading card", 1, true), "the HUD's own card too")
	end)

	-- Every full-screen scrim in the source is hidden or in a disabled
	-- ScreenGui until its card opens (the audit above runs the builders it
	-- can; this catches the rest by reading them).
	t.test("every full-screen dim lives in a disabled screen or starts hidden", function()
		local dir = "src/StarterPlayer/StarterPlayerScripts/"
		local checked = 0
		for _, file in ipairs({ "QuickMenuUI.luau", "ShopUI.luau", "QualityPickerUI.luau" }) do
			local src = fs.readFile(dir .. file)
			local hiddenOrDisabled = string.find(src, "scrim.Visible = false", 1, true)
				or string.find(src, "screen.Enabled = false", 1, true)
				or string.find(src, "g.Enabled = false", 1, true)
			t.ok(hiddenOrDisabled, file .. ": its dim is not on screen at join")
			checked += 1
		end
		t.eq(checked, 3) -- What's new has no dim at all (see above)
	end)
end
