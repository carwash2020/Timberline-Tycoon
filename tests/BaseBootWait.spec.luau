--!nocheck
-- "[BaseBoot] no Remotes folder" (Connor's Studio log, 12 October 2026).
-- GameServer is what creates ReplicatedStorage.Remotes, and it starts only
-- when MapBuilder's SellArea appears (it waits up to 600 s for it). BaseBoot
-- started with the server and waited 60 s for the folder. With a 300 s world
-- build the folder did not exist yet at +60 s, BaseBoot gave up, and SaveNow
-- and PaintAllType were never bound. The name and the parent were right; the
-- wait was shorter than the build. Fix: BaseBoot waits as long as GameServer
-- does (Net.RemotesWaitSeconds). Source-level, since a boot script runs on
-- require and cannot be driven from here.
return function(t)
	local fs = require("@lune/fs")
	local Net = t.shared("Net")

	local function code(path: string): string
		return (string.gsub(fs.readFile(path), "%-%-[^\n]*", ""))
	end

	t.test("the Remotes folder is the one GameServer makes: same name, same parent", function()
		local game = code("src/ServerScriptService/GameServer.server.luau")
		t.ok(string.find(game, 'remotes.Name = "Remotes"', 1, true), "GameServer names it Remotes")
		t.ok(string.find(game, "remotes.Parent = ReplicatedStorage", 1, true), "under ReplicatedStorage")
		local boot = code("src/ServerScriptService/BaseBoot.server.luau")
		t.ok(string.find(boot, 'ReplicatedStorage:WaitForChild("Remotes"', 1, true), "BaseBoot looks for the same")
	end)

	t.test("BaseBoot waits at least as long as GameServer waits for the world", function()
		local game = code("src/ServerScriptService/GameServer.server.luau")
		local worldWait = tonumber(string.match(game, 'WaitForChild%("SellArea", (%d+)%)'))
		t.ok(worldWait, "found GameServer's wait for the world")
		t.ok(
			Net.RemotesWaitSeconds >= worldWait,
			"BaseBoot's wait ("
				.. Net.RemotesWaitSeconds
				.. " s) must out-last the world build wait ("
				.. worldWait
				.. " s)"
		)
		local boot = code("src/ServerScriptService/BaseBoot.server.luau")
		t.ok(
			string.find(boot, 'WaitForChild("Remotes", Net.RemotesWaitSeconds)', 1, true),
			"BaseBoot uses the shared wait, not a number of its own"
		)
		t.ok(not string.find(boot, 'WaitForChild("Remotes", 60)', 1, true), "the 60 s wait is gone")
		-- The 12 October build took 300 s; the old wait gave up at 60.
		t.ok(Net.RemotesWaitSeconds > 300)
	end)

	t.test("no other server script waits on the Remotes folder for less than the world build", function()
		local function walk(dir, out)
			for _, entry in ipairs(fs.readDir(dir)) do
				local path = dir .. "/" .. entry
				if fs.isDir(path) then
					walk(path, out)
				elseif string.match(entry, "%.luau$") then
					table.insert(out, path)
				end
			end
		end
		local files = {}
		walk("src/ServerScriptService", files)
		for _, path in ipairs(files) do
			if not string.find(path, "/Vendor/", 1, true) then
				for seconds in string.gmatch(code(path), 'WaitForChild%("Remotes", (%d+)%)') do
					t.ok(tonumber(seconds) >= 600, path .. " waits only " .. seconds .. " s for the Remotes folder")
				end
			end
		end
	end)
end
