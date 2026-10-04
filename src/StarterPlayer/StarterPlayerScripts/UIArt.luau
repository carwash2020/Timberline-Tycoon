--!strict
-- UIArt: the HUD skins. Asset ids live only here. These are Image ids
-- (a Decal id does not load when a script sets ImageLabel.Image). Each
-- source is 256x256. sliceCenter is the flat Paper (#F0E1C3) center, and
-- the border on screen is that margin times sliceScale (4 px on the
-- plaque, 12 px on the panel and the buttons).

local UIArt = {}

export type Skin = {
	id: string,
	sliceCenter: Rect,
	sliceScale: number,
}

local function entry(id: string, minX: number, minY: number, maxX: number, maxY: number, sliceScale: number): Skin
	return {
		id = id,
		sliceCenter = Rect.new(minX, minY, maxX, maxY),
		sliceScale = sliceScale,
	}
end

local skins: { [string]: Skin } = {
	Plaque = entry("rbxassetid://139841387610705", 24, 24, 232, 232, 1 / 6),
	Panel = entry("rbxassetid://90740664574742", 48, 48, 208, 208, 0.25),
	Button = entry("rbxassetid://72427678124813", 48, 48, 208, 208, 0.25),
	ButtonPressed = entry("rbxassetid://74100852047057", 48, 48, 208, 208, 0.25),
}

UIArt.Plaque = skins.Plaque
UIArt.Panel = skins.Panel
UIArt.Button = skins.Button
UIArt.ButtonPressed = skins.ButtonPressed

UIArt.Names = { "Plaque", "Panel", "Button", "ButtonPressed" }

function UIArt.Get(name: string): Skin?
	return skins[name]
end

-- How far the flat center sits in from the edge, in screen pixels.
function UIArt.Inset(art: Skin): number
	return math.ceil(art.sliceCenter.Min.X * art.sliceScale - 1e-6)
end

return UIArt
