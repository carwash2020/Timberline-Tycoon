--!nocheck
-- Every ScrollingFrame the client builds hides the gamepad's selection box
-- (UITheme.HiddenSelection): the engine's default box is panel-sized and drew
-- a rectangle over whole scrolling lists. A creation that really wants the
-- default goes on the allow-list, with a reason.
return function(t)
	local fs = require("@lune/fs")
	local ALLOW = {} -- file name -> reason

	t.test("every ScrollingFrame creation sets SelectionImageObject", function()
		local dir = "src/StarterPlayer/StarterPlayerScripts"
		local seen = 0
		for _, name in ipairs(fs.readDir(dir)) do
			if string.match(name, "%.luau$") and ALLOW[name] == nil then
				local src = fs.readFile(dir .. "/" .. name)
				for var in string.gmatch(src, 'local ([%w_]+) = Instance%.new%("ScrollingFrame"%)') do
					seen += 1
					local pattern = var .. "%.SelectionImageObject%s*=%s*UITheme%.HiddenSelection%(%)"
					t.ok(string.find(src, pattern) ~= nil, name .. ": " .. var .. " keeps the default selection box")
				end
			end
		end
		t.ok(seen >= 10, "found the ScrollingFrames (" .. seen .. ")")
	end)
end
