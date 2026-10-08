--!strict
-- QuickMenuLogic: the gamepad's quick menu as pure rules. One button
-- (the View / Select button) opens a panel with a big tile for every HUD
-- destination, in a grid the stick or D-pad walks one step at a time; A
-- opens the tile, B or View again closes it (StarterPlayerScripts/QuickMenuUI
-- draws it; HudNav holds the destinations that HUD buttons register).
--
-- The View button used to open Badges alone (BadgeData.OpenGamepad). Badges
-- is now a tile here, so the button has one job and every bind stays
-- unique (InputKit.Target.menu lists it).

local GamepadNavLogic = require(script.Parent.GamepadNavLogic)

local QuickMenuLogic = {}

-- The one gamepad button that opens it. Not L3 (running), not a D-pad
-- direction (HudRules.PadKeys owns those), not ButtonX/Y/B/A.
QuickMenuLogic.OpenGamepad = Enum.KeyCode.ButtonSelect

QuickMenuLogic.Title = "QUICK MENU"
QuickMenuLogic.Footer = "A select  ·  B close"

-- The tiles' order, by destination id. A destination missing from this
-- list (a new HUD button) goes after these, by label. "hud" is the tile
-- that puts the cursor on the HUD's own buttons.
QuickMenuLogic.Order = {
	"saves",
	"store",
	"badges",
	"daily",
	"guide",
	"settings",
	"land",
	"plans",
	"hammer",
	"tutorial",
	"calltruck",
	"instantdelivery",
	"owner",
	"hud",
} :: { string }

export type Entry = { id: string, label: string }

local rank: { [string]: number } = {}
for i, id in ipairs(QuickMenuLogic.Order) do
	rank[id] = i
end

-- `entries` in tile order: the canonical order above, then unknown ids by
-- label. A repeated id keeps its first entry. The list is a new table.
function QuickMenuLogic.Sort(entries: { Entry }): { Entry }
	local seen: { [string]: boolean } = {}
	local kept: { Entry } = {}
	for _, entry in ipairs(entries) do
		if not seen[entry.id] then
			seen[entry.id] = true
			table.insert(kept, entry)
		end
	end
	table.sort(kept, function(a, b)
		local ra, rb = rank[a.id] or math.huge, rank[b.id] or math.huge
		if ra ~= rb then
			return ra < rb
		end
		if a.label ~= b.label then
			return a.label < b.label
		end
		return a.id < b.id
	end)
	return kept
end

-- A tile's label, capped so a long one fits its tile.
QuickMenuLogic.MaxLabel = 16

function QuickMenuLogic.Label(text: string): string
	local upper = string.upper(text)
	if #upper > QuickMenuLogic.MaxLabel then
		return string.sub(upper, 1, QuickMenuLogic.MaxLabel - 1) .. "…"
	end
	return upper
end

-- The id a HUD side button gets from its name ("Saves" -> "saves").
function QuickMenuLogic.IdFor(name: string): string
	return string.lower((string.gsub(name, "[^%w]", "")))
end

QuickMenuLogic.TileW = 168 -- a tile's UI px: wide for the longest label
QuickMenuLogic.TileH = 64
QuickMenuLogic.MinTileH = 48 -- never smaller than a thumb-free target
QuickMenuLogic.Gap = 12

export type Layout = {
	columns: number,
	rows: number,
	cellW: number,
	cellH: number,
	gap: number,
	gridW: number,
	gridH: number,
	rects: { GamepadNavLogic.Rect },
	links: { [number]: GamepadNavLogic.GridLink },
}

-- The grid for `count` tiles inside `availW` x `availH` UI px (the screen
-- less the panel's own padding, title and footer).
function QuickMenuLogic.Layout(count: number, availW: number, availH: number): Layout
	local columns = GamepadNavLogic.Columns(count)
	-- On a narrow screen use fewer columns, so tiles stay wide enough.
	while columns > 1 and columns * QuickMenuLogic.TileW * 0.75 + (columns - 1) * QuickMenuLogic.Gap > availW do
		columns -= 1
	end
	local cellW, cellH = GamepadNavLogic.FitCell(
		count,
		columns,
		availW,
		availH,
		QuickMenuLogic.TileW,
		QuickMenuLogic.TileH,
		QuickMenuLogic.Gap,
		QuickMenuLogic.MinTileH
	)
	local rects: { GamepadNavLogic.Rect } = {}
	for i = 1, count do
		rects[i] = GamepadNavLogic.GridRect(i, count, columns, cellW, cellH, QuickMenuLogic.Gap)
	end
	local gridW, gridH = GamepadNavLogic.GridSize(count, columns, cellW, cellH, QuickMenuLogic.Gap)
	return {
		columns = math.max(math.min(columns, count), 1),
		rows = if count > 0 then math.ceil(count / math.max(math.min(columns, count), 1)) else 0,
		cellW = cellW,
		cellH = cellH,
		gap = QuickMenuLogic.Gap,
		gridW = gridW,
		gridH = gridH,
		rects = rects,
		links = GamepadNavLogic.GridLinks(count, columns),
	}
end

-- Whether a press closes the open menu: B, Escape, or the open button
-- again.
function QuickMenuLogic.Closes(key: Enum.KeyCode): boolean
	return GamepadNavLogic.Closes(key.Name, QuickMenuLogic.OpenGamepad.Name)
end

-- Whether the open button works right now: not while typing in a text box.
function QuickMenuLogic.CanOpen(typing: boolean): boolean
	return not typing
end

return QuickMenuLogic
