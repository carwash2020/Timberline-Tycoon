--!nocheck
-- The store panel (Lane P): fits a 667x375 phone and a 1080p screen with
-- at least two whole cards showing, every tap target 44 px, and its
-- colours come from UITheme only.
return function(t)
	local fs = require("@lune/fs")
	local Vector2 = t.roblox.Vector2
	local Instance = t.roblox.Instance
	-- UITheme.Button's signals, which @lune/roblox lacks.
	local function signal()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end
	for _, name in ipairs({ "Activated", "InputBegan", "InputEnded", "SelectionLost", "MouseEnter", "MouseLeave" }) do
		pcall(t.roblox.implementProperty, "TextButton", name, signal)
		pcall(t.roblox.implementProperty, "GuiButton", name, signal)
	end
	local loader = t.loader({
		globals = {
			workspace = {
				GetAttribute = function()
					return nil
				end,
				CurrentCamera = { ViewportSize = Vector2.new(1920, 1080) },
			},
		},
		services = {
			GuiService = {
				SelectedObject = nil,
				IsTenFootInterface = function()
					return false
				end,
			},
			Players = {
				LocalPlayer = {
					attrs = { Cash = 0, StoreStage = 6, Pass_LuxAxe = true },
					GetAttribute = function(self, k)
						return self.attrs[k]
					end,
				},
			},
			UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			TextChatService = {},
			MarketplaceService = {},
			CollectionService = {},
		},
		mocks = {
			HUD = {
				SetModal = function() end,
				BesideCash = function()
					return Instance.new("Frame")
				end,
			},
			ShopUI = { SetStoreOpener = function() end },
		},
	})
	local StoreUI = loader:load("StarterPlayer/StarterPlayerScripts/StoreUI")

	t.test("a phone (667x375, UIScale 0.78) shows two columns and whole cards", function()
		local l = StoreUI.Layout(Vector2.new(667, 375), 0.78)
		t.ok(l.columns >= 2, "two or three columns")
		t.ok(l.visibleCards >= 2, "two cards without a scroll: " .. l.visibleCards)
		t.ok(l.panel.X * 0.78 <= 667 - 2 * StoreUI.Margin * 0.78 + 0.5, "inside the screen's width")
		t.ok(l.panel.Y * 0.78 <= 375 + 1e-6, "inside the screen's height")
		t.ok(l.card.X >= 220, "a card is wide enough for its name and pill: " .. l.card.X)
		t.ok(StoreUI.TabsH * 0.78 >= 44 - 1e-6 or StoreUI.TabsH >= 44, "tabs are a full tap")
	end)

	t.test("a 1920x1080 screen (UIScale 1.25) shows three columns, capped in size", function()
		local l = StoreUI.Layout(Vector2.new(1920, 1080), 1.25)
		t.eq(l.columns, 3)
		t.ok(l.visibleCards >= 6, "two full rows: " .. l.visibleCards)
		t.eq(l.panel.X, StoreUI.MaxW)
		t.eq(l.panel.Y, StoreUI.MaxH)
	end)

	t.test("price text is 14 px in hand and 18 on a TV", function()
		t.eq(StoreUI.PriceTextPx(false), 14)
		t.eq(StoreUI.PriceTextPx(true), 18)
	end)

	t.test("no colour is written in StoreUI: every one is a UITheme token", function()
		local code = {}
		for line in string.gmatch(fs.readFile("src/StarterPlayer/StarterPlayerScripts/StoreUI.luau"), "[^\n]+") do
			table.insert(code, (string.gsub(line, "%-%-.*$", "")))
		end
		local source = table.concat(code, "\n")
		t.eq(string.find(source, "Color3.fromRGB", 1, true), nil)
		t.eq(string.find(source, "Color3.fromHex", 1, true), nil)
		t.eq(string.find(source, "Color3.new", 1, true), nil)
		t.eq(string.find(source, "ButtonR2", 1, true), nil, "R2 is the swing")
	end)

	t.test("the card facts: owned beats sale, packs show their scaled cash", function()
		local StoreData = t.shared("StoreData")
		t.eq(StoreUI.CardFacts("Pass", StoreData.Pass("LuxAxe")).state, "Owned")
		t.eq(
			StoreUI.CardFacts("Pass", StoreData.Pass("DoubleCash")).state,
			"Pending",
			"no answer yet: never Buy, never Coming soon"
		)
		local pack = StoreUI.CardFacts("Product", StoreData.Product("Cash10k"))
		t.ok(string.find(pack.extra, "229,600", 1, true) ~= nil, "S6 large pack: " .. tostring(pack.extra))
	end)

	---------------------------------------------------------------------------
	-- T387: the card layout and the price states
	---------------------------------------------------------------------------

	local MULTS = { Small = 0.85, Normal = 1, Large = 1.15 }

	local function meets(a, b)
		return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
	end

	t.test(
		"on every card the price button never meets the amount or the description, at Small, Normal and Large",
		function()
			for name, mult in pairs(MULTS) do
				for _, cardW in ipairs({ 220, 260, 300, 380 }) do
					for _, bw in ipairs({ StoreUI.PillW, StoreUI.PillWFailed }) do
						local r = StoreUI.CardLayout(cardW, mult, bw)
						local label = name .. " " .. cardW .. " " .. bw
						t.ok(not meets(r.button, r.amount), label .. ": button over amount")
						t.ok(not meets(r.button, r.desc), label .. ": button over description")
						t.ok(not meets(r.button, r.title), label .. ": button over title")
						t.ok(not meets(r.button, r.icon), label .. ": button over icon")
						t.ok(not meets(r.status, r.button), label .. ": status under the button")
						t.ok(not meets(r.amount, r.desc), label .. ": amount over description")
						-- The button sits inside the footer, 8 px from the card's right edge, at least 44 x 44.
						t.ok(r.button.w >= 44 and r.button.h >= 44, label .. ": button too small")
						t.eq(cardW - (r.button.x + r.button.w), StoreUI.CardPad, label .. ": 8 px from the right edge")
						t.eq(StoreUI.CardPad, 8)
						t.ok(r.footer.h >= 44, label .. ": footer too short")
						t.ok(r.button.y >= r.footer.y and r.button.y + r.button.h <= r.footer.y + r.footer.h, label)
						t.eq(r.amount.h, 20)
						t.ok(r.status.w >= 0)
						-- Text stays at or over its floor on screen.
						t.ok(r.bodyPx * mult >= 14 - 1e-6, label .. ": body under 14")
						t.ok(r.titlePx * mult >= 20 - 1e-6, label .. ": title under 20")
						t.ok(r.height > r.footer.y + r.footer.h, label)
					end
				end
			end
		end
	)

	local function build(kind, key, state)
		local StoreData = t.shared("StoreData")
		local item = if kind == "Pass" then StoreData.Pass(key) else StoreData.Product(key)
		local parent = Instance.new("Frame")
		local facts = StoreUI.CardFacts(kind, item)
		if state then
			facts.state = state
		end
		local pill = StoreUI._card(parent, kind, item, facts)
		return parent:GetChildren()[1], pill
	end

	t.test(
		"a card is one vertical list: art, title, two-line description, amount, footer, nothing on top of anything",
		function()
			local row, pill = build("Product", "Cash1k", "Buy")
			local stack = row:FindFirstChildOfClass("UIListLayout")
			t.ok(stack ~= nil, "a UIListLayout")
			t.eq(stack.FillDirection, t.roblox.Enum.FillDirection.Vertical)
			t.eq(stack.Padding.Offset, 6)
			local names = {}
			for _, child in ipairs(row:GetChildren()) do
				if child:IsA("GuiObject") then
					names[child.LayoutOrder] = child.Name
					t.eq(child.Position, t.roblox.UDim2.new(), child.Name .. " is placed by the list, not by hand")
				end
			end
			t.eq(names, { "ArtRow", "Title", "Body", "Live", "Footer" })
			local body = row.Body
			t.eq(body.TextWrapped, true)
			t.eq(body.TextTruncate, t.roblox.Enum.TextTruncate.AtEnd)
			local fit = body:FindFirstChildOfClass("UITextSizeConstraint")
			t.ok(fit ~= nil and fit.MinTextSize >= 14, "the description keeps at least 14")
			t.ok(body.Size.Y.Offset <= 2 * math.ceil(body.TextSize * 1.2), "two lines at most")
			t.eq(row.Live.Size.Y.Offset, 20)
			t.ok(string.find(row.Live.Text, "+$", 1, true) ~= nil, "the amount has its own row: " .. row.Live.Text)
			local footer = row.Footer
			t.ok(footer.Size.Y.Offset >= 44)
			local root = footer:FindFirstChild("Pill")
			t.ok(root ~= nil)
			t.eq(root.AnchorPoint, Vector2.new(1, 0.5))
			t.ok(root.Size.X.Offset >= 44 and root.Size.Y.Offset >= 44)
			t.eq(
				root.Position,
				t.roblox.UDim2.fromScale(1, 0.5),
				"right edge of the footer, which sits 8 px inside the card"
			)
			t.eq(row:FindFirstChildOfClass("UIPadding").PaddingRight.Offset, 8)
			-- The selectable is the button face itself, and its focus ring is a Border UIStroke.
			t.eq(pill, root.Face)
			t.ok(pill:IsA("TextButton"))
			local ring = pill.SelectionImageObject
			t.ok(ring ~= nil)
			local stroke = ring:FindFirstChildOfClass("UIStroke")
			t.ok(stroke ~= nil)
			t.eq(stroke.ApplyStrokeMode, t.roblox.Enum.ApplyStrokeMode.Border)
		end
	)

	t.test("the card says R$ while Roblox's price is on its way, then Price unavailable with Buy off", function()
		local StorePrices = loader:load("StarterPlayer/StarterPlayerScripts/StorePrices")
		StorePrices._reset()
		-- Waiting: a real id with no answer yet is a Pending card, "R$", and cannot buy.
		local row, pill = build("Pass", "TowService")
		t.eq(row.Footer.Pill.Face.Text, "R$")
		t.eq(StoreUI.CanBuy("Pending", false), false)
		-- Roblox says it is for sale and the price is here: Buy with the live price.
		StorePrices._set("Pass", "TowService", 99, true)
		local _, ok = build("Pass", "TowService")
		t.ok(ok ~= nil)
		t.eq(StoreUI.CanBuy("Buy", false), true)
		-- Every retry failed: "Price unavailable", and no press sends a prompt.
		StorePrices._reset()
		StorePrices._setFailed("Pass", "TowService")
		local failedRow = build("Pass", "TowService")
		local face = failedRow.Footer.Pill.Face
		t.eq(face.Text, "Price unavailable")
		t.eq(failedRow.Footer.Pill.Size.X.Offset, StoreUI.PillWFailed)
		t.eq(StoreUI.CanBuy("Buy", true), false)
		t.eq(StoreUI.CanBuy("Pending", true), false)
		t.eq(StoreUI.CanBuy("Owned", false), false)
		StorePrices._reset()
	end)

	t.test("no Robux number is written in StoreUI or StoreBoard", function()
		for _, path in ipairs({
			"src/StarterPlayer/StarterPlayerScripts/StoreUI.luau",
			"src/ReplicatedStorage/Shared/StoreBoard.luau",
		}) do
			local code = {}
			for line in string.gmatch(fs.readFile(path), "[^\n]+") do
				table.insert(code, (string.gsub(line, "%-%-.*$", "")))
			end
			local source = table.concat(code, "\n")
			for str in string.gmatch(source, '"([^"\n]*)"') do
				t.eq(string.find(str, "R%$%s*%d"), nil, path .. ": " .. str)
				t.eq(string.find(str, "%d%s*R%$"), nil, path .. ": " .. str)
				t.eq(string.find(str, "%d+%s*[Rr]obux"), nil, path .. ": " .. str)
			end
			t.eq(string.find(source, "PriceInRobux", 1, true), nil, path)
			t.eq(string.find(source, "price%s*=%s*%d"), nil, path .. " writes a price")
			-- The only words on a pill come from StoreCopy / StorePrices.
			t.eq(string.find(source, '"R$"', 1, true), nil, path .. " has the R$ word in StoreCopy only")
			t.eq(string.find(source, '"Price unavailable"', 1, true), nil, path)
		end
	end)
end
