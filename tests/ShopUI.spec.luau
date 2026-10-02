--!nocheck
-- The shop screens' copy (ShopUI's three shops and StoreUI's Robux Store):
-- every subtitle reads in full on a phone, where it gets two lines of the
-- narrowest panel (UI-19), so none is longer than ShopUI.SubtitleMax.
return function(t)
	local fs = require("@lune/fs")
	local dir = "src/StarterPlayer/StarterPlayerScripts/"
	local MAX = 40 -- ShopUI.SubtitleMax

	t.test("every shop subtitle is 40 characters at most", function()
		local shop = fs.readFile(dir .. "ShopUI.luau")
		t.ok(string.find(shop, "ShopUI.SubtitleMax = " .. MAX, 1, true), "the limit the screens state")
		local found = 0
		for _, file in ipairs({ "ShopUI.luau", "StoreUI.luau" }) do
			local source = fs.readFile(dir .. file)
			for text in string.gmatch(source, '\n\tsubtitle = "([^"]*)"') do
				found += 1
				t.ok(utf8.len(text) <= MAX, string.format("%s: %q is %d long", file, text, utf8.len(text)))
				t.ok(#text > 0, file .. ": a subtitle")
			end
		end
		t.eq(found, 4, "the Tool Shed, the Dealership, Hearth & Home and the Store")
	end)
end
