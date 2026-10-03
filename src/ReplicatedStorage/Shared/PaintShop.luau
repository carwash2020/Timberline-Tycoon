--!strict
-- Paint Shop: the cosmetic truck colors a pass owner may apply.
-- The server clamps every request to this palette. Nothing here changes
-- speed, capacity or price.

local ItemCatalog = require(script.Parent.ItemCatalog)

local PaintShop = {}

PaintShop.Cooldown = 2 -- seconds between accepted color changes

-- Fixed swatches. A request for any other color is refused.
PaintShop.Palette = {
	"#8E3B2F",
	"#2F6DB5",
	"#3E6B3A",
	"#E6D3A3",
	"#4A4F57",
	"#C4A46A",
	"#F4F1EA",
	"#2A2A2A",
}

export type Request = {
	ownsPass: boolean,
	ownsTruck: boolean,
	callerUserId: number,
	ownerUserId: number,
	color: unknown,
	now: number,
	lastAt: number?,
}

function PaintShop.Normalize(color: unknown): string?
	if type(color) ~= "string" then
		return nil
	end
	local hex = string.match(color, "^%s*(#%x%x%x%x%x%x)%s*$")
	if not hex then
		return nil
	end
	return string.upper(hex)
end

function PaintShop.InPalette(color: string): boolean
	for _, swatch in ipairs(PaintShop.Palette) do
		if swatch == color then
			return true
		end
	end
	return false
end

-- Drops anything that isn't a catalog truck painted in a palette color.
function PaintShop.Sanitize(raw: any): { [string]: string }
	local out: { [string]: string } = {}
	if type(raw) ~= "table" then
		return out
	end
	for key, value in pairs(raw) do
		local color = PaintShop.Normalize(value)
		if type(key) == "string" and ItemCatalog.GetTruck(key) and color and PaintShop.InPalette(color) then
			out[key] = color
		end
	end
	return out
end

-- ok, and either the normalized color or why not.
-- A player can paint only their own truck, only from the palette, and
-- at most once per Cooldown.
function PaintShop.Decide(req: Request): (boolean, string)
	if req.ownsPass ~= true then
		return false, "You need the Paint Shop pass."
	end
	if req.callerUserId ~= req.ownerUserId or req.ownsTruck ~= true then
		return false, "That's not your truck."
	end
	local color = PaintShop.Normalize(req.color)
	if not color or not PaintShop.InPalette(color) then
		return false, "Pick a color from the Paint Shop palette."
	end
	if type(req.lastAt) == "number" and req.now - req.lastAt < PaintShop.Cooldown then
		return false, "Give the paint a moment."
	end
	return true, color
end

return PaintShop
