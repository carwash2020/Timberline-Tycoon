--!nocheck
-- Scripts may not write the player's own game settings: setting
-- UserGameSettings.MouseSensitivity or GamepadCameraSensitivity logs
-- "Insufficient permissions" on every join. So no file under src/ may name
-- either property (not a write, a read, a string key, or a comment). The
-- Camera speed row was dropped for this (see SettingsUI); the saved
-- settings.cameraSensitivity field is a different name and stays.
return function(t)
	local fs = require("@lune/fs")

	local function walk(dir: string, out: { string })
		for _, entry in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				walk(path, out)
			elseif string.match(entry, "%.luau?$") then
				table.insert(out, path)
			end
		end
	end

	-- Squash `"Mouse" .. "Sensitivity"` style joins and whitespace first.
	local function squash(text: string): string
		local joined = string.gsub(text, "[\"'%]%[]%s*%.%.%s*[\"'%[]", "")
		return (string.gsub(joined, "%s+", ""))
	end

	t.test("no source writes UserGameSettings MouseSensitivity or GamepadCameraSensitivity", function()
		local files: { string } = {}
		walk("src", files)
		t.ok(#files > 100, "the scan found the source tree (" .. #files .. " files)")
		local offenders: { string } = {}
		for _, path in ipairs(files) do
			local text = fs.readFile(path)
			local flat = squash(text)
			for _, name in ipairs({ "MouseSensitivity", "GamepadCameraSensitivity" }) do
				if string.find(text, name, 1, true) or string.find(flat, name, 1, true) then
					table.insert(offenders, path .. " names " .. name)
				end
			end
		end
		table.sort(offenders)
		t.eq(offenders, {}, "the engine camera speed is never written")
	end)
end
