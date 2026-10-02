--!nocheck
-- SellService (V2_PLAN.md §5): wood resting on the pad sells by volume,
-- pays its owner (or last holder), once, with one toast per payee.

return function(t)
	local roblox = t.roblox
	local Instance, Vector3 = roblox.Instance, roblox.Vector3
	local WoodData = t.shared("WoodData")

	local function setup()
		local s = {
			clock = 0,
			paid = {},
			toasts = {},
			released = {},
			forgotten = {},
			sold = {},
			inZone = {},
			bed = {}, -- [UserId] = the models on their truck beds (TruckLoad.PiecesOn)
			room = 1e9, -- $ left under the wallet cap
		}
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
			bedPieces = function(p)
				return s.bed[p.UserId] or {}
			end,
			walletRoom = function()
				return s.room
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

	-- M1.6: wood riding on a truck (TruckLoad) on the pad, and Instant
	-- Delivery v2.
	t.test("the pad's query looks only in the Wood folder: a truck on the pad never sells", function()
		local made = {}
		local loader = t.loader({
			services = { Players = {
				GetPlayerByUserId = function()
					return nil
				end,
			} },
			globals = {
				OverlapParams = {
					new = function()
						local params = {}
						table.insert(made, params)
						return params
					end,
				},
				workspace = {
					GetPartBoundsInBox = function(_, cf, size, params)
						made.asked = { cf = cf, size = size, params = params }
						return {}
					end,
				},
			},
		})
		local SellService = loader:server("SellService")
		local folder = Instance.new("Folder")
		local zone = Instance.new("Part")
		zone.Size = Vector3.new(24, 12, 26)
		SellService._use({
			zone = zone,
			woodFolder = folder,
			resolve = function()
				return nil
			end,
			addCash = function() end,
			saleMultiplier = function()
				return 1
			end,
			notify = function() end,
			release = function() end,
			forget = function() end,
		})
		SellService.Tick()
		local params = made.asked.params
		t.eq(params.FilterType, roblox.Enum.RaycastFilterType.Include)
		t.eq(params.FilterDescendantsInstances, { folder }, "the Wood folder only")
		t.eq(made.asked.size, zone.Size)
	end)

	t.test("wood resting on a truck's bed in the zone sells; the truck's own parts never do", function()
		local s = setup()
		-- A truck backed onto the pad: its bed, BedZone and walls are in the
		-- zone too, but they aren't wood (no Wood tag, no record).
		local truck = Instance.new("Model")
		truck:AddTag("Truck")
		local bed = Instance.new("Part")
		bed.Name = "BedFloor"
		bed.Parent = truck
		local bedZone = Instance.new("Part")
		bedZone.Name = "BedZone"
		bedZone.Parent = bed
		local mine, a = s.piece("a", 1, "oak", 6)
		-- The log is welded to the bed (BedAutoWeld): selling it still works.
		local weld = Instance.new("WeldConstraint")
		weld.Name = "BedWeld"
		weld.Parent = a
		s.inZone = { bed, bedZone, a }
		s.tick(0)
		local sales = s.tick(0.4)
		t.eq(#sales, 1)
		t.eq(sales[1].pieces, 1)
		t.eq(mine.Parent, nil, "the log is gone, its weld with it")
		t.ok(truck:FindFirstChild("BedFloor") == bed and bed.Parent == truck, "the truck is untouched")
	end)

	t.test("SellBed: Instant Delivery sells the wood on your beds from anywhere", function()
		local s = setup()
		local SellService = s.SellService
		local ma = s.piece("a", 1, "oak", 10)
		local mb = s.piece("b", 0, "pine", 5, { holder = 1 }) -- unowned, last held by you: yours
		local mc = s.piece("c", 2, "birch", 4) -- a friend's: it pays them
		local md = s.piece("d", 9, "oak", 3, { holder = 8 }) -- nobody online to pay: it stays
		s.bed[1] = { ma, mb, mc, md }
		local spent = 0
		local sales, why = SellService.SellBed(s.player(1), function()
			spent += 1
			return true
		end)
		t.eq(why, nil)
		t.eq(spent, 1, "one use")
		t.eq(#sales, 2, "you and your friend")
		local oak, pine = WoodData.Get("oak").v2, WoodData.Get("pine").v2
		t.eq(s.paid[1].id, 1)
		t.eq(s.paid[1].amount, math.floor(10 * oak.logPrice + 5 * pine.logPrice + 0.5))
		t.eq(s.paid[2].id, 2)
		t.eq(s.paid[2].amount, math.floor(4 * WoodData.Get("birch").v2.logPrice * 2 + 0.5), "their 2x Cash")
		t.eq(ma.Parent, nil)
		t.eq(mc.Parent, nil)
		t.ok(md.Parent ~= nil, "no payee online: left on the bed")
		t.eq(#s.released, 3)
		t.eq(#s.forgotten, 3)
		t.ok(string.find(s.toasts[1].text, "Sold 2 pieces", 1, true) ~= nil, s.toasts[1].text)
	end)

	t.test("SellBed checks the wallet first (as the v1 bed did), then spends a use", function()
		local s = setup()
		local SellService = s.SellService
		local ma = s.piece("a", 1, "oak", 10)
		s.bed[1] = { ma }
		local worth = math.floor(10 * WoodData.Get("oak").v2.logPrice + 0.5)
		local spent = 0
		local function spend()
			spent += 1
			return true
		end
		s.room = worth - 1
		local sales, why = SellService.SellBed(s.player(1), spend)
		t.eq(#sales, 0)
		t.eq(why, "wallet")
		t.eq(spent, 0, "no use spent")
		t.eq(s.toasts[1].text, SellService.WalletText(worth, worth - 1))
		t.ok(string.find(s.toasts[1].text, "your wallet only has room for", 1, true) ~= nil)
		s.room = 0
		SellService.SellBed(s.player(1), spend)
		t.ok(string.find(s.toasts[2].text, "Your wallet is full ($2,000,000)", 1, true) ~= nil, s.toasts[2].text)
		t.ok(ma.Parent ~= nil, "nothing sold")
		-- Room enough, but no uses left.
		s.room = 1e9
		local _, why2 = SellService.SellBed(s.player(1), function()
			return false
		end)
		t.eq(why2, "spent")
		t.eq(s.toasts[3].text, SellService.NoDeliveriesText)
		t.ok(ma.Parent ~= nil)
		-- An empty bed: nothing spent.
		s.bed[1] = {}
		local _, why3 = SellService.SellBed(s.player(1), spend)
		t.eq(why3, "empty")
		t.eq(spent, 0)
		t.eq(s.toasts[4].text, SellService.BedEmptyText)
		-- Then it goes.
		s.bed[1] = { ma }
		local sales4 = SellService.SellBed(s.player(1), spend)
		t.eq(#sales4, 1)
		t.eq(spent, 1)
	end)

	t.test("a piece already selling on the pad isn't sold again by SellBed", function()
		local s = setup()
		local ma, a = s.piece("a", 1, "oak", 10)
		s.inZone = { a }
		s.tick(0)
		s.tick(0.4)
		t.eq(#s.paid, 1)
		s.bed[1] = { ma }
		local _, why = s.SellService.SellBed(s.player(1))
		t.eq(why, "empty")
		t.eq(#s.paid, 1)
	end)
end
