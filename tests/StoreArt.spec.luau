--!nocheck
-- Store card pictures: every consumer shows the Roblox image ids through
-- the asset thumbnail URL, which renders any image-like asset. Nothing here
-- claims the thumbnails render; that needs Roblox (scripts/check-store-icons.ps1).
return function(t)
	local fs = require("@lune/fs")
	local StoreArt = t.shared("StoreArt")
	local StoreData = t.shared("StoreData")

	local function code(path)
		local out = {}
		for line in string.gmatch(fs.readFile(path), "[^\n]+") do
			table.insert(out, (string.gsub(line, "%-%-.*$", "")))
		end
		return table.concat(out, "\n")
	end

	t.test("ImageFor builds the rbxthumb Asset URL at the asked size", function()
		t.eq(StoreArt.ImageFor(91282142796474, 150), "rbxthumb://type=Asset&id=91282142796474&w=150&h=150")
		t.eq(StoreArt.ImageFor(79037897236948), "rbxthumb://type=Asset&id=79037897236948&w=150&h=150")
		t.eq(StoreArt.ImageFor(71028498113750, StoreArt.Large), "rbxthumb://type=Asset&id=71028498113750&w=420&h=420")
	end)

	t.test("a 0 or bad id gives no image", function()
		t.eq(StoreArt.ImageFor(0), "")
		t.eq(StoreArt.ImageFor(-5), "")
		t.eq(StoreArt.ImageFor(1.5), "")
		t.eq(StoreArt.ImageFor(nil), "")
		t.eq(StoreArt.ImageFor(0 / 0), "")
	end)

	t.test("every nonzero StoreData image gives a thumbnail URL, every zero gives none", function()
		local nonzero = 0
		for _, list in ipairs({ StoreData.Passes, StoreData.Products }) do
			for _, item in ipairs(list) do
				local url = StoreArt.ImageFor(item.image, StoreArt.Small)
				if item.image > 0 then
					nonzero += 1
					t.eq(url, string.format("rbxthumb://type=Asset&id=%d&w=150&h=150", item.image), item.key)
				else
					t.eq(url, "", item.key)
				end
			end
		end
		t.eq(nonzero, 9, "all nine rows carry an image id")
	end)

	t.test("no store image is built as a raw rbxassetid:// URL", function()
		for _, path in ipairs({
			"src/StarterPlayer/StarterPlayerScripts/StoreUI.luau",
			"src/ReplicatedStorage/Shared/StoreBoard.luau",
			"src/ReplicatedStorage/Shared/StoreData.luau",
			"src/ReplicatedStorage/Shared/StoreArt.luau",
		}) do
			t.ok(not string.find(code(path), "rbxassetid", 1, true), path .. " has a raw rbxassetid")
		end
		for _, path in ipairs({
			"src/StarterPlayer/StarterPlayerScripts/StoreUI.luau",
			"src/ReplicatedStorage/Shared/StoreBoard.luau",
		}) do
			t.ok(string.find(code(path), "StoreArt.ImageFor(item.image", 1, true), path .. " uses the helper")
		end
	end)

	t.test("the letter or mark fallback is still reachable", function()
		local ui = code("src/StarterPlayer/StarterPlayerScripts/StoreUI.luau")
		t.ok(string.find(ui, 'result == "Failure"', 1, true), "a failed load")
		t.ok(string.find(ui, "mark.Visible = true", 1, true), "shows the mark again")
		t.ok(string.find(ui, 'disc.Image = ""', 1, true), "an id of 0 keeps the mark")
		local board = code("src/ReplicatedStorage/Shared/StoreBoard.luau")
		t.ok(string.find(board, 'disc.Image = ""', 1, true), "board id 0 keeps the glyph")
		t.ok(string.find(board, '"Glyph"', 1, true), "board glyph")
	end)
end
