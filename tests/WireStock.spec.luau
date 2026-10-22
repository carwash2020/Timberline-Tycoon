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

	t.test("a wire longer than the longest wire is refused for length whatever is in the box", function()
		local s = setup({ units = 500 })
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", s.WireSupply.MaxLength + 1, 0)
		s.owner.root.Position = Vector3.new(116, 3, 100) -- between the two, in reach of both
		t.eq({ s.Service.Link(s.owner, "sw", "lamp") }, { false, "span" })
		t.eq(s.profile.wireUnits, 500)
	end)

	t.test("a wire exactly the longest uses exactly that much", function()
		local s = setup({ units = 100 })
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", s.WireSupply.MaxLength, 0)
		s.owner.root.Position = Vector3.new(116, 3, 100)
		t.eq({ s.Service.Link(s.owner, "sw", "lamp") }, { true, nil })
		t.eq(s.profile.wireUnits, 100 - s.WireSupply.MaxLength)
	end)

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

	t.test("buying: the amount you ask for, at the catalog price, from your cash, into your box", function()
		local s = setup({ units = 3, cash = 500 })
		local price = s.WireSupply.UnitPrice()
		s.Service.OnWire(s.owner, "buy", 10)
		t.eq(s.profile.wireUnits, 13)
		t.eq(s.profile.cash, 500 - 10 * price)
		t.eq(#s.spent, 1)
		t.eq(s.spent[1].amount, 10 * price)
		t.eq(s.published[#s.published].units, 13)
	end)

	t.test("buying with too little cash, too much, a fraction or rubbish changes nothing", function()
		local s = setup({ units = 3, cash = 500 })
		local price = s.WireSupply.UnitPrice()
		s.profile.cash = price * 4
		s.Service.OnWire(s.owner, "buy", 5)
		t.eq(s.profile.wireUnits, 3, "not enough cash")
		t.ok(#s.toasts > 0, "told why")
		s.profile.cash = 1e9
		for _, bad in ipairs({ 0, -1, 2.5, 0 / 0, math.huge, "10", {}, true, s.WireSupply.MaxBuy + 1 }) do
			s.Service.OnWire(s.owner, "buy", bad)
		end
		s.Service.OnWire(s.owner, "buy")
		s.Service.OnWire(s.owner, "buy", 5, "extra")
		t.eq(s.profile.wireUnits, 3)
		t.eq(#s.spent, 0, "no cash moved")
	end)

	t.test("a box holds at most MaxStock: a buy that would pass it is refused", function()
		local s = setup({ units = 0, cash = 1e9 })
		s.profile.wireUnits = s.WireSupply.MaxStock - 2
		s.Service.OnWire(s.owner, "buy", 3)
		t.eq(s.profile.wireUnits, s.WireSupply.MaxStock - 2)
		t.eq(#s.spent, 0)
	end)

	t.test("only the plot's owner buys; a visitor with build rights uses the owner's wire but cannot buy", function()
		local s = setup({ units = 10, cash = 500, visitorBuilds = true })
		s.add("sw", "SparkSwitch", 0, 0)
		s.add("lamp", "SparkLamp", 6, 0)
		s.Service.OnWire(s.visitor, "buy", 5)
		t.eq(s.profile.wireUnits, 10, "the visitor's buy did nothing")
		t.eq(#s.spent, 0)
	end)

	t.test("every request is rate limited under the Wire budget, buying included", function()
		local keys = {}
		local s = setup({ units = 0, cash = 500, rate = false, keys = keys })
		s.Service.OnWire(s.owner, "buy", 5)
		t.eq(s.profile.wireUnits, 0)
		t.eq(keys, { "Wire" })
		t.eq(#s.spent, 0)
	end)

	t.test("with no wallet bound a buy does nothing (and does not error)", function()
		local s = setup({ units = 0, cash = 500 })
		s.Service.BindWallet(nil)
		s.Service.OnWire(s.owner, "buy", 5)
		t.eq(s.profile.wireUnits, 0)
	end)
end
