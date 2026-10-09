--!nocheck
-- Palette: every shared colour has the hex from the V1 pack.
return function(t)
	local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")
	local Kit = t.load("ReplicatedStorage/Shared/Art/Kit")

	local HEX = {
		MeadowGrass = "#64B838",
		DeepMeadow = "#529E30",
		TrailDirt = "#8E6C4A",
		WetMud = "#5A4A3E",
		ShoreSand = "#D8C69A",
		CliffRock = "#7E766C",
		FreshSnow = "#EEF3F7",
		BlueIce = "#A9D3E6",
		AshBasalt = "#3A3433",
		QuarrySlate = "#5B5650",
		LavaGlow = "#FF6A1E",
		TownCobble = "#9C958A",
		RoadGravel = "#A8A49C",
		PavedRoad = "#55585A",
		TimberBrown = "#7A5230",
		PlankHoney = "#C49A63",
		WeatheredPlank = "#9C8466",
		BarnRed = "#9E3B2E",
		PineTrim = "#2F5D3A",
		RoofSlate = "#4A4F57",
		StoneBase = "#8C877E",
		IronBlack = "#2B2B2E",
		Brass = "#C9A24A",
		SignCream = "#F3E7C9",
		SignInk = "#2A2420",
		CoinGold = "#F2C14E",
		SaleGreen = "#4CC36A",
		StopRed = "#D9534F",
		SkyBlue = "#6FB7E8",
		FrostGlow = "#BFE3F2",
		EmberGlow = "#FF7A1A",
		GloamGlow = "#7A4FD0",
		LumenGlow = "#FFF4C2",
		StarfallGlow = "#BFD8FF",
		SparkTeal = "#3FC9C0",
	}

	t.test("every palette name is the pack hex", function()
		local seen = {}
		for _, name in ipairs(Palette.Names()) do
			seen[name] = true
			t.eq(Palette.Hex(name), HEX[name], name)
			t.eq(Palette.Get(name), Kit.hex(HEX[name]), name .. " color")
			t.eq(Palette[name], Kit.hex(HEX[name]), name .. " field")
		end
		for name in pairs(HEX) do
			t.eq(seen[name], true, name .. " is listed")
		end
		t.eq(#Palette.Names(), 35)
	end)

	t.test("an unknown name fails", function()
		t.fails(function()
			Palette.Get("NotAColor")
		end, "unknown")
	end)
end
