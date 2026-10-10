--!nocheck
-- StorePrices: the client's own price (regional pricing), retried, and the
-- server never reads a price for anything a player sees (QA P7).
return function(t)
	local fs = require("@lune/fs")
	local ProductInfo = t.shared("Store/ProductInfo")

	t.test("GetProductInfoAsync when the client has it, GetProductInfo otherwise", function()
		local used = {}
		local modern = {
			GetProductInfoAsync = function(_, id)
				table.insert(used, "async " .. id)
				return { PriceInRobux = 1 }
			end,
			GetProductInfo = function(_, id)
				table.insert(used, "old " .. id)
				return { PriceInRobux = 1 }
			end,
		}
		ProductInfo.Get(modern, 7, "Pass")
		local old = {
			GetProductInfo = function(_, id)
				table.insert(used, "old " .. id)
				return {}
			end,
		}
		ProductInfo.Get(old, 8, "Product")
		t.eq(used, { "async 7", "old 8" })
	end)

	t.test("a failed lookup retries after 2, 4 and 8 seconds, then gives up", function()
		local waits, calls = {}, 0
		local flaky = {
			GetProductInfo = function()
				calls += 1
				error("HTTP 503")
			end,
		}
		local info = ProductInfo.Fetch(flaky, 1, "Pass", 4, function(s)
			table.insert(waits, s)
		end)
		t.eq(info, nil)
		t.eq(calls, 4)
		t.eq(waits, { 2, 4, 8 })
		local n = 0
		local late = {
			GetProductInfo = function()
				n += 1
				if n < 3 then
					error("busy")
				end
				return { PriceInRobux = 5 }
			end,
		}
		t.eq(ProductInfo.Fetch(late, 1, "Pass", 4, function() end).PriceInRobux, 5)
	end)

	t.test("no server code reads a price, and StorePrices is the client's only lookup", function()
		for _, path in ipairs({
			"src/ServerScriptService/BoxService.luau",
			"src/ServerScriptService/MonetizationService.luau",
			"src/ServerScriptService/StoreSaleService.luau",
		}) do
			local code = {}
			for line in string.gmatch(fs.readFile(path), "[^\n]+") do
				table.insert(code, (string.gsub(line, "%-%-.*$", "")))
			end
			local source = table.concat(code, "\n")
			t.eq(string.find(source, "PriceInRobux", 1, true), nil, path)
			t.eq(string.find(source, "GetProductInfo", 1, true), nil, path .. " goes through Store/ProductInfo")
		end
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/StoreUI.luau")
		t.eq(string.find(ui, "GetProductInfo", 1, true), nil, "StoreUI asks StorePrices")
		local hover = fs.readFile("src/StarterPlayer/StarterPlayerScripts/HoverTagUI.luau")
		t.ok(string.find(hover, "StorePrices.HoverText", 1, true) ~= nil, "the gold box tag is priced on the client")
	end)
end
