--!nocheck
-- IdleService: what the server counts as activity, the warning at 18
-- minutes, the removal at 20, the grace period, and the wiring.
return function(t)
	local Vector3 = t.roblox.Vector3
	local MIN = 60

	local function setup(options)
		options = options or {}
		local now = 1000
		local toasts = {}
		local onRequest
		local players = {}
		local playersService = {
			GetPlayers = function()
				return players
			end,
		}
		local workspaceStub = {
			GetAttribute = function(_, name)
				return if options.studioScale and name == "IdleScale" then options.studioScale else nil
			end,
		}
		local loader = t.loader({
			mocks = {
				RateLimiter = {
					OnRequest = function(fn)
						onRequest = fn
					end,
				},
			},
			services = {
				Players = playersService,
				RunService = {
					IsStudio = function()
						return options.studio == true
					end,
				},
			},
			globals = {
				task = {
					spawn = function() end,
					wait = function() end,
				},
				workspace = workspaceStub,
			},
		})
		local Idle = loader:server("IdleService")
		Idle.Init({
			notify = function(player, text)
				table.insert(toasts, { player.Name, text })
			end,
			clock = function()
				return now
			end,
			loop = false,
		})
		local kicks = {}
		local function newPlayer(name)
			local chatted = {}
			local at = Vector3.new(0, 3, 0)
			local root = {
				IsA = function(_, class)
					return class == "BasePart"
				end,
			}
			local player = {
				Name = name,
				Parent = playersService,
				Chatted = {
					Connect = function(_, fn)
						table.insert(chatted, fn)
					end,
				},
				Character = {
					FindFirstChild = function(_, child)
						return if child == "HumanoidRootPart" then root else nil
					end,
				},
			}
			root.Position = at
			function player:Kick(message)
				table.insert(kicks, { name, message })
				self.Parent = nil
			end
			function player.move(to)
				root.Position = to
			end
			function player.chat()
				for _, fn in ipairs(chatted) do
					fn("hello")
				end
			end
			table.insert(players, player)
			return player
		end
		return {
			Idle = Idle,
			newPlayer = newPlayer,
			toasts = toasts,
			kicks = kicks,
			request = function(player, name)
				onRequest(player, name)
			end,
			advance = function(seconds)
				now += seconds
			end,
		}
	end

	t.test("an idle player is warned at 18 minutes and removed at 20, with a message that says to rejoin", function()
		local s = setup()
		local ann = s.newPlayer("Ann")
		s.Idle.Start(ann)
		s.advance(17 * MIN)
		s.Idle.Tick()
		t.eq(#s.toasts, 0)
		s.advance(1 * MIN)
		s.Idle.Tick()
		t.eq(#s.toasts, 1)
		t.ok(string.find(s.toasts[1][2], "2 minutes", 1, true) ~= nil, s.toasts[1][2])
		s.advance(2 * MIN)
		s.Idle.Tick()
		t.eq(#s.kicks, 1)
		t.ok(string.find(s.kicks[1][2], "Rejoin", 1, true) ~= nil, "the kick message tells them to rejoin")
		t.eq(s.Idle.IsTracked(ann), false)
	end)

	t.test("any remote counts as activity, even one that was over its budget", function()
		local s = setup()
		local ann = s.newPlayer("Ann")
		s.Idle.Start(ann)
		s.advance(19 * MIN)
		s.request(ann, "ChopTree") -- RateLimiter.Allow saw a remote
		s.Idle.Tick()
		t.eq(#s.toasts, 0, "no warning: they just acted")
		s.advance(19 * MIN)
		s.Idle.Tick()
		t.eq(#s.kicks, 0)
		s.advance(2 * MIN)
		s.Idle.Tick()
		t.eq(#s.kicks, 1, "20 minutes of nothing after that")
	end)

	t.test("chat counts as activity", function()
		local s = setup()
		local ann = s.newPlayer("Ann")
		s.Idle.Start(ann)
		s.advance(19 * MIN + 30)
		ann.chat()
		s.advance(60)
		s.Idle.Tick()
		t.eq(#s.kicks, 0)
		t.eq(#s.toasts, 0)
	end)

	t.test("moving counts as activity; standing still with idle jitter does not", function()
		local s = setup()
		local ann = s.newPlayer("Ann")
		local bob = s.newPlayer("Bob")
		s.Idle.Start(ann)
		s.Idle.Start(bob)
		for _ = 1, 19 do
			s.advance(1 * MIN)
			ann.move(Vector3.new(ann.Character:FindFirstChild("HumanoidRootPart").Position.X + 3, 3, 0)) -- walking
			bob.move(Vector3.new(0.1, 3, 0.1)) -- breathing
			s.Idle.Tick()
		end
		t.eq(#s.kicks, 0)
		t.eq(#s.toasts, 2, "only Bob was warned: at 18 minutes, and reminded at 19")
		t.eq(s.toasts[1][1], "Bob")
		t.eq(s.toasts[2][1], "Bob")
		s.advance(1 * MIN + 1)
		ann.move(Vector3.new(500, 3, 0))
		s.Idle.Tick()
		t.eq(#s.kicks, 1)
		t.eq(s.kicks[1][1], "Bob")
	end)

	t.test("nobody is removed in their first five minutes in the world", function()
		local s = setup()
		local ann = s.newPlayer("Ann")
		s.Idle.Start(ann) -- the clock starts when they can play
		s.advance(4 * MIN + 59)
		s.Idle.Tick()
		t.eq(#s.kicks + #s.toasts, 0)
	end)

	t.test("a long load or picker before they can play is not idle time: the clock starts at Start", function()
		local s = setup()
		local later = s.newPlayer("Later")
		s.advance(60 * MIN) -- an hour on the loading card and the pickers
		s.Idle.Start(later)
		s.advance(10)
		s.Idle.Tick()
		t.eq(#s.kicks + #s.toasts, 0)
	end)

	t.test("a player the service never started is never touched", function()
		local s = setup()
		local ann = s.newPlayer("Ann")
		s.advance(60 * MIN)
		s.request(ann, "ClientReady")
		s.Idle.Tick()
		t.eq(#s.kicks + #s.toasts, 0, "still loading: not tracked, so not idle")
	end)

	t.test("stopping forgets the player, and a player who left is dropped without a kick", function()
		local s = setup()
		local ann = s.newPlayer("Ann")
		local bob = s.newPlayer("Bob")
		s.Idle.Start(ann)
		s.Idle.Start(bob)
		s.Idle.Stop(ann)
		bob.Parent = nil
		s.advance(30 * MIN)
		s.Idle.Tick()
		t.eq(#s.kicks, 0)
		t.eq(s.Idle.IsTracked(ann), false)
		t.eq(s.Idle.IsTracked(bob), false)
	end)

	t.test("Studio: off unless IdleScale is set, and then the minutes shrink", function()
		local off = setup({ studio = true })
		local ann = off.newPlayer("Ann")
		off.Idle.Start(ann)
		off.advance(60 * MIN)
		off.Idle.Tick()
		t.eq(#off.kicks, 0, "a playtest left alone is never ended")

		local fast = setup({ studio = true, studioScale = 0.01 })
		local bob = fast.newPlayer("Bob")
		fast.Idle.Start(bob)
		fast.advance(12) -- 20 minutes at 1/100 is 12 seconds
		fast.Idle.Tick()
		t.eq(#fast.kicks, 1)
	end)

	t.test(
		"wiring: GameServer starts the clock when they can play, stops it on leave, and listens for Activity",
		function()
			local fs = require("@lune/fs")
			local server = fs.readFile("src/ServerScriptService/GameServer.server.luau")
			local canPlay = string.find(server, "LoadState.PlayerCanPlay(player.Name)", 1, true)
			local start = string.find(server, "IdleService.Start(player)", 1, true)
			t.ok(canPlay ~= nil and start ~= nil and canPlay < start)
			t.ok(string.find(server, "IdleService.Stop(player)", 1, true) ~= nil)
			t.ok(string.find(server, "IdleService.Init({ notify = notify })", 1, true) ~= nil)
			t.ok(string.find(server, "remote.Activity.OnServerEvent", 1, true) ~= nil)
			local net = t.shared("Net")
			t.ok(table.find(net.RemoteNames, "Activity") ~= nil, "the remote exists")
			local limiter = fs.readFile("src/ServerScriptService/RateLimiter.luau")
			t.ok(string.find(limiter, "Activity = 2", 1, true) ~= nil, "and is rate limited")
			local ping = fs.readFile("src/StarterPlayer/StarterPlayerScripts/IdlePing.luau")
			t.ok(string.find(ping, "ButtonR2", 1, true) == nil, "no R2 binding")
			local client = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Client.client.luau")
			t.ok(string.find(client, "require(script.Parent.IdlePing)", 1, true) ~= nil, "the client starts it")
		end
	)
end
