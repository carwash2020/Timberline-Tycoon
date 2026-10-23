--!strict
-- HammerPicker: the rules of the blueprint picker the hammer opens (T420). Pure,
-- so the picker (BuildMenuUI), PlotUI and the tests agree.
--
--   * Six tabs, always: Walls, Floors, Doors, Roofs, Fences, Supports. A piece
--     with none of those homes (stairs, furniture, houses) goes on an extra tab
--     after them, shown only when it has a piece, so nothing becomes unplaceable.
--   * One card per print: its name, size, a sentence saying what it is for, and
--     what it costs, all from the existing data (PlotData, BlueprintBook,
--     BuildMenuLogic.Tile). Nothing is priced here.
--   * Pad keys: LB and RB change tab, the D-pad moves over the cards, A picks, B
--     (or Esc) closes. The right trigger is never a picker key (it grabs and chops).
--   * Wire is not a print: it is its own item (WireSupply), so no card, tab or
--     category here is about wiring.

local BlueprintBook = require(script.Parent.BlueprintBook)
local BuildMenuLogic = require(script.Parent.BuildMenuLogic)
local PlotData = require(script.Parent.PlotData)

local HammerPicker = {}

HammerPicker.Tabs = { "Walls", "Floors", "Doors", "Roofs", "Fences", "Supports" } :: { string }

-- Extra tabs, after the six, for what the six do not hold.
local EXTRA = { "Stairs", "Indoor", "Decor", "Houses", BuildMenuLogic.MoreKind } :: { string }

-- Pieces that have no `kind` in PlotData, or sit in a kind that is not the tab
-- they belong on. This is the picker's own grouping: PlotData is untouched.
local TAB_OF: { [string]: string } = {
	-- glass walls and the shop front are walls
	PictureWall8 = "Walls",
	PictureWall12 = "Walls",
	TallPictureWall8 = "Walls",
	TallPictureWall12 = "Walls",
	GlassDoorWall8 = "Walls",
	ShopFront12 = "Walls",
	-- the overhang roofs and the roof trims are roofs
	FlatRoofOver8 = "Roofs",
	FlatRoofOver12 = "Roofs",
	FlatRoofOver12x8 = "Roofs",
	Fascia8 = "Roofs",
	Awning8 = "Roofs",
	-- a balcony is a floor you build out
	Balcony8 = "Floors",
	Staircase8 = "Stairs",
	-- what holds the rest up
	Post = "Supports",
	Beam8 = "Supports",
}

-- What each print is for, in a sentence of its own (at most 90 characters, so a
-- card shows it in two short lines).
local BLURB: { [string]: string } = {
	Wall4 = "A short wall, 4 studs. Fills a gap or finishes a corner.",
	Wall = "A straight wall, 8 studs. Most rooms are made of these.",
	Wall12 = "A long wall, 12 studs, for big rooms and the sides of halls.",
	TallWall4 = "A narrow wall, 4 wide and 10 tall. Good beside a door.",
	TallWall8 = "A tall wall, 8 wide and 10 high, for a two-storey front.",
	HalfWall8 = "A low wall, 3 studs high. Fences off a yard or a counter.",
	DoorWall8 = "A wall with a doorway in it. Hang a Door in the gap.",
	WindowWall8 = "A wall with a window opening. Add a Window for glass.",
	SandWall4 = "A sandstone wall, 4 studs. Carry slabs to it to finish it.",
	PictureWall8 = "A mostly glass wall. You see through it, not walk through.",
	PictureWall12 = "A wide glass wall, 12 studs, with a bar in the middle.",
	TallPictureWall8 = "A glass wall 10 tall and 8 wide. Fills a tall room with light.",
	TallPictureWall12 = "A tall glass wall, 12 wide, for a big hall or a shop.",
	GlassDoorWall8 = "A glass wall with a doorway. Hang a Door in it.",
	ShopFront12 = "A glass shop front with a doorway and a solid stall riser.",
	Floor4 = "A small floor, 4 by 4 studs. Patches a gap or floors a closet.",
	Floor = "A square of floor. Lay a few side by side for a room.",
	Foundation8 = "A raised base, 8 by 8 and 2 tall. Lifts a building off the ground.",
	SandFloor4 = "A sandstone floor, 4 by 4. Carry slabs to it to finish it.",
	Balcony8 = "A balcony, 8 by 4, railed at the front and sides.",
	Door = "A door that swings open. Hang it in a door wall.",
	Window = "A pane of glass for a window wall. It stays clear.",
	SandArch8 = "A sandstone arch with a 4 by 6 opening, for a gate.",
	FlatRoof8 = "A flat roof, 8 by 8, with a short overhang.",
	SlopedRoof8 = "A sloped roof, 8 along the eave and 4 deep, rising 3.",
	RoofCorner = "A hip corner, 4 by 4, rising 3. Turns a roof round a corner.",
	RoofRidge8 = "The cap where two slopes meet. Sit it on the roof base.",
	FlatRoofOver8 = "A flat roof, 8 by 8, overhanging 1.5 studs with a dark edge.",
	FlatRoofOver12 = "A big flat roof, 12 by 12, overhanging 1.5 studs all round.",
	FlatRoofOver12x8 = "A wide flat roof, 12 by 8, overhanging 1.5 studs all round.",
	Fascia8 = "A trim band for a roof edge. Resize it, face it toward the roof.",
	Awning8 = "A striped canopy for a shop front. High at the wall.",
	Fence = "A run of fence, 8 studs. Keeps your plot tidy.",
	FenceGate4 = "A gate, 4 studs, that swings open. Goes in a gap in a fence.",
	Railing8 = "An 8-stud railing for a porch, balcony or deck edge.",
	Post = "A 6-stud post. Holds up a porch roof or marks a fence corner.",
	Beam8 = "An 8-stud beam. Spans between posts to carry a roof or floor.",
	Stairs = "A flight of stairs, rising toward the back.",
	Ramp8 = "A ramp rising 2 studs over 8, toward the back.",
	Staircase8 = "Eight steps up one storey, 8 long. The top is at the back.",
}

local GENERIC: { [string]: string } = {
	Indoor = "Furniture for the inside of your building.",
	Decor = "A touch of decoration for your plot.",
	Houses = "A whole building. Place the plan, then fill it with planks.",
	More = "A piece for your plot. Move it, turn it or sell it later.",
	Stairs = "A way up to the next floor.",
}
local GENERIC_ANY = "A piece for your plot. Move it, turn it or sell it later."
local NOTE_MAX = 62 -- a note longer than this does not fit a card's three lines

function HammerPicker.HasBlurb(id: string): boolean
	return BLURB[id] ~= nil
end

-- What this print is for.
function HammerPicker.Explain(bp: PlotData.Blueprint): string
	local own = BLURB[bp.id]
	if own then
		return own
	end
	local tab = BuildMenuLogic.KindOf({ id = bp.id, bp = bp, group = "", stock = 0 })
	if type(bp.note) == "string" and bp.note ~= "" and #bp.note < NOTE_MAX then
		return bp.note .. "."
	end
	return GENERIC[tab] or GENERIC_ANY
end

-- Whether `id` is something the picker offers: a blueprint, not an item such as wire.
function HammerPicker.IsPrint(id: string): boolean
	return PlotData.Blueprint(id) ~= nil
end

-- The tab an entry is on.
function HammerPicker.TabOf(entry: BlueprintBook.Entry): string
	local own = TAB_OF[entry.id]
	if own then
		return own
	end
	return BuildMenuLogic.KindOf(entry)
end

export type Tab = { id: string, label: string, kind: string, entries: { BlueprintBook.Entry } }

-- The six tabs (even with nothing on them), then each extra one that has
-- something. Every entry is on exactly one tab, in the entries' own order.
function HammerPicker.TabList(entries: { BlueprintBook.Entry }): { Tab }
	local by: { [string]: { BlueprintBook.Entry } } = {}
	for _, entry in ipairs(entries) do
		local tab = HammerPicker.TabOf(entry)
		by[tab] = by[tab] or {}
		table.insert(by[tab], entry)
	end
	local out: { Tab } = {}
	for _, label in ipairs(HammerPicker.Tabs) do
		table.insert(out, { id = label, label = label, kind = label, entries = by[label] or {} })
	end
	for _, label in ipairs(EXTRA) do
		local list = by[label]
		if list and #list > 0 then
			table.insert(out, { id = label, label = label, kind = label, entries = list })
		end
	end
	return out
end

export type Card = {
	id: string,
	name: string,
	blurb: string, -- what it is for
	sizeText: string,
	costText: string, -- what it takes and costs, from the plan's own data
	fee: number, -- cash to place it (0 when stocked or free)
	state: string, -- "ready" | "cant" | "locked"
	chip: string?, -- the lock or price chip text
	message: string?, -- what A on a card that cannot go ahead says
	stock: number,
	seal: string,
}

function HammerPicker.Card(entry: BlueprintBook.Entry, ctx: BlueprintBook.Context): Card
	local tile = BuildMenuLogic.Tile(entry, ctx)
	return {
		id = entry.id,
		name = tile.name,
		blurb = HammerPicker.Explain(entry.bp),
		sizeText = tile.sizeText,
		costText = BlueprintBook.NeedsText(entry.bp, entry.stock),
		fee = tile.cost,
		state = tile.state,
		chip = tile.chip,
		message = tile.message,
		stock = entry.stock,
		seal = tile.seal,
	}
end

---------------------------------------------------------------------------
-- Layout (design px, before any UIScale)
---------------------------------------------------------------------------

-- A card is: the picture, the name plate, a blurb of at most `blurbLines` lines
-- and a cost of at most `costLines`. The heights hold exactly those lines.
export type CardSizes = {
	artH: number,
	nameH: number,
	nameText: number,
	blurbText: number,
	blurbLines: number,
	blurbH: number,
	costText: number,
	costLines: number,
	costH: number,
	gap: number,
	h: number, -- the whole card
	pad: number, -- text inset each side
}

local function sizes(artH: number, nameText: number, blurbText: number, costText: number): CardSizes
	local gap = 4
	local nameH = math.ceil(nameText * 1.2) * 2
	local blurbH = math.ceil(blurbText * 1.25) * 3
	local costH = math.ceil(costText * 1.2) * 2
	return {
		artH = artH,
		nameH = nameH,
		nameText = nameText,
		blurbText = blurbText,
		blurbLines = 3,
		blurbH = blurbH,
		costText = costText,
		costLines = 2,
		costH = costH,
		gap = gap,
		h = artH + nameH + blurbH + costH + gap * 4,
		pad = 8,
	}
end

HammerPicker.PhoneCard = sizes(44, 16, 14, 14)
HammerPicker.WideCard = sizes(56, 18, 15, 15)

function HammerPicker.CardSizes(phone: boolean): CardSizes
	return if phone then HammerPicker.PhoneCard else HammerPicker.WideCard
end

-- Cards are wider than the build menu's old tiles, because each one carries a
-- sentence: two across on a phone, three on a computer, up to four on a big TV.
function HammerPicker.Columns(gridWidth: number, phone: boolean): number
	if phone then
		return 2
	end
	return math.clamp(math.floor(gridWidth / 236), 3, 4)
end

export type Grid = { gridW: number, cols: number, tileW: number, textW: number }

-- The card grid inside a panel `panelW` wide: same panel, rail and scrollbar as
-- BuildMenuLogic.GridFor, with this module's columns.
function HammerPicker.GridFor(panelW: number, phone: boolean): Grid
	local base = BuildMenuLogic.GridFor(panelW, phone)
	local cols = HammerPicker.Columns(base.gridW, phone)
	local tileW = (base.gridW - BuildMenuLogic.TileGap * (cols - 1)) / cols
	return { gridW = base.gridW, cols = cols, tileW = tileW, textW = tileW - HammerPicker.CardSizes(phone).pad * 2 }
end

---------------------------------------------------------------------------
-- Selection and navigation
---------------------------------------------------------------------------

export type Direction = BuildMenuLogic.Direction

HammerPicker.Step = BuildMenuLogic.Step

export type State = { tab: number, card: number, effect: string? }

-- One key's effect on the picker. `counts[i]` is how many cards tab `i` holds;
-- `cols` the grid's columns. Tab changes wrap and pick the new tab's first card
-- (0 when it is empty); the D-pad stays on the grid; "select" asks to pick the
-- card (effect "pick") and "close" asks to close (effect "close").
function HammerPicker.Navigate(state: State, action: string, counts: { number }, cols: number): State
	local tabs = #counts
	local tab = math.clamp(state.tab, 1, math.max(tabs, 1))
	local count = counts[tab] or 0
	local card = if count > 0 then math.clamp(state.card, 1, count) else 0
	if action == "tabNext" or action == "tabPrev" then
		local to = BuildMenuLogic.NextCategory(tab, tabs, if action == "tabPrev" then -1 else 1)
		return { tab = to, card = if (counts[to] or 0) > 0 then 1 else 0 }
	elseif action == "up" or action == "down" or action == "left" or action == "right" then
		return { tab = tab, card = BuildMenuLogic.Step(count, cols, card, action :: Direction) }
	elseif action == "select" then
		return { tab = tab, card = card, effect = if card >= 1 then "pick" else nil }
	elseif action == "close" then
		return { tab = tab, card = card, effect = "close" }
	end
	return { tab = tab, card = card }
end

-- The picker's pad and close keys. The right trigger is not one.
HammerPicker.Keys = {
	Enum.KeyCode.ButtonL1,
	Enum.KeyCode.ButtonR1,
	Enum.KeyCode.DPadUp,
	Enum.KeyCode.DPadDown,
	Enum.KeyCode.DPadLeft,
	Enum.KeyCode.DPadRight,
	Enum.KeyCode.ButtonA,
	Enum.KeyCode.ButtonB,
	Enum.KeyCode.Escape,
} :: { Enum.KeyCode }

local ACTION_OF: { [string]: string } = {
	ButtonL1 = "tabPrev",
	ButtonR1 = "tabNext",
	DPadUp = "up",
	DPadDown = "down",
	DPadLeft = "left",
	DPadRight = "right",
	ButtonA = "select",
	ButtonB = "close",
	Escape = "close",
}

function HammerPicker.ActionOf(key: Enum.KeyCode): string?
	return ACTION_OF[key.Name]
end

---------------------------------------------------------------------------
-- When it opens
---------------------------------------------------------------------------

export type EquipState = {
	onPlot: boolean, -- standing on your own plot
	placing: boolean, -- a ghost is out
	panelOpen: boolean, -- the Land panel or a sheet is up
	pickerOpen: boolean,
}

-- Taking the hammer out opens the picker, once, on your own plot, when nothing
-- else has the screen.
function HammerPicker.OpensOnEquip(state: EquipState): boolean
	return state.onPlot and not state.placing and not state.panelOpen and not state.pickerOpen
end

return HammerPicker
