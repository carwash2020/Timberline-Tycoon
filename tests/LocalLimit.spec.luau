--!nocheck
-- Luau compiles at most 200 local variables in scope at once; the 201st is
-- "Out of local registers ... exceeded limit 200", a load error that Studio
-- reports but Lune's compile did not (12 October 2026: WorldPlan had 205
-- top-level locals, so MapBuilder, GameServer and the client's world modules
-- all failed to load and the server stuck at "Starting the server 2%").
-- This counts the top-level `local` lines of every module and keeps a margin.
return function(t)
	local fs = require("@lune/fs")
	local Limit = 190 -- Luau's hard limit is 200 (top-level locals plus a few temporaries)

	local function walk(dir: string, out: { string })
		for _, name in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path, out)
			elseif string.sub(name, -5) == ".luau" then
				table.insert(out, path)
			end
		end
	end

	t.test("no module has more top-level locals than the Luau limit allows", function()
		local files = {}
		walk("src", files)
		t.ok(#files > 100, "found the source files")
		for _, path in ipairs(files) do
			local count = 0
			for line in string.gmatch(fs.readFile(path), "[^\n]+") do
				if string.sub(line, 1, 6) == "local " then
					count += 1
				end
			end
			t.ok(count <= Limit, string.format("%s has %d top-level locals (limit %d)", path, count, Limit))
		end
	end)
end
