--!nocheck
-- What the preview's night preset lights (WLD-19): the parts and lights the
-- game's LightingController switches on after dark. export.luau tags them in
-- the scene it writes, and viewer.html uses the tags on a camera marked
-- `night = true`:
--   * a part named WindowGlass, LampGlow, LanternGlow or LampBulb glows Neon at night,
--     in its night colour (GlowColor);
--   * a light inside one of those parts, or anywhere in a "StreetLamp"-tagged
--     model, is on at night even if it was built switched off (IsNightLight).
-- tests/PreviewNight.spec.luau keeps the names and colours in step with
-- src/StarterPlayer/StarterPlayerScripts/LightingController.luau.

local Night = {}

-- LightingController's GLOW_NAMES.
Night.GlowNames = { WindowGlass = true, LampGlow = true, LanternGlow = true, LampBulb = true }

-- LightingController's WINDOW_NIGHT (255, 196, 110) and LANTERN_NIGHT
-- (255, 200, 110), as hex.
Night.WindowColor = "FFC46E"
Night.LanternColor = "FFC86E"
-- WoodData.LanternGlow, without the hash. Approved. WoodFX swaps NightGlow
-- parts to this at night, and the preview's night cameras do the same.
Night.WoodGlow = "FFC45C"

-- The colour (hex, no "#") a part glows at night, or nil when the game
-- doesn't light it. Like LightingController's trackGlowPart: a window takes
-- the warm window colour, a part that is already Neon keeps its own colour,
-- and any other glow part takes the lantern colour. A part marked NightGlow
-- (Lanternwood leaves, the core band, and planks) takes the wood colour.
function Night.GlowColor(part): string?
	if not part:IsA("BasePart") then
		return nil
	elseif Night.GlowNames[part.Name] then
		if part.Name == "WindowGlass" then
			return Night.WindowColor
		elseif part.Material.Name == "Neon" then
			return part.Color:ToHex()
		end
		return Night.LanternColor
	elseif part:GetAttribute("NightGlow") == true then
		return Night.WoodGlow
	end
	return nil
end

-- Whether the game turns a light on at night: it sits in a glow part, or in
-- a "StreetLamp"-tagged model (LightingController's trackLamp).
function Night.IsNightLight(light): boolean
	local parent = light.Parent
	if parent and parent:IsA("BasePart") and Night.GlowNames[parent.Name] then
		return true
	end
	local at = parent
	while at do
		if at:HasTag("StreetLamp") then
			return true
		end
		at = at.Parent
	end
	return false
end

return Night
