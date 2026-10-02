--!nocheck
-- SellService (V2_PLAN.md §5): wood resting on the pad sells by volume,
-- pays its owner (or last holder), once, with one toast per payee.

return function(t)
	local roblox = t.roblox
	local Instance, Vector3 = roblox.Instance, roblox.Vector3
	local WoodData = t.shared("WoodData")

	-- `options.room`: the wallet's room (addCash credits at most this).
	local function setup(options)
		options = options or {}
		local s = { clock = 0, paid = {}, toasts = {}, released = {}, forgotten = {}, sold = {}, inZone = {} }
		local loader =
			t.loader({ services = { Players = {
				GetPlayerByUserId = function()
					return nil
				end,
			} } })
		local SellService = loader:server("SellService")
		s.SellService = SellService
		s.players = {}
		local function player(id)
			local p = s.players[id]
			if not p then
				p = { UserId = id, Name = "P" .. id }
				s.players[id] = p
			end
			return p
		end
		s.player = player
		s.online = { [1] = true, [2] = true }
		s.records = {}
		local folder = Instance.new("Folder")
		s.folder = folder
		local zone = Instance.new("Part")
		s.zone = zone
		function s.piece(id, owner, woodId, volume, extra)
			local m = Instance.new("Model")
			m.Name = "Wood_" .. id
			m:AddTag("Wood")
			local part = Instance.new("Part")
			part.Parent = m
			m.PrimaryPart = part
			m:SetAttribute("WoodId", woodId)
			m:SetAttribute("Volume", volume)
			for k, v in pairs(extra or {}) do
				m:SetAttribute(k, v)
			end
			m.Parent = folder
			s.records[m] = { model = m, ownerId = owner, lastHolderId = extra and extra.holder or nil }
			return m, part
		end
		SellService._use({
			zone = zone,
			woodFolder = folder,
			resolve = function(model)
				return s.records[model]
			end,
			addCash = function(p, amount, reason, sku)
				table.insert(s.paid, { id = p.UserId, amount = amount, reason = reason, sku = sku })
				return if options.room then math.min(amount, options.room) else nil
			end,
			saleMultiplier = function(p)
				return if p.UserId == 2 then 2 else 1
			end,
			notify = function(p, text)
				table.insert(s.toasts, { id = p.UserId, text = text })
			end,
			release = function(model)
				table.insert(s.released, model)
			end,
			forget = function(model)
				table.insert(s.forgotten, model)
			end,
			onSold = function(sale)
				table.insert(s.sold, sale)
				if options.failFor == sale.payee.UserId then
					error("a broken listener")
				end
			end,
			partsInZone = function()
				return s.inZone
			end,
			now = function()
				return s.clock
			end,
			player = function(id)
				return if s.online[id] then player(id) else nil
			end,
		})
		function s.tick(dt)
			s.clock += dt or 0
			return SellService.Tick()
		end
		return s
	end

	t.test("wood sells after resting a moment on the pad, paying its owner by volume", function()
		local s = setup()
		local _, part = s.piece("a", 1, "oak", 10)
		s.inZone = { part }
		t.eq(#s.tick(0), 0) -- just arrived
		t.eq(#s.tick(0.1), 0)
		local sales = s.tick(0.3)
		t.eq(#sales, 1)
		local oak = WoodData.Get("oak").v2
		t.eq(s.paid[1].id, 1)
		t.eq(s.paid[1].amount, math.floor(10 * oak.logPrice + 0.5))
		t.eq(s.paid[1].sku, "wood")
		t.eq(s.toasts[1].text, string.format("Sold 1 piece · 10 u³ · $%d", s.paid[1].amount))
		t.eq(#s.released, 1)
		t.eq(#s.forgotten, 1)
		t.eq(s.sold[1].woods.oak, 10)
	end)

	t.test("a piece that leaves the zone starts its wait again", function()
		local s = setup()
		local _, part = s.piece("a", 1, "oak", 4)
		s.inZone = { part }
		s.tick(0)
		s.tick(0.2)
		s.inZone = {}
		s.tick(0.1)
		s.inZone = { part }
		t.eq(#s.tick(0.1), 0, "back in: waits again")
		t.eq(#s.tick(0.35), 1)
	end)

	t.test("it pays the owner, not the pusher; an owner who left pays the last holder; else nobody", function()
		local s = setup()
		local _, a = s.piece("a", 1, "oak", 4, { holder = 2 })
		local _, b = s.piece("b", 9, "oak", 4, { holder = 2 }) -- owner 9 left
		local _, c = s.piece("c", 9, "oak", 4, { holder = 8 }) -- nobody online
		s.inZone = { a, b, c }
		s.tick(0)
		s.tick(0.5)
		local ids = {}
		for _, p in ipairs(s.paid) do
			ids[p.id] = (ids[p.id] or 0) + p.amount
		end
		t.ok(ids[1] ~= nil, "owner 1 paid")
		t.ok(ids[2] ~= nil, "last holder paid for the left owner's piece")
		t.eq(ids[8], nil)
		t.eq(ids[9], nil)
		t.eq(#s.forgotten, 3, "all three are gone")
	end)

	t.test("one payment and one toast per payee per tick; 2x Cash once on the total", function()
		local s = setup()
		local _, a = s.piece("a", 2, "pine", 3)
		local _, b = s.piece("b", 2, "pine", 4)
		s.inZone = { a, b, a } -- a part listed twice counts once
		s.tick(0)
		s.tick(0.4)
		t.eq(#s.paid, 1)
		t.eq(#s.toasts, 1)
		local pine = WoodData.Get("pine").v2
		t.eq(s.paid[1].amount, math.floor(7 * pine.logPrice * 2 + 0.5))
		t.ok(string.find(s.toasts[1].text, "Sold 2 pieces · 7 u³", 1, true) ~= nil, s.toasts[1].text)
	end)

	t.test("planks pay the plank price; figures and 2x Wood count", function()
		local s = setup()
		local _, a = s.piece("a", 1, "maple", 2, { Kind = "plank", Figure = "curly", Boost = 2 })
		s.inZone = { a }
		s.tick(0)
		s.tick(0.4)
		local SellLogic = t.shared("SellLogic")
		t.eq(s.paid[1].amount, SellLogic.Payout(SellLogic.PieceValue("maple", "plank", 2, "curly", 2), 1))
		t.eq(s.sold[1].figures[1], "curly")
	end)

	t.test("never twice: a piece already selling, unknown, dead or a shop item is left alone", function()
		local s = setup()
		local ma, a = s.piece("a", 1, "oak", 4)
		local mb, b = s.piece("b", 1, "oak", 4)
		local mc, c = s.piece("c", 1, "oak", 4)
		local _, d = s.piece("d", 1, "oak", 4)
		s.records[ma].selling = true
		s.records[mb] = nil
		s.records[mc].shopItem = true
		s.inZone = { a, b, c, d }
		s.tick(0)
		local sales = s.tick(0.5)
		t.eq(#sales, 1)
		t.eq(sales[1].pieces, 1)
		-- And the sold one doesn't sell again.
		s.tick(0.5)
		t.eq(#s.paid, 1)
	end)

	t.test("wood without a known wood or volume doesn't sell", function()
		local s = setup()
		local _, a = s.piece("a", 1, "nonsense", 4)
		local _, b = s.piece("b", 1, "oak", 0)
		s.inZone = { a, b }
		s.tick(0)
		s.tick(0.5)
		t.eq(#s.paid, 0)
	end)

	-- M1.8b: the onSold hook gets what the quests and dailies count.
	t.test("the sale carries what reached the wallet, each piece's u³ and the figured u³", function()
		local s = setup({ room = 5 })
		local _, a = s.piece("a", 1, "pine", 3)
		local _, b = s.piece("b", 1, "pine", 4, { Figure = "curly" })
		s.inZone = { a, b }
		s.tick(0)
		local sales = s.tick(0.4)
		t.eq(#sales, 1)
		local sale = sales[1]
		t.ok(sale.paid > 5, "worth more than the wallet's room")
		t.eq(sale.credited, 5, "the cap took the rest")
		t.ok(string.find(s.toasts[1].text, "· $5", 1, true) ~= nil, "the toast says what was credited")
		t.eq(s.sold[1], sale, "the hook gets the same sale")
		table.sort(sale.pieceVolumes)
		t.eq(sale.pieceVolumes, { 3, 4 })
		t.eq(sale.figured, 4)
		t.eq(sale.pieces, 2)
		-- With room for it all (addCash says nothing back): all of it.
		local plain = setup()
		local _, c = plain.piece("c", 1, "oak", 10)
		plain.inZone = { c }
		plain.tick(0)
		local paid = plain.tick(0.4)[1]
		t.eq(paid.credited, paid.paid)
		t.eq(paid.figured, 0)
		t.eq(paid.pieceVolumes, { 10 })
	end)

	-- M1.7b: the Sky Bin's sale pays its entries as the pad pays pieces.
	t.test("PayEntries pays figure x boost x plank price, 2x Cash once, with the pad's toast and hook", function()
		local s = setup()
		local SellLogic = t.shared("SellLogic")
		local entries = {
			SellLogic.Entry("maple", "plank", 2, "curly", 2),
			SellLogic.Entry("lumenwood", "log", 12, nil, 1),
			{ w = "oak", v = 0 / 0 }, -- a broken entry counts for nothing
		}
		local p2 = s.player(2) -- 2x Cash
		local sale = s.SellService.PayEntries(p2, entries)
		local maple = WoodData.Get("maple").v2
		local lumen = WoodData.Get("lumenwood").v2
		local ForestLogic = t.shared("ForestLogic")
		local value = 2 * maple.plankPrice * ForestLogic.Multiplier("curly") * 2 + 12 * lumen.logPrice
		t.eq(#s.paid, 1, "one AddCash")
		t.eq(s.paid[1].id, 2)
		t.eq(s.paid[1].amount, math.floor(value * 2 + 0.5))
		t.eq(s.paid[1].sku, "wood")
		t.eq(sale.pieces, 2)
		t.eq(sale.volume, 14)
		t.eq(sale.credited, sale.paid)
		t.eq(sale.figures, { "curly" })
		t.eq(sale.figured, 2)
		t.eq(sale.woods, { maple = 2, lumenwood = 12 })
		t.eq(sale.pieceVolumes, { 2, 12 })
		t.eq(s.toasts[1].text, SellLogic.SaleText(2, 14, sale.paid))
		t.eq(s.sold, { sale }, "the tutorial, dailies and reveals hear of it")
		t.eq(#s.released + #s.forgotten, 0, "no pieces in the world were touched")
	end)

	t.test("PayEntries: the wallet's room, nothing to pay, and before Init", function()
		local s = setup({ room = 5 })
		local SellLogic = t.shared("SellLogic")
		local sale = s.SellService.PayEntries(s.player(1), { SellLogic.Entry("lumenwood", "log", 10, nil, 1) })
		t.eq(sale.credited, 5, "the cap took the rest")
		t.ok(string.find(s.toasts[1].text, "· $5", 1, true) ~= nil, s.toasts[1].text)
		local none = s.SellService.PayEntries(s.player(1), { { w = "oak", v = -1 } })
		t.eq(none.pieces, 0)
		t.eq(#s.paid, 1, "nothing paid")
		t.eq(#s.toasts, 1, "nothing said")
		t.eq(#s.sold, 1, "nothing heard")
		s.SellService._reset()
		t.eq(s.SellService.PayEntries(s.player(1), { SellLogic.Entry("oak", "log", 4) }), nil, "not running")
	end)

	t.test("a listener that errors for one payee doesn't stop the next one's pay", function()
		local s = setup({ failFor = 1 })
		local _, a = s.piece("a", 1, "oak", 4)
		local _, b = s.piece("b", 2, "oak", 4)
		s.inZone = { a, b }
		s.tick(0)
		local sales = s.tick(0.4)
		t.eq(#sales, 2)
		t.eq(#s.paid, 2, "both paid")
		t.eq(#s.sold, 2, "both heard")
	end)
end
