--!nocheck
return function(t)
	local G = t.shared("GateSignLogic")

	t.test("snow: the coat protects, otherwise the words in red", function()
		local without = G.State("snow", {})
		t.eq(without.met, false)
		t.eq(without.color, G.Red)
		t.ok(string.find(without.text, "Coat", 1, true) ~= nil)
		local with = G.State("snow", { InsulatedCoat = true })
		t.eq(with.text, "Protected")
		t.eq(with.color, G.Green)
	end)

	t.test("volcano and the hollow follow their gear; the sky needs the pass", function()
		t.eq(G.State("volcano", { HeatBoots = true }).met, true)
		t.eq(G.State("volcano", { InsulatedCoat = true }).met, false)
		t.eq(G.State("grove", { Lantern = true }).text, "Protected")
		local sky = G.State("sky", {})
		t.eq(sky.met, false)
		t.ok(string.find(sky.text, "Gondola Pass", 1, true) ~= nil)
		t.eq(G.State("sky", { GondolaPass = true }).text, "Protected")
	end)

	t.test("a gate with no requirement is Open, and no sign ever shows a price", function()
		t.eq(G.State("starter", {}).text, "Open")
		t.eq(G.State("nowhere", {}).text, "Open")
		for _, id in ipairs({ "snow", "volcano", "grove", "sky" }) do
			t.ok(not string.find(G.State(id, {}).text, "$", 1, true), id .. " names no price")
		end
	end)
end
