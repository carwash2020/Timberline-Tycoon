--!nocheck
-- The right trigger belongs to the engine: Roblox fires Tool.Activated for the
-- equipped tool on it by itself, and a ContextActionService bind (or any read
-- that sinks it) breaks chopping on Xbox. So no file under src/ may name the
-- button at all: not a bind, not an InputBegan read, not a key table, not a
-- string, not a comment. Extra gamepad actions live on RB (ButtonR1), X, A.
-- There is no exemption list; this scans every file.
return function(t)
	local fs = require("@lune/fs")

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

	t.test("no file under src/ names ButtonR2", function()
		local files: { string } = {}
		walk("src", files)
		t.ok(#files > 100, "the scan found the source tree (" .. #files .. " files)")
		local offenders: { string } = {}
		for _, path in ipairs(files) do
			local text = fs.readFile(path)
			if string.find(text, "ButtonR2", 1, true) or string.find(squash(text), "ButtonR2", 1, true) then
				table.insert(offenders, path)
			end
		end
		table.sort(offenders)
		t.eq(offenders, {}, "ButtonR2 is never bound, read or listed")
	end)

	t.test("the gamepad actions that used the trigger sit on RB or A", function()
		local InputKit = t.shared("InputKit")
		local function padOf(binds, action)
			for _, bind in ipairs(binds) do
				if bind.action == action then
					return bind.gamepad and bind.gamepad.Name
				end
			end
			return nil
		end
		t.eq(padOf(InputKit.WireBinds, "Pick"), "ButtonR1")
		t.eq(padOf(InputKit.Target.drag, "Grab"), "ButtonR1")
		t.eq(padOf(InputKit.Target.placer, "Place"), "ButtonA")
	end)
end
