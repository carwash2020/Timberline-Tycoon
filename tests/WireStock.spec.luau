--!nocheck
-- WireStock (T420, server): wire is a single-use item. The server sells it by
-- the amount (the Wire remote's "buy"), takes the wire a link uses out of your
-- box, refuses a link you have too little wire for or that is longer than the
-- longest wire, and checks every request again (rate, owner, range, whole
-- numbers). Cash only moves through the wallet the game binds (EconomyService).
return function(t)
	local Vector3, CFrame = t.roblox.Vector3, t.roblox.CFrame
	local Instance = t.roblox.Instance

	local function setup(options)
		options = options or {}
		local allowed = options.rate ~= false
		local loader = t.loader({
			globals = {
				workspace = {
					GetPartBoundsInBox = function()
						return {}
					end,
				},
				OverlapParams = {
					new = function()
						return {}
					end,
				},
			},
			mocks = {
				RateLimiter = {
					Allow = function(_, key)
						table.insert(options.keys or {}, key)
						return allowed
					end,
				},
			},
		})
		local LogicService = loader:server("LogicService")
		local PlotData = loader:shared("PlotData")
		local BlueprintModels = loader:shared("BlueprintModels")
		local WireSupply = loader:shared("WireSupply")

		local toasts = {}
		local function newPlayer(userId)
			local root = { Position = Vector3.new(100, 3, 100) }
			return {
				UserId = userId,
				Character = {
					FindFirstChild = function(_, name)
						return if name == "HumanoidRootPart" then root else nil
					end,
				},
				root = root,
			}
		end
		local owner, visitor = newPlayer(1), newPlayer(2)
		local profile = {
			plot = { placed = {}, wires = {} },
			permissions = {},
			wireUnits = options.units or 0,
			cash = options.cash or 0,
		}
		local items = Instance.new("Folder")
		local host = { cframe = CFrame.new(100, 0, 100), items = items }
		LogicService.Bind(function(player)
			if player == owner or options.visitorBuilds == true then
				return host, profile, owner, false
			end
			return nil, nil, nil, true
		end, function(player, text)
			table.insert(toasts, { player = player, text = text })
		end)
		local spent, published = {}, {}
		LogicService.BindWallet({
			spend = function(player, amount, reason, sku)
				table.insert(spent, { player = player, amount = amount, reason = reason, sku = sku })
				if profile.cash < amount then
					return false
				end
				profile.cash -= amount
				return true
			end,
			publish = function(player, units)
				table.insert(published, { player = player, units = units })
			end,
		})
		local function add(uid, blueprintId, x, z)
			local item = { uid = uid, blueprintId = blueprintId, x = x, z = z, rot = 0 }
			table.insert(profile.plot.placed, item)
			local model = BlueprintModels.Build(PlotData.Blueprint(blueprintId), false)
			model.Name = uid
			model:PivotTo(host.cframe * CFrame.new(x, 0, z))
			model:SetAttribute("Open", false)
			model.Parent = items
			local ctx = {
				slot = host,
				model = model,
				item = item,
				ownerOf = function()
					return owner, profile
				end,
			}
			LogicService.Attach(ctx)
			return model, ctx
		end
		return {
			Service = LogicService,
			WireSupply = WireSupply,
			owner = owner,
			visitor = visitor,
			profile = profile,
			toasts = toasts,
			spent = spent,
			published = published,
			add = add,
		}
	end

	t.test("a link takes its length in wire out of your box and tells the client the new count", function()
		local s = setup({ units = 20 })
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 6, 0)
		t.eq({ s.Service.Link(s.owner, "sw", "lamp") }, { true, nil })
		t.eq(s.profile.wireUnits, 14, "6 studs, 6 units")
		t.eq(s.published[#s.published].units, 14)
		t.eq(s.profile.plot.wires, { { from = "sw", to = "lamp" } })
	end)

	t.test("a link is refused, and nothing is taken, when the box is short; the toast says by how much", function()
		local s = setup({ units = 4 })
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 6, 0)
		local ok, why = s.Service.Link(s.owner, "sw", "lamp")
		t.eq({ ok, why }, { false, "wire" })
		t.eq(s.profile.wireUnits, 4)
		t.eq(s.profile.plot.wires, {})
		s.Service.OnWire(s.owner, "sw", 1, "lamp", 1)
		t.ok(string.find(s.toasts[#s.toasts].text, "2", 1, true), "needs 2 more: " .. s.toasts[#s.toasts].text)
	end)

	-- Two pieces 30 apart and a player standing between them, so both are in reach.
	local function pair(units, options)
		local s = setup(options or { units = units })
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 30, 0)
		s.owner.root.Position = Vector3.new(115, 3, 100)
		return s
	end
	local function via(...)
		local out = {}
		for _, p in ipairs({ ... }) do
			table.insert(out, { x = p[1], z = p[2] })
		end
		return out
	end

	t.test("a run of exactly 64 studs along its bends passes and uses exactly 64 units", function()
		local s = pair(100)
		t.eq({ s.Service.Link(s.owner, "sw", "lamp", 1, 1, via({ 0, 17 }, { 30, 17 })) }, { true })
		t.eq(s.profile.wireUnits, 36)
		t.eq(s.profile.plot.wires[1].via, via({ 0, 17 }, { 30, 17 }), "the corners are kept")
	end)

	t.test("64.01 studs along the path fails whatever is in the box, and nothing is used", function()
		local s = pair(300)
		t.eq({ s.Service.Link(s.owner, "sw", "lamp", 1, 1, via({ 0, 17.005 }, { 30, 17.005 })) }, { false, "span" })
		t.eq(s.profile.wireUnits, 300)
		t.eq(s.profile.plot.wires, {})
	end)

	t.test("four bends pass; a fifth is refused with nothing used", function()
		local s = pair(100)
		local four = via({ 5, 3 }, { 10, -3 }, { 15, 3 }, { 20, -3 })
		t.eq({ s.Service.Link(s.owner, "sw", "lamp", 1, 1, four) }, { true })
		local used = 100 - s.profile.wireUnits
		t.ok(used > 30 and used <= 64, "used " .. used)
		local s2 = pair(100)
		local five = via({ 5, 3 }, { 10, -3 }, { 15, 3 }, { 20, -3 }, { 25, 3 })
		t.eq({ s2.Service.Link(s2.owner, "sw", "lamp", 1, 1, five) }, { false, "bends" })
		t.eq(s2.profile.wireUnits, 100)
		t.eq(s2.profile.plot.wires, {})
	end)

	t.test("two pieces nearer than 64 apart are refused when their bends make the run longer", function()
		local s = pair(300)
		t.eq(({ s.Service.Link(s.owner, "sw", "lamp", 1, 1, via({ 0, 40 }, { 30, 40 })) })[2], "span")
		t.eq(s.profile.wireUnits, 300)
	end)

	t.test("pieces more than 64 studs apart in a straight line are refused", function()
		local s = setup({ units = 300 })
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 64.01, 0)
		s.owner.root.Position = Vector3.new(116, 3, 100)
		t.eq(({ s.Service.Link(s.owner, "sw", "lamp") })[2], "reach", "out of reach of one end")
		s.owner.root.Position = Vector3.new(100 + 32, 3, 100)
		t.eq(({ s.Service.Link(s.owner, "sw", "lamp") })[2], "reach")
		t.eq(s.profile.wireUnits, 300)
	end)

	t.test(
		"the length is the server's: a number from the client in the corners slot is refused, not believed",
		function()
			local s = pair(100)
			for _, bad in ipairs({ 1, "5", true, { { x = "1", z = 2 } }, { { x = 0 / 0, z = 1 } }, { len = 3 } }) do
				s.Service.OnWire(s.owner, "sw", 1, "lamp", 1, bad)
			end
			t.eq(s.profile.plot.wires, {})
			t.eq(s.profile.wireUnits, 100)
			-- A claimed small length cannot lower the charge either: only corners count, the rest is the pieces' places.
			s.Service.OnWire(s.owner, "sw", 1, "lamp", 1, via({ 0, 10 }, { 30, 10 }))
			t.eq(s.profile.wireUnits, 100 - 50)
		end
	)

	t.test("a link the rules refuse (a repeat, the wrong ports) uses no wire", function()
		local s = setup({ units = 50 })
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 6, 0)
		s.Service.Link(s.owner, "sw", "lamp")
		local before = s.profile.wireUnits
		t.eq(({ s.Service.Link(s.owner, "sw", "lamp") })[2], "dup")
		t.eq(({ s.Service.Link(s.owner, "lamp", "sw") })[2], "from")
		t.eq(s.profile.wireUnits, before)
	end)

	t.test("cutting wires gives nothing back: wire is single use", function()
		local s = setup({ units = 20 })
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 6, 0)
		s.Service.Link(s.owner, "sw", "lamp")
		s.Service.Cut(s.owner, "sw")
		t.eq(s.profile.wireUnits, 14)
	end)

	t.test("the switch's Wire prompt uses wire as well, and says so when the box is empty", function()
		local s = setup({ units = 0 })
		local _, ctx = s.add("sw", "SparkSwitch", 0, 0)
		s.add("near", "SparkLamp", 4, 0)
		s.Service.WireNearest(ctx, s.owner)
		t.eq(s.profile.plot.wires, {})
		t.ok(string.find(s.toasts[#s.toasts].text, "wire", 1, true), s.toasts[#s.toasts].text)
		s.profile.wireUnits = 10
		s.Service.WireNearest(ctx, s.owner)
		t.eq(#s.profile.plot.wires, 1)
		t.eq(s.profile.wireUnits, 6)
	end)

	t.test("buying: a pack at the catalog price, from your cash, into your box", function()
		local s = setup({ units = 3, cash = 500 })
		local price = s.WireSupply.UnitPrice()
		s.Service.OnWire(s.owner, "buy", 64)
		t.eq(s.profile.wireUnits, 67)
		t.eq(s.profile.cash, 500 - 64 * price)
		t.eq(#s.spent, 1)
		t.eq(s.spent[1].amount, 64 * price)
		t.eq(s.published[#s.published].units, 67)
	end)

	t.test("every pack is sold: 32, 64 and 160", function()
		for _, pack in ipairs({ 32, 64, 160 }) do
			local s = setup({ units = 0, cash = 1e6 })
			s.Service.OnWire(s.owner, "buy", pack)
			t.eq(s.profile.wireUnits, pack)
		end
	end)

	t.test("any other amount is refused, with no cash moved", function()
		local s = setup({ units = 3, cash = 1e9 })
		for _, bad in ipairs({ 0, -1, -32, 1, 10, 31, 33, 63, 100, 161, 2.5, 32.5, 0 / 0, math.huge, "32", {}, true }) do
			s.Service.OnWire(s.owner, "buy", bad)
		end
		s.Service.OnWire(s.owner, "buy")
		s.Service.OnWire(s.owner, "buy", 32, "extra")
		t.eq(s.profile.wireUnits, 3)
		t.eq(#s.spent, 0, "no cash moved")
		t.eq(s.profile.cash, 1e9)
	end)

	t.test("too little cash buys nothing", function()
		local s = setup({ units = 3, cash = 500 })
		s.profile.cash = s.WireSupply.UnitPrice() * 32 - 1
		s.Service.OnWire(s.owner, "buy", 32)
		t.eq(s.profile.wireUnits, 3)
		t.ok(#s.toasts > 0, "told why")
	end)

	t.test(
		"a spend that fails after the check changes nothing: no wire added, no unit used, nothing published",
		function()
			local s = setup({ units = 3, cash = 1e6 })
			local before = #s.published
			s.Service.BindWallet({
				spend = function()
					return false -- the wallet refused after our own check passed
				end,
				publish = function(player, units)
					table.insert(s.published, { player = player, units = units })
				end,
			})
			s.Service.OnWire(s.owner, "buy", 32)
			t.eq(s.profile.wireUnits, 3)
			t.eq(#s.published, before)
			t.eq(s.profile.cash, 1e6)
		end
	)

	t.test("a box holds at most 320: a pack that would pass it is refused", function()
		local s = setup({ units = 0, cash = 1e9 })
		s.profile.wireUnits = s.WireSupply.MaxStock - 31
		s.Service.OnWire(s.owner, "buy", 32)
		t.eq(s.profile.wireUnits, s.WireSupply.MaxStock - 31)
		t.eq(#s.spent, 0)
		s.profile.wireUnits = s.WireSupply.MaxStock - 32
		s.Service.OnWire(s.owner, "buy", 32)
		t.eq(s.profile.wireUnits, 320)
	end)

	t.test("only the plot's owner buys; a visitor with build rights uses the owner's wire but cannot buy", function()
		local s = setup({ units = 10, cash = 500, visitorBuilds = true })
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 6, 0)
		s.Service.OnWire(s.visitor, "buy", 32)
		t.eq(s.profile.wireUnits, 10, "the visitor's buy did nothing")
		t.eq(#s.spent, 0)
	end)

	t.test("every request is rate limited under the Wire budget, buying included", function()
		local keys = {}
		local s = setup({ units = 0, cash = 500, rate = false, keys = keys })
		s.Service.OnWire(s.owner, "buy", 32)
		t.eq(s.profile.wireUnits, 0)
		t.eq(keys, { "Wire" })
		t.eq(#s.spent, 0)
	end)

	t.test("with no wallet bound a buy does nothing (and does not error)", function()
		local s = setup({ units = 0, cash = 500 })
		s.Service.BindWallet(nil)
		s.Service.OnWire(s.owner, "buy", 32)
		t.eq(s.profile.wireUnits, 0)
	end)
end
