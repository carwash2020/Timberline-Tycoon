--!strict
-- HudLayout: the screen geometry the HUD works out from real sizes, as
-- plain maths (no Instances), so tests can check it.
--   * SideColumn(): where the side buttons' column stands (clear of the
--     corner and a phone's jump button), and Stack(): the buttons, stacked
--     up from its bottom-right corner in columns no taller than the room.
--   * ShopArea(): what the shop panel is centred in, under the top bar;
--     ShopHeader(): how tall its title and subtitle block is.
--   * ClearOf(): a centred panel's area, shrunk or lowered so the panel
--     stays clear of something drawn over it (the cash row over the shop).
--   * ToastLane(): where the toasts stack, clear of the top-right corner
--     and the left column (the tutorial tracker).
--   * ModalLane(): where they stack while a panel (the shop) is open over
--     the game: inside its bottom edge, clear of its title and buttons.
--   * BottomRow(): the load chip and the hint, side by side above the
--     hotbar, clear of a phone's jump button.
--   * ClockLine(): which corner line the clock goes in.
--   * TopRow(): where the cash row sits, in screen pixels (its screen is
--     not scaled), in the top bar or just under it.
-- Everything else is in a screen's offsets (UIScale units), y down.

local HudLayout = {}

export type Rect = { left: number, top: number, right: number, bottom: number }

-- The side buttons' column on their screen (HUD's SideButtons: the device's
-- safe area, the top bar's strip included), `screen` big, all in its
-- offsets. Its bottom-right corner sits at the right `margin`, but never
-- further right than a phone's `jump` button (nil without touch
-- controls), `clearance` above that button, or without one `belowCentre`
-- under the screen's middle. The buttons may stack up to `gap` under
-- `cornerBottom` (the bottom of the corner's second line). Returns that
-- corner and the room above it (Stack's `room`).
function HudLayout.SideColumn(
	screen: Vector2,
	cornerBottom: number,
	jump: Rect?,
	margin: number,
	gap: number,
	clearance: number,
	belowCentre: number
): (Vector2, number)
	local right = screen.X - margin
	local bottom = screen.Y / 2 + belowCentre
	if jump then
		right = math.min(right, jump.right)
		bottom = jump.top - clearance
	end
	return Vector2.new(right, bottom), bottom - (cornerBottom + gap)
end

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

-- The shop panel's header (ShopUI): 14 above the title, the title (30),
-- 2, the subtitle, and 10 under it. The subtitle takes one 16 px line on a
-- computer or a TV, and two (32) on a phone, where its narrower panel
-- wraps it (UI-19).
HudLayout.SubtitleLine = 16
function HudLayout.ShopHeader(phone: boolean): number
	local lines = if phone then 2 else 1
	return 14 + 30 + 2 + lines * HudLayout.SubtitleLine + 10
end

local SHOP_SIDE = 12 -- the shop's area: in from the sides,
local SHOP_GAP = 8 -- and from the top bar and the bottom

-- What the shop panel is centred in, on a `screen`-sized screen whose top
-- bar ends `topBar` down (both in its offsets): `SHOP_GAP` under the bar
-- and above the bottom, 12 in from the sides (before ClearOf keeps it clear
-- of the cash row).
function HudLayout.ShopArea(screen: Vector2, topBar: number): Rect
	return {
		left = SHOP_SIDE,
		top = math.max(0, topBar) + SHOP_GAP,
		right = screen.X - SHOP_SIDE,
		bottom = screen.Y - SHOP_GAP,
	}
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
-- (toasts left-aligned there) rather than centred at the top; `modal`
-- when it's inside an open panel (ModalLane: left-aligned, and the stack
-- grows up from `bottom` instead of down from `top`).
export type Lane = {
	left: number,
	top: number,
	right: number,
	bottom: number,
	max: number,
	under: boolean,
	modal: boolean,
}

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
			modal = false,
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
		modal = false,
	}
end

local MODAL_INSET = 20 -- a panel's frame (8) and its rows' padding (12): the lane lines up with the rows
local MODAL_BUTTONS = 140 -- the strip down a panel's right side with the rows' buttons (ShopUI: 100 wide, 96 on a phone, and 40 of padding and frame)
local MODAL_PHONE_TOASTS = 1 -- toasts at once in a panel on a phone

-- The toast lane while a panel (the shop, HUD.SetModal) is open over the
-- game, `panel` in the same screen's offsets: inside the panel, LANE_GAP
-- above its bottom edge, the stack growing upward from there (`modal`).
-- It lines up with the panel's rows on the left and ends left of their
-- buttons, `maxW` wide at most; a panel too narrow for `minW` there gets
-- `minW` (over the buttons if it must). One toast on a phone; elsewhere up
-- to three, and never above the panel's middle, so its title and subtitle
-- stay clear. With `hotbar` (on a phone: the top of the band along the
-- bottom where Roblox's tool hotbar draws over everything), a panel that
-- reaches down into it gets its lane ending above it instead, but no
-- higher than one toast under the panel's middle.
function HudLayout.ModalLane(panel: Rect, maxW: number, minW: number, phone: boolean, hotbar: number?): Lane
	local left = panel.left + MODAL_INSET
	local right = math.min(left + maxW, panel.right - MODAL_BUTTONS - LANE_GAP)
	if right - left < minW then
		right = math.max(left, math.min(left + minW, panel.right - MODAL_INSET))
	end
	local bottom = panel.bottom - LANE_GAP
	local middle = (panel.top + panel.bottom) / 2
	if hotbar and hotbar < bottom then
		bottom = math.max(hotbar, math.min(bottom, middle + TOAST_ROW))
	end
	local max = if phone
		then MODAL_PHONE_TOASTS
		else math.clamp(math.floor((bottom - middle + LANE_GAP) / TOAST_ROW), 1, LANE_TOASTS)
	return {
		left = left,
		top = bottom - max * TOAST_ROW,
		right = right,
		bottom = bottom,
		max = max,
		under = false,
		modal = true,
	}
end

-- The bottom row (HUD): the load chip, then the hint, `gap` apart, on one
-- line above the hotbar, centred on a `screenW`-wide screen but kept
-- between `low` and `high` (x: the left margin, and a phone's jump button
-- or the right margin). `chipW` is 0 while the chip is hidden; `hintW` is
-- how wide the hint is now. Returns the widest the hint may be (at most
-- `hintCap`: it truncates past that) so the row fits between them, and
-- where the row's centre goes: the screen's, or as far left of it as the
-- row needs to end before `high`.
function HudLayout.BottomRow(
	screenW: number,
	chipW: number,
	hintW: number,
	gap: number,
	low: number,
	high: number,
	hintCap: number
): (number, number)
	local chip = if chipW > 0 then chipW + gap else 0
	local hintMax = math.max(0, math.min(hintCap, high - low - chip))
	local width = chip + math.min(hintW, hintMax)
	local centre = math.min(screenW / 2, high - width / 2)
	return hintMax, math.max(centre, low + width / 2)
end

export type ClockLine = "beside" | "under" | "none"

-- Which corner line the clock goes in. On a computer or a TV: beside the
-- cash (the first line). On a phone it moves to the second (with the
-- pouch and Daily Goals), leaving the first to the cash row and the Store;
-- and while the tutorial runs it's hidden, because on a small phone that
-- line would then reach the tracker. `tutorialStep` is the TutorialStep
-- attribute as read (any type): 0 once the tutorial's done or skipped;
-- above 0, or not a number yet (nil while the save loads), it's running
-- (as HudRules.TutorialRunning has it), so the clock doesn't flash into
-- line 2 before the save arrives.
function HudLayout.ClockLine(phone: boolean, tutorialStep: unknown): ClockLine
	if not phone then
		return "beside"
	end
	local running = type(tutorialStep) ~= "number" or tutorialStep > 0
	return if running then "none" else "under"
end

export type TopRowPlace = {
	right: number, -- screen px: the row's right edge (anchor x)
	top: number, -- screen px: the row's top (anchor y)
	inBar: boolean,
}

local TOP_MARGIN = 12 -- in from the right of the free spot
local TOP_FIT_SLACK = 16 -- a row wider than the bar's width minus this sits under it
local TOP_TEXT_PAD = 4 -- px the bar must keep above and below the cash text

-- Where the cash row sits on a ScreenGui with ScreenInsets None, anchor
-- (1, 0), in screen pixels. `topbar` is GuiService.TopbarInset as read.
-- `leftSafe` and `rightSafe` are the device's unsafe insets (GetGuiInset's
-- X on the left and the right: a notch). `textHeight` is the cash text in
-- pixels; it is never shrunk to fit. `fallbackTop` is UITheme.TopBar() + 4.
-- In the bar, the right edge is min(topbar.Max.X, viewport.X - rightSafe)
-- minus 12 and the row is centred on the bar's height. It sits under the
-- bar when the inset is empty, the row is wider than the bar's width
-- minus 16, the bar is shorter than the text plus 4 px above and below,
-- or that in-bar spot would cross a Roblox button or the notch.
-- `typeof(Rect.new(...))` is the Roblox datatype. This file's own `Rect`
-- is the {left, top, right, bottom} table, and that name wins as a type.
function HudLayout.TopRow(
	viewport: Vector2,
	topbar: typeof(Rect.new(0, 0, 0, 0)),
	row: Vector2,
	textHeight: number,
	leftSafe: number,
	rightSafe: number,
	fallbackTop: number
): TopRowPlace
	local function underBar(): TopRowPlace
		local limit = viewport.X - rightSafe
		local right = limit - TOP_MARGIN
		-- Keep the left edge out of a left notch when the row still fits
		-- in the safe width.
		if right - row.X < leftSafe then
			local pinned = leftSafe + row.X
			if pinned <= limit then
				right = pinned
			end
		end
		return { right = right, top = fallbackTop, inBar = false }
	end

	local barW, barH = topbar.Width, topbar.Height
	local textBand = textHeight + TOP_TEXT_PAD * 2
	if barW <= 0 or barH <= 0 or row.X > barW - TOP_FIT_SLACK or barH < textBand then
		return underBar()
	end

	local right = math.min(topbar.Max.X, viewport.X - rightSafe) - TOP_MARGIN
	local left = right - row.X
	if left < math.max(topbar.Min.X, leftSafe) or right > topbar.Max.X then
		return underBar()
	end
	local top = topbar.Min.Y + (barH - row.Y) / 2
	return { right = right, top = top, inBar = true }
end

return HudLayout
