--!nocheck
-- No Robux number is ever written in the game: every price is Roblox's,
-- read live on the player's client. Store words live in StoreCopy.
return function(t)
	local fs = require("@lune/fs")
	local StoreCopy = t.shared("Store/StoreCopy")

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

	t.test("no digits next to R$ or Robux in any string in src/", function()
		local hits = {}
		for _, path in ipairs(walk("src", {})) do
			if not string.find(path, "/Vendor/", 1, true) then
				local source = fs.readFile(path)
				for line in string.gmatch(source, "[^\n]+") do
					local code = string.gsub(line, "%-%-.*$", "")
					for str in string.gmatch(code, '"([^"]*)"') do
						if
							string.find(str, "R%$%s*%d")
							or string.find(str, "%d%s*R%$")
							or string.find(str, "%d+%s*[Rr]obux")
							or string.find(str, "[Rr]obux%s*%d")
						then
							table.insert(hits, path .. ": " .. str)
						end
					end
				end
			end
		end
		t.eq(hits, {})
	end)

	t.test("the pill says only R$ until Roblox's price is back, then that one number", function()
		t.eq(StoreCopy.Price(nil), "R$")
		t.eq(StoreCopy.Price(0 / 0), "R$")
		t.eq(StoreCopy.Price(149), "R$ 149")
		t.eq(StoreCopy.Soon, "Coming soon")
		t.eq(StoreCopy.NotForSale, "That isn't for sale yet.")
		t.eq(StoreCopy.NoAnswer, "Roblox's store didn't answer. Try again in a moment.")
	end)

	t.test("no gifting or trading words anywhere in the store", function()
		local files = {
			"src/ReplicatedStorage/Shared/Store/StoreCopy.luau",
			"src/ReplicatedStorage/Shared/StoreData.luau",
			"src/StarterPlayer/StarterPlayerScripts/StoreUI.luau",
			"src/ServerScriptService/MonetizationService.luau",
		}
		for _, path in ipairs(files) do
			local source = string.lower(fs.readFile(path))
			t.eq(string.find(source, "giftpurchase", 1, true), nil, path)
			t.eq(string.find(source, "tradeservice", 1, true), nil, path)
			t.eq(string.find(source, "promptgamepasspurchase(%s*[%w_]+%s*,%s*[%w_]+%s*,"), nil, path)
		end
	end)
end
