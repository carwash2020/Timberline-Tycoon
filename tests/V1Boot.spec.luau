--!nocheck
-- The v1 boot list. SecretService is Lane B's; this only reserves the name.
return function(t)
	local V1Boot = t.server("V1Boot")

	t.test("SecretService is on the boot list", function()
		local found = false
		for _, name in ipairs(V1Boot.Services) do
			if name == "SecretService" then
				found = true
			end
		end
		t.ok(found)
		t.eq(table.find(V1Boot.Services, "TradeService"), nil, "trading is not in V1")
	end)
end
