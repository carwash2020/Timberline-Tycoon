--!strict
-- HudLayout: the screen geometry the HUD works out from real sizes, as
-- plain maths (no Instances), so tests can check it.
--   * Stack(): the side buttons, stacked up from a bottom-right corner in
--     columns no taller than the room there.
--   * ClearOf(): a centred panel's area, shrunk or lowered so the panel
--     stays clear of something drawn over it (the cash row over the shop).
--   * ToastLane(): where the toasts stack, clear of the top-right corner
--     and the left column (the tutorial tracker).
--   * ClockLine(): which corner line the clock goes in.
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

-- Lifts whole columns of Stack()'s `spots` (boxes `sizes`, the stack's
-- bottom-right corner at `corner` in screen offsets) that would overlap
-- `band` so they sit `gap` above it, if the column's top stays below
-- `top`; columns that don't overlap, or can't fit above it, stay put.
function HudLayout.LiftClear(
	spots: { Vector2 },
	sizes: { Vector2 },
	corner: Vector2,
	band: Rect,
	top: number,
	gap: number
): { Vector2 }
	local out: { Vector2 } = table.clone(spots)
	-- Group by column (same x offset).
	local columns: { [number]: { number } } = {}
	for i, spot in ipairs(spots) do
		columns[spot.X] = columns[spot.X] or {}
		table.insert(columns[spot.X], i)
	end
	for x, members in pairs(columns) do
		local lift = 0
		local highest = math.huge -- the column's top edge
		for _, i in ipairs(members) do
			local size = sizes[i]
			local right = corner.X - x
			local left = right - size.X
			local bottom = corner.Y - spots[i].Y
			local boxTop = bottom - size.Y
			highest = math.min(highest, boxTop)
			if
				left < band.right + gap
				and right > band.left - gap
				and bottom > band.top - gap
				and boxTop < band.bottom
			then
				lift = math.max(lift, bottom - (band.top - gap))
			end
		end
		if lift > 0 and highest - lift >= top then
			for _, i in ipairs(members) do
				out[i] = Vector2.new(spots[i].X, spots[i].Y + lift)
			end
		end
	end
	return out
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

-- Where the toasts stack (newest on top): a strip of screen from `top`
-- down to `bottom`, `right - left` wide (the widest a toast may be), that
-- holds `max` toasts at once; `under` when it's under the left column
-- (toasts left-aligned there) rather than centred at the top.
export type Lane = { left: number, top: number, right: number, bottom: number, max: number, under: boolean }

local LANE_GAP = 8 -- between the lane and what it keeps clear of
local LANE_TOASTS = 3 -- toasts at once in a lane at the top
local UNDER_TOASTS = 2 -- and under the left column (a phone)
local TOAST_ROW = 48 -- the room a toast takes in a lane: a two-line toast and the gap under it

-- The toast lane on a `screen`-sized screen with the top-right `corner`
-- (both its lines: the cash row and what's beside and under it) and the
-- left `column` (the Field Guide button, the tutorial tracker, Murph's
-- card, and off a phone Roblox's chat window above them; nil if there's
-- none yet), all in the same screen's offsets.
--   * Where the band between the column and the corner is at least `minW`
--     wide (a computer, a TV): the lane is centred in it, at the corner's
--     top, at most `maxW` wide, and takes three toasts.
--   * Narrower (a phone): directly under the column, at its width (at
--     least `minW`, at most `maxW`), and takes two. If the column is so
--     short that the lane would reach the corner, it ends left of the
--     corner, or (if that leaves less than `minW`) starts under the
--     corner. Where there's no room for two above `floor` (the lowest a
--     toast may reach; the screen's bottom if nil), it takes one.
-- The lane never overlaps the corner or the column, at any height.
function HudLayout.ToastLane(
	screen: Vector2,
	corner: Rect,
	column: Rect?,
	maxW: number,
	minW: number,
	floor: number?
): Lane
	local margin = screen.X - corner.right -- the corner sits at the right margin, the column at the left one
	local bottom = floor or screen.Y
	local bandLeft = if column then column.right + LANE_GAP else margin
	local bandRight = corner.left - LANE_GAP
	if bandRight - bandLeft >= minW then
		local width = math.min(maxW, bandRight - bandLeft)
		local left = bandLeft + (bandRight - bandLeft - width) / 2
		return {
			left = left,
			top = corner.top,
			right = left + width,
			bottom = bottom,
			max = LANE_TOASTS,
			under = false,
		}
	end
	-- Under the column (or, with none yet, from the top-left margin).
	local left = if column then column.left else margin
	local top = if column then column.bottom + LANE_GAP else corner.top
	local columnWidth = if column then column.right - column.left else 0
	local width = math.min(maxW, math.max(columnWidth, minW), screen.X - margin - left)
	if top < corner.bottom + LANE_GAP and left + width > corner.left - LANE_GAP then
		local room = corner.left - LANE_GAP - left
		if room >= minW then
			width = room
		else
			top = corner.bottom + LANE_GAP
		end
	end
	local fits = math.floor((bottom - top + LANE_GAP) / TOAST_ROW)
	return {
		left = left,
		top = top,
		right = left + math.max(0, width),
		bottom = bottom,
		max = math.clamp(fits, 1, UNDER_TOASTS),
		under = true,
	}
end

export type ClockLine = "beside" | "under" | "none"

-- Which corner line the clock goes in. On a computer or a TV: beside the
-- cash (the first line). On a phone it moves to the second (with the
-- pouch and Daily Goals), leaving the first to the cash row and the Store;
-- and while the tutorial runs (`tutorialStep` > 0) it's hidden, because on
-- a small phone that line would then reach the tracker.
function HudLayout.ClockLine(phone: boolean, tutorialStep: number): ClockLine
	if not phone then
		return "beside"
	end
	return if tutorialStep > 0 then "none" else "under"
end

return HudLayout
