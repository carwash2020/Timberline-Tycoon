--!strict
-- ShopHoursLogic: when each shop is open. Pure. B07 calls IsOpen(shopId, hour).
-- That signature stays (shop id, hour 0..24) -> boolean. NextOpen returns the
-- hour the door next unlocks. Callers pass WorldTime.Hour() (no argument), so
-- Studio's ClockOverride on workspace flows through the same clock as the sky.
--
-- Hours (Designer, 06:22 MT): Tool Shed never closes. Hearth & Home is open
-- from HearthOpen until HearthClose. The Dealership is open from DealerOpen
-- until DealerClose. The interval is half-open: open at the first minute,
-- closed at the last. A shop with no span (the Tool Shed, or an id this
-- module does not know) stays open, so a typo cannot lock a counter.

local WorldTime = require(script.Parent.WorldTime)

local ShopHoursLogic = {}

-- Hearth & Home, 7:00 to 21:00. TBD (Designer).
ShopHoursLogic.HearthOpen = 7
ShopHoursLogic.HearthClose = 21
-- Dealership opens at DealerOpen and closes at DealerClose. TBD (Designer).
ShopHoursLogic.DealerOpen = 7
ShopHoursLogic.DealerClose = 20

-- Used when the server clock cannot be read (the test runner has no
-- workspace). Noon, so every spanned shop is open. TBD (Builder).
ShopHoursLogic.FallbackHour = 12

-- Hours board on the door frame, in studs, drawn at this many pixels a stud.
-- TBD (Builder).
ShopHoursLogic.SignWidthStuds = 4
ShopHoursLogic.SignHeightStuds = 2
ShopHoursLogic.SignDepthStuds = 0.3
ShopHoursLogic.SignPixelsPerStud = 50
-- The board's bottom stays above the walk path. TBD (Builder).
ShopHoursLogic.SignClearY = 6.2

-- Zzz sits this many studs above the counter top, and fades out past this
-- distance. TBD (Builder).
ShopHoursLogic.ZzzAbove = 3
ShopHoursLogic.ZzzMaxDistance = 40
-- Zzz glyph size in pixels, over the 14 px tag minimum. TBD (Builder).
ShopHoursLogic.ZzzTextPx = 18
-- Billboard width, in glyphs, and the padding under the glyph. TBD (Builder).
ShopHoursLogic.ZzzWidthGlyphs = 3
ShopHoursLogic.ZzzPad = 8
-- Zzz ink, 0-255. TBD (Builder).
ShopHoursLogic.ZzzRed = 245
ShopHoursLogic.ZzzGreen = 235
ShopHoursLogic.ZzzBlue = 215

-- The lying keeper's top stays this many studs under the counter top.
-- SleepBodyHalf is half the lying body's height. TBD (Builder).
ShopHoursLogic.SleepClearance = 1
ShopHoursLogic.SleepBodyHalf = 1.2

-- How long an inside player can hold a closed door open, in seconds, and how
-- far past the front face still counts as inside. TBD (Builder).
ShopHoursLogic.ExitHold = 8
ShopHoursLogic.OutsidePad = 0.5

-- How often the server re-reads the clock. TBD (Builder).
ShopHoursLogic.PollSeconds = 15

export type Span = { open: number, close: number }

local SPANS: { [string]: Span } = {
	HearthAndHome = { open = ShopHoursLogic.HearthOpen, close = ShopHoursLogic.HearthClose },
	Dealership = { open = ShopHoursLogic.DealerOpen, close = ShopHoursLogic.DealerClose },
}

function ShopHoursLogic.Shops(): { string }
	return { "ToolShed", "HearthAndHome", "Dealership" }
end

function ShopHoursLogic.Span(shopId: string): Span?
	return SPANS[shopId]
end

local function wrap(hour: number): number
	local h = hour % 24
	if h < 0 then
		h += 24
	end
	return h
end

-- Half-open interval. When openAt > closeAt the shift crosses midnight.
function ShopHoursLogic.OpenAt(openAt: number, closeAt: number, hour: number): boolean
	local h = wrap(hour)
	if openAt == closeAt then
		return true
	end
	if openAt < closeAt then
		return h >= openAt and h < closeAt
	end
	return h >= openAt or h < closeAt
end

-- The clock hour the span next opens. Always openAt, even while the span
-- is already open (the opening time, not "now").
function ShopHoursLogic.NextOpenAt(openAt: number, _closeAt: number, _hour: number): number
	return wrap(openAt)
end

function ShopHoursLogic.IsOpen(shopId: string, hour: number): boolean
	local span = SPANS[shopId]
	if span == nil then
		return true
	end
	return ShopHoursLogic.OpenAt(span.open, span.close, hour)
end

function ShopHoursLogic.NextOpen(shopId: string, hour: number): number
	local span = SPANS[shopId]
	local h = wrap(hour)
	if span == nil then
		return h
	end
	return ShopHoursLogic.NextOpenAt(span.open, span.close, h)
end

-- 7 -> "7:00", 7.5 -> "7:30". No leading zero on the hour.
function ShopHoursLogic.FormatHour(hour: number): string
	local h = wrap(hour)
	local whole = math.floor(h + 1e-6)
	local minutes = math.floor((h - whole) * 60 + 0.5)
	if minutes >= 60 then
		whole += 1
		minutes = 0
	end
	whole = whole % 24
	return string.format("%d:%02d", whole, minutes)
end

function ShopHoursLogic.SignText(shopId: string, hour: number): string
	local span = SPANS[shopId]
	if span == nil then
		return "Open all day"
	end
	if ShopHoursLogic.IsOpen(shopId, hour) then
		return string.format(
			"Open %s to %s",
			ShopHoursLogic.FormatHour(span.open),
			ShopHoursLogic.FormatHour(span.close)
		)
	end
	return string.format("Closed, opens %s", ShopHoursLogic.FormatHour(ShopHoursLogic.NextOpen(shopId, hour)))
end

-- The hour the sky shows. WorldTime.Hour() with no argument, so a Studio
-- ClockOverride is honoured. Falls back when the clock cannot be read.
function ShopHoursLogic.Now(): number
	local ok, hour = pcall(function()
		return WorldTime.Hour()
	end)
	if ok and type(hour) == "number" then
		return hour
	end
	return ShopHoursLogic.FallbackHour
end

-- along is the player's offset from the counter along its LookVector (positive
-- toward the street). doorAt is the front face on that same axis.
function ShopHoursLogic.IsOutside(along: number, doorAt: number): boolean
	return along > doorAt + ShopHoursLogic.OutsidePad
end

-- The server allows the door when the shop is open, or when the player is
-- still inside (so they can leave after close).
function ShopHoursLogic.MayOpenDoor(isOpen: boolean, outside: boolean): boolean
	return isOpen or not outside
end

function ShopHoursLogic.WriteSigns(root: Instance, hour: number)
	if type((root :: any).GetDescendants) ~= "function" then
		return
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d.Name == "Hours" and d:IsA("TextLabel") then
			local gui = d.Parent
			local board = if gui then gui.Parent else nil
			local shopId = if board then board:GetAttribute("ShopId") else nil
			if type(shopId) == "string" then
				d.Text = ShopHoursLogic.SignText(shopId, hour)
			end
		end
	end
end

return ShopHoursLogic
