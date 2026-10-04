--!nocheck
-- The Robux store: opening selects Passes, B and Esc close it, TV prices are 18 px.
return function(t)
	local Enum = t.roblox.Enum
	local Instance = t.roblox.Instance
	local gui = {
		SelectedObject = nil,
		IsTenFootInterface = function()
			return false
		end,
	}
	local loader = t.loader({
		services = {
			GuiService = gui,
			Players = { LocalPlayer = {} },
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

	t.test("opening selects the first tab, and B or Esc closes the store", function()
		local tab = Instance.new("TextButton")
		tab.Name = "Passes"
		StoreUI._open(tab)
		t.eq(gui.SelectedObject, tab)
		t.eq(StoreUI.ApplyKey(Enum.KeyCode.ButtonB), "close")
		t.eq(gui.SelectedObject, nil)
		StoreUI._open(tab)
		t.eq(StoreUI.ApplyKey(Enum.KeyCode.Escape), "close")
		t.eq(gui.SelectedObject, nil)
		t.eq(StoreUI.PriceTextPx(false), 14)
		t.eq(StoreUI.PriceTextPx(true), 18)
	end)
end
