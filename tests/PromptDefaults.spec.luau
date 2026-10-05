--!nocheck
-- Every ProximityPrompt in src gets a gamepad key: PromptDefaults, or an
-- explicit GamepadKeyCode before the next prompt.
return function(t)
	local fs = require("@lune/fs")

	local function window(src, at)
		local nxt = string.find(src, 'Instance.new("ProximityPrompt")', at + 10, true)
		local stop = if nxt then nxt - 1 else #src
		local lines = 0
		for pos = at, stop do
			if string.sub(src, pos, pos) == "\n" then
				lines += 1
				if lines >= 40 then
					stop = pos
					break
				end
			end
		end
		return string.sub(src, at, stop)
	end

	local function bare(src)
		local misses = {}
		local i = 1
		while true do
			local at = string.find(src, 'Instance.new("ProximityPrompt")', i, true)
			if not at then
				break
			end
			local slice = window(src, at)
			local covered = string.find(slice, "PromptDefaults", 1, true)
				or string.find(slice, ".GamepadKeyCode", 1, true)
			if not covered then
				table.insert(misses, at)
			end
			i = at + 10
		end
		return misses
	end

	local function walk(dir, out)
		for _, name in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path, out)
			elseif string.sub(name, -5) == ".luau" then
				table.insert(out, path)
			end
		end
	end

	t.test("a prompt with no gamepad key fails the scan", function()
		local src = [[
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Chop"
			prompt.Parent = part
		]]
		t.eq(#bare(src), 1)
		local fixed = src .. '\nInputKit.PromptDefaults(prompt, "Interact")\n'
		t.eq(#bare(fixed), 0)
	end)

	t.test("every prompt in src has a gamepad key", function()
		local files = {}
		walk("src", files)
		local bad = {}
		for _, path in ipairs(files) do
			local misses = bare(fs.readFile(path))
			if #misses > 0 then
				table.insert(bad, path .. " (" .. tostring(#misses) .. ")")
			end
		end
		t.eq(bad, {})
	end)
end
