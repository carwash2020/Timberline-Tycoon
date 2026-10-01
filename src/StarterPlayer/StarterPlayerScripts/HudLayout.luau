--!strict
-- HudLayout: the screen geometry the HUD works out from real sizes, as
-- plain maths (no Instances), so tests can check it.
--   * Stack(): the side buttons, stacked up from a bottom-right corner in
--     columns no taller than the room there.
--   * ClearOf(): a centred panel's area, shrunk or lowered so the panel
--     stays clear of something drawn over it (the cash row over the shop).
-- Everything is in a screen's offsets (UIScale units), y down.

local HudLayout = {}

export type Rect = { left: number, top: number, right: number, bottom: number }

-- Stacks boxes up from a bottom-right corner: the last box sits in the
-- corner and the ones before it above it, in a column at most `room`
-- tall; what doesn't fit starts another column to its left (each column
-- as wide as its widest box). `sizes` go top to bottom. Returns where
-- each box's bottom-right corner goes, as an offset left and up from the
-- corner. A column always takes one box, even one taller than the room.
function HudLayout.Stack(sizes: { Vector2 }, room: number, gap: number): { Vector2 }
	local spots: { Vector2 } = table.create(#sizes)
	local x, y, width = 0, 0, 0
	for i = #sizes, 1, -1 do
		local size = sizes[i]
		if y > 0 and y + size.Y > room then
			x += width + gap
			y, width = 0, 0
		end
		spots[i] = Vector2.new(x, y)
		y += size.Y + gap
		width = math.max(width, size.X)
	end
	return spots
end

-- The panel a size-capped panel centred in `area` takes.
function HudLayout.Centred(area: Rect, max: Vector2): Rect
	local w = math.min(max.X, area.right - area.left)
	local h = math.min(max.Y, area.bottom - area.top)
	local left = area.left + (area.right - area.left - w) / 2
	local top = area.top + (area.bottom - area.top - h) / 2
	return { left = left, top = top, right = left + w, bottom = top + h }
end

local function overlaps(a: Rect, b: Rect, gap: number): boolean
	return a.left < b.right + gap and a.right > b.left - gap and a.top < b.bottom + gap and a.bottom > b.top - gap
end

-- The area to centre a panel (at most `max`) in so it stays `gap` clear of
-- `avoid`, a box in the area's top-right corner: `area` itself if the
-- panel already misses it; else the area cut short on the right, to end
-- left of `avoid` (the panel keeps its height); or, if that would leave
-- the panel narrower than `minWidth`, the area starting below `avoid`.
function HudLayout.ClearOf(area: Rect, max: Vector2, avoid: Rect, gap: number, minWidth: number): Rect
	if not overlaps(HudLayout.Centred(area, max), avoid, gap) then
		return area
	end
	local right = avoid.left - gap
	if right - area.left >= minWidth then
		return { left = area.left, top = area.top, right = right, bottom = area.bottom }
	end
	return { left = area.left, top = math.max(area.top, avoid.bottom + gap), right = area.right, bottom = area.bottom }
end

return HudLayout
