--!nocheck
-- AdminService: the commands do their work for the owner, and for nobody else.
return function(t)
	local function boot(studio)
		local calls = { cash = {}, spent = {}, gifts = {}, kicks = {}, toasts = {}, replaced = {} }
		local players = {}
		local function add(userId, name)
			local p = {
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
		local loader = t.loader({
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
					GetProfile = function()
						return {}
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
		return Admin, calls, cash, players
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
end
