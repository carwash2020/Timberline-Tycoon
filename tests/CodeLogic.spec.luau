--!nocheck
-- Redeem codes: the pure rules (Shared/CodeLogic), the data (ServerScriptService/CodeData)
-- and the server flow (CodeService) with mocks.
return function(t)
	local Logic = t.shared("CodeLogic")

	local function entry(over)
		local e = {
			id = "test",
			code = "HELLO-1",
			enabled = true,
			expires = "2026-12-31",
			reward = { kind = "cash", amount = 500 },
		}
		for k, v in pairs(over or {}) do
			e[k] = v
		end
		return e
	end

	-- 2026-12-31 23:59:59 UTC
	local LAST_SECOND = 1798761599

	t.test("Normalize trims, upper-cases and keeps only letters, digits, - and _", function()
		t.eq(Logic.Normalize("  hello-1 "), "HELLO-1")
		t.eq(Logic.Normalize("he llo_2"), "HELLO_2")
		t.eq(Logic.Normalize("a!@#b"), "AB")
		t.eq(Logic.Normalize(""), nil)
		t.eq(Logic.Normalize("   "), nil)
		t.eq(Logic.Normalize(42), nil)
		t.eq(Logic.Normalize(nil), nil)
		t.eq(Logic.Normalize(string.rep("A", 33)), nil, "longer than 32")
		t.eq(Logic.Normalize(string.rep("A", 5000)), nil, "a huge string is refused unread")
	end)

	t.test("ExpiryTime: end of that UTC day, and bad dates are nil", function()
		t.eq(Logic.ExpiryTime("2026-12-31"), LAST_SECOND)
		t.eq(Logic.ExpiryTime("1970-01-01"), 86399)
		t.eq(Logic.ExpiryTime("2024-02-29"), 1709251199, "a leap day")
		t.eq(Logic.ExpiryTime("2026-02-29"), nil, "not a leap year")
		t.eq(Logic.ExpiryTime("2026-13-01"), nil)
		t.eq(Logic.ExpiryTime("2026-00-10"), nil)
		t.eq(Logic.ExpiryTime("2026-04-31"), nil)
		t.eq(Logic.ExpiryTime("12/31/2026"), nil)
		t.eq(Logic.ExpiryTime(nil), nil)
	end)

	t.test("Expired: good through 23:59:59 UTC, expired a second later; unreadable dates are expired", function()
		local e = entry()
		t.ok(not Logic.Expired(e, LAST_SECOND))
		t.ok(Logic.Expired(e, LAST_SECOND + 1))
		t.ok(not Logic.Expired(e, 0))
		t.ok(Logic.Expired(entry({ expires = "soon" }), 0), "never forever")
	end)

	t.test("ValidReward: cash in range or a granted piece, nothing else", function()
		t.ok(Logic.ValidReward({ kind = "cash", amount = 1 }))
		t.ok(Logic.ValidReward({ kind = "cash", amount = Logic.MaxCash }))
		t.ok(not Logic.ValidReward({ kind = "cash", amount = 0 }))
		t.ok(not Logic.ValidReward({ kind = "cash", amount = Logic.MaxCash + 1 }))
		t.ok(not Logic.ValidReward({ kind = "cash", amount = 1.5 }))
		t.ok(not Logic.ValidReward({ kind = "cash", amount = 0 / 0 }))
		t.ok(not Logic.ValidReward({ kind = "cash", amount = "100" }))
		t.ok(Logic.ValidReward({ kind = "piece", id = "CopperLampPost" }))
		t.ok(not Logic.ValidReward({ kind = "piece", id = "NotAPiece" }))
		t.ok(not Logic.ValidReward({ kind = "robux", amount = 10 }), "no Robux")
		t.ok(not Logic.ValidReward({ kind = "pass", id = "DoubleWood" }), "no paid items")
		t.ok(not Logic.ValidReward({ kind = "cash", amount = 5, robux = 10 }), "no extra keys")
		t.ok(not Logic.ValidReward({ kind = "piece", id = "GoldChest", amount = 5 }))
		t.ok(not Logic.ValidReward(nil))
		t.ok(not Logic.ValidReward("cash"))
	end)

	t.test("Check: unknown, disabled, expired, used and ok", function()
		local e = entry()
		local used = { ["Code:test"] = true }
		t.eq(Logic.Check(nil, {}, 0), "invalid")
		t.eq(Logic.Check(entry({ enabled = false }), {}, 0), "invalid", "disabled reads as unknown")
		t.eq(Logic.Check(entry({ reward = { kind = "robux", amount = 5 } }), {}, 0), "invalid")
		t.eq(Logic.Check(e, {}, LAST_SECOND + 1), "expired")
		t.eq(Logic.Check(e, used, 0), "used")
		t.eq(Logic.Check(e, {}, 0), "ok")
		t.eq(Logic.Check(e, used, LAST_SECOND + 1), "expired", "expired beats used")
	end)

	t.test("Find matches the normalised code", function()
		local list = { entry({ id = "a", code = "ALPHA" }), entry({ id = "b", code = "Beta-2" }) }
		t.eq(Logic.Find(list, "ALPHA").id, "a")
		t.eq(Logic.Find(list, "BETA-2").id, "b")
		t.eq(Logic.Find(list, "GAMMA"), nil)
	end)

	t.test("the lockout: six wrong codes in a minute lock the box for thirty seconds", function()
		local misses = {}
		for i = 1, 5 do
			misses = Logic.NoteMiss(misses, 100 + i)
		end
		t.eq(Logic.Locked(misses, 106), 0, "five misses: still open")
		misses = Logic.NoteMiss(misses, 106)
		t.eq(Logic.Locked(misses, 106), 30)
		t.eq(Logic.Locked(misses, 120), 16)
		t.eq(Logic.Locked(misses, 137), 0, "the lock runs out")
		t.eq(#Logic.NoteMiss(misses, 400), 1, "old misses fall out of the window")
	end)

	t.test("CodeData: every row is well formed, ids and codes are unique, and nothing is live by accident", function()
		local Data = t.server("CodeData")
		t.ok(#Data.List >= 1)
		local ids, codes = {}, {}
		local placeholders = 0
		for _, row in ipairs(Data.List) do
			t.ok(type(row.id) == "string" and row.id ~= "", "has an id")
			t.ok(not ids[row.id], row.id .. " id is unique")
			ids[row.id] = true
			local code = Logic.Normalize(row.code)
			t.ok(code ~= nil, row.id .. " has a typeable code")
			t.eq(code, string.upper(row.code), row.id .. " is written in its normal form")
			t.ok(not codes[code], row.id .. " code is unique")
			codes[code] = true
			t.ok(Logic.ExpiryTime(row.expires) ~= nil, row.id .. " has a real UTC expiry date")
			t.ok(Logic.ValidReward(row.reward), row.id .. " pays cash or a free piece only")
			if string.find(row.code, "PLACEHOLDER", 1, true) then
				placeholders += 1
				t.eq(row.enabled, false, "the placeholder is disabled")
			end
		end
		t.ok(placeholders >= 1, "the shipped list is the disabled placeholder")
		for _, row in ipairs(Data.List) do
			if row.enabled then
				t.ok(not string.find(row.code, "PLACEHOLDER", 1, true), "a placeholder is never enabled")
			end
		end
	end)

	t.test("CodeData lives on the server only (no replicated copy for players to read)", function()
		local fs = require("@lune/fs")
		t.ok(fs.isFile("src/ServerScriptService/CodeData.luau"))
		t.ok(not fs.isFile("src/ReplicatedStorage/Shared/CodeData.luau"))
	end)

	-- CodeService ----------------------------------------------------------
	local function setup(list, now, options)
		options = options or {}
		local profile = { cash = options.cash or 0, onboarding = {} }
		local granted, added = {}, {}
		local player = { Name = "Tester", UserId = 7 }
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				EconomyService = {
					AddCash = function(_, amount, reason, sku)
						local room = (options.cap or 1000000) - profile.cash
						local credited = math.max(0, math.min(room, amount))
						profile.cash += credited
						table.insert(added, { amount = amount, reason = reason, sku = sku, credited = credited })
						return credited, amount - credited
					end,
				},
				PlotService = {
					CanGrant = function()
						if options.stockFull then
							return false, "full"
						end
						return true, nil
					end,
					GrantPiece = function(_, id, source)
						table.insert(granted, { id = id, source = source })
						return true, nil
					end,
				},
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
			},
		})
		local Service = loader:server("CodeService")
		Service.SetList(list)
		local clockNow = { value = now or 0 }
		Service.SetClock(function()
			return clockNow.value
		end)
		return Service, player, profile, added, granted, clockNow
	end

	t.test("redeeming pays once, marks the code used, and a second try is refused", function()
		local Service, player, profile, added = setup({ entry() }, 0)
		local ok, message = Service.Redeem(player, " hello-1 ")
		t.ok(ok)
		t.eq(profile.cash, 500)
		t.eq(added[1].sku, "code")
		t.eq(profile.onboarding["Code:test"], true, "saved")
		t.ok(string.find(message, "$500", 1, true))
		local again, why = Service.Redeem(player, "HELLO-1")
		t.ok(not again)
		t.eq(why, Logic.Messages.used)
		t.eq(profile.cash, 500, "no second payment")
		t.eq(#added, 1)
	end)

	t.test("an expired code pays nothing and is not marked", function()
		local Service, player, profile, added, _, clock = setup({ entry() }, LAST_SECOND + 1)
		local ok, why = Service.Redeem(player, "HELLO-1")
		t.ok(not ok)
		t.eq(why, Logic.Messages.expired)
		t.eq(profile.cash, 0)
		t.eq(#added, 0)
		clock.value = LAST_SECOND
		t.ok(Service.Redeem(player, "HELLO-1"), "the last second still counts")
	end)

	t.test("unknown and disabled codes read the same: invalid", function()
		local Service, player = setup({ entry({ enabled = false }) }, 0)
		local _, a = Service.Redeem(player, "HELLO-1")
		local _, b = Service.Redeem(player, "NOPE")
		t.eq(a, Logic.Messages.invalid)
		t.eq(b, Logic.Messages.invalid)
		local _, c = Service.Redeem(player, "   ")
		t.eq(c, Logic.Messages.empty)
		local _, d = Service.Redeem(player, 12345)
		t.eq(d, Logic.Messages.empty)
	end)

	t.test(
		"a reward over the wallet cap is clamped by AddCash, a full wallet refuses without using the code",
		function()
			local Service, player, profile = setup({ entry() }, 0, { cash = 999800, cap = 1000000 })
			local ok, message = Service.Redeem(player, "HELLO-1")
			t.ok(ok)
			t.eq(profile.cash, 1000000, "clamped to the cap")
			t.ok(string.find(message, "didn't fit", 1, true))
			local full, fullProfile = nil, nil
			local Service2, player2, profile2 = setup({ entry() }, 0, { cash = 1000000, cap = 1000000 })
			full = Service2.Redeem(player2, "HELLO-1")
			fullProfile = profile2
			t.ok(not full)
			t.eq(fullProfile.onboarding["Code:test"], nil, "not used up")
		end
	)

	t.test("a piece reward goes through GrantPiece; a full stock refuses without using the code", function()
		local list = { entry({ reward = { kind = "piece", id = "CopperLampPost" } }) }
		local Service, player, profile, _, granted = setup(list, 0)
		t.ok(Service.Redeem(player, "HELLO-1"))
		t.eq(granted, { { id = "CopperLampPost", source = "code" } })
		t.eq(profile.onboarding["Code:test"], true)
		local Service2, player2, profile2, _, granted2 = setup(list, 0, { stockFull = true })
		local ok, why = Service2.Redeem(player2, "HELLO-1")
		t.ok(not ok)
		t.eq(why, Logic.Messages.stock)
		t.eq(#granted2, 0)
		t.eq(profile2.onboarding["Code:test"], nil)
	end)

	t.test("a Robux-shaped reward in the data is refused at redeem time", function()
		local Service, player, profile, added = setup({ entry({ reward = { kind = "robux", amount = 100 } }) }, 0)
		local ok, why = Service.Redeem(player, "HELLO-1")
		t.ok(not ok)
		t.eq(why, Logic.Messages.invalid)
		t.eq(profile.cash, 0)
		t.eq(#added, 0)
	end)

	t.test("six wrong guesses lock the box, even for the right code, until the lock runs out", function()
		local Service, player, _, _, _, clock = setup({ entry() }, 0)
		for _ = 1, 6 do
			Service.Redeem(player, "WRONG")
		end
		local ok, why = Service.Redeem(player, "HELLO-1")
		t.ok(not ok)
		t.eq(why, Logic.Messages.locked)
		clock.value += 31
		t.ok(Service.Redeem(player, "HELLO-1"), "open again")
	end)

	t.test("the remote is rate limited and the server never trusts the client", function()
		local fs = require("@lune/fs")
		local service = fs.readFile("src/ServerScriptService/CodeService.luau")
		t.ok(string.find(service, 'RateLimiter.Allow(player, "RedeemCode")', 1, true))
		t.ok(string.find(service, "EconomyService.AddCash", 1, true), "cash only through EconomyService")
		t.eq(string.find(service, "profile.cash", 1, true), nil, "never writes the wallet itself")
		local Net = t.shared("Net")
		t.ok(table.find(Net.RemoteNames, "RedeemCode") ~= nil)
		t.ok(table.find(Net.RemoteNames, "CodeResult") ~= nil)
	end)
end
