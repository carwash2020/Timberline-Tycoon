--!strict
-- TextAnchor: where a billboard of text over someone's head may sit so it is
-- never drawn inside a wall or through one (Connor: "sometimes the text pops
-- up in walls still", a half-hidden line inside a shop wall). Pure rules;
-- the client does the rays at a low rate (NPCController, PromptUI) and asks
-- these what to do with the answers.
--
-- What went wrong: a bubble's tail sits TopOffset + BubbleClearance above
-- the head and the card grows UP from there by a fixed number of PIXELS, so
-- its height in studs is bigger the farther the camera is. Under a shop's
-- low ceiling that put the top of the card in the roof, and the depth test
-- clipped it half away; a sideways offset (StudsOffset X is camera space)
-- could put it in a side wall; and with AlwaysOnTop the prompt cards drew
-- through every wall.
--
--   * Lift: the tail's height above the head centre, lowered under a ceiling
--     (the up-ray's hit) so the whole card fits, never lower than just above
--     the hat. If it will not fit even there, `fits` is false: a bubble
--     hides (it is only ambient chatter now; real conversations use the
--     dialogue box) and a name tag stays just above the hat.
--   * Side: the sideways offset becomes 0 when a wall is in the way.
--   * NextHidden: a ray from the camera to the text blocked by a wall hides
--     it at once; it comes back after a couple of clear checks, so a camera
--     brushing a corner does not flicker.

local TextAnchor = {}

TextAnchor.Margin = 0.35 -- studs of air under a ceiling, to the card's top
TextAnchor.MinClearance = 0.25 -- studs above the hat top: the tail never lower
TextAnchor.ProbeExtra = 14 -- studs past the wanted tail that the up-ray reaches
TextAnchor.CheckSeconds = 0.25 -- the client's ray rate: 4 a second
TextAnchor.ClearChecks = 2 -- clear checks in a row before hidden text returns
TextAnchor.Fov = 70 -- the default camera
TextAnchor.SideProbe = 0.6 -- studs past the sideways offset the wall ray reaches

-- Studs one screen pixel spans at `distance` studs, on a viewport `viewH` tall.
function TextAnchor.StudsPerPixel(distance: number, viewH: number): number
	local half = math.tan(math.rad(TextAnchor.Fov / 2))
	return 2 * math.max(distance, 0.1) * half / math.max(viewH, 1)
end

-- How tall `heightPx` of billboard is in the world at `distance`.
function TextAnchor.CardStuds(heightPx: number, distance: number, viewH: number): number
	return heightPx * TextAnchor.StudsPerPixel(distance, viewH)
end

-- About how tall a speech bubble is, in px, for `chars` characters of text at
-- `textSize` in a card `width` px wide: the lines (the label stops at four),
-- its padding and the tail under it. An estimate, a little generous.
function TextAnchor.CardPx(chars: number, width: number, textSize: number): number
	local perLine = math.max(8, math.floor(width / (textSize * 0.55)))
	local lines = math.clamp(math.ceil(chars / perLine), 1, 4)
	return lines * math.ceil(textSize * 1.2) + 14 + 18
end

-- The tail's height above the head centre.
--   topOffset: head centre to hat top; clearance: the wanted air above it;
--   headroom: studs from the head centre up to a ceiling, nil under open sky;
--   cardStuds: the card's height above the tail, in studs.
-- Returns the lift, and whether the card fits under the ceiling at it.
function TextAnchor.Lift(topOffset: number, clearance: number, headroom: number?, cardStuds: number): (number, boolean)
	local wanted = topOffset + clearance
	if headroom == nil then
		return wanted, true
	end
	local floor = topOffset + TextAnchor.MinClearance
	local most = headroom - TextAnchor.Margin - cardStuds
	local lift = math.min(wanted, most)
	if lift < floor then
		return floor, false
	end
	return lift, true
end

-- The sideways offset to use: the wanted one, or 0 when a wall is there.
function TextAnchor.Side(wanted: number, blocked: boolean): number
	if blocked then
		return 0
	end
	return wanted
end

-- Whether text is hidden after one more occlusion check. `occluded` is
-- whether a wall lies between the camera and the text now; `clear` the clear
-- checks so far. Returns (hidden, clear).
function TextAnchor.NextHidden(hidden: boolean, occluded: boolean, clear: number): (boolean, number)
	if occluded then
		return true, 0
	end
	local count = clear + 1
	if hidden and count < TextAnchor.ClearChecks then
		return true, count
	end
	return false, count
end

-- Whether a prompt card on a part may be drawn on top of the scene: only
-- when it is adorned to a thing the camera would otherwise see it through
-- (a counter's own centre), never one over a person's head, which the
-- scene's walls must hide.
function TextAnchor.OnTop(overHead: boolean): boolean
	return not overHead
end

return TextAnchor
