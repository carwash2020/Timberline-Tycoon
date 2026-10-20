--!strict
-- NameFade: an NPC's nameplate gives way to its Talk card. Both are
-- pixel-sized billboards on the same head about 1.5 studs apart, so no studs
-- offset can keep them apart at every distance and screen scale. While a Talk
-- prompt shows on a head, that head's nameplate fades out (0.15 s) and fades
-- back (0.15 s) when the prompt goes. Pure rules, no clocks: the client feeds
-- in `dt`, the specs feed in whole numbers.
--
--   * A show count per head: two prompts on one NPC do not bring the name
--     back until both are gone, and a hide with no show never goes negative.
--   * Transparency runs 0 (drawn) to 1 (gone) at 1 / Duration per second.
--   * Rects are screen pixels around the head's own screen point (x right,
--     y up), so "do the name and the card overlap" is a plain rectangle test.

local NameFade = {}

NameFade.Duration = 0.15 -- seconds, each way

export type State = {
	counts: { [any]: number }, -- prompts showing on each head
	alpha: { [any]: number }, -- 0 drawn .. 1 gone, for each head still fading or hidden
}

function NameFade.new(): State
	return { counts = {}, alpha = {} }
end

-- A prompt now shows on `key` (a head). Returns the count.
function NameFade.Show(state: State, key: any): number
	local count = (state.counts[key] or 0) + 1
	state.counts[key] = count
	if state.alpha[key] == nil then
		state.alpha[key] = 0
	end
	return count
end

-- A prompt on `key` went away. Never below zero. Returns the count.
function NameFade.Hide(state: State, key: any): number
	local count = math.max((state.counts[key] or 0) - 1, 0)
	if count > 0 then
		state.counts[key] = count
	else
		state.counts[key] = nil
	end
	return count
end

function NameFade.Count(state: State, key: any): number
	return state.counts[key] or 0
end

-- Transparency the name is heading for.
function NameFade.Target(state: State, key: any): number
	return if (state.counts[key] or 0) > 0 then 1 else 0
end

-- Current transparency of `key`'s nameplate (0 when it was never touched).
function NameFade.Transparency(state: State, key: any): number
	return state.alpha[key] or 0
end

-- Moves one number toward `target` by `dt` seconds of the fade.
function NameFade.Approach(current: number, target: number, dt: number): number
	local step = math.max(dt, 0) / NameFade.Duration
	if current < target then
		return math.min(current + step, target)
	end
	return math.max(current - step, target)
end

-- Advances every fading head by `dt`. Returns the heads that changed, so the
-- caller only touches those labels. A head fully back and with no prompt is
-- forgotten.
function NameFade.Step(state: State, dt: number): { any }
	local changed: { any } = {}
	for key, now in pairs(state.alpha) do
		local nextAlpha = NameFade.Approach(now, NameFade.Target(state, key), dt)
		if nextAlpha ~= now then
			state.alpha[key] = nextAlpha
			table.insert(changed, key)
		end
		if nextAlpha == 0 and (state.counts[key] or 0) == 0 then
			state.alpha[key] = nil
		end
	end
	return changed
end

-- Seconds for a hidden name to be fully back once its last prompt is gone.
function NameFade.BackWithin(state: State, key: any): number
	return NameFade.Transparency(state, key) * NameFade.Duration
end

---------------------------------------------------------------------------
-- Rectangles
---------------------------------------------------------------------------

export type Rect = { x0: number, y0: number, x1: number, y1: number }

function NameFade.Overlap(a: Rect?, b: Rect?): boolean
	if a == nil or b == nil then
		return false
	end
	return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
end

-- Studs one screen pixel spans at `distance` (the camera's default field of view).
function NameFade.StudsPerPixel(distance: number, viewH: number): number
	local half = math.tan(math.rad(35))
	return 2 * math.max(distance, 0.1) * half / math.max(viewH, 1)
end

-- A billboard of `size` pixels whose middle is `offsetY` studs above the head,
-- `dx`/`dy` studs off the head sideways/up on screen (another NPC), as pixels.
function NameFade.TagRect(size: { x: number, y: number }, offsetY: number, spp: number, dx: number?, dy: number?): Rect
	local cx = (dx or 0) / spp
	local cy = ((dy or 0) + offsetY) / spp
	return { x0 = cx - size.x / 2, x1 = cx + size.x / 2, y0 = cy - size.y / 2, y1 = cy + size.y / 2 }
end

-- The Talk card: its tail `lift` studs above the head, growing up `height` px.
function NameFade.CardRect(size: { x: number, y: number }, lift: number, spp: number): Rect
	local base = lift / spp
	return { x0 = -size.x / 2, x1 = size.x / 2, y0 = base, y1 = base + size.y }
end

-- The nameplate rect that is actually drawn: none once it has faded out.
function NameFade.Visible(rect: Rect, transparency: number): Rect?
	if transparency >= 1 then
		return nil
	end
	return rect
end

-- Whether another NPC's nameplate (drawn, `dx`/`dy` studs from the prompted
-- head on screen) would sit under the shown card. That nameplate fades too.
function NameFade.Covered(
	tag: { x: number, y: number },
	tagOffsetY: number,
	card: { x: number, y: number },
	lift: number,
	spp: number,
	dx: number,
	dy: number
): boolean
	return NameFade.Overlap(NameFade.TagRect(tag, tagOffsetY, spp, dx, dy), NameFade.CardRect(card, lift, spp))
end

return NameFade
