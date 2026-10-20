--!strict
-- BandLogic (T398): the colour of the thin cut-preview band. Dark ink on a
-- light or mid bark, light cream on a dark bark, so the line always reads.

local BandLogic = {}

BandLogic.Ink = Color3.fromRGB(0x2A, 0x24, 0x20) -- SignInk #2A2420
BandLogic.Cream = Color3.fromRGB(0xF3, 0xE7, 0xC9) -- SignCream #F3E7C9
-- A bark is "dark" when its relative luminance (0 black .. 1 white) is below
-- this. Cherry (0.051), emberwood, ironwood and phantomwood fall under it;
-- bogcypress (0.074), pine, frostwood (0.086) and oak stay over.
BandLogic.DarkBelow = 0.06

local function linear(c: number): number
	if c <= 0.04045 then
		return c / 12.92
	end
	return ((c + 0.055) / 1.055) ^ 2.4
end

-- WCAG relative luminance of a colour, 0 to 1.
function BandLogic.Luminance(c: Color3): number
	return 0.2126 * linear(c.R) + 0.7152 * linear(c.G) + 0.0722 * linear(c.B)
end

function BandLogic.IsDark(bark: Color3): boolean
	return BandLogic.Luminance(bark) < BandLogic.DarkBelow
end

-- The band colour for a bark; an unknown bark gets the ink.
function BandLogic.ColorFor(bark: Color3?): Color3
	if bark ~= nil and BandLogic.IsDark(bark) then
		return BandLogic.Cream
	end
	return BandLogic.Ink
end

return BandLogic
