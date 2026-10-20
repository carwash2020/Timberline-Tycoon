--!nocheck
-- BandLogic (T398): which bark gets the cream band and which the ink one.
return function(t)
	local BandLogic = t.shared("BandLogic")
	local WoodData = t.shared("WoodData")

	local function rgb(c)
		return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
	end

	t.test("ink is SignInk and cream is SignCream", function()
		t.eq(rgb(BandLogic.Ink), { 0x2A, 0x24, 0x20 })
		t.eq(rgb(BandLogic.Cream), { 0xF3, 0xE7, 0xC9 })
	end)

	t.test("luminance runs from 0 (black) to 1 (white)", function()
		t.ok(BandLogic.Luminance(t.roblox.Color3.fromRGB(0, 0, 0)) < 1e-9)
		t.ok(math.abs(BandLogic.Luminance(t.roblox.Color3.fromRGB(255, 255, 255)) - 1) < 1e-6)
	end)

	t.test("the dark barks get cream and the light and mid barks get ink", function()
		local dark = { "emberwood", "phantomwood", "ironwood", "cherry" }
		local light = { "oak", "frostwood", "birch", "pine", "maple", "palmwood", "lumenwood", "bogcypress", "willow" }
		for _, id in ipairs(dark) do
			local wood = WoodData.Get(id)
			t.ok(BandLogic.IsDark(wood.trunkColor), id .. " is dark")
			t.eq(rgb(BandLogic.ColorFor(wood.trunkColor)), { 0xF3, 0xE7, 0xC9 }, id)
		end
		for _, id in ipairs(light) do
			local wood = WoodData.Get(id)
			t.ok(not BandLogic.IsDark(wood.trunkColor), id .. " is not dark")
			t.eq(rgb(BandLogic.ColorFor(wood.trunkColor)), { 0x2A, 0x24, 0x20 }, id)
		end
		t.eq(rgb(BandLogic.ColorFor(nil)), { 0x2A, 0x24, 0x20 }, "unknown bark: ink")
	end)
end
