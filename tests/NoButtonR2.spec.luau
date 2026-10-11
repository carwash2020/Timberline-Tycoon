--!nocheck
-- The right trigger belongs to the engine: Roblox fires Tool.Activated for the
-- equipped tool on it by itself, and a ContextActionService bind (or any read
-- that sinks it) breaks chopping on Xbox. So the source never BINDS it and
-- never names it, with exactly one exception: the pad's grab READS it, only
-- with empty hands (GrabLogic.PadGrabAllowed), and that one use is the single
-- constant GrabLogic.PadGrabKey. Every other file, comment or string that
-- names the button fails this spec, and so does a second use anywhere.
return function(t)
	local fs = require("@lune/fs")

	local ALLOWED_FILE = "src/ReplicatedStorage/Shared/GrabLogic.luau"
	local ALLOWED_LINE = "GrabLogic.PadGrabKey = Enum.KeyCode.ButtonR2"

	local function walk(dir: string, out: { string })
		for _, entry in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				walk(path, out)
			elseif string.match(entry, "%.luau?$") or string.match(entry, "%.json$") then
				table.insert(out, path)
			end
		end
	end

	-- A name split across a concatenation would slip past a plain search, so
	-- squash `"Button" .. "R2"` style joins and whitespace before looking.
	local function squash(text: string): string
		local joined = string.gsub(text, "[\"'%]%[]%s*%.%.%s*[\"'%[]", "")
		return (string.gsub(joined, "%s+", ""))
	end

	local function count(text: string, needle: string): number
		local n, from = 0, 1
		while true do
			local at = string.find(text, needle, from, true)
			if not at then
				return n
			end
			n += 1
			from = at + #needle
		end
	end

	local function sources(): { [string]: string }
		local files: { string } = {}
		walk("src", files)
		t.ok(#files > 100, "the scan found the source tree (" .. #files .. " files)")
		local out = {}
		for _, path in ipairs(files) do
			out[path] = fs.readFile(path)
		end
		return out
	end

	t.test("no file under src/ names ButtonR2 except the one grab constant", function()
		local offenders: { string } = {}
		for path, text in pairs(sources()) do
			local plain = count(text, "ButtonR2")
			local joined = count(squash(text), "ButtonR2")
			if path == ALLOWED_FILE then
				-- Exactly the constant's line, once, with no hidden joins.
				if plain ~= 1 or joined ~= 1 or not string.find(text, ALLOWED_LINE, 1, true) then
					table.insert(offenders, path .. " (more than the one allowed use)")
				end
			elseif plain > 0 or joined > 0 then
				table.insert(offenders, path)
			end
		end
		table.sort(offenders)
		t.eq(offenders, {}, "ButtonR2 is named once, as GrabLogic.PadGrabKey, and nowhere else")
	end)

	t.test("the grab key is read, never bound, anywhere", function()
		local offenders: { string } = {}
		for path, text in pairs(sources()) do
			for line in string.gmatch(text, "[^\n]+") do
				local names = string.find(line, "PadGrabKey", 1, true) or string.find(line, "ButtonR2", 1, true)
				local binds = string.find(line, "BindAction", 1, true)
					or string.find(line, "BindActivate", 1, true)
					or string.find(line, "ContextActionService", 1, true)
				if names and binds then
					table.insert(offenders, path .. ": " .. line)
				end
			end
		end
		t.eq(offenders, {}, "no ContextActionService bind takes the right trigger")
	end)

	t.test("the grab is DragController's only use, and it checks for a tool first", function()
		local drag = fs.readFile("src/StarterPlayer/StarterPlayerScripts/DragController.luau")
		t.ok(string.find(drag, "GrabLogic.PadGrabKey", 1, true), "DragController reads the key from GrabLogic")
		local reads = string.find(drag, "input.KeyCode == GrabLogic.PadGrabKey", 1, true)
		local allowed = string.find(drag, "GrabLogic.PadGrabAllowed(toolOut(char)", 1, true)
		local grabs = string.find(drag, 'grab("pad", nil)', 1, true)
		t.ok(
			reads and allowed and grabs and reads < allowed and allowed < grabs,
			"the tool check comes before the grab"
		)
		-- Nothing but DragController reads it as input.
		local users: { string } = {}
		for path, text in pairs(sources()) do
			if
				string.find(text, "GrabLogic.PadGrabKey", 1, true)
				and path ~= "src/ReplicatedStorage/Shared/GrabLogic.luau"
			then
				table.insert(users, path)
			end
		end
		table.sort(users)
		t.eq(users, {
			"src/ReplicatedStorage/Shared/InputKit.luau",
			"src/StarterPlayer/StarterPlayerScripts/DragController.luau",
		}, "only the drag controller (and the key table InputKit lists it in)")
	end)

	t.test("the gamepad actions sit where they should", function()
		local InputKit = t.shared("InputKit")
		local function padOf(binds, action)
			for _, bind in ipairs(binds) do
				if bind.action == action then
					return bind.gamepad and bind.gamepad.Name
				end
			end
			return nil
		end
		t.eq(padOf(InputKit.WireBinds, "Pick"), "ButtonR1", "wire pick stays on RB")
		t.eq(padOf(InputKit.Target.drag, "Grab"), "ButtonR2", "the pad grab is the right trigger (empty hands)")
		t.eq(padOf(InputKit.Target.placer, "Place"), "ButtonA")
	end)
end
