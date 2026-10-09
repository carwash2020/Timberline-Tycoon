--!strict
-- Palette: one name for every colour the town shares. Art modules ask for
-- a name (Palette.TimberBrown, or Palette.Get) instead of typing a hex.
-- SpecBuild rows use the same names. Pure: Kit.hex only, no instances.

local Kit = require(script.Parent.Kit)

local Palette = {}

local HEX: { [string]: string } = {
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

function Palette.Hex(name: string): string
	local h = HEX[name]
	if h == nil then
		error("unknown palette color " .. name, 2)
	end
	return h
end

function Palette.Get(name: string): Color3
	return Kit.hex(Palette.Hex(name))
end

function Palette.Names(): { string }
	local names: { string } = {}
	for name in pairs(HEX) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

Palette.MeadowGrass = Kit.hex(HEX.MeadowGrass)
Palette.DeepMeadow = Kit.hex(HEX.DeepMeadow)
Palette.TrailDirt = Kit.hex(HEX.TrailDirt)
Palette.WetMud = Kit.hex(HEX.WetMud)
Palette.ShoreSand = Kit.hex(HEX.ShoreSand)
Palette.CliffRock = Kit.hex(HEX.CliffRock)
Palette.FreshSnow = Kit.hex(HEX.FreshSnow)
Palette.BlueIce = Kit.hex(HEX.BlueIce)
Palette.AshBasalt = Kit.hex(HEX.AshBasalt)
Palette.QuarrySlate = Kit.hex(HEX.QuarrySlate)
Palette.LavaGlow = Kit.hex(HEX.LavaGlow)
Palette.TownCobble = Kit.hex(HEX.TownCobble)
Palette.RoadGravel = Kit.hex(HEX.RoadGravel)
Palette.PavedRoad = Kit.hex(HEX.PavedRoad)
Palette.TimberBrown = Kit.hex(HEX.TimberBrown)
Palette.PlankHoney = Kit.hex(HEX.PlankHoney)
Palette.WeatheredPlank = Kit.hex(HEX.WeatheredPlank)
Palette.BarnRed = Kit.hex(HEX.BarnRed)
Palette.PineTrim = Kit.hex(HEX.PineTrim)
Palette.RoofSlate = Kit.hex(HEX.RoofSlate)
Palette.StoneBase = Kit.hex(HEX.StoneBase)
Palette.IronBlack = Kit.hex(HEX.IronBlack)
Palette.Brass = Kit.hex(HEX.Brass)
Palette.SignCream = Kit.hex(HEX.SignCream)
Palette.SignInk = Kit.hex(HEX.SignInk)
Palette.CoinGold = Kit.hex(HEX.CoinGold)
Palette.SaleGreen = Kit.hex(HEX.SaleGreen)
Palette.StopRed = Kit.hex(HEX.StopRed)
Palette.SkyBlue = Kit.hex(HEX.SkyBlue)
Palette.FrostGlow = Kit.hex(HEX.FrostGlow)
Palette.EmberGlow = Kit.hex(HEX.EmberGlow)
Palette.GloamGlow = Kit.hex(HEX.GloamGlow)
Palette.LumenGlow = Kit.hex(HEX.LumenGlow)
Palette.StarfallGlow = Kit.hex(HEX.StarfallGlow)
Palette.SparkTeal = Kit.hex(HEX.SparkTeal)

return Palette
