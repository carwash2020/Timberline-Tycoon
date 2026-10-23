--!nocheck
-- T421 palette pins (Connor): the trailer coupler is #B0241C. The Timber Classic's trim and rims are #5A3B26 and stay so;
-- that colour is baked into its GLB (the part-built Classic has cream rims in code), so there is nothing in code to pin
-- for it and no code recolours it.
return function(t)
	local roblox = t.roblox
	local TruckArt = t.load("ReplicatedStorage/Shared/Art/TruckArt")
	local TruckLayout = t.shared("TruckLayout")
	local ItemCatalog = t.shared("ItemCatalog")

	t.test("the coupler token is #B0241C and every built trailer's Coupler wears it", function()
		t.eq(TruckArt.CouplerColor, roblox.Color3.fromHex("#B0241C"))
		local n = 0
		for _, truck in ipairs(ItemCatalog.TruckList()) do
			if truck.look.bedLength <= 0 then
				continue
			end
			local lay = TruckLayout.For(truck)
			for _, trailer in ipairs(ItemCatalog.TrailerList()) do
				local model = TruckArt.Build(truck, lay, trailer, TruckLayout.ForTrailer(trailer, lay))
				local coupler = model:FindFirstChild("Coupler", true)
				t.ok(coupler ~= nil, truck.id .. " + " .. trailer.id .. " has a coupler")
				t.eq(coupler.Color, roblox.Color3.fromHex("#B0241C"), truck.id .. " + " .. trailer.id)
				n += 1
			end
		end
		t.eq(n, 15)
	end)

	t.test("the tail lamps' red is the same #B0241C", function()
		t.eq(TruckArt.TaillightColor, roblox.Color3.fromHex("#B0241C"))
	end)
end
