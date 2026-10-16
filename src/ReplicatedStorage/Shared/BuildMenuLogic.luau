--!strict
-- BuildMenuLogic: the pure part of the hammer's "Blueprints" menu (BuildMenuUI):
-- which category each entry is in, how a card reads, how the stick and the
-- D-pad move over the grid, and the layout numbers. No Instances, no services.
-- The rules stay where they are: BlueprintBook.Row says what a card shows and
-- whether it can be placed (price, tier and stage rules are not repeated here),
-- BlueprintBook.Allowed and PlotLogic.Check say what the server will accept.

local BlueprintBook = require(script.Parent.BlueprintBook)
local ItemCatalog = require(script.Parent.ItemCatalog)
local PlotData = require(script.Parent.PlotData)
local PlotLogic = require(script.Parent.PlotLogic)

local BuildMenuLogic = {}

-- Rail order. A category shows only when it has at least one entry. More is
-- the catch-all for pieces with no `kind` (no card art yet), so a sawmill or a
-- glass wall can still be placed from the menu. Labels are 7 letters or fewer.
BuildMenuLogic.Kinds = {
	"Walls",
	"Floors",
	"Doors",
	"Stairs",
	"Roofs",
	"Fences",
	"Indoor",
	"Decor",
	"Houses",
	"More",
} :: { string }

BuildMenuLogic.MoreKind = "More"
BuildMenuLogic.LandLabel = "Land" -- the action row at the bottom of the rail: not a category

export type Category = { kind: string, label: string, entries: { BlueprintBook.Entry } }

local KNOWN: { [string]: boolean } = {}
for _, kind in ipairs(BuildMenuLogic.Kinds) do
	KNOWN[kind] = true
end

-- The category of one entry: its kind, or More.
function BuildMenuLogic.KindOf(entry: BlueprintBook.Entry): string
	local kind = entry.bp.kind
	if type(kind) == "string" and KNOWN[kind] and kind ~= BuildMenuLogic.MoreKind then
		return kind
	end
	return BuildMenuLogic.MoreKind
end

-- The entries (BlueprintBook.Entries order: locked rows last) split into rail
-- categories. Every entry is in exactly one.
function BuildMenuLogic.Categories(entries: { BlueprintBook.Entry }): { Category }
	local by: { [string]: { BlueprintBook.Entry } } = {}
	for _, entry in ipairs(entries) do
		local kind = BuildMenuLogic.KindOf(entry)
		by[kind] = by[kind] or {}
		table.insert(by[kind], entry)
	end
	local out: { Category } = {}
	for _, kind in ipairs(BuildMenuLogic.Kinds) do
		local list = by[kind]
		if list and #list > 0 then
			table.insert(out, { kind = kind, label = kind, entries = list })
		end
	end
	return out
end

export type TileView = {
	id: string,
	name: string,
	sizeText: string,
	cost: number, -- 0 when stocked or free
	state: string, -- "ready" | "cant" | "locked"
	chip: string?, -- the lock or price chip text (locked and cant)
	message: string?, -- what A on a card that cannot go ahead says
	seal: string, -- "Buildings" | "Decor" | "Other"
}

-- How one card reads, built on BlueprintBook.Row.
function BuildMenuLogic.Tile(entry: BlueprintBook.Entry, ctx: BlueprintBook.Context): TileView
	local row = BlueprintBook.Row(entry, ctx)
	local bp = entry.bp
	local state = if row.state == "locked" then "locked" elseif row.state == "cant" then "cant" else "ready"
	local cost = 0
	if entry.stock == 0 and not PlotLogic.FreeToPlace(bp) then
		cost = PlotData.Price(bp)
	end
	return {
		id = entry.id,
		name = row.name,
		sizeText = BlueprintBook.SizeText(bp),
		cost = cost,
		state = state,
		chip = if state ~= "ready" then row.button else nil,
		message = row.message,
		seal = if entry.group == "Buildings" then "Buildings" elseif entry.group == "Decor" then "Decor" else "Other",
	}
end

---------------------------------------------------------------------------
-- Sizes and layout (design px, before any UIScale)
---------------------------------------------------------------------------

export type Sizes = {
	rail: number,
	row: number,
	icon: number,
	bar: number,
	label: number,
	tileW: number,
	tileH: number,
	plate: number,
	name: number,
	minText: number,
	stroke: number,
}

BuildMenuLogic.PhoneSizes = {
	rail = 132,
	row = 56,
	icon = 44,
	bar = 6,
	label = 16,
	tileW = 150,
	tileH = 120,
	plate = 42,
	name = 16,
	minText = 14,
	stroke = 4,
} :: Sizes

BuildMenuLogic.WideSizes = {
	rail = 200,
	row = 60,
	icon = 48,
	bar = 6,
	label = 18,
	tileW = 170,
	tileH = 140,
	plate = 48,
	name = 18,
	minText = 14,
	stroke = 4,
} :: Sizes

function BuildMenuLogic.SizesFor(phone: boolean): Sizes
	return if phone then BuildMenuLogic.PhoneSizes else BuildMenuLogic.WideSizes
end

BuildMenuLogic.Margin = 12 -- the panel's gap to the screen edge
BuildMenuLogic.Pad = 14 -- inside the panel
BuildMenuLogic.RailGap = 12
BuildMenuLogic.Scrollbar = 8
BuildMenuLogic.TileGap = 8
BuildMenuLogic.PlatePad = 8 -- each side of the name inside its plate
BuildMenuLogic.PanelMax = { phone = 724, wide = 960 } -- design px

-- Grid columns: a phone has 3; a computer or a TV fits clamp(floor(gridW / 178), 3, 4).
function BuildMenuLogic.Columns(gridWidth: number, phone: boolean): number
	if phone then
		return 3
	end
	return math.clamp(math.floor(gridWidth / 178), 3, 4)
end

export type Grid = {
	gridW: number,
	cols: number,
	tileW: number, -- a card's real width
	plateTextW: number, -- the room the name has inside its plate
}

-- The grid inside a panel `panelW` wide (design px): its width, columns and
-- the card width that results.
function BuildMenuLogic.GridFor(panelW: number, phone: boolean): Grid
	local sizes = BuildMenuLogic.SizesFor(phone)
	local gridW = panelW - BuildMenuLogic.Pad * 2 - sizes.rail - BuildMenuLogic.RailGap - BuildMenuLogic.Scrollbar
	local cols = BuildMenuLogic.Columns(gridW, phone)
	local tileW = (gridW - BuildMenuLogic.TileGap * (cols - 1)) / cols
	return { gridW = gridW, cols = cols, tileW = tileW, plateTextW = tileW - BuildMenuLogic.PlatePad * 2 }
end

export type Layout = {
	phone: boolean,
	sizes: Sizes,
	panelW: number,
	gridW: number,
	cols: number,
	tileW: number,
	plateTextW: number,
}

-- The numbers the menu is laid out with, in design px. `viewW` is the usable
-- screen width in screen px and `scale` the UIScale (1 on a phone: the menu runs
-- at scale 1 there so a name is 16 real px).
function BuildMenuLogic.Layout(viewW: number, phone: boolean, scale: number): Layout
	local designW = viewW / math.max(scale, 0.01)
	local panelW = math.min(
		designW - BuildMenuLogic.Margin * 2,
		if phone then BuildMenuLogic.PanelMax.phone else BuildMenuLogic.PanelMax.wide
	)
	local grid = BuildMenuLogic.GridFor(panelW, phone)
	return {
		phone = phone,
		sizes = BuildMenuLogic.SizesFor(phone),
		panelW = panelW,
		gridW = grid.gridW,
		cols = grid.cols,
		tileW = grid.tileW,
		plateTextW = grid.plateTextW,
	}
end

-- The colour a card shows when it has no picture (or the picture is still
-- loading): the same swatch the Blueprints rows have always used.
function BuildMenuLogic.Swatch(bp: any): string
	local mill = ItemCatalog.GetSawmill(bp.id)
	local machine = ItemCatalog.GetMachine(bp.id)
	if mill then
		return mill.color
	elseif machine then
		return machine.color
	elseif bp.boxes and bp.boxes[1] then
		return bp.boxes[1].color
	end
	return "#654321"
end

---------------------------------------------------------------------------
-- Navigation (stick and D-pad)
---------------------------------------------------------------------------

export type Direction = "up" | "down" | "left" | "right"

-- Where a D-pad press moves from tile `index` (1-based) in a grid of `count`
-- tiles and `cols` columns. Left and right stay on the row, up and down stay
-- in the column and clamp at the edge; the last row may be short, so a move
-- never lands on a tile that does not exist: down from a column the last row
-- lacks goes to the last tile.
function BuildMenuLogic.Step(count: number, cols: number, index: number, direction: Direction): number
	if count <= 0 then
		return 0
	end
	cols = math.max(cols, 1)
	index = math.clamp(index, 1, count)
	local col = (index - 1) % cols + 1
	if direction == "left" then
		return if col > 1 then index - 1 else index
	elseif direction == "right" then
		return if col < cols and index + 1 <= count then index + 1 else index
	elseif direction == "up" then
		return if index - cols >= 1 then index - cols else index
	end
	-- down
	if index + cols <= count then
		return index + cols
	end
	local row = math.ceil(index / cols)
	local lastRow = math.ceil(count / cols)
	return if row < lastRow then count else index
end

-- The next category along the rail (wraps both ways).
function BuildMenuLogic.NextCategory(index: number, count: number, direction: number): number
	if count <= 0 then
		return 0
	end
	return (index - 1 + (if direction < 0 then -1 else 1)) % count + 1
end

-- Selecting a category selects its first tile.
function BuildMenuLogic.FirstTile(_category: Category): number
	return 1
end

return BuildMenuLogic
