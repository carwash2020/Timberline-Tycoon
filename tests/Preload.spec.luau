--!nocheck
-- T415 preload: ContentProvider:PreloadAsync only for the first view (the player's axe, Murph, the spawn
-- town's buildings), never the whole manifest, and never more than PerfPolicy.PreloadCap ids.
return function(t)
	local PerfPolicy = t.shared("PerfPolicy")
	local FirstView = t.load("ReplicatedStorage/Shared/FirstView")
	local MeshManifest = t.load("ReplicatedStorage/Shared/Art/MeshManifest")
	local fs = require("@lune/fs")

	t.test("the cap is a fixed number", function()
		t.eq(type(PerfPolicy.PreloadCap), "number")
		t.ok(PerfPolicy.PreloadCap > 0 and PerfPolicy.PreloadCap <= 200)
	end)

	t.test("the first-view list is at or under the cap, unique, and not empty", function()
		local list = FirstView.List()
		t.ok(#list > 0)
		t.ok(#list <= PerfPolicy.PreloadCap, #list .. " ids")
		local seen = {}
		for _, id in ipairs(list) do
			t.ok(string.match(id, "^rbxassetid://%d+$"), id)
			t.ok(not seen[id], "duplicate " .. id)
			seen[id] = true
		end
	end)

	t.test("every id in it belongs to a first-view group", function()
		local allowed = {}
		for _, group in ipairs(MeshManifest.Groups(true)) do
			if table.find(FirstView.Groups, group.name) then
				for _, e in ipairs(group.entries) do
					allowed["rbxassetid://" .. e.id] = true
				end
			end
		end
		for _, id in ipairs(FirstView.List()) do
			t.ok(allowed[id], id .. " is not in a first-view group")
		end
		for _, name in ipairs({ "npcs", "trees", "kit", "machines", "vehicles", "items" }) do
			t.eq(table.find(FirstView.Groups, name), nil, name .. " is not first view")
		end
	end)

	t.test("the client preloads that list through ContentProvider, capped, and tells the loading screen", function()
		local boot = fs.readFile("src/StarterPlayer/StarterPlayerScripts/FirstViewPreload.client.luau")
		t.ok(string.find(boot, "FirstView.List", 1, true))
		t.ok(string.find(boot, "PreloadAsync", 1, true))
		t.ok(string.find(boot, "FirstViewReady", 1, true))
		local screen = fs.readFile("src/ReplicatedFirst/LoadingScreen.client.luau")
		t.ok(string.find(screen, "FirstViewReady", 1, true))
		t.ok(string.find(screen, "PRELOAD_WAIT", 1, true), "the wait has a limit")
	end)

	t.test("no other client ContentProvider:PreloadAsync takes a world list", function()
		local found = {}
		local function walk(dir)
			for _, name in ipairs(fs.readDir(dir)) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					walk(path)
				elseif
					string.sub(name, -5) == ".luau"
					and string.find(fs.readFile(path), "ContentProvider", 1, true)
					and string.find(fs.readFile(path), "PreloadAsync", 1, true)
				then
					table.insert(found, path)
				end
			end
		end
		walk("src")
		table.sort(found)
		t.eq(found, {
			"src/ReplicatedStorage/Shared/ColorMapGuard.luau",
			"src/StarterPlayer/StarterPlayerScripts/FirstViewPreload.client.luau",
			"src/StarterPlayer/StarterPlayerScripts/UIArt.luau",
		})
	end)
end
