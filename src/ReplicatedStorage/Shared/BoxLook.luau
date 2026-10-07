--!strict
-- BoxLook: the colours of a shop box and of the block it stands on. Pure.
--
-- Connor (7 October 2026, from Lumber Tycoon 2): "I want our boxes to reflect
-- closer to this". An LT2 box is a dark, near-black solid with the item seen
-- through a window, and the shop's display case stands each item on a solid
-- colour block. So a box is charcoal and carries ONE accent colour for what
-- it holds, and the same colour is the block it stands on in the shop
-- (ShopInterior) and the band on its name strip (BoxArt).
--
-- The accent is the category's, except an axe, which takes its TIER colour
-- (the same grey, blue, gold, violet, fire as the axe itself), and the
-- machines, which split into sawmill, planer, belt and the rest.

local BoxLook = {}

-- The dark body of every box (Robux boxes use a dark gold instead).
BoxLook.Charcoal = Color3.fromRGB(34, 36, 41)
BoxLook.CharcoalGold = Color3.fromRGB(64, 48, 18)
BoxLook.Gold = Color3.fromRGB(227, 183, 60)
BoxLook.Light = Color3.fromRGB(245, 245, 240) -- the name on a dark accent
BoxLook.Ink = Color3.fromRGB(28, 28, 32) -- the name on a light accent

-- One accent per kind of goods.
BoxLook.Categories = {
	Axe = Color3.fromRGB(214, 69, 52),
	Sawmill = Color3.fromRGB(232, 136, 40),
	Planer = Color3.fromRGB(226, 98, 160),
	Belt = Color3.fromRGB(139, 195, 74),
	Machine = Color3.fromRGB(240, 196, 48),
	Gear = Color3.fromRGB(46, 168, 148),
	Blueprint = Color3.fromRGB(70, 130, 220),
	Cosmetic = Color3.fromRGB(160, 100, 214),
	Robux = Color3.fromRGB(227, 183, 60),
	Truck = Color3.fromRGB(66, 170, 96),
	Trailer = Color3.fromRGB(110, 150, 175),
} :: { [string]: Color3 }

BoxLook.Default = Color3.fromRGB(120, 124, 132)

-- An axe's accent by its tier, in ladder order (bright enough to read on the
-- charcoal box: a black Obsidian Axe is violet, a rusty one orange).
BoxLook.AxeTiers = {
	RustyAxe = Color3.fromRGB(176, 116, 70),
	SteelAxe = Color3.fromRGB(150, 164, 178),
	HardenedAxe = Color3.fromRGB(96, 168, 150),
	SilverAxe = Color3.fromRGB(214, 222, 232),
	CobaltAxe = Color3.fromRGB(58, 112, 224),
	GoldAxe = Color3.fromRGB(244, 188, 28),
	ObsidianAxe = Color3.fromRGB(138, 84, 214),
	InfernoAxe = Color3.fromRGB(255, 96, 34),
	StarfallAxe = Color3.fromRGB(86, 214, 255),
} :: { [string]: Color3 }

-- The category an item is shown under: the kind, with the machines split.
function BoxLook.CategoryOf(kind: string, itemId: string?): string
	if kind == "Machine" and itemId ~= nil then
		if string.sub(itemId, 1, 6) == "Planer" then
			return "Planer"
		elseif string.sub(itemId, 1, 8) == "Conveyor" then
			return "Belt"
		end
	end
	return kind
end

-- Whether a kind of goods has its own accent.
function BoxLook.Known(kind: string): boolean
	return (BoxLook.Categories :: { [string]: Color3? })[kind] ~= nil
end

function BoxLook.CategoryColor(kind: string, itemId: string?): Color3
	return BoxLook.Categories[BoxLook.CategoryOf(kind, itemId)] or BoxLook.Default
end

-- The accent colour of a box (and of its block on the shelf).
function BoxLook.Accent(kind: string, itemId: string?): Color3
	if kind == "Axe" and itemId ~= nil then
		local tier = BoxLook.AxeTiers[itemId]
		if tier then
			return tier
		end
	end
	return BoxLook.CategoryColor(kind, itemId)
end

-- The text colour that reads on `color`.
function BoxLook.InkOn(color: Color3): Color3
	local luma = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	return if luma > 0.55 then BoxLook.Ink else BoxLook.Light
end

return BoxLook
