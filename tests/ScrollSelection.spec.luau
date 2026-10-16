--!nocheck
-- Every ScrollingFrame the client builds hides the gamepad's selection box
-- (UITheme.HiddenSelection): the engine's default box is panel-sized and drew
-- a rectangle over whole scrolling lists. Every way of creating one is caught,
-- anywhere under src/: Instance.new("ScrollingFrame") (either quote, typed or
-- untyped local, a module-level or field assignment), a creation that is not
-- assigned to a name (it cannot be checked, so it fails), and a function that
-- returns a ScrollingFrame (the file must set the property somewhere). A
-- creation that really wants the default goes on the allow-list, with a reason.
return function(t)
	local fs = require("@lune/fs")
	-- "path/File.luau:variable" or "path/File.luau" -> reason
	local ALLOW = {}

	local function walk(dir, out)
		for _, name in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path, out)
			elseif string.match(name, "%.luau$") then
				table.insert(out, path)
			end
		end
		return out
	end

	local function assignedName(line)
		return string.match(line, "^%s*local%s+([%w_]+)%s*:[^=]-=%s*Instance%.new%(")
			or string.match(line, "^%s*local%s+([%w_]+)%s*=%s*Instance%.new%(")
			or string.match(line, "^%s*([%w_%.]+)%s*=%s*Instance%.new%(")
	end

	t.test("every ScrollingFrame creation hides the selection box, however it is assigned", function()
		local seen = 0
		for _, path in ipairs(walk("src", {})) do
			local src = fs.readFile(path)
			if string.find(src, "ScrollingFrame", 1, true) and not ALLOW[path] then
				for line in string.gmatch(src, "[^\n]+") do
					if string.find(line, "Instance%.new%(%s*[\"']ScrollingFrame[\"']") then
						seen += 1
						local var = assignedName(line)
						t.ok(var ~= nil, path .. ": a ScrollingFrame that is not assigned to a name: " .. line)
						if var and not ALLOW[path .. ":" .. var] then
							local pattern = string.gsub(var, "%.", "%%.")
								.. "%.SelectionImageObject%s*=%s*UITheme%.HiddenSelection%(%)"
							t.ok(
								string.find(src, pattern) ~= nil,
								path .. ": " .. var .. " keeps the default selection box"
							)
						end
					end
				end
				-- A helper that returns a ScrollingFrame builds one somewhere: the
				-- file must set the property.
				if string.find(src, "%)%s*:%s*ScrollingFrame%s*\n") then
					t.ok(
						string.find(src, "SelectionImageObject", 1, true) ~= nil,
						path .. ": returns a ScrollingFrame but never sets SelectionImageObject"
					)
				end
			end
		end
		t.ok(seen >= 10, "found the ScrollingFrames (" .. seen .. ")")
	end)

	t.test("the checker itself: a creation without the property is caught", function()
		t.eq(assignedName('\tlocal list: ScrollingFrame = Instance.new("ScrollingFrame")'), "list")
		t.eq(assignedName('\tbody = Instance.new("ScrollingFrame")'), "body")
		t.eq(assignedName('\tself.list = Instance.new("ScrollingFrame")'), "self.list")
		t.eq(assignedName('\tparentIt(Instance.new("ScrollingFrame"))'), nil)
	end)
end
