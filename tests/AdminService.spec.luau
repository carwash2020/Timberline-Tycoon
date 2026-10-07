--!nocheck
-- AdminService: the commands do their work for the owner, and for nobody else.
return function(t)
	local function boot(studio)
		local calls = { cash = {}, spent = {}, gifts = {}, kicks = {}, toasts = {}, replaced = {} }
		local players = {}
		local profiles = {}
		local function add(userId, name)
			local root = { Anchored = false }
			local p = {
				root = root,
				Character = {
					FindFirstChild = function(_, childName)
						if childName == "HumanoidRootPart" then
							return root
						end
						return nil
					end,
				},
				UserId = userId,
				Name = name,
				attrs = {},
				GetAttribute = function(self, key)
					return self.attrs[key]
				end,
				SetAttribute = function(self, key, value)
					self.attrs[key] = value
				end,
				Kick = function(_, reason)
					table.insert(calls.kicks, { name, reason })
				end,
			}
			players[name] = p
			return p
		end
		local Players = {
			GetPlayerByUserId = function(_, id)
				for _, p in pairs(players) do
					if p.UserId == id then
						return p
					end
				end
				return nil
			end,
			GetPlayers = function()
				local list = {}
				for _, p in pairs(players) do
					table.insert(list, p)
				end
				return list
			end,
			FindFirstChild = function(_, name)
				return players[name]
			end,
		}
		local cash = { Connor = 50, Bob = 400, Eve = 10 }
		local wsAttrs = {}
		local fakeWorkspace = {
			clock = 1790000000,
			GetServerTimeNow = function(self)
				return self.clock
			end,
			GetAttribute = function(_, k)
				return wsAttrs[k]
			end,
			SetAttribute = function(_, k, v)
				wsAttrs[k] = v
			end,
		}
		local loader = t.loader({
			globals = { workspace = fakeWorkspace },
			services = {
				Players = Players,
				RunService = {
					IsStudio = function()
						return studio
					end,
				},
				TextChatService = {},
				HttpService = {
					GenerateGUID = function()
						return "guid"
					end,
				},
			},
			mocks = {
				EconomyService = {
					AddCash = function(player, amount)
						table.insert(calls.cash, { player.Name, amount })
						cash[player.Name] += amount
						return amount, 0
					end,
					GetCash = function(player)
						return cash[player.Name]
					end,
					SpendCash = function(player, amount)
						table.insert(calls.spent, { player.Name, amount })
						cash[player.Name] -= amount
						return true
					end,
					ReplaceCash = function(player, amount)
						table.insert(calls.replaced, { player.Name, amount })
						cash[player.Name] = amount
					end,
				},
				ProfileService = {
					GetProfile = function(player)
						profiles[player.Name] = profiles[player.Name]
							or {
								plot = { claimed = true, tier = 2, squares = { "0,0" }, placed = {} },
								axes = {},
								blueprintBook = {},
								tutorialDone = false,
								tutorialStep = 3,
							}
						return profiles[player.Name]
					end,
				},
				ShopService = {
					ChargeAndGrant = function(player, box)
						table.insert(calls.gifts, { player.Name, box.kind, box.itemId, box.free })
						return true, "thanks"
					end,
				},
			},
		})
		local Admin = loader:server("AdminService")
		Admin.Creator = function()
			return "User", 100 -- Connor's account owns the experience
		end
		Admin.SetNotify(function(player, message)
			table.insert(calls.toasts, { player.Name, message })
		end)
		add(100, "Connor")
		add(200, "Bob")
		add(300, "Eve")
		calls.results = {}
		Admin.SetReply(function(player, ok, text)
			table.insert(calls.results, { player.Name, ok, text })
		end)
		calls.profiles = profiles
		calls.access = {}
		calls.now = 1000
		Admin.SetAccessSend(function(player, payload)
			table.insert(calls.access, { player.Name, payload })
		end)
		Admin.SetClock(function()
			return calls.now
		end)
		Admin.SetThrottle(0)
		return Admin, calls, cash, players, wsAttrs, fakeWorkspace
	end

	t.test("the owner's commands move cash and gift items", function()
		local Admin, calls, cash = boot(false)
		t.eq(Admin.Run(100, "/give Bob 500"), true)
		t.eq(cash.Bob, 900)
		t.eq(Admin.Run(100, "/take Bob 300"), true)
		t.eq(cash.Bob, 600)
		t.eq(Admin.Run(100, "/take Eve 999"), true)
		t.eq(calls.spent[2], { "Eve", 10 }, "taking more than they have takes what they have")
		t.eq(Admin.Run(100, "/setcash Bob 0"), true)
		t.eq(cash.Bob, 0)
		t.eq(Admin.Run(100, "/gift Bob Axe SteelAxe"), true)
		t.eq(calls.gifts[1], { "Bob", "Axe", "SteelAxe", true })
		-- A blueprint is a rolled plan the player carries (ShopService hands it over).
		t.eq(Admin.Run(100, "/gift Bob Blueprint Wall"), true)
		t.eq(calls.gifts[2], { "Bob", "Blueprint", "Wall", true })
	end)

	t.test("nobody else can do any of it: not a player, not a guess, not Studio's absence", function()
		local Admin, calls, cash = boot(false)
		for _, line in ipairs({
			"/give Bob 500",
			"/give Eve 500",
			"/setcash Eve 999999",
			"/gift Eve Axe StarfallAxe",
			"/gift Eve Blueprint Cabin",
			"/kick Connor",
			"/ban Connor perm",
			"/announce hi",
		}) do
			t.eq(Admin.Run(200, line), false, "Bob: " .. line)
			t.eq(Admin.Run(300, line), false, "Eve: " .. line)
		end
		t.eq(#calls.cash + #calls.spent + #calls.gifts + #calls.kicks + #calls.replaced, 0)
		t.eq(cash, { Connor = 50, Bob = 400, Eve = 10 })
	end)

	t.test("a group-owned experience gives nobody the owner's tools, and a bad amount does nothing", function()
		local Admin, calls = boot(false)
		Admin.Creator = function()
			return "Group", 100
		end
		t.eq(Admin.Run(100, "/give Bob 5"), false)
		Admin.Creator = function()
			return "User", 100
		end
		t.eq(Admin.Run(100, "/give Bob -5"), true, "it ran, and refused the amount")
		t.eq(Admin.Run(100, "/give Bob 99999999"), true)
		t.eq(#calls.cash, 0)
	end)

	t.test("the owner can't kick themselves, and a kick uses the reason", function()
		local Admin, calls = boot(false)
		Admin.Run(100, "/kick Connor")
		t.eq(#calls.kicks, 0)
		Admin.Run(100, "/kick Bob stop that")
		t.eq(calls.kicks[1], { "Bob", "stop that" })
	end)

	t.test("/superrun toggles the owner's own attribute, and only the owner can run it", function()
		local Admin, _, _, players = boot(false)
		t.eq(Admin.Run(200, "/superrun"), false)
		t.eq(players.Bob.attrs.SuperRun, nil)
		t.eq(Admin.Run(100, "/superrun"), true)
		t.eq(players.Connor.attrs.SuperRun, true)
		Admin.Run(100, "/superrun")
		t.eq(players.Connor.attrs.SuperRun, nil, "off again")
	end)

	t.test("the menu's request runs for the owner and for nobody else", function()
		local Admin, calls, cash, players = boot(false)
		t.eq(Admin.RunRequest(players.Connor, { action = "give", target = "Bob", amount = 500 }), true)
		t.eq(cash.Bob, 900)
		t.eq(Admin.RunRequest(players.Bob, { action = "give", target = "Bob", amount = 500 }), false)
		t.eq(Admin.RunRequest(players.Eve, { action = "setcash", target = "Eve", amount = 999999 }), false)
		t.eq(Admin.RunRequest(players.Bob, { action = "kick", target = "Connor" }), false)
		t.eq(cash, { Connor = 50, Bob = 900, Eve = 10 })
		t.eq(#calls.kicks, 0)
		t.eq(Admin.RunRequest(players.Connor, { action = "ban", target = "Bob" }), false, "off the menu's list")
		t.eq(Admin.RunRequest(players.Connor, "give Bob 5"), false)
	end)

	t.test("time control: speed, set hour and reset are the owner's, quiet, and live in memory only", function()
		local Admin, calls, _, players, ws, workspace = boot(false)
		local WorldTime = t.shared("WorldTime")
		-- Someone else gets nothing.
		t.eq(Admin.Run(200, "/timespeed 60"), false)
		t.eq(Admin.RunRequest(players.Bob, { action = "timespeed", speed = 60 }), false)
		t.eq(ws.TimeSpeed, nil)
		-- The owner: a whitelisted speed, anchored at "now" so the sky carries on.
		local before = WorldTime.ClockTime(workspace.clock)
		t.eq(Admin.Run(100, "/timespeed 20"), true)
		t.eq(ws.TimeSpeed, 20)
		workspace.clock += 60 -- a real minute later it is twenty game minutes on
		t.eq(
			WorldTime.Scaled(workspace.clock, ws.TimeAnchorReal, ws.TimeAnchorGame, ws.TimeSpeed),
			1790000000 + 20 * 60
		)
		t.ok(math.abs(before - WorldTime.ClockTime(ws.TimeAnchorGame)) < 1e-6, "no jump when the speed changed")
		-- Off the list: nothing changes.
		Admin.Run(100, "/timespeed 7")
		Admin.Run(100, "/timespeed 1000")
		Admin.Run(100, "/timespeed abc")
		t.eq(ws.TimeSpeed, 20)
		-- Set the hour, keeping the speed.
		t.eq(Admin.Run(100, "/settime noon"), true)
		t.ok(math.abs(WorldTime.ClockTime(ws.TimeAnchorGame) - 12) < 1e-6)
		t.eq(ws.TimeSpeed, 20)
		Admin.Run(100, "/settime 6:30pm")
		t.ok(math.abs(WorldTime.ClockTime(ws.TimeAnchorGame) - 18.5) < 1e-6)
		local anchor = ws.TimeAnchorGame
		Admin.Run(100, "/settime 25:00")
		Admin.Run(100, "/settime later")
		t.eq(ws.TimeAnchorGame, anchor, "a bad hour changes nothing")
		-- Reset clears all of it: real time again.
		t.eq(Admin.Run(100, "/timereset"), true)
		t.eq({ ws.TimeSpeed, ws.TimeAnchorReal, ws.TimeAnchorGame }, {})
		-- Quiet: only the owner was told anything.
		for _, toast in ipairs(calls.toasts) do
			t.eq(toast[1], "Connor")
		end
		-- The menu reaches the same handlers, from presets only.
		t.eq(Admin.RunRequest(players.Connor, { action = "timespeed", speed = 4 }), true)
		t.eq(ws.TimeSpeed, 4)
		t.eq(Admin.RunRequest(players.Connor, { action = "settime", time = "midnight" }), true)
		t.ok(math.abs(WorldTime.ClockTime(ws.TimeAnchorGame)) < 1e-6)
		t.eq(Admin.RunRequest(players.Connor, { action = "settime", time = "9:15pm" }), false)
		t.eq(Admin.RunRequest(players.Connor, { action = "timespeed", speed = 5 }), false)
		t.eq(Admin.RunRequest(players.Connor, { action = "timereset" }), true)
		t.eq(ws.TimeSpeed, nil)
	end)

	t.test("time speed is never saved: AdminService only writes workspace attributes", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/ServerScriptService/AdminService.luau")
		local block = string.match(source, "local function writeClock.-handlers%.god")
		t.ok(block, "the time handlers moved")
		t.eq(string.find(block, "Profile", 1, true), nil)
		t.eq(string.find(block, "DataStore", 1, true), nil)
	end)

	t.test("only the owner's client is told to show the menu", function()
		local Admin, _, _, players = boot(false)
		Admin.Mark(players.Connor)
		Admin.Mark(players.Bob)
		t.eq(players.Connor.attrs.IsOwner, true)
		t.eq(players.Bob.attrs.IsOwner, nil)
	end)

	t.test("unknown commands and a player who isn't there do nothing", function()
		local Admin, calls = boot(false)
		t.eq(Admin.Run(100, "/nonsense"), false)
		t.eq(Admin.Run(999, "/give Bob 5"), false, "no such player on the server")
		Admin.Run(100, "/give Nobody 5")
		t.eq(#calls.cash, 0)
	end)

	t.test("the hub's new requests run for the owner only, and answer with a result line", function()
		local Admin, calls, _, players = boot(false)
		local owner = players.Connor
		-- Freeze: toggles, never the owner, never from a player.
		t.eq(Admin.RunRequest(players.Bob, { action = "freeze", target = "Eve" }), false)
		t.eq(players.Eve.root.Anchored, false)
		t.eq(Admin.RunRequest(owner, { action = "freeze", target = "Eve" }), true)
		t.eq(players.Eve.root.Anchored, true)
		t.eq(Admin.RunRequest(owner, { action = "freeze", target = "Eve" }), true)
		t.eq(players.Eve.root.Anchored, false)
		t.eq(Admin.RunRequest(owner, { action = "freeze", target = "Connor" }), true, "it ran and refused")
		t.eq(calls.results[#calls.results][2], false)
		-- Stats is read-only and says what it found.
		t.eq(Admin.RunRequest(owner, { action = "stats", target = "Bob" }), true)
		local last = calls.results[#calls.results]
		t.eq(last[1], "Connor")
		t.eq(last[2], true)
		t.ok(string.find(last[3], "Bob", 1, true) and string.find(last[3], "tier 2", 1, true), last[3])
		t.eq(#calls.cash + #calls.spent + #calls.replaced, 0, "stats changes nothing")
		t.eq(Admin.RunRequest(players.Eve, { action = "stats", target = "Bob" }), false)
		-- Unlock every building: only through the book's own rule.
		t.eq(Admin.RunRequest(players.Bob, { action = "unlockbp", target = "Bob" }), false)
		t.eq(#calls.profiles.Bob.blueprintBook, 0, "a refused request never touched the save")
		t.eq(Admin.RunRequest(owner, { action = "unlockbp", target = "Bob" }), true)
		t.ok(#calls.profiles.Bob.blueprintBook > 0)
		-- Tutorial reset goes through the wired hook.
		local reset = {}
		Admin.SetHooks({
			resetTutorial = function(p)
				table.insert(reset, p.Name)
			end,
		})
		t.eq(Admin.RunRequest(players.Bob, { action = "resettutorial", target = "Eve" }), false)
		t.eq(Admin.RunRequest(owner, { action = "resettutorial", target = "Eve" }), true)
		t.eq(reset, { "Eve" })
		-- A refusal says why and is red.
		t.eq(Admin.RunRequest(owner, { action = "give", target = "Nobody", amount = 5 }), true)
		t.eq(calls.results[#calls.results][2], false)
		-- Off the whitelist: refused with a line, nothing ran.
		t.eq(Admin.RunRequest(owner, { action = "setcash", target = "Bob", amount = -1 }), false)
		t.eq(calls.results[#calls.results][2], false)
		-- A non-owner gets no result line at all (nothing to learn from).
		local count = #calls.results
		t.eq(Admin.RunRequest(players.Eve, { action = "give", target = "Eve", amount = 5 }), false)
		t.eq(#calls.results, count)
	end)

	t.test("the menu can announce and shut down for the owner only, and can't kick the owner", function()
		local Admin, calls, _, players = boot(false)
		local owner = players.Connor
		local toasts = #calls.toasts
		t.eq(Admin.RunRequest(owner, { action = "announce", text = "hello" }), true)
		t.ok(#calls.toasts > toasts, "everyone was told")
		t.eq(Admin.RunRequest(players.Bob, { action = "announce", text = "hi" }), false)
		t.eq(Admin.RunRequest(owner, { action = "announce", text = "" }), false)
		t.eq(Admin.RunRequest(players.Bob, { action = "shutdown" }), false)
		t.eq(#calls.kicks, 0)
		-- In Studio everyone counts as owner; the speaker still can't kick themself.
		local StudioAdmin, studioCalls, _, studioPlayers = boot(true)
		t.eq(StudioAdmin.RunRequest(studioPlayers.Connor, { action = "kick", target = "Connor" }), true)
		t.eq(#studioCalls.kicks, 0)
		t.eq(StudioAdmin.RunRequest(studioPlayers.Connor, { action = "kick", target = "Bob" }), true)
		t.eq(#studioCalls.kicks, 1)
		t.eq(StudioAdmin.RunRequest(studioPlayers.Connor, { action = "shutdown" }), true)
		t.eq(#studioCalls.kicks, 4, "everyone went")
	end)

	local function lastAccess(calls, name, kind)
		for i = #calls.access, 1, -1 do
			local entry = calls.access[i]
			if entry[1] == name and entry[2].kind == kind then
				return entry[2]
			end
		end
		return nil
	end

	t.test("only the owner can grant or revoke: not a stranger, not a delegate, not a TESTER", function()
		local Admin, calls, _, players = boot(false)
		-- A stranger gets nothing, by chat or by the hub.
		t.eq(Admin.Run(200, "/delegate Eve helper 1h"), false)
		t.eq(
			Admin.RunRequest(players.Bob, { action = "delegate", target = "Eve", role = "HELPER", expiry = "1h" }),
			false
		)
		t.eq(next(Admin.Delegates()), nil)
		t.eq(#calls.results, 0, "no answer for a stranger")
		-- The owner grants.
		t.eq(Admin.Run(100, "/delegate Bob moderator 1h"), true)
		t.eq(Admin.Delegates()[200].role, "MODERATOR")
		t.eq(Admin.Delegates()[200].grantedBy, 100)
		-- A delegate cannot grant, revoke or list, by chat or by the hub.
		t.eq(Admin.Run(200, "/delegate Eve helper 1h"), false)
		t.eq(Admin.Run(200, "/undelegate Bob"), false)
		t.eq(Admin.Run(200, "/delegates"), false)
		t.eq(
			Admin.RunRequest(players.Bob, { action = "delegate", target = "Eve", role = "HELPER", expiry = "1h" }),
			false
		)
		t.eq(Admin.RunRequest(players.Bob, { action = "undelegate", target = "Bob" }), false)
		t.eq(Admin.Delegates()[300], nil)
		t.ok(Admin.Delegates()[200] ~= nil, "Bob still has exactly what he was given")
		-- A TESTER cannot manage delegation either, nor make another TESTER.
		t.eq(Admin.Run(100, "/delegate Eve tester 1h"), true, "the owner is warned, nothing is granted")
		t.eq(Admin.Delegates()[300], nil, "TESTER needs the second step")
		t.eq(Admin.Run(100, "/delegate Eve tester 1h confirm"), true)
		t.eq(Admin.Delegates()[300].role, "TESTER")
		t.eq(Admin.Run(300, "/delegate Bob tester 1h confirm"), false)
		t.eq(Admin.Run(300, "/undelegate Bob"), false)
		t.eq(Admin.Run(300, "/delegates"), false)
		t.eq(
			Admin.RunRequest(
				players.Eve,
				{ action = "delegate", target = "Bob", role = "TESTER", expiry = "1h", confirmed = true }
			),
			false
		)
		t.eq(Admin.Delegates()[200].role, "MODERATOR")
		-- Only the owner revokes, at once.
		t.eq(Admin.Run(100, "/undelegate Eve"), true)
		t.eq(Admin.Delegates()[300], nil)
		t.eq(lastAccess(calls, "Eve", "revoked") ~= nil, true, "their menu is told to close")
		t.eq(Admin.Run(300, "/give Eve 500"), false)
	end)

	t.test("a delegate has exactly the role's powers and never aims one at the owner", function()
		local Admin, calls, cash, players = boot(false)
		Admin.Run(100, "/delegate Bob moderator 1h")
		local access = lastAccess(calls, "Bob", "access")
		t.eq(access.role, "delegate")
		t.eq(access.tester, false)
		t.ok(table.find(access.actions, "kick") ~= nil)
		t.eq(table.find(access.actions, "give"), nil, "the hub is built from this: no cash tools")
		t.eq(table.find(access.actions, "delegate"), nil)
		-- What a moderator may do.
		t.eq(Admin.RunRequest(players.Bob, { action = "kick", target = "Eve" }), true)
		t.eq(calls.kicks[1][1], "Eve")
		t.eq(Admin.RunRequest(players.Bob, { action = "stats", target = "Eve" }), true)
		-- What he may not, by chat or the hub.
		for _, line in ipairs({
			"/give Bob 500",
			"/take Eve 5",
			"/setcash Bob 999",
			"/superrun",
			"/shutdown",
			"/gift Eve Axe SteelAxe",
			"/resettutorial Eve",
			"/unlockbp Bob",
			"/unban 5",
			"/ban Eve perm",
			"/ban Eve 2",
			"/timespeed 60",
		}) do
			t.eq(Admin.Run(200, line), false, line)
		end
		t.eq(
			Admin.RunRequest(
				players.Bob,
				{ action = "give", target = "Bob", amount = 5, role = "TESTER", confirmed = true }
			),
			false,
			"a role sent by the client means nothing"
		)
		t.eq(cash, { Connor = 50, Bob = 400, Eve = 10 })
		t.eq(#calls.gifts + #calls.replaced + #calls.cash, 0)
		t.eq(players.Bob.attrs.SuperRun, nil)
		-- Never the owner: no kick, ban, teleport, freeze, stats, heal or gift.
		local before = #calls.kicks
		for _, line in ipairs({
			"/kick Connor",
			"/ban Connor 1",
			"/goto Connor",
			"/bring Connor",
			"/freeze Connor",
			"/stats Connor",
			"/heal Connor",
		}) do
			t.eq(Admin.Run(200, line), false, line)
		end
		t.eq(#calls.kicks, before)
		t.eq(players.Connor.root.Anchored, false)
		-- Everything a delegate does is on the owner's audit list, with both ids in the log text.
		local audit = lastAccess(calls, "Connor", "audit")
		t.ok(
			audit and string.find(audit.text, "Bob", 1, true) and string.find(audit.text, "MODERATOR", 1, true),
			audit and audit.text
		)
	end)

	t.test("a builder gifts only to themself, a custom role has only the ticked powers", function()
		local Admin, calls, _, players = boot(false)
		Admin.Run(100, "/delegate Bob builder 24h")
		t.eq(
			Admin.RunRequest(players.Bob, { action = "gift", target = "Bob", kind = "Axe", itemId = "SteelAxe" }),
			true
		)
		t.eq(calls.gifts[1], { "Bob", "Axe", "SteelAxe", true })
		t.eq(
			Admin.RunRequest(players.Bob, { action = "gift", target = "Eve", kind = "Axe", itemId = "SteelAxe" }),
			false
		)
		t.eq(#calls.gifts, 1)
		Admin.Run(100, "/delegate Eve custom heal,stats 1h")
		t.eq(Admin.Run(300, "/stats Bob"), true)
		t.eq(Admin.Run(300, "/kick Bob"), false)
		t.eq(Admin.Run(100, "/delegate Eve custom give 1h"), true, "it ran and refused")
		t.eq(Admin.Delegates()[300].powers, { "heal", "stats" }, "give is never delegable")
	end)

	t.test("a grant ends: expiry, leaving (session), and revoking, each at once", function()
		local Admin, calls, _, players = boot(false)
		Admin.Run(100, "/delegate Bob helper 1h")
		Admin.Run(100, "/delegate Eve helper session")
		Admin.Run(100, "/delegate 999 helper 24h") -- by UserId, not in the server
		t.ok(Admin.Delegates()[999] ~= nil)
		t.eq(Admin.Run(200, "/stats Eve"), true)
		calls.now += 3599
		t.eq(Admin.Run(200, "/stats Eve"), true, "not yet")
		calls.now += 2
		t.eq(Admin.Run(200, "/stats Eve"), false, "an hour is up")
		t.eq(Admin.Delegates()[200], nil)
		t.ok(lastAccess(calls, "Bob", "revoked"))
		t.eq(Admin.RunRequest(players.Bob, { action = "stats", target = "Eve" }), false)
		-- A session grant goes when its player leaves.
		Admin.PlayerLeft(players.Eve)
		t.eq(Admin.Delegates()[300], nil)
		-- The sweep ends expired ones nobody used.
		calls.now += 86400
		Admin.Sweep()
		t.eq(Admin.Delegates()[999], nil)
		-- A session grant needs the player here; an unknown name is refused.
		t.eq(Admin.Run(100, "/delegate 12345 helper session"), true)
		t.eq(Admin.Delegates()[12345], nil)
		-- The owner can never be a delegate.
		Admin.Run(100, "/delegate Connor helper 1h")
		t.eq(Admin.Delegates()[100], nil)
	end)

	t.test(
		"TESTER: two steps to grant, short, destructive actions confirmed, shown to the owner, never the owner",
		function()
			local Admin, calls, cash, players = boot(false)
			-- The warning, not a grant.
			Admin.RunRequest(players.Connor, { action = "delegate", target = "Bob", role = "TESTER", expiry = "1h" })
			t.eq(Admin.Delegates()[200], nil)
			t.ok(string.find(calls.results[#calls.results][3], "trust", 1, true), calls.results[#calls.results][3])
			t.eq(calls.results[#calls.results][2], false)
			-- Never until revoked, never persisted.
			Admin.Run(100, "/delegate Bob tester server confirm")
			t.eq(Admin.Delegates()[200], nil)
			t.eq(
				Admin.RunRequest(
					players.Connor,
					{ action = "delegate", target = "Bob", role = "TESTER", expiry = "1h", confirmed = true }
				),
				true
			)
			local g = Admin.Delegates()[200]
			t.eq(g.role, "TESTER")
			t.eq(g.expiresAt, calls.now + 3600)
			local access = lastAccess(calls, "Bob", "access")
			t.eq(access.tester, true)
			t.ok(table.find(access.actions, "shutdown") ~= nil and table.find(access.actions, "give") ~= nil)
			t.eq(table.find(access.actions, "delegate"), nil)
			-- Full power for what is not destructive...
			t.eq(Admin.RunRequest(players.Bob, { action = "give", target = "Eve", amount = 5 }), true)
			t.eq(cash.Eve, 15)
			t.eq(Admin.RunRequest(players.Bob, { action = "superrun" }), true)
			t.eq(players.Bob.attrs.SuperRun, true)
			-- ...and an extra confirmation for what is.
			t.eq(Admin.RunRequest(players.Bob, { action = "take", target = "Eve", amount = 5 }), false)
			t.eq(cash.Eve, 15)
			t.eq(
				Admin.Run(200, "/kick Eve"),
				false,
				"chat has no second step, so TESTER's destructive tools are hub-only"
			)
			t.eq(#calls.kicks, 0)
			local toasts = #calls.toasts
			t.eq(Admin.RunRequest(players.Bob, { action = "take", target = "Eve", amount = 5, confirmed = true }), true)
			t.eq(cash.Eve, 10)
			local shown = false
			for i = toasts + 1, #calls.toasts do
				if calls.toasts[i][1] == "Connor" and string.find(calls.toasts[i][2], "TESTER", 1, true) then
					shown = true
				end
			end
			t.ok(shown, "the owner sees a TESTER's destructive action on screen")
			local audit = lastAccess(calls, "Connor", "audit")
			t.ok(audit and string.find(audit.text, "TESTER", 1, true) and string.find(audit.text, "Bob", 1, true))
			t.eq(Admin.RunRequest(players.Bob, { action = "kick", target = "Eve", confirmed = true }), true)
			t.eq(calls.kicks[1][1], "Eve")
			-- Never the owner, whatever the confirmation.
			for _, request in ipairs({
				{ action = "kick", target = "Connor", confirmed = true },
				{ action = "ban", target = "Connor", hours = "perm", confirmed = true },
				{ action = "take", target = "Connor", amount = 5, confirmed = true },
				{ action = "setcash", target = "Connor", amount = 0, confirmed = true },
				{ action = "goto", target = "Connor" },
				{ action = "freeze", target = "Connor" },
				{ action = "resettutorial", target = "Connor", confirmed = true },
			}) do
				t.eq(Admin.RunRequest(players.Bob, request), false, request.action)
			end
			t.eq(cash.Connor, 50)
			t.eq(players.Connor.root.Anchored, false)
			-- It ends with the hour, closing the menu.
			calls.now += 3601
			t.eq(Admin.RunRequest(players.Bob, { action = "give", target = "Eve", amount = 5 }), false)
			t.ok(lastAccess(calls, "Bob", "revoked"))
			t.eq(players.Bob.attrs.SuperRun, nil, "its super run ended with it")
		end
	)

	t.test("a delegate's requests are slower than the owner's", function()
		local Admin, _, _, players = boot(false)
		Admin.Run(100, "/delegate Bob helper 1h")
		Admin.SetThrottle(60)
		t.eq(Admin.RunRequest(players.Bob, { action = "stats", target = "Eve" }), true)
		t.eq(Admin.RunRequest(players.Bob, { action = "stats", target = "Eve" }), false, "too soon")
		t.eq(Admin.RunRequest(players.Connor, { action = "stats", target = "Eve" }), true)
		t.eq(
			Admin.RunRequest(players.Connor, { action = "stats", target = "Eve" }),
			true,
			"the owner is not slowed here"
		)
	end)

	t.test("every new tool has a chat handler", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/ServerScriptService/AdminService.luau")
		for _, name in ipairs({ "god", "heal", "tospawn", "freeze", "stats", "resettutorial", "unlockbp", "shutdown" }) do
			t.ok(string.find(source, "handlers." .. name .. " =", 1, true), name)
		end
	end)

	t.test("the server never trusts the IsOwner attribute, and the free-gift flag is set nowhere else", function()
		local fs = require("@lune/fs")
		local dir = "src/ServerScriptService"
		for _, entry in ipairs(fs.readDir(dir)) do
			if string.match(entry, "%.luau$") then
				local source = fs.readFile(dir .. "/" .. entry)
				t.ok(
					not string.find(source, 'GetAttribute("IsOwner")', 1, true),
					entry .. " reads IsOwner: the attribute only shows the menu button"
				)
				if entry ~= "AdminService.luau" and entry ~= "ShopService.luau" then
					t.ok(not string.find(source, "free = true", 1, true), entry .. " passes the free-gift flag")
				end
			end
		end
	end)

	t.test("/sample builds on the owner's plot only: not a player, not a delegate, not even a TESTER", function()
		local Admin, calls, _, players = boot(false)
		local placed, cleared = {}, {}
		Admin.SetHooks({
			placeSample = function(player, name)
				table.insert(placed, { player.Name, name })
				return true, "Built the " .. name .. "."
			end,
			clearSamples = function(player)
				table.insert(cleared, player.Name)
				return 3
			end,
		})
		t.eq(Admin.Run(100, "/sample modern"), true)
		t.eq(placed, { { "Connor", "modern" } })
		t.eq(calls.toasts[#calls.toasts][2], "Built the modern.")
		t.eq(Admin.Run(100, "/sample clear"), true)
		t.eq(cleared, { "Connor" })
		t.eq(calls.toasts[#calls.toasts][2], "Took down 3 sample pieces.")
		Admin.Run(100, "/sample")
		t.eq(#placed, 1, "no name places nothing")
		-- A stranger gets nothing at all.
		t.eq(Admin.Run(200, "/sample modern"), false)
		t.eq(Admin.Run(300, "/sample clear"), false)
		-- A delegate with every power a role can hold, and a TESTER, are refused.
		t.eq(Admin.Run(100, "/delegate Bob builder 1h"), true)
		t.eq(Admin.Run(200, "/sample modern"), false, "BUILDER")
		t.eq(Admin.Run(100, "/delegate Eve tester 1h confirm"), true)
		t.eq(Admin.Delegates()[300].role, "TESTER")
		t.eq(Admin.Run(300, "/sample modern"), false, "TESTER")
		t.eq(Admin.Run(300, "/sample clear"), false, "TESTER")
		t.eq(#placed, 1)
		t.eq(#cleared, 1)
		_ = players
	end)

	t.test("/sample without its hooks refuses politely", function()
		local Admin, calls = boot(false)
		Admin.SetHooks({})
		t.eq(Admin.Run(100, "/sample modern"), true)
		t.eq(calls.toasts[#calls.toasts][2], "Samples aren't available here.")
	end)
end
