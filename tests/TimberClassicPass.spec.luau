--!nocheck
-- T421 (Connor): the Timber Classic is granted by the Classic game pass, never sold for cash. The server decides, by its
-- own ownership state (MonetizationService: UserOwnsGamePassAsync in a pcall, kept per player, cleared when the player
-- leaves, flipped by PromptGamePassPurchaseFinished); a client's spawn request without the pass is refused. Owners
-- spawn it free. A failed check never grants. The Pickup stays cash-buyable at its price and the Classic is in no
-- cash list.
return function(t)
	local Enum = t.roblox.Enum
	local ItemCatalog = t.shared("ItemCatalog")
	local ShopLogic = t.shared("ShopLogic")
	local ItemBox = t.shared("ItemBox")
	local Rule = t.shared("VehicleSpawnRule")
	local Gate = t.shared("VehicleMeshGate")
	local classic = ItemCatalog.GetTruck("TimberClassic")

	-- Its meshes are in (made-up ids, and the stats the piece table needs): the pass is the only thing left to decide.
	local function stockClassic()
		Gate.SetIds(Gate.FakeIds())
		Gate.ClassicStats = true
	end
	local function unstock()
		Gate.SetIds(nil)
		Gate.ClassicStats = false
	end

	local function setup(options)
		options = options or {}
		local loader = t.loader()
		local Schema = loader:server("ProfileSchema")
		local profile = loader:shared("Util").deepCopy(Schema.Template)
		if options.passes then
			profile.passes = options.passes
		end
		local player = {
			UserId = 7,
			Name = "Tester",
			attrs = {},
			SetAttribute = function(self, key, value)
				self.attrs[key] = value
			end,
			GetAttribute = function(self, key)
				return self.attrs[key]
			end,
		}
		local calls = { owns = 0 }
		local passFinished
		local market = {
			PromptGamePassPurchase = function() end,
			PromptProductPurchase = function() end,
			UserOwnsGamePassAsync = function(_, _, id)
				calls.owns += 1
				if (options.passErrors or 0) > 0 then
					options.passErrors -= 1
					error("HTTP 500 (the service hiccupped)")
				end
				return options.ownsPass == id
			end,
			GetProductInfo = function()
				return { IsForSale = true, PriceInRobux = 300 }
			end,
			PromptGamePassPurchaseFinished = {
				Connect = function(_, fn)
					passFinished = fn
				end,
			},
		}
		local players = {
			GetPlayerByUserId = function(_, id)
				return if id == player.UserId then player else nil
			end,
		}
		player.Parent = players
		loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
					ProcessPurchaseAsync = function()
						return Enum.ProductPurchaseDecision.PurchaseGranted
					end,
				},
			},
			services = {
				MarketplaceService = market,
				Players = players,
				RunService = {
					IsStudio = function()
						return false
					end,
					IsServer = function()
						return true
					end,
				},
			},
			globals = {
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					wait = function() end,
				},
			},
		})
		local StoreData = loader:shared("StoreData")
		for i, item in ipairs(StoreData.Passes) do
			item.id = 100 + i
		end
		local Monetization = loader:server("MonetizationService")
		Monetization.Init({ OnServerEvent = { Connect = function() end } }, function() end, function()
			return 1_000_000
		end)
		Monetization.PlayerJoined(player, profile)
		return {
			M = Monetization,
			StoreData = StoreData,
			player = player,
			profile = profile,
			calls = calls,
			finish = function(purchased)
				passFinished(player, StoreData.Pass("TimberClassic").id, purchased)
			end,
		}
	end

	-- What VehicleService.SpawnTruck asks, from the same pieces.
	local function mayDrive(s)
		local PaidItems = t.shared("PaidItems")
		local has = Rule.OwnsPass(
			s.player:GetAttribute("Pass_TimberClassic"),
			PaidItems.SaveHasPass(s.profile, "TimberClassic")
		)
		return Rule.CanSpawn(classic, has)
	end

	t.test("a non-owner's spawn request is refused, with the pass named", function()
		stockClassic()
		local s = setup({ ownsPass = nil })
		local ok, why = mayDrive(s)
		t.eq(ok, false)
		t.ok(string.find(why, "Classic pass", 1, true), tostring(why))
		unstock()
	end)

	t.test("an owner's request is allowed, with no cash charged", function()
		stockClassic()
		local probe = setup({})
		local s = setup({ ownsPass = probe.StoreData.Pass("TimberClassic").id })
		t.eq(s.player.attrs.Pass_TimberClassic, true)
		t.eq((mayDrive(s)), true)
		t.eq(s.profile.cash, 0, "free: nothing was charged")
		unstock()
	end)

	t.test("the answer is kept: asking again does not call Roblox again", function()
		local probe = setup({})
		local s = setup({ ownsPass = probe.StoreData.Pass("TimberClassic").id })
		local after = s.calls.owns
		for _ = 1, 5 do
			t.eq(s.M.HasPass(s.player, "TimberClassic"), true)
		end
		t.eq(s.calls.owns, after, "a cache hit makes no second async call")
	end)

	t.test("a failed ownership check counts as not owned and never grants", function()
		stockClassic()
		local probe = setup({})
		local s = setup({ ownsPass = probe.StoreData.Pass("TimberClassic").id, passErrors = 100 })
		t.eq(s.M.HasPass(s.player, "TimberClassic"), false)
		t.eq(s.player.attrs.Pass_TimberClassic, nil)
		t.eq((mayDrive(s)), false)
		unstock()
	end)

	t.test("PromptGamePassPurchaseFinished flips it: bought grants, declined does not", function()
		stockClassic()
		local s = setup({})
		s.finish(false)
		t.eq(s.M.HasPass(s.player, "TimberClassic"), false)
		t.eq((mayDrive(s)), false)
		s.finish(true)
		t.eq(s.M.HasPass(s.player, "TimberClassic"), true)
		t.eq((mayDrive(s)), true)
		unstock()
	end)

	t.test("leaving clears the cache", function()
		local s = setup({})
		s.finish(true)
		t.eq(s.M.HasPass(s.player, "TimberClassic"), true)
		s.M.PlayerRemoving(s.player)
		t.eq(s.M.HasPass(s.player, "TimberClassic"), false)
	end)

	t.test("with its meshes missing it is not spawned, even for the owner", function()
		Gate.SetIds(nil) -- the real, empty ids
		local ok, why = Rule.CanSpawn(classic, true)
		t.eq(ok, false)
		t.ok(string.find(why, "isn't ready", 1, true), tostring(why))
	end)

	t.test("the Pickup stays cash-buyable at its price; the Classic is in no cash list", function()
		local pickup = ItemCatalog.GetTruck("Pickup")
		t.eq(pickup.priceCash, 1200, "the Pickup's price is unchanged")
		t.eq(pickup.v2.price, 400)
		t.eq(ShopLogic.TruckForCash(pickup), true)
		t.eq(ShopLogic.TruckForCash(classic), false)
		for _, entry in ipairs(ItemBox.Showroom) do
			t.ok(entry.id ~= "TimberClassic", "not in the showroom's cash stock")
		end
		-- Its priceCash is the recall-fee basis it already had (ShopLogic.RespawnFee): it is not offered for sale.
		t.eq(classic.sold, false)
		t.eq(classic.robux, true)
	end)
end
