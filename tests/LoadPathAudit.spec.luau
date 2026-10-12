--!nocheck
-- The load and spawn path, read from the source (12 October 2026, "Ensure any
-- loading bugs have been fixed"). Studio cannot run here; these stop a gap
-- that costs a player a 90 s wait, a fall or a stuck card from coming back.
return function(t)
	local fs = require("@lune/fs")
	local JoinFlow = t.shared("JoinFlow")

	local function walk(dir, out)
		for _, name in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path, out)
			elseif string.sub(name, -5) == ".luau" then
				table.insert(out, path)
			end
		end
		return out
	end
	local function has(text, needle)
		return string.find(text, needle, 1, true) ~= nil
	end

	local game = fs.readFile("src/ServerScriptService/GameServer.server.luau")
	local map = fs.readFile("src/ServerScriptService/MapBuilder.server.luau")

	t.test("every first-player gate is opened by a statement that no failed step can skip", function()
		local server = ""
		for _, path in ipairs(walk("src/ServerScriptService", {})) do
			server ..= fs.readFile(path) .. "\n"
		end
		for _, gate in ipairs(JoinFlow.FirstPlayerGates) do
			t.ok(has(server, 'Gates.Set("' .. gate .. '")'), gate .. " has a setter")
		end
		-- MapBuilder's gates sit at the top level, after the step() calls (which xpcall their body).
		for _, gate in ipairs({ "terrain", "town", "world" }) do
			t.ok(
				has(map, '\nLoadState.Gates.Set("' .. gate .. '")'),
				gate .. " is set at the top level, not inside a step"
			)
		end
		-- GameServer's: not inside safely() either.
		for _, gate in ipairs({ "plots", "murph", "services" }) do
			t.ok(has(game, '\nLoadState.Gates.Set("' .. gate .. '")'), gate .. " is set at the top level")
		end
	end)

	t.test("the world gate is not opened before the spawn pad exists", function()
		local pad = string.find(map, 'spawn.Name = "SpawnLocation"', 1, true)
		local town = string.find(map, '\nLoadState.Gates.Set("town")', 1, true)
		local world = string.find(map, '\nLoadState.Gates.Set("world")', 1, true)
		t.ok(pad and town and world and pad < town and town < world, "pad, then town gate, then world gate")
		t.ok(has(map, "spawn.Anchored = true"), "the pad is anchored")
	end)

	t.test("only GameServer loads characters, and nothing else touches the spawn before the world", function()
		for _, path in ipairs(walk("src", {})) do
			if not has(path, "Vendor") and not has(path, "GameServer.server.luau") then
				local text = fs.readFile(path)
				t.ok(not has(text, ":LoadCharacter"), path .. " does not load characters")
				t.ok(not has(text, "CharacterAutoLoads = true"), path .. " does not turn auto-loads on")
			end
		end
	end)

	t.test(
		"a dead character is streamed for and put on its pad again, and a fall below the world is a put-back",
		function()
			t.ok(has(game, "VoidRescue.new()"), "every character is watched for the void")
			t.ok(has(game, "task.spawn(watchForVoid"), "from onCharacterAdded")
			t.ok(has(game, "character:PivotTo(pad.CFrame"), "it is moved, not killed")
			local died = string.find(game, "humanoid.Died:Connect", 1, true)
			local stream = died and string.find(game, "streamAroundSpawn(player)", died, true)
			local load = stream and string.find(game, "loadCharacter(player)", stream, true)
			t.ok(died and stream and load, "the respawn streams the spawn area, then loads")
		end
	)

	t.test("nothing between the save and the character can end the join", function()
		-- These ran bare; an error ended onPlayerAdded before enterWorld, so the player never got a character.
		t.ok(has(game, 'safely("equipped truck"'), "the equipped truck is guarded")
		t.ok(has(game, 'safely("settings and pending cash"'), "settings and pending cash are guarded")
		local enter = string.find(game, "pcall(enterWorld", 1, true)
		t.ok(
			enter and has(game, "the join flow failed; loading the character anyway"),
			"a failed flow still loads the character"
		)
	end)
end
