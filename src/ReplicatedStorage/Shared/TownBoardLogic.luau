--!strict
-- TownBoardLogic: the rules of the town leaderboard board (Lane X). Pure,
-- so TownBoardArt (the model), TownBoardService (the updates) and the specs
-- share one set of numbers.
--
-- The board is a 14 x 8 stud sign on two posts in the town square, facing
-- south onto MainStreet (WorldPlan.LeaderboardBoard, 8 studs north of the
-- street's edge, between the gondola path and the Tool Shed). It shows the
-- top ten by lifetime cash, read from LeaderboardService's cache (the one
-- read a minute the Settings tab already uses), in two columns of five.
--   * Only opted-in players are in that cache's answer, so only they show.
--   * Empty, failed and loading states have their own line.
--   * Everything is in canvas pixels on a 100-px-per-stud face (1400 x 800).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeaderboardLogic = require(ReplicatedStorage.Shared.LeaderboardLogic)
local Util = require(ReplicatedStorage.Shared.Util)

local TownBoardLogic = {}

TownBoardLogic.Title = "TOP LUMBERJACKS"
TownBoardLogic.EmptyText = "No one is on the board yet. Turn it on in Settings, Leaderboard."
TownBoardLogic.FailedText = "The board couldn't load. Try again soon."
TownBoardLogic.LoadingText = "Loading the board..."
-- The plaque under the board (the sign line that points at the opt-in).
TownBoardLogic.SignText = "Want a spot? Settings, then Leaderboard"
TownBoardLogic.CashSuffix = " earned"

TownBoardLogic.Rows = 10 -- LeaderboardLogic.Size
TownBoardLogic.Columns = 2
TownBoardLogic.PerColumn = 5
TownBoardLogic.TopRanks = 3 -- ranks 1..3 print in amber
TownBoardLogic.NameMax = 20 -- characters kept of a name (Roblox names are at most 20)

-- Geometry, in studs. The board's front (-Z) faces the street.
TownBoardLogic.BoardSize = Vector3.new(14, 8, 0.4) -- the walnut field
TownBoardLogic.Frame = 0.3 -- brass frame width
TownBoardLogic.PostWidth = 0.8
TownBoardLogic.PostX = 7.7 -- posts' centres either side (flush with the frame)
TownBoardLogic.OuterBottom = 2.0 -- ground to the frame's lower edge
TownBoardLogic.PlaqueSize = Vector3.new(14.6, 1.2, 0.3)
TownBoardLogic.PlaqueY = 1.0 -- plaque centre over the ground
TownBoardLogic.PostOver = 0.5 -- posts stand this far over the frame's top
TownBoardLogic.PostSink = 1.0 -- and this far into the ground
TownBoardLogic.PartCap = 12
TownBoardLogic.MaxDistance = 120 -- SurfaceGui.MaxDistance, studs

-- The face's pixels: 100 per stud.
TownBoardLogic.PxPerStud = 100
TownBoardLogic.CanvasSize = Vector2.new(1400, 800)

-- Layout on that canvas.
TownBoardLogic.HeaderH = 150
TownBoardLogic.RowH = 116
TownBoardLogic.RowGap = 6
TownBoardLogic.RowsTop = 176
TownBoardLogic.ColW = 650
TownBoardLogic.ColLeft = { 40, 710 }
TownBoardLogic.Medal = 92 -- rank circle
TownBoardLogic.NameTextPx = 60
TownBoardLogic.CashTextPx = 42
TownBoardLogic.TitleTextPx = 120
TownBoardLogic.MessageTextPx = 64

export type Rect = { x: number, y: number, w: number, h: number }
export type Slot = { plate: Rect, medal: Rect, rank: Rect, name: Rect, cash: Rect }

-- Where row `i` (1..10) sits: column by rank (1 to 5 left, 6 to 10 right).
function TownBoardLogic.Slot(i: number): Slot
	local perColumn = TownBoardLogic.PerColumn
	local col = (i - 1) // perColumn + 1
	local row = (i - 1) % perColumn
	local x = TownBoardLogic.ColLeft[col] or TownBoardLogic.ColLeft[#TownBoardLogic.ColLeft]
	local y = TownBoardLogic.RowsTop + row * (TownBoardLogic.RowH + TownBoardLogic.RowGap)
	local h = TownBoardLogic.RowH
	local m = TownBoardLogic.Medal
	local textX = x + 16 + m + 14
	local textW = x + TownBoardLogic.ColW - 12 - textX
	return {
		plate = { x = x, y = y, w = TownBoardLogic.ColW, h = h },
		medal = { x = x + 16, y = y + (h - m) // 2, w = m, h = m },
		rank = { x = x + 16, y = y + (h - m) // 2, w = m, h = m },
		name = { x = textX, y = y + 4, w = textW, h = 62 },
		cash = { x = textX, y = y + 66, w = textW, h = 46 },
	}
end

-- The title across the top, and the message box over the rows.
function TownBoardLogic.TitleRect(): Rect
	return { x = 100, y = 12, w = 1200, h = TownBoardLogic.HeaderH - 24 }
end

function TownBoardLogic.MessageRect(): Rect
	return { x = 120, y = 250, w = 1160, h = 420 }
end

-- A name, cut to NameMax characters with an ellipsis (a Roblox name never
-- needs it; this only guards a bad row).
function TownBoardLogic.FitName(name: string): string
	local clean = LeaderboardLogic.CleanName(name)
	local length = utf8.len(clean) or #clean
	if length <= TownBoardLogic.NameMax then
		return clean
	end
	local cut = utf8.offset(clean, TownBoardLogic.NameMax) or (TownBoardLogic.NameMax + 1) -- the byte after the kept characters
	return string.sub(clean, 1, cut - 1) .. "…"
end

export type Line = { rank: string, name: string, cash: string, top: boolean }
export type State = "loading" | "failed" | "empty" | "rows"
export type View = { state: State, message: string, lines: { Line } }

-- What the board shows. `rows` is LeaderboardService.Top() (nil: loading, or
-- failed when `failed`). Rows are ranked by the service already; this takes
-- the first ten, prints rank, name and "$X earned", and picks the state.
function TownBoardLogic.View(rows: { LeaderboardLogic.Row }?, failed: boolean): View
	if rows == nil then
		if failed then
			return { state = "failed", message = TownBoardLogic.FailedText, lines = {} }
		end
		return { state = "loading", message = TownBoardLogic.LoadingText, lines = {} }
	end
	local lines: { Line } = {}
	for _, row in ipairs(rows) do
		if #lines >= TownBoardLogic.Rows then
			break
		end
		local score = LeaderboardLogic.SanitizeScore(row.score) or 0
		local rank = if type(row.rank) == "number" then row.rank else #lines + 1
		table.insert(lines, {
			rank = tostring(rank),
			name = TownBoardLogic.FitName(row.name),
			cash = Util.formatCash(score) .. TownBoardLogic.CashSuffix,
			top = rank <= TownBoardLogic.TopRanks,
		})
	end
	if #lines == 0 then
		return { state = "empty", message = TownBoardLogic.EmptyText, lines = lines }
	end
	return { state = "rows", message = "", lines = lines }
end

-- Placement. The footprint is the posts' outer edges, turned by the board's
-- yaw (the board faces -Z in its own frame). Returns x0, x1, z0, z1.
function TownBoardLogic.Footprint(cf: CFrame): (number, number, number, number)
	local hx = TownBoardLogic.PostX + TownBoardLogic.PostWidth / 2
	local hz = math.max(TownBoardLogic.BoardSize.Z, TownBoardLogic.PostWidth) / 2
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for _, x in ipairs({ -hx, hx }) do
		for _, z in ipairs({ -hz, hz }) do
			local p = cf:PointToWorldSpace(Vector3.new(x, 0, z))
			x0 = math.min(x0, p.X)
			x1 = math.max(x1, p.X)
			z0 = math.min(z0, p.Z)
			z1 = math.max(z1, p.Z)
		end
	end
	return x0, x1, z0, z1
end

-- True when the box overlaps the board's footprint, with `margin` studs of
-- room all round (default none).
function TownBoardLogic.Overlaps(cf: CFrame, x0: number, x1: number, z0: number, z1: number, margin: number?): boolean
	local m = margin or 0
	local a0, a1, b0, b1 = TownBoardLogic.Footprint(cf)
	return a0 - m < x1 and a1 + m > x0 and b0 - m < z1 and b1 + m > z0
end

return TownBoardLogic
