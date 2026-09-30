--!nocheck
-- Cash only moves through EconomyService, and the wallet cap holds.
return function(t)
	local function setup(cash)
		local profile = { cash = cash, totalEarned = 0 }
		local player = {
			Name = "Tester",
			attrs = {},
			SetAttribute = function(self, key, value)
				self.attrs[key] = value
			end,
		}
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
			},
		})
		return loader:server("EconomyService"), loader:shared("GameConfig"), player, profile
	end

	t.test("AddCash credits, mirrors the Cash attribute and counts totalEarned", function()
		local Economy, _, player, profile = setup(0)
		local credited, overflow = Economy.AddCash(player, 9, "test")
		t.eq({ credited, overflow }, { 9, 0 })
		t.eq(profile.cash, 9)
		t.eq(profile.totalEarned, 9)
		t.eq(player.attrs.Cash, 9)
	end)

	t.test("AddCash stops at the wallet cap and reports the overflow", function()
		local Economy, GameConfig, player, profile = setup(0)
		local cap = GameConfig.CashCap
		profile.cash = cap - 100
		local credited, overflow = Economy.AddCash(player, 250, "test")
		t.eq({ credited, overflow }, { 100, 150 })
		t.eq(profile.cash, cap)
		credited, overflow = Economy.AddCash(player, 50, "test")
		t.eq({ credited, overflow }, { 0, 50 })
		t.eq(profile.totalEarned, 100, "overflow isn't earned")
	end)

	t.test("AddCash ignores zero, negative and fractional junk", function()
		local Economy, _, player, profile = setup(10)
		t.eq({ Economy.AddCash(player, 0, "test") }, { 0, 0 })
		t.eq({ Economy.AddCash(player, -5, "test") }, { 0, 0 })
		t.eq({ Economy.AddCash(player, 2.9, "test") }, { 2, 0 })
		t.eq(profile.cash, 12)
	end)

	t.test("SpendCash refuses when short and never goes negative", function()
		local Economy, _, player, profile = setup(100)
		t.ok(not Economy.SpendCash(player, 150, "test"))
		t.eq(profile.cash, 100)
		t.ok(Economy.SpendCash(player, 100, "test"))
		t.eq(profile.cash, 0)
		t.ok(not Economy.SpendCash(player, -10, "test"), "negative spends would add cash")
		t.eq(profile.cash, 0)
	end)

	t.test("Refund gives spent cash back up to the cap, without counting it as earned", function()
		local Economy, GameConfig, player, profile = setup(0)
		t.eq({ Economy.Refund(player, 40, "sold a fence") }, { 40, 0 })
		t.eq(profile.cash, 40)
		t.eq(profile.totalEarned, 0)
		t.eq(player.attrs.Cash, 40)
		profile.cash = GameConfig.CashCap - 10
		t.eq({ Economy.Refund(player, 25, "test") }, { 10, 15 })
		t.eq(profile.cash, GameConfig.CashCap)
		t.eq({ Economy.Refund(player, -5, "test") }, { 0, 0 })
	end)

	t.test("no profile, no cash", function()
		local Economy = setup(0)
		t.eq({ Economy.AddCash({ Name = "Stranger" }, 10, "test") }, { 0, 0 })
		t.ok(not Economy.SpendCash({ Name = "Stranger" }, 1, "test"))
	end)
end
