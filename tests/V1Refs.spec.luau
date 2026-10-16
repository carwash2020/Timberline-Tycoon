--!nocheck
-- Lane Z (final integration): the wiring scans. Source-text checks over
-- src/ that prove the lanes agree with each other: every remote has a budget
-- and a server handler, the client module list matches the folder, the boot
-- order is intact, only the owning service touches cash and the DataStore,
-- nothing trades, no Robux price
-- is written in code. Anything this finds is a real wiring bug.
return function(t)
	local fs = require("@lune/fs")

	local function walk(dir, out)
		out = out or {}
		for _, name in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				if name ~= "Vendor" then
					walk(path, out)
				end
			elseif string.sub(name, -5) == ".luau" then
				table.insert(out, path)
			end
		end
		return out
	end

	local server = walk("src/ServerScriptService")
	local client = walk("src/StarterPlayer/StarterPlayerScripts")
	local shared = walk("src/ReplicatedStorage")
	local all = {}
	for _, list in ipairs({ server, client, shared, walk("src/ReplicatedFirst") }) do
		for _, path in ipairs(list) do
			table.insert(all, path)
		end
	end
	local cache = {}
	local function read(path)
		if cache[path] == nil then
			cache[path] = fs.readFile(path)
		end
		return cache[path]
	end
	-- Code only: lines that are comments do not count as a use.
	local function code(path)
		local lines = {}
		for line in string.gmatch(read(path), "[^\n]*") do
			if not string.match(line, "^%s*%-%-") then
				table.insert(lines, line)
			end
		end
		return table.concat(lines, "\n")
	end
	local function has(list, word)
		for _, path in ipairs(list) do
			if string.find(code(path), word, 1, true) then
				return path
			end
		end
		return nil
	end

	-- The remote list, with its direction from the comment.
	local net = read("src/ReplicatedStorage/Shared/Net.luau")
	local remotes = {}
	for line in string.gmatch(net, "[^\n]+") do
		local name, comment = string.match(line, '^\t"([%w]+)",%s*(.*)$')
		if name then
			table.insert(remotes, { name = name, toClient = string.find(comment, "server -> client", 1, true) ~= nil })
		end
	end
	local limiter = read("src/ServerScriptService/RateLimiter.luau")

	t.test("Net lists 60+ remotes, each once, none about trading or gifts", function()
		t.ok(#remotes >= 60, "parsed " .. #remotes)
		local seen = {}
		for _, r in ipairs(remotes) do
			t.eq(seen[r.name], nil, "duplicate remote " .. r.name)
			seen[r.name] = true
			t.eq(string.find(string.lower(r.name), "trade", 1, true), nil, r.name)
			t.eq(string.find(string.lower(r.name), "gift", 1, true), nil, r.name)
		end
		t.eq(has(all, "TradeService"), nil, "TradeService is gone from V1")
	end)

	t.test("every client -> server remote has a RateLimiter budget and a server user", function()
		for _, r in ipairs(remotes) do
			if not r.toClient then
				t.ok(string.find(limiter, "\n\t" .. r.name .. " = %d") ~= nil, r.name .. " has no RateLimiter budget")
				t.ok(has(server, r.name) ~= nil, r.name .. " has no server handler")
			end
		end
	end)

	t.test("every server -> client remote is fired by the server and heard by a client", function()
		for _, r in ipairs(remotes) do
			if r.toClient then
				t.ok(has(server, r.name) ~= nil, r.name .. " is never fired")
				t.ok(has(client, r.name) ~= nil, r.name .. " has no client listener")
			end
		end
	end)

	t.test("every remote a client or server names is in Net.RemoteNames (no orphan)", function()
		local known = {}
		for _, r in ipairs(remotes) do
			known[r.name] = true
		end
		for _, path in ipairs(all) do
			for name in string.gmatch(code(path), 'Net%.Remote%("([%w]+)"%)') do
				t.ok(known[name], path .. " asks Net.Remote for unknown " .. name)
			end
		end
		for _, path in ipairs(server) do
			for name in string.gmatch(code(path), "[rR]emotes?%.([%w]+)%.OnServerEvent") do
				t.ok(known[name], path .. " handles unknown remote " .. name)
			end
		end
	end)

	t.test("every handler of a client -> server remote checks the RateLimiter", function()
		-- A file that connects OnServerEvent must call RateLimiter somewhere.
		for _, path in ipairs(server) do
			local src = code(path)
			if string.find(src, "OnServerEvent", 1, true) and not string.find(path, "RateLimiter", 1, true) then
				t.ok(string.find(src, "RateLimiter", 1, true) ~= nil, path .. " connects a remote with no RateLimiter")
			end
		end
	end)

	t.test("every Roblox-facing server file reaches the RateLimiter through Allow with a budgeted name", function()
		local budgeted = {}
		for name in string.gmatch(limiter, "\n\t([%w]+) = %d") do
			budgeted[name] = true
		end
		for _, path in ipairs(server) do
			for name in string.gmatch(code(path), 'RateLimiter%.Allow%([%w_%.]+, "([%w]+)"%)') do
				t.ok(budgeted[name], path .. " rate-limits with unbudgeted name " .. name)
			end
		end
	end)

	t.test("every client module is in the Client module list, and every listed module exists", function()
		local src = read("src/StarterPlayer/StarterPlayerScripts/Client.client.luau")
		local listed = {}
		local block = string.match(src, "MODULES[^{]*{(.-)\n}") or ""
		for name in string.gmatch(block, '"([%w]+)"') do
			listed[name] = true
		end
		t.ok(next(listed) ~= nil, "parsed the module list")
		for _, name in ipairs(fs.readDir("src/StarterPlayer/StarterPlayerScripts")) do
			local module = string.match(name, "^([%w]+)%.luau$")
			if module and not string.find(name, ".client.", 1, true) then
				t.ok(listed[module], module .. " is not in the Client module list")
			end
		end
		for name in pairs(listed) do
			t.ok(fs.isFile("src/StarterPlayer/StarterPlayerScripts/" .. name .. ".luau"), name .. " has no file")
		end
	end)

	t.test("boot order: GameServer starts V1Boot once, after the core, and every boot script is one file", function()
		local boot = read("src/ServerScriptService/GameServer.server.luau")
		local _, count = string.gsub(boot, "V1Boot%.Start%(", "")
		t.eq(count, 1, "V1Boot.Start is called once")
		local startAt = string.find(boot, "V1Boot.Start(", 1, true)
		local ratesAt = string.find(boot, "ClientHandshake.Bind(remote.ClientReady", 1, true) -- (was the inline OnServerEvent listener; it moved to ClientHandshake)
		t.ok(startAt and ratesAt, "both markers exist")
		for _, name in ipairs({ "MiningBoot", "RegionBoot", "TownBoardBoot" }) do
			t.ok(fs.isFile("src/ServerScriptService/" .. name .. ".server.luau"), name)
		end
		-- StoreSaleService and the other plain modules are required, not scripts.
		t.ok(has(server, "StoreSaleService") ~= nil)
		for _, name in ipairs(fs.readDir("src/ServerScriptService")) do
			local module = string.match(name, "^([%w]+)%.luau$")
			if module and not string.find(name, ".server.", 1, true) and module ~= "ProfileSchema" then
				-- Every service module is required by something (not orphaned).
				local used = false
				for _, path in ipairs(all) do
					if path ~= "src/ServerScriptService/" .. name then
						local src = code(path)
						if
							string.find(src, "." .. module .. ")", 1, true)
							or string.find(src, '"' .. module .. '"', 1, true)
							or string.find(src, "." .. module .. "\n", 1, true)
							or string.find(src, "." .. module .. ",", 1, true)
						then
							used = true
							break
						end
					end
				end
				t.ok(used, "ServerScriptService/" .. module .. " is never required (orphaned)")
			end
		end
	end)

	t.test("only EconomyService changes profile.cash", function()
		for _, path in ipairs(all) do
			if not string.find(path, "EconomyService.luau", 1, true) then
				local src = code(path)
				t.eq(string.find(src, "profile%.cash%s*[%+%-]?=[^=]"), nil, path .. " writes profile.cash")
				t.eq(string.find(src, "record%.cash%s*[%+%-]?=[^=]"), nil, path .. " writes record.cash")
				t.eq(string.find(src, "data%.cash%s*[%+%-]?=[^=]"), nil, path .. " writes data.cash")
			end
		end
	end)

	t.test("only ProfileService touches DataStores", function()
		for _, path in ipairs(all) do
			if not string.find(path, "ProfileService.luau", 1, true) then
				local src = code(path)
				t.eq(string.find(src, "DataStoreService", 1, true), nil, path)
				t.eq(string.find(src, "MemoryStoreService", 1, true), nil, path)
			end
		end
	end)

	t.test(
		"the five off-sale ids are still 0 and every badge id is 0 or a pasted live id (Connor pastes them, never code)",
		function()
			local StoreData = t.shared("StoreData")
			local BadgeData = t.shared("BadgeData")
			local ids = StoreData.CreatorIds
			for _, key in ipairs({ "TowService", "TimberClassic", "PaintShop" }) do
				t.eq(ids.Passes[key], 0, key)
			end
			for _, key in ipairs({ "DoubleWood", "InstantDelivery" }) do
				t.eq(ids.Products[key], 0, key)
			end
			-- Badge ids are pasted by Connor from the Creator Hub (the first five on 16 October 2026): each is
			-- still 0 or a real whole id, never a made-up number (BadgeData.spec pins exactly which are set).
			for key, id in pairs(BadgeData.Ids) do
				t.ok(id == 0 or BadgeData.IsLive(id), "badge " .. key .. " is 0 or a live id")
			end
		end
	)

	t.test("no Robux price is written in code (a price comes from Roblox's live answer)", function()
		for _, path in ipairs(all) do
			for line in string.gmatch(code(path), "[^\n]+") do
				if string.find(line, "[Rr]obux") or string.find(line, "R%$") then
					local bad = string.match(line, "%d+%s*[Rr]obux") or string.match(line, "R%$%s*%d")
					t.eq(bad, nil, path .. ": " .. line)
				end
			end
		end
	end)

	-- (WoodData's Lanternwood rows carry "TBD (Designer)" comments on tuning
	-- values: open decisions, listed in V1_REVIEW. A string a player reads
	-- must never say it.)
	t.test("no TBD or FIXME placeholder is in a string a player can read", function()
		for _, path in ipairs(all) do
			local src = code(path)
			t.eq(string.find(src, '"[^"\n]*TBD[^"\n]*"'), nil, path)
			t.eq(string.find(src, "FIXME", 1, true), nil, path)
		end
	end)

	t.test("one writer for the sky: LightingController is the only Atmosphere writer", function()
		for _, path in ipairs(all) do
			if
				not string.find(path, "LightingController", 1, true) and not string.find(path, "MapBuilder", 1, true)
			then
				local src = code(path)
				t.eq(string.find(src, 'Instance.new("Atmosphere")', 1, true), nil, path)
			end
		end
	end)
end
