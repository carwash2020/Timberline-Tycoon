--!nocheck
-- WireRemote (T420): the Wire remote end to end on the server. A fake RemoteEvent
-- carries each request into LogicService's real handler; the wallet is the real
-- EconomyService (its own ProfileService stand-in, as EconomyService.spec has), the
-- rate limiter is the real one, and the plot lookup behaves like PlotService's
-- hostFor: you build on your own plot while standing on it, a visitor needs the
-- owner's flag, and off every plot you get nothing. Then the wire box is saved,
-- read back as a new join, and published again.
return function(t)
	local Vector3, CFrame = t.roblox.Vector3, t.roblox.CFrame
	local Instance = t.roblox.Instance

	local function world(options)
		options = options or {}
		local profile = {
			cash = options.cash or 0,
			totalEarned = 0,
			pendingCash = 0,
			plot = { placed = {}, wires = {} },
			permissions = {},
			wireUnits = options.units or 0,
		}
		local function newPlayer(id)
			local root = { Position = Vector3.new(115, 3, 100) }
			return {
				UserId = id,
				Name = "P" .. id,
				attrs = {},
				Character = {
					FindFirstChild = function(_, name)
						return if name == "HumanoidRootPart" then root else nil
					end,
				},
				root = root,
				SetAttribute = function(self, key, value)
					self.attrs[key] = value
				end,
			}
		end
		local owner, visitor = newPlayer(1), newPlayer(2)
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
				ProfileService = {
					GetProfile = function(p)
						return if p == owner then profile else nil
					end,
				},
			},
		})
		local Service = loader:server("LogicService")
		local Economy = loader:server("EconomyService")
		local PlotData = loader:shared("PlotData")
		local BlueprintModels = loader:shared("BlueprintModels")
		local WireSupply = loader:shared("WireSupply")
		local items = Instance.new("Folder")
		local host = { cframe = CFrame.new(100, 0, 100), items = items }
		local toasts = {}
		-- PlotService.hostFor, in miniature: standing on your own plot builds on it.
		local onPlot = true
		Service.Bind(function(player, flag)
			if not onPlot then
				return nil, nil, nil, false
			end
			if player == owner then
				return host, profile, owner, false
			end
			if profile.permissions.anyone and profile.permissions.anyone[flag] then
				return host, profile, owner, false
			end
			return nil, nil, nil, true
		end, function(player, text)
			table.insert(toasts, { player = player, text = text })
		end)
		Service.BindWallet({
			spend = function(buyer, amount, reason, sku)
				return Economy.SpendCash(buyer, amount, reason, sku)
			end,
			publish = function(buyer, units)
				buyer:SetAttribute("WireUnits", units)
			end,
		})
		-- The remote: Init connects the real handler to OnServerEvent.
		local handler
		Service.Init({
			OnServerEvent = {
				Connect = function(_, fn)
					handler = fn
				end,
			},
		})
		local function fire(player, ...)
			handler(player, ...)
		end
		local function add(uid, blueprintId, x, z)
			local item = { uid = uid, blueprintId = blueprintId, x = x, z = z, rot = 0 }
			table.insert(profile.plot.placed, item)
			local model = BlueprintModels.Build(PlotData.Blueprint(blueprintId), false)
			model.Name = uid
			model:PivotTo(host.cframe * CFrame.new(x, 0, z))
			model:SetAttribute("Open", false)
			model.Parent = items
			Service.Attach({
				slot = host,
				model = model,
				item = item,
				ownerOf = function()
					return owner, profile
				end,
			})
		end
		add("sw", "SparkSwitch", 0, 0)
		add("lamp", "SparkLamp", 30, 0)
		return {
			fire = fire,
			owner = owner,
			visitor = visitor,
			profile = profile,
			toasts = toasts,
			WireSupply = WireSupply,
			loader = loader,
			leave = function()
				onPlot = false
			end,
			Service = Service,
		}
	end

	local price = 2

	t.test("a buy through the remote spends real cash and fills the box", function()
		local w = world({ cash = 1000 })
		price = w.WireSupply.UnitPrice()
		w.fire(w.owner, "buy", 64)
		t.eq(w.profile.wireUnits, 64)
		t.eq(w.profile.cash, 1000 - 64 * price)
		t.eq(w.owner.attrs.WireUnits, 64)
		t.eq(w.owner.attrs.Cash, 1000 - 64 * price, "EconomyService mirrored the new cash")
	end)

	t.test("too little cash: nothing bought, nothing spent", function()
		local w = world({ cash = 32 * 2 - 1 })
		w.fire(w.owner, "buy", 32)
		t.eq(w.profile.wireUnits, 0)
		t.eq(w.profile.cash, 32 * 2 - 1)
	end)

	t.test("off your plot you cannot buy or wire", function()
		local w = world({ cash = 1000, units = 50 })
		w.leave()
		w.fire(w.owner, "buy", 32)
		w.fire(w.owner, "sw", 1, "lamp", 1)
		t.eq(w.profile.wireUnits, 50)
		t.eq(w.profile.cash, 1000)
		t.eq(w.profile.plot.wires, {})
	end)

	t.test("a non-owner cannot buy, and a visitor with the build flag cannot spend the owner's cash", function()
		local w = world({ cash = 1000, units = 10 })
		w.fire(w.visitor, "buy", 32)
		t.eq(w.profile.wireUnits, 10, "no flag: refused")
		w.profile.permissions = { anyone = { build = true } }
		w.fire(w.visitor, "buy", 32)
		t.eq(w.profile.wireUnits, 10, "with the flag: still the owner's purse")
		t.eq(w.profile.cash, 1000)
	end)

	t.test("fractional and negative amounts, and anything off the packs, are refused", function()
		local w = world({ cash = 1e6 })
		for _, bad in ipairs({ 32.5, 0.5, -32, -1, 0, 31, 33, 96, 200, 320 }) do
			w.fire(w.owner, "buy", bad)
		end
		t.eq(w.profile.wireUnits, 0)
		t.eq(w.profile.cash, 1e6)
	end)

	t.test("an over-length run is rejected and uses no wire; a legal one uses its own measured length", function()
		local w = world({ units = 200 })
		w.fire(w.owner, "sw", 1, "lamp", 1, { { x = 0, z = 40 }, { x = 30, z = 40 } })
		t.eq(w.profile.wireUnits, 200)
		t.eq(w.profile.plot.wires, {})
		w.fire(w.owner, "sw", 1, "lamp", 1, { { x = 0, z = 10 }, { x = 30, z = 10 } })
		t.eq(w.profile.wireUnits, 150, "10 + 30 + 10")
		t.eq(#w.profile.plot.wires, 1)
		t.eq(w.owner.attrs.WireUnits, 150)
	end)

	t.test("a short box leaves wireUnits and wires as they were", function()
		local w = world({ units = 20 })
		w.fire(w.owner, "sw", 1, "lamp", 1)
		t.eq(w.profile.wireUnits, 20)
		t.eq(w.profile.plot.wires, {})
	end)

	t.test("wireUnits survive a save and a rejoin, and are published again", function()
		local w = world({ cash = 1000 })
		w.fire(w.owner, "buy", 160)
		w.fire(w.owner, "sw", 1, "lamp", 1, { { x = 0, z = 10 }, { x = 30, z = 10 } })
		t.eq(w.profile.wireUnits, 110)
		-- Saved as JSON, as the store does, then loaded as a new join.
		local serde = require("@lune/serde")
		local saved = serde.decode("json", serde.encode("json", w.profile))
		local Schema = w.loader:server("ProfileSchema")
		local Util = w.loader:shared("Util")
		-- A load fills the template under what was saved (ProfileService.Reconcile), then Migrate runs.
		local loaded = Util.deepCopy(Schema.Template)
		loaded.wireUnits = saved.wireUnits
		loaded.plot = saved.plot
		Schema.Migrate(loaded)
		saved = loaded
		t.eq(saved.wireUnits, 110, "the box came back")
		t.eq(saved.plot.wires[1].via, { { x = 0, z = 10 }, { x = 30, z = 10 } }, "and the run's corners")
		-- The join publishes it for the client.
		local rejoin = world({})
		rejoin.profile.wireUnits = saved.wireUnits
		local Blueprints = rejoin.loader:server("BlueprintService")
		rejoin.profile.blueprintBook = {}
		Blueprints.Publish(rejoin.owner)
		t.eq(rejoin.owner.attrs.WireUnits, 110)
	end)

	t.test("every request is rate limited by the real limiter: a burst past the budget is dropped", function()
		local w = world({ cash = 1e6 })
		for _ = 1, 40 do
			w.fire(w.owner, "buy", 32)
		end
		t.ok(w.profile.wireUnits < 40 * 32, "the budget stopped the burst: " .. w.profile.wireUnits)
		t.ok(w.profile.wireUnits >= 32)
	end)
end
