--!strict
-- GamepadNavLogic: how a gamepad moves the GuiService selection between
-- buttons, as pure rules (no Instances, no GuiService), so tests can check
-- them. The client side is StarterPlayerScripts/GamepadNav (panels: focus,
-- trap, restore) and HudNav (the HUD's buttons, wired by these rules).
--
--   * Order: nodes in reading order (rows top to bottom, left to right
--     inside a row). The first one is where a gamepad starts on the HUD.
--   * Links: for every node, which node a push up / down / left / right
--     lands on: the nearest one that way, and with `wrap` the far side
--     when nothing is that way (so every push goes somewhere).
--   * GridLinks / GridRect: the quick menu's tiles, index by index, one
--     step per push, wrapping in rows and columns.
--   * Restore: what closing a panel does with the selection.
--   * Closes: which presses close a panel (B everywhere, and the quick
--     menu's own button).
-- Nodes are screen rectangles: x, y the top-left, w, h the size.

local GamepadNavLogic = {}

export type Node = { id: string, x: number, y: number, w: number, h: number }
export type Link = { up: string?, down: string?, left: string?, right: string? }
export type GridLink = { up: number, down: number, left: number, right: number }
export type Rect = { x: number, y: number, w: number, h: number }

-- Two nodes are one row when their centres are within this fraction of the
-- shorter one's height.
GamepadNavLogic.RowTolerance = 0.6
-- How much a miss across the push counts against a candidate, against the
-- distance along it (nearest by line first, then by distance).
GamepadNavLogic.CrossWeight = 3
-- How far off the line a candidate may be, against how far along it is.
GamepadNavLogic.ConeFactor = 4
-- A wrap lands this much more on the same line than on the far edge.
GamepadNavLogic.WrapCross = 4

GamepadNavLogic.Directions = { "up", "down", "left", "right" }

local function finite(n: number): number
	if n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return n
end

local function centre(node: Node): (number, number)
	return finite(node.x) + finite(node.w) / 2, finite(node.y) + finite(node.h) / 2
end

---------------------------------------------------------------------------
-- Reading order
---------------------------------------------------------------------------

-- The nodes in reading order. Rows are found top to bottom: a node joins
-- the current row when its centre is within RowTolerance of the row's
-- first node's; inside a row they go left to right. Ties keep id order, so
-- the same layout always gives the same list.
function GamepadNavLogic.Order(nodes: { Node }): { Node }
	local byTop: { Node } = table.clone(nodes)
	table.sort(byTop, function(a: Node, b: Node): boolean
		local _, ay = centre(a)
		local _, by = centre(b)
		if ay ~= by then
			return ay < by
		end
		return a.id < b.id
	end)
	local rows: { { Node } } = {}
	local rowY = 0
	local rowH = 0
	for _, node in ipairs(byTop) do
		local _, cy = centre(node)
		local row = rows[#rows]
		local near = math.min(rowH, math.max(finite(node.h), 1)) * GamepadNavLogic.RowTolerance
		if row and math.abs(cy - rowY) <= near then
			table.insert(row, node)
		else
			table.insert(rows, { node })
			rowY = cy
			rowH = math.max(finite(node.h), 1)
		end
	end
	local ordered: { Node } = {}
	for _, row in ipairs(rows) do
		table.sort(row, function(a: Node, b: Node): boolean
			local ax = centre(a)
			local bx = centre(b)
			if ax ~= bx then
				return ax < bx
			end
			return a.id < b.id
		end)
		for _, node in ipairs(row) do
			table.insert(ordered, node)
		end
	end
	return ordered
end

-- Where a gamepad starts: the first node in reading order, or nil.
function GamepadNavLogic.First(nodes: { Node }): Node?
	return GamepadNavLogic.Order(nodes)[1]
end

---------------------------------------------------------------------------
-- Nearest-neighbour links
---------------------------------------------------------------------------

-- How far past each other two spans are (0 when they overlap).
local function gap(aStart: number, aSize: number, bStart: number, bSize: number): number
	local a0, a1 = aStart, aStart + aSize
	local b0, b1 = bStart, bStart + bSize
	return math.max(0, math.max(a0, b0) - math.min(a1, b1))
end

-- Along the push (positive = that way) and across it, from `a` to `b`.
local function along(a: Node, b: Node, dir: string): (number, number)
	local ax, ay = centre(a)
	local bx, by = centre(b)
	if dir == "right" then
		return bx - ax, gap(a.y, a.h, b.y, b.h)
	elseif dir == "left" then
		return ax - bx, gap(a.y, a.h, b.y, b.h)
	elseif dir == "down" then
		return by - ay, gap(a.x, a.w, b.x, b.w)
	end
	return ay - by, gap(a.x, a.w, b.x, b.w)
end

-- The far-edge coordinate a wrap in `dir` looks for (smaller is farther
-- round): the left edge for a push right, and so on.
local function edge(node: Node, dir: string): number
	local cx, cy = centre(node)
	if dir == "right" then
		return cx
	elseif dir == "left" then
		return -cx
	elseif dir == "down" then
		return cy
	end
	return -cy
end

-- The opposite of each direction (a wrap looks behind).
local OPPOSITE: { [string]: string } = { up = "down", down = "up", left = "right", right = "left" }

-- The node a push in `dir` from `from` lands on, among `nodes`, or nil.
-- A candidate has to be that way (its centre past `from`'s along the push)
-- and inside a cone: no further off the line than ConeFactor times how far
-- along it is, so a push never hops to something on the other side of the
-- screen that only happens to be a little lower.
local function pick(from: Node, nodes: { Node }, dir: string, wrap: boolean): Node?
	local best: Node? = nil
	local bestScore = math.huge
	for _, other in ipairs(nodes) do
		if other.id ~= from.id then
			local primary, across = along(from, other, dir)
			if primary > 1 and across <= primary * GamepadNavLogic.ConeFactor then
				local score = primary + GamepadNavLogic.CrossWeight * across
				if score < bestScore or (score == bestScore and best ~= nil and other.id < best.id) then
					best, bestScore = other, score
				end
			end
		end
	end
	if best or not wrap then
		return best
	end
	-- Nothing that way: go round to the far side, keeping to the same line
	-- where there is one. Only what is behind us counts (the bottom of the
	-- screen for a push up from the top); on a single line, anything else.
	local behind = OPPOSITE[dir]
	local pool: { Node } = {}
	for _, other in ipairs(nodes) do
		if other.id ~= from.id and (along(from, other, behind)) > 1 then
			table.insert(pool, other)
		end
	end
	if #pool == 0 then
		for _, other in ipairs(nodes) do
			if other.id ~= from.id then
				table.insert(pool, other)
			end
		end
	end
	local lowest = math.huge
	for _, other in ipairs(pool) do
		lowest = math.min(lowest, edge(other, dir))
	end
	bestScore = math.huge
	for _, other in ipairs(pool) do
		local _, across = along(from, other, dir)
		local score = GamepadNavLogic.WrapCross * across + (edge(other, dir) - lowest)
		if score < bestScore or (score == bestScore and best ~= nil and other.id < best.id) then
			best, bestScore = other, score
		end
	end
	return best
end

-- For every node, the node each push lands on. `wrap` (the default is on)
-- sends a push with nothing in that direction round to the far side; with
-- one node, every push stays on it.
function GamepadNavLogic.Links(nodes: { Node }, wrap: boolean?): { [string]: Link }
	local wraps = wrap ~= false
	local links: { [string]: Link } = {}
	for _, node in ipairs(nodes) do
		local link: Link = {}
		for _, dir in ipairs(GamepadNavLogic.Directions) do
			local target = pick(node, nodes, dir, wraps);
			(link :: any)[dir] = if target then target.id else (if wraps and #nodes == 1 then node.id else nil)
		end
		links[node.id] = link
	end
	return links
end

---------------------------------------------------------------------------
-- A grid of tiles (the quick menu)
---------------------------------------------------------------------------

-- How many columns `count` tiles use: one row of up to 3, then 3 across up
-- to 9, then 4.
function GamepadNavLogic.Columns(count: number): number
	if count <= 3 then
		return math.max(count, 1)
	elseif count <= 9 then
		return 3
	end
	return 4
end

-- The tile each push lands on, by 1-based index, for `count` tiles in
-- `columns` columns filled left to right then down. Every push moves one
-- step and wraps: left from the first column goes to the row's last tile,
-- up from the top goes to the bottom of the same column (or the last tile
-- when that column is short), and so on.
function GamepadNavLogic.GridLinks(count: number, columns: number): { [number]: GridLink }
	local links: { [number]: GridLink } = {}
	if count < 1 then
		return links
	end
	local cols = math.clamp(math.floor(columns), 1, count)
	local rows = math.ceil(count / cols)
	for i = 1, count do
		local row = math.floor((i - 1) / cols)
		local col = (i - 1) % cols
		local rowFirst = row * cols + 1
		local rowLast = math.min(rowFirst + cols - 1, count)
		local left = if i == rowFirst then rowLast else i - 1
		local right = if i == rowLast then rowFirst else i + 1
		local function at(r: number): number
			local index = r * cols + col + 1
			return if index > count then count else index
		end
		links[i] = {
			up = at((row - 1) % rows),
			down = at((row + 1) % rows),
			left = left,
			right = right,
		}
	end
	return links
end

-- Tile `index`'s rectangle in a grid of `columns` columns, cells
-- `cellW` x `cellH` with `gap` between, from the grid's top-left. The last
-- row is centred when it is short.
function GamepadNavLogic.GridRect(
	index: number,
	count: number,
	columns: number,
	cellW: number,
	cellH: number,
	gapPx: number
): Rect
	local cols = math.clamp(math.floor(columns), 1, math.max(count, 1))
	local row = math.floor((index - 1) / cols)
	local col = (index - 1) % cols
	local inRow = math.min(cols, count - row * cols)
	local rowW = inRow * cellW + (inRow - 1) * gapPx
	local fullW = cols * cellW + (cols - 1) * gapPx
	local lead = (fullW - rowW) / 2
	return { x = lead + col * (cellW + gapPx), y = row * (cellH + gapPx), w = cellW, h = cellH }
end

-- The whole grid's size.
function GamepadNavLogic.GridSize(
	count: number,
	columns: number,
	cellW: number,
	cellH: number,
	gapPx: number
): (number, number)
	if count < 1 then
		return 0, 0
	end
	local cols = math.clamp(math.floor(columns), 1, count)
	local rows = math.ceil(count / cols)
	return cols * cellW + (cols - 1) * gapPx, rows * cellH + (rows - 1) * gapPx
end

-- The cell size that fits `count` tiles in `columns` columns inside
-- `availW` x `availH`: the wanted size (`wantW` x `wantH`), shrunk evenly
-- (never below `minH` tall) when the grid would not fit.
function GamepadNavLogic.FitCell(
	count: number,
	columns: number,
	availW: number,
	availH: number,
	wantW: number,
	wantH: number,
	gapPx: number,
	minH: number
): (number, number)
	local cols = math.clamp(math.floor(columns), 1, math.max(count, 1))
	local rows = math.ceil(math.max(count, 1) / cols)
	local w = math.min(wantW, (availW - (cols - 1) * gapPx) / cols)
	local h = math.min(wantH, (availH - (rows - 1) * gapPx) / rows)
	return math.max(w, 1), math.max(h, math.min(minH, wantH))
end

---------------------------------------------------------------------------
-- Opening and closing a panel
---------------------------------------------------------------------------

-- Where the selection goes back to when a panel closes, as plain facts
-- about the button that opened it (`opener`, nil when the panel opened
-- with nothing selected, as the D-pad shortcuts do), and where the
-- selection is now:
--   * "opener": the selection was inside the panel (or on nothing) and the
--     opener is still there to land on;
--   * "clear": the selection was inside the panel (or on nothing) and
--     there is nowhere to go back to: walking again;
--   * "keep": the selection is already somewhere else (the player moved
--     on, another panel took it): leave it.
export type Opener = { shown: boolean, selectable: boolean }

function GamepadNavLogic.Restore(
	opener: Opener?,
	selectionInside: boolean,
	selectionNone: boolean
): "opener" | "clear" | "keep"
	if not (selectionInside or selectionNone) then
		return "keep"
	end
	if opener and opener.shown and opener.selectable then
		return "opener"
	end
	return if selectionNone then "keep" else "clear"
end

-- Which button a panel opened now remembers as its opener: the one the
-- caller named (`returnTo`, the quick menu naming the HUD button of what it
-- opens), else the one selected now when it isn't inside the new panel,
-- else none.
function GamepadNavLogic.Opener<T>(returnTo: T?, selected: T?, selectedInsidePanel: boolean): T?
	if returnTo ~= nil then
		return returnTo
	end
	if selected ~= nil and not selectedInsidePanel then
		return selected
	end
	return nil
end

-- The presses that close an open panel on a gamepad: B, and the quick
-- menu's own button (names of KeyCodes). Escape is the keyboard's.
GamepadNavLogic.CloseKeys = { "ButtonB", "Escape" }

function GamepadNavLogic.Closes(keyName: string, quickKeyName: string?): boolean
	if keyName == quickKeyName then
		return true
	end
	for _, name in ipairs(GamepadNavLogic.CloseKeys) do
		if name == keyName then
			return true
		end
	end
	return false
end

-- The size HUD buttons get on a gamepad, so a stick can't miss them: at
-- least `minW` x `minH` (UI px) whatever the keyboard size was.
GamepadNavLogic.PadButtonW = 160
GamepadNavLogic.PadButtonH = 48

function GamepadNavLogic.PadSize(w: number, h: number): (number, number)
	return math.max(w, GamepadNavLogic.PadButtonW), math.max(h, GamepadNavLogic.PadButtonH)
end

return GamepadNavLogic
