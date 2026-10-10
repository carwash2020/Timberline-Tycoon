--!nocheck
-- The store panel (Lane P): fits a 667x375 phone and a 1080p screen with
-- at least two whole cards showing, every tap target 44 px, and its
-- colours come from UITheme only.
return function(t)
	local fs = require("@lune/fs")
	local Vector2 = t.roblox.Vector2
	local Instance = t.roblox.Instance
	local loader = t.loader({
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
		t.eq(StoreUI.CardFacts("Pass", StoreData.Pass("DoubleCash")).state, "Soon", "no answer yet: never Buy")
		local pack = StoreUI.CardFacts("Product", StoreData.Product("Cash10k"))
		t.ok(string.find(pack.extra, "229,600", 1, true) ~= nil, "S6 large pack: " .. tostring(pack.extra))
	end)
end
