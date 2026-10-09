--!strict
-- PhoneHud: what the HUD's side column holds on a phone, as plain data and
-- maths so a spec can check it.
--
-- On a phone the column is three 44 x 44 icon buttons (MENU, HAMMER, Sell
-- here), one column, 8 px apart, no wrap. SAVES, "Send truck home" and the
-- owner's button move inside MENU (the quick menu lists them). A computer
-- and a controller keep the wider text buttons in the column, unchanged.
-- Names are the HUD.SideButton names, so no caller changes.

local PhoneHud = {}

export type Icon = {
	key: string, -- the UITheme.HudIcons entry
	text: string, -- the short text shown when the image is missing or fails to load
}

PhoneHud.Size = 44 -- an icon button's face, square (a fingertip)
PhoneHud.Glyph = 28 -- its image, centred: 8 px of padding each side
PhoneHud.Gap = 8 -- between the buttons' faces
PhoneHud.EdgeMargin = 12 -- from the safe edge (UITheme.Margin on a phone)

-- Top to bottom.
PhoneHud.Column = { "Menu", "Hammer", "InstantDelivery" } :: { string }

PhoneHud.Icons = {
	Menu = { key = "Menu", text = "MENU" },
	Hammer = { key = "Hammer", text = "BUILD" },
	InstantDelivery = { key = "SellHere", text = "SELL" },
} :: { [string]: Icon }

-- Buttons that live inside MENU on a phone.
PhoneHud.Folded = {
	Saves = true,
	CallTruck = true,
	Owner = true,
} :: { [string]: boolean }

-- On a phone, the style an icon button wears instead of its text style:
-- the green ones go deeper so a cream icon clears 3:1.
PhoneHud.IconStyle = {
	Hammer = "iconGreen",
	InstantDelivery = "iconGreen",
} :: { [string]: string }

function PhoneHud.IconFor(name: string): Icon?
	return PhoneHud.Icons[name]
end

function PhoneHud.IsFolded(name: string): boolean
	return PhoneHud.Folded[name] == true
end

-- The gap to hand HudLayout.Stack on a phone. A button's root is its face
-- plus the drop edge (`drop`), so the faces end up exactly `PhoneHud.Gap` apart.
function PhoneHud.StackGap(drop: number): number
	return PhoneHud.Gap - drop
end

return PhoneHud
