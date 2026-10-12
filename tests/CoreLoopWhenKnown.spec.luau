--!nocheck
-- Connor's Studio log (12 October 2026): "[Load] client ChopSawController
-- Start took 8.03s" and "SawmillController Start took 8.02s". Those Starts
-- polled for the CoreLoopActive attribute with task.wait (8 to 120 s); the
-- server had not published it (MapBuilder sets it after its requires, and
-- never when one of them fails). A Start must not yield: and after the wait
-- ran out the controller decided for the v1 loop for good, even if the
-- attribute arrived a second later. CoreLoop.WhenKnown fixes both.
return function(t)
	local fs = require("@lune/fs")
	local CoreLoop = t.shared("CoreLoop")

	-- A stand-in for workspace: attributes and their changed signals.
	local function fakeRoot()
		local attrs = {}
		local listeners = {}
		local root = {}
		function root:GetAttribute(name)
			return attrs[name]
		end
		function root:GetAttributeChangedSignal(name)
			return {
				Connect = function(_, fn)
					local conn = { live = true }
					function conn:Disconnect()
						self.live = false
					end
					listeners[name] = listeners[name] or {}
					table.insert(listeners[name], { fn = fn, conn = conn })
					return conn
				end,
			}
		end
		local function set(name, value)
			attrs[name] = value
			for _, l in ipairs(listeners[name] or {}) do
				if l.conn.live then
					l.fn()
				end
			end
		end
		local function live(name)
			local n = 0
			for _, l in ipairs(listeners[name] or {}) do
				if l.conn.live then
					n += 1
				end
			end
			return n
		end
		return root, set, live
	end

	t.test("WhenKnown runs at once when the loop is already published, with no connection left", function()
		local root, set, live = fakeRoot()
		set(CoreLoop.ActiveAttribute, 2)
		local ran = 0
		CoreLoop.WhenKnown(function()
			ran += 1
		end, root)
		t.eq(ran, 1)
		t.eq(live(CoreLoop.ActiveAttribute), 0)
	end)

	t.test("WhenKnown returns at once while the loop is unknown, and runs once when it lands, however late", function()
		local root, set, live = fakeRoot()
		local ran = 0
		local started = os.clock()
		CoreLoop.WhenKnown(function()
			ran += 1
		end, root)
		t.ok(os.clock() - started < 0.5, "it did not wait")
		t.eq(ran, 0, "not before the server says")
		t.eq(live(CoreLoop.ActiveAttribute), 1)
		set("SomethingElse", 1)
		t.eq(ran, 0, "other attributes do not count")
		set(CoreLoop.ActiveAttribute, 2)
		t.eq(ran, 1)
		set(CoreLoop.ActiveAttribute, 1)
		t.eq(ran, 1, "only once")
		t.eq(live(CoreLoop.ActiveAttribute), 0, "and the connection is gone")
	end)

	t.test("WhenKnown ignores the attribute being cleared", function()
		local root, set = fakeRoot()
		local ran = 0
		CoreLoop.WhenKnown(function()
			ran += 1
		end, root)
		set(CoreLoop.ActiveAttribute, nil)
		t.eq(ran, 0)
		set(CoreLoop.ActiveAttribute, 1)
		t.eq(ran, 1)
	end)

	local function code(path: string): string
		return (string.gsub(fs.readFile(path), "%-%-[^\n]*", ""))
	end

	t.test("no client module polls for CoreLoopActive with task.wait in a Start", function()
		local dir = "src/StarterPlayer/StarterPlayerScripts"
		local polled = {}
		for _, entry in ipairs(fs.readDir(dir)) do
			if string.match(entry, "%.luau$") then
				local source = code(dir .. "/" .. entry)
				if
					string.find(source, "GetAttribute%(CoreLoop%.ActiveAttribute%) == nil and")
					or string.find(source, "ActiveAttribute%) == nil and waited")
				then
					table.insert(polled, entry)
				end
			end
		end
		t.eq(polled, {}, "these still poll (use CoreLoop.WhenKnown): " .. table.concat(polled, ", "))
	end)

	t.test("the seven loop-dependent controllers start through WhenKnown", function()
		for _, name in ipairs({
			"ChopSawController",
			"SawmillController",
			"CarryController",
			"ChopController",
			"DragController",
			"CutController",
			"WoodFX",
		}) do
			local source = code("src/StarterPlayer/StarterPlayerScripts/" .. name .. ".luau")
			t.ok(string.find(source, "CoreLoop.WhenKnown(startLoop)", 1, true), name .. " uses WhenKnown")
		end
	end)

	-- The same log: ForgeUI waited 60 s for the Remotes folder, QuestUI 30 s
	-- for Murph, but a new server takes 300 s to build the world. The wait
	-- must outlast the build, or the Forge never opens and the card has no face.
	t.test("client waits for server-made things outlast the world build", function()
		local Net = t.shared("Net")
		t.ok(Net.RemotesWaitSeconds > 300)
		local forge = code("src/StarterPlayer/StarterPlayerScripts/ForgeUI.luau")
		t.ok(
			string.find(forge, 'WaitForChild("Remotes", Net.RemotesWaitSeconds)', 1, true),
			"ForgeUI waits for the Remotes folder as long as the server may take"
		)
		t.ok(not string.find(forge, 'WaitForChild("Remotes", 60)', 1, true), "the 60 s wait is gone")
		local quest = code("src/StarterPlayer/StarterPlayerScripts/QuestUI.luau")
		t.ok(string.find(quest, "QuestUI.PortraitWait = 600", 1, true))
		t.ok(not string.find(quest, 'WaitForChild("Murph", 30)', 1, true), "Murph's portrait waits past the build")
		t.ok(not string.find(quest, 'WaitForChild("TimberlineMap", 30)', 1, true))
	end)

	t.test("the loading card does not depend on a bare require of its sibling", function()
		local card = code("src/ReplicatedFirst/LoadingScreen.client.luau")
		local waits = string.find(card, 'WaitForChild("LoadingTips"', 1, true)
		local requires = string.find(card, "require(script.Parent.LoadingTips)", 1, true)
		local guard = string.find(card, "pcall(function()", 1, true)
		t.ok(waits and requires and guard, "waits for it, then requires it, inside a pcall")
		t.ok(guard < waits and waits < requires, "in that order")
	end)
end
