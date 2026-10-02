--!nocheck
-- SellService (V2_PLAN.md §5): wood resting on the pad sells by volume,
-- pays its owner (or last holder), once, with one toast per payee.

return function(t)
	local roblox = t.roblox
	local Instance, Vector3 = roblox.Instance, roblox.Vector3
	local WoodData = t.shared("WoodData")

	local function setup()
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
end
