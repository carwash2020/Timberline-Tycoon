--!nocheck
-- The Robux store icons (Connor's image uploads, 12 October 2026): which row
-- carries which image id, that setting an image never puts a row on sale or
-- reveals a hidden one, and that Connor's PowerShell check lists them all.
-- Not claimed here: that each id renders the right picture or has cleared
-- moderation. That needs Roblox; scripts/check-store-icons.ps1 checks it.
return function(t)
	local fs = require("@lune/fs")
	local StoreData = t.shared("StoreData")
	local StoreSale = t.shared("Store/StoreSale")

	local EXPECT = {
		Pass = { DoubleCash = 129566569237407, LuxAxe = 80267879981455 },
		Product = {
			Cash1k = 95950318286949,
			Cash10k = 102370875631166,
			DoubleWood = 83265240736148,
			InstantDelivery = 96661273504040,
		},
	}

	t.test("each of the six rows carries exactly its image id", function()
		for kind, keys in pairs(EXPECT) do
			for key, id in pairs(keys) do
				local item = if kind == "Pass" then StoreData.Pass(key) else StoreData.Product(key)
				t.eq(item.image, id, key)
			end
		end
	end)

	t.test("no image id appears on two rows, and every id is well formed", function()
		local seen = {}
		for _, entry in ipairs(StoreData.Ordered()) do
			local id = entry.item.image
			t.eq(type(id), "number", entry.key)
			t.eq(id % 1, 0, entry.key .. " whole number")
			t.ok(id >= 10 ^ 9 and id < 10 ^ 16, entry.key .. " 10 to 16 digits")
			t.ok(not seen[id], "image id on two rows: " .. tostring(id) .. " (" .. entry.key .. ")")
			seen[id] = entry.key
		end
	end)

	t.test("the $1,000 and $10,000 game passes are not store rows", function()
		for _, entry in ipairs(StoreData.Ordered()) do
			t.ok(entry.item.id ~= 2005844842 and entry.item.id ~= 2004962887, entry.key)
			t.ok(entry.item.image ~= entry.item.id, entry.key .. " image is not its own Creator Hub id")
		end
	end)

	t.test("an image never changes what is on sale: ids and off-sale rows are as before", function()
		t.eq(StoreData.CreatorIds.Products.DoubleWood, 0)
		t.eq(StoreData.CreatorIds.Products.InstantDelivery, 0)
		t.eq(StoreData.CreatorIds.Passes.TowService, 0)
		t.eq(StoreData.CreatorIds.Passes.TimberClassic, 0)
		t.eq(StoreData.CreatorIds.Passes.PaintShop, 0)
		t.eq(#StoreData.ListedPasses(), 2)
		t.eq(#StoreData.ListedProducts(), 2)
		for _, key in ipairs({ "DoubleWood", "InstantDelivery" }) do
			local p = StoreData.Product(key)
			t.ok(p.image > 0, key .. " has its picture")
			t.eq(StoreData.IsForSale(p.id), false, key .. " has no id")
			t.eq(StoreData.ProductById(p.id), nil, key .. " cannot be bought or granted")
			-- Roblox saying "for sale" still cannot sell a row with no id.
			for _, answer in ipairs({ true, false }) do
				local state = StoreSale.CardState(p, { robloxForSale = answer })
				t.ok(state == "Soon" or state == "Hidden", key .. " stays a non-buyable card: " .. state)
			end
		end
		for _, key in ipairs({ "TowService", "TimberClassic", "PaintShop" }) do
			local p = StoreData.Pass(key)
			t.eq(StoreData.PassById(p.id), nil, key .. " has no purchase path")
			local state = StoreSale.CardState(p, { robloxForSale = true })
			t.ok(state == "Soon" or state == "Hidden", key .. " not buyable: " .. state)
		end
	end)

	t.test("the older three store images stay on their own rows", function()
		t.eq(StoreData.Pass("TowService").image, 91282142796474)
		t.eq(StoreData.Pass("TimberClassic").image, 79037897236948)
		t.eq(StoreData.Pass("PaintShop").image, 71028498113750)
	end)

	t.test("check-store-icons.ps1 lists all six ids with their rows, is read-only and opens nothing", function()
		local ps = fs.readFile("scripts/check-store-icons.ps1")
		local rowName = {
			[129566569237407] = "2x Cash",
			[80267879981455] = "Lux Axe",
			[95950318286949] = "Small Cash Pack",
			[102370875631166] = "Large Cash Pack",
			[83265240736148] = "2x Wood",
			[96661273504040] = "Instant Delivery",
		}
		for id, name in pairs(rowName) do
			t.ok(string.find(ps, tostring(id), 1, true) ~= nil, "script lists " .. tostring(id))
			t.ok(string.find(ps, name, 1, true) ~= nil, "script names row " .. name)
		end
		t.ok(string.find(ps, "thumbnails.roblox.com/v1/assets", 1, true) ~= nil)
		t.ok(string.find(ps, "size=420x420", 1, true) ~= nil)
		t.ok(string.find(ps, "STORE-ICONS-CHECK.md", 1, true) ~= nil)
		t.ok(string.find(ps, "tell the build agent which pair", 1, true) ~= nil, "swap note")
		for _, state in ipairs({ "Completed", "Pending", "Blocked", "InReview" }) do
			t.ok(string.find(ps, state, 1, true) ~= nil, state)
		end
		for _, bad in ipairs({ "Start-Process", "Invoke-Item", "Remove-Item", "Invoke-WebRequest -Method Post" }) do
			t.ok(string.find(ps, bad, 1, true) == nil, "script must not use " .. bad)
		end
		for kind, keys in pairs(EXPECT) do
			for key in pairs(keys) do
				local item = if kind == "Pass" then StoreData.Pass(key) else StoreData.Product(key)
				t.ok(string.find(ps, tostring(item.image), 1, true) ~= nil, key .. " id in script matches the game")
			end
		end
	end)
end
