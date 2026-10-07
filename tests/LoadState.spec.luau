--!nocheck
-- LoadState: the server's start-up bookkeeping (gates, the deferred queue,
-- the loading bar's stage, and the one summary line Studio's Output is read
-- from: "[Load] ready for play at +X s; fully built at +Y s").
return function(t)
	local roblox = t.roblox

	local function setup()
		local lines = {}
		local ws = roblox.Instance.new("Folder")
		ws.Name = "Workspace"
		local clock = { now = 100 }
		local loader = t.loader({
			globals = {
				workspace = ws,
				print = function(...)
					table.insert(lines, table.concat({ ... }, " "))
				end,
				os = {
					clock = function()
						return clock.now
					end,
					time = os.time,
				},
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					wait = function() end,
				},
			},
		})
		local LoadState = loader:server("LoadState")
		clock.now = 100 -- the module's own start
		local function summary()
			for _, line in ipairs(lines) do
				if string.find(line, "ready for play at", 1, true) then
					return line
				end
			end
			return nil
		end
		return LoadState, lines, clock, ws, summary
	end

	t.test("the summary prints once, when both the first player can play and everything is built", function()
		local LoadState, lines, clock, _, summary = setup()
		LoadState.Seal()
		t.eq(summary(), nil, "nothing yet: no player")
		clock.now = 112.5
		LoadState.PlayerCanPlay("Connor")
		t.eq(LoadState.Gates.IsReady("firstPlayer"), true)
		-- The queue was already empty when sealed, so it is built at the seal.
		local ready, built = LoadState.Times()
		t.eq(ready, 12.5)
		t.ok(built ~= nil, "fully built was declared at the seal")
		t.eq(summary(), string.format("[Load] ready for play at +%.1f s; fully built at +%.1f s", ready, built))
		-- A second player changes nothing.
		clock.now = 130
		LoadState.PlayerCanPlay("Friend")
		local count = 0
		for _, line in ipairs(lines) do
			if string.find(line, "ready for play at", 1, true) then
				count += 1
			end
		end
		t.eq(count, 1)
	end)

	t.test("fully built waits for the deferred queue and for tracked background jobs", function()
		local LoadState, _, clock, _, summary = setup()
		local ranStep = false
		LoadState.Track("forest")
		LoadState.Queue.Add({
			name = "decor",
			tier = 2,
			run = function()
				ranStep = true
			end,
		})
		LoadState.Seal()
		clock.now = 105
		LoadState.PlayerCanPlay("Connor")
		t.eq(summary(), nil, "the forest and the queue are not done: not fully built")
		LoadState.Queue.Start() -- (task.spawn is synchronous here)
		t.eq(ranStep, true)
		t.eq(summary(), nil, "the forest is still planting")
		clock.now = 160
		LoadState.Finish("forest")
		local ready, built = LoadState.Times()
		t.eq(ready, 5)
		t.eq(built, 60)
		t.eq(summary(), "[Load] ready for play at +5.0 s; fully built at +60.0 s")
		t.eq(LoadState.Gates.IsReady("deferred"), true)
	end)

	t.test("fully built can come first: the line waits for the first player", function()
		local LoadState, _, clock, _, summary = setup()
		clock.now = 110
		LoadState.Seal()
		t.eq(summary(), nil)
		clock.now = 140
		LoadState.PlayerCanPlay("Connor")
		t.eq(summary(), "[Load] ready for play at +40.0 s; fully built at +10.0 s")
	end)

	t.test("Stage only moves the loading bar forward and says so in the Output", function()
		local LoadState, lines, _, ws = setup()
		LoadState.Stage("terrain")
		t.eq(ws:GetAttribute("LoadStage"), "terrain")
		LoadState.Stage("town")
		LoadState.Stage("terrain")
		t.eq(ws:GetAttribute("LoadStage"), "town", "never back")
		LoadState.Stage("world")
		t.eq(ws:GetAttribute("LoadStage"), "world")
		local staged = 0
		for _, line in ipairs(lines) do
			if string.find(line, "] +", 1, true) and string.find(line, " stage ", 1, true) then
				staged += 1
			end
		end
		t.ok(staged >= 3, "a [Load] line per stage")
	end)

	t.test("the queue's lines carry when each step finished", function()
		local LoadState, lines = setup()
		LoadState.Queue.Add({
			name = "NPC Millie",
			tier = 1,
			run = function() end,
		})
		LoadState.Queue.Start()
		local found = false
		for _, line in ipairs(lines) do
			if
				string.find(line, "[Load] deferred NPC Millie took", 1, true)
				and string.find(line, "(done at +", 1, true)
			then
				found = true
			end
		end
		t.ok(found)
	end)

	t.test("the gates the start-up uses exist from the start", function()
		local LoadState = setup()
		for _, name in ipairs({ "meshes", "terrain", "town", "world", "services", "firstPlayer", "npcs", "deferred" }) do
			t.eq(LoadState.Gates.IsReady(name), false, name .. " starts shut")
		end
		LoadState.Gates.Set("world")
		t.eq(LoadState.Gates.IsReady("world"), true)
	end)
end
