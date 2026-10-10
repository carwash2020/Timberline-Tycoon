--!nocheck
-- StoreSale: one card-state rule for the store, the board and the shelf, and
-- the paid boosts that are never clamped (Connor, 8 Oct 2:04 PM).
return function(t)
	local StoreSale = t.shared("Store/StoreSale")
	local SellLogic = t.shared("SellLogic")
	local GameConfig = t.shared("GameConfig")

	t.test("Owned beats everything; no answer is never Buy", function()
		local item = { id = 5, offSale = "soon" }
		t.eq(StoreSale.CardState(item, { owned = true, robloxForSale = false }), "Owned")
		t.eq(StoreSale.CardState({ id = 0, offSale = "hidden" }, { owned = true }), "Owned", "owned even at id 0")
		t.eq(StoreSale.CardState(item, { robloxForSale = true }), "Buy")
		t.eq(StoreSale.CardState(item, { robloxForSale = nil }), "Soon", "lookup not back yet")
		t.eq(StoreSale.CardState(item, { robloxForSale = false }), "Soon")
		t.eq(StoreSale.CardState({ id = 5, offSale = "hidden" }, { robloxForSale = false }), "Hidden")
		t.eq(StoreSale.CardState({ id = 0, offSale = "soon" }, { robloxForSale = true }), "Soon", "id 0 never sells")
	end)

	t.test("a cash pack that would pass the cap is Wallet full", function()
		local pack = { id = 9, offSale = "soon" }
		t.eq(StoreSale.CardState(pack, { robloxForSale = true, cash = 0, cap = 100, packCash = 100 }), "Buy")
		t.eq(StoreSale.CardState(pack, { robloxForSale = true, cash = 1, cap = 100, packCash = 100 }), "WalletFull")
	end)

	t.test("Roblox's answer: IsForSale, or a bare price counts as on sale", function()
		t.eq(StoreSale.ReadInfo({ IsForSale = true }), true)
		t.eq(StoreSale.ReadInfo({ IsForSale = false, PriceInRobux = 99 }), false)
		t.eq(StoreSale.ReadInfo({ PriceInRobux = 99 }), true)
		t.eq(StoreSale.ReadInfo({}), nil)
		t.eq(StoreSale.ReadInfo(nil), nil)
		t.eq(StoreSale.ReadPrice({ PriceInRobux = 99.7 }), 99)
		t.eq(StoreSale.ReadPrice({ PriceInRobux = -1 }), nil)
		t.eq(StoreSale.AttrName("Pass", "DoubleCash"), "StoreOnSale_Pass_DoubleCash")
	end)

	t.test("the prompt gate and the world gate", function()
		t.eq(StoreSale.MayPrompt(5, true), true)
		t.eq(StoreSale.MayPrompt(5, nil), false)
		t.eq(StoreSale.MayPrompt(0, true), false)
		t.eq(StoreSale.ShowInWorld(5, nil), true, "not answered yet: shown; the purchase is still gated")
		t.eq(StoreSale.ShowInWorld(5, false), false)
		t.eq(StoreSale.ShowInWorld(0, true), false)
	end)

	t.test("2x Cash x 2x Wood x Lux pays the full product; BonusCap clamps only free bonuses", function()
		local free = SellLogic.PieceValue("pine", "plank", 1, nil, 1, false, 2, 2, 1.10)
		local base = SellLogic.PieceValue("pine", "plank", 1, nil, 1, false, 1, 1, 1)
		t.ok(math.abs(free / base - SellLogic.BonusCap) < 1e-9, "free stack clamps to 3.0")
		local paid = SellLogic.PieceValue("pine", "plank", 1, nil, 2, true, 2, 2, 1.10)
		t.ok(math.abs(paid / base - 3 * 2 * GameConfig.LuxSellBonus) < 1e-9, "2x Wood and Lux on top")
		local log = SellLogic.PieceValue("pine", "log", 1, nil, 1, false)
		local all = SellLogic.PieceValue("pine", "log", 1, nil, 2, true) * 2 -- 2x Cash on the sale total
		t.ok(math.abs(all / log - 2 * 2 * GameConfig.LuxSellBonus) < 1e-9, "4.4x, never capped")
	end)
end
