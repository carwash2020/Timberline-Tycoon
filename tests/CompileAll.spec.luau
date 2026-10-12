--!nocheck
-- Every module has to compile the way Studio compiles it. Studio does not
-- fold constants into the bytecode, so `local X = 5` takes a register there;
-- Lune's normal compile folds them away. 12 October 2026: WorldPlan had 205
-- top-level locals, compiled fine in the specs and failed in Studio ("Out of
-- local registers ... exceeded limit 200"), so MapBuilder, GameServer and
-- most of the client's world modules never loaded. Compiling at optimization
-- level 0 reproduces Studio's limits (locals, registers, upvalues, constants,
-- nesting) for every file under src, so CI catches them.
return function(t)
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")

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

	t.test("every module under src compiles with no optimization (Studio's limits)", function()
		local files = {}
		walk("src", files)
		t.ok(#files > 300, "found the source files")
		for _, path in ipairs(files) do
			local ok, err = pcall(function()
				return luau.compile(fs.readFile(path), { optimizationLevel = 0, debugLevel = 0 })
			end)
			t.ok(ok, string.format("%s does not compile: %s", path, tostring(err)))
		end
	end)
end
