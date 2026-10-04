--!nocheck
-- Planting, the seed pouch and the grove meter are gone from the live
-- tree. These tokens must not come back in the game, its tests, its
-- tools, or the design and economy write-ups.
return function(t)
	local fs = require("@lune/fs")

	local needles = {
		"Heart" .. "seed",
		"Plant" .. "Seed",
		"Seeds" .. "_",
		"Vitality" .. "_",
	}

	local function walk(path: string, out: { string })
		if not fs.isDir(path) then
			table.insert(out, path)
			return
		end
		for _, name in ipairs(fs.readDir(path)) do
			if name ~= ".git" then
				walk(path .. "/" .. name, out)
			end
		end
	end

	local function hits(text: string): string?
		for _, needle in ipairs(needles) do
			local at = string.find(text, needle, 1, true)
			if at then
				local line = 1
				for i = 1, at do
					if string.sub(text, i, i) == "\n" then
						line += 1
					end
				end
				return needle .. " at line " .. line
			end
		end
		return nil
	end

	t.test("no planting leftovers in the live tree, tests, tools or the economy write-ups", function()
		local files = {}
		walk("src", files)
		walk("tests", files)
		walk("tools", files)
		table.insert(files, "GAME_DESIGN.md")
		table.insert(files, "ECONOMY.md")
		table.insert(files, "ECONOMY_V1.md")
		local bad = {}
		for _, path in ipairs(files) do
			if string.sub(path, -6) == ".luau" or string.sub(path, -3) == ".md" or string.sub(path, -4) == ".lua" then
				local found = hits(fs.readFile(path))
				if found then
					table.insert(bad, path .. ": " .. found)
				end
			end
		end
		t.eq(bad, {}, table.concat(bad, "\n"))
	end)
end
