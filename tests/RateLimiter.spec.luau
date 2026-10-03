--!nocheck
-- Spam is dropped quietly; only floods earn strikes; five strikes kick.
return function(t)
	local now = 0
	local fakeOs = setmetatable({
		clock = function()
			return now
		end,
	}, { __index = os })

	local function setup()
		now = 100
		local loader = t.loader({ globals = { os = fakeOs } })
		return loader:server("RateLimiter"), loader
	end

	local function fakePlayer()
		return {
			Name = "Tester",
			kicked = nil,
			Kick = function(self, reason)
				self.kicked = reason
			end,
		}
	end

	local function burst(limiter, player, remote, n)
		local allowed = 0
		for _ = 1, n do
			if limiter.Allow(player, remote) then
				allowed += 1
			end
		end
		return allowed
	end

	t.test("allows up to the limit per second, then drops", function()
		local limiter = setup()
		local player = fakePlayer()
		t.eq(burst(limiter, player, "ChopTree", 10), 4)
		now += 1
		t.eq(burst(limiter, player, "ChopTree", 3), 3, "a new second, a new budget")
	end)

	t.test("the v2 loop's Chop (M1.3): six swings a second", function()
		local limiter = setup()
		t.eq(burst(limiter, fakePlayer(), "Chop", 10), 6)
	end)

	t.test("every client-to-server remote in Net has a budget", function()
		local limiter = setup()
		local Net = t.shared("Net")
		-- Server-to-client remotes need none.
		local skip = { CashChanged = true, Notify = true, WorldFX = true }
		for _, name in ipairs(Net.RemoteNames) do
			if not skip[name] then
				t.ok(limiter.Allow(fakePlayer(), name), name .. " has a LIMITS entry")
			end
		end
	end)

	t.test("Instant Delivery has its own budget, separate from selling", function()
		local limiter = setup()
		local player = fakePlayer()
		t.eq(burst(limiter, player, "SellLogs", 4), 4)
		t.ok(not limiter.Allow(player, "SellLogs"))
		t.eq(burst(limiter, player, "UseInstantDelivery", 2), 2, "its own two a second")
		t.ok(not limiter.Allow(player, "UseInstantDelivery"))
		now += 1
		t.ok(limiter.Allow(player, "UseInstantDelivery"), "a new second")
		t.ok(limiter.Allow(player, "SellLogs"), "and selling has its own second")
	end)

	t.test("remotes have separate budgets; unknown remotes are refused", function()
		local limiter = setup()
		local player = fakePlayer()
		t.eq(burst(limiter, player, "ChopTree", 4), 4)
		t.eq(burst(limiter, player, "BuyItem", 5), 3)
		t.ok(not limiter.Allow(player, "NotARemote"))
	end)

	t.test("mashing never kicks; a flood strikes once per second", function()
		local limiter, loader = setup()
		local player = fakePlayer()
		for _ = 1, 30 do -- 30 seconds of 4x over the limit
			burst(limiter, player, "ChopTree", 16)
			now += 1
		end
		t.eq(player.kicked, nil)
		t.eq(#loader.warnings, 0, "no strikes below 5x")
		burst(limiter, player, "ChopTree", 100)
		t.eq(#loader.warnings, 1, "one strike for one flooded second")
		t.eq(player.kicked, nil)
	end)

	t.test("five floods inside a minute kick; spaced-out floods don't", function()
		local limiter = setup()
		local slow = fakePlayer()
		for _ = 1, 5 do
			burst(limiter, slow, "ChopTree", 100)
			now += 61 -- each strike has expired before the next
		end
		t.eq(slow.kicked, nil)
		local fast = fakePlayer()
		for _ = 1, 5 do
			burst(limiter, fast, "ChopTree", 100)
			now += 1
		end
		t.ok(fast.kicked ~= nil, "kicked after 5 strikes in 60 s")
	end)

	t.test("Forget clears a player's budgets", function()
		local limiter = setup()
		local player = fakePlayer()
		burst(limiter, player, "SellLogs", 4)
		t.ok(not limiter.Allow(player, "SellLogs"))
		limiter.Forget(player)
		t.ok(limiter.Allow(player, "SellLogs"))
	end)
end
