--!nocheck
-- T416 item 0: no keep-out overlay (the red Scatter debug strips) exists in the built world. The overlay is
-- a preview-tool aid (tools/preview/scenes/_t414d2.luau, off unless T414_OVERLAY=1); the game never builds it.
return function(t)
	local fs = require("@lune/fs")

	local function banned(name)
		local n = string.lower(name)
		return string.find(n, "keepout", 1, true) ~= nil
			or string.find(n, "keep-out", 1, true) ~= nil
			or string.find(n, "keep_out", 1, true) ~= nil
			or string.find(n, "overlay", 1, true) ~= nil
	end

	local function offenders(root)
		local out = {}
		for _, d in ipairs(root:GetDescendants()) do
			if banned(d.Name) then
				table.insert(out, d:GetFullName())
			end
		end
		return out
	end

	t.test("no keep-out overlay part or model exists under TimberlineMap at boot", function()
		local world = t.support("WorldBuild").Get(t)
		t.ok(world.map ~= nil, "the map is built")
		local found = offenders(world.map)
		t.eq(#found, 0, "overlay instances: " .. table.concat(found, ", "))
		t.ok(world.map:FindFirstChild("Scatter") ~= nil, "the scatter is part of what was checked")
	end)

	t.test("the check does catch an overlay (control)", function()
		local m = t.roblox.Instance.new("Model")
		local lines = t.roblox.Instance.new("Model")
		lines.Name = "KeepOuts"
		lines.Parent = m
		local p = t.roblox.Instance.new("Part")
		p.Name = "Line"
		p.Parent = lines
		t.eq(#offenders(m), 1)
	end)

	local function scan(dir, hits)
		for _, entry in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				scan(path, hits)
			elseif string.match(entry, "%.luau$") then
				local src = fs.readFile(path)
				for _, pat in ipairs({ '"KeepOuts"', '"KeepOut', "'KeepOuts'", '"Overlay' }) do
					if string.find(src, pat, 1, true) then
						table.insert(hits, path .. " " .. pat)
					end
				end
			end
		end
	end

	t.test("nothing under src/ names or creates a keep-out overlay", function()
		local hits = {}
		scan("src", hits)
		t.eq(#hits, 0, table.concat(hits, "; "))
	end)

	t.test("the preview helper draws the overlay only when asked", function()
		local src = fs.readFile("tools/preview/scenes/_t414d2.luau")
		t.ok(string.find(src, 'process.env.T414_OVERLAY == "1"', 1, true) ~= nil, "gated by T414_OVERLAY")
		t.ok(string.find(src, "if process.env.T414_OVERLAY", 1, true) ~= nil)
	end)
end
