--!strict
-- KitPaint: the paint for a plot's kit pieces. Pure, so the server (which
-- decides), the hammer's palette (which draws) and the tests agree.
--
--   * A piece is painted by id from a short palette. "natural" is the
--     default and the current look: the wood you filled it with shows. Any
--     other id covers the piece's wood and trim with that colour (glass and
--     glow never take paint).
--   * Paint is cosmetic and free. It is saved on the placed piece
--     (`paint`, ProfileSchema) and is not part of the fee, the planks, the
--     piece's size or what it sells for.
--   * Only kit pieces are painted. A prebuilt shed or cabin is not (its
--     look is a model, not parts that take a tint).

local KitPaint = {}

export type Swatch = {
	id: string,
	name: string,
	color: string, -- hex; "natural" has none (the wood shows)
}

KitPaint.Natural = "natural"
KitPaint.Material = "SmoothPlastic" -- a painted surface is smooth, not grained
-- Roles (BlueprintModels) that take paint. Glass, Glow, Sign and the rest do not.
KitPaint.Roles = { "Wood", "Door", "Trim" } :: { string }
-- How far the painter may stand from the piece (studs). Building reach is a
-- plot's edge plus a margin (PlotService), this is the brush.
KitPaint.Reach = 40

-- Twelve, in the order the palette shows them: the wood itself, then the
-- whites, darks and a spread of house colours (modern white and charcoal,
-- dark brown, brick, sage, mustard).
KitPaint.Palette = {
	{ id = "natural", name = "Wood (natural)", color = "" },
	{ id = "white", name = "White", color = "#F4F4F0" },
	{ id = "offwhite", name = "Off-white", color = "#E4DFD0" },
	{ id = "charcoal", name = "Charcoal", color = "#3A3D42" },
	{ id = "black", name = "Black", color = "#1C1C1E" },
	{ id = "darkbrown", name = "Dark brown", color = "#4A3224" },
	{ id = "redbrown", name = "Red-brown", color = "#7A3B2A" },
	{ id = "tan", name = "Tan", color = "#C4A67A" },
	{ id = "slate", name = "Slate blue", color = "#5F7A94" },
	{ id = "sage", name = "Sage green", color = "#8FA58A" },
	{ id = "brick", name = "Brick red", color = "#A8412F" },
	{ id = "mustard", name = "Mustard", color = "#D9A935" },
} :: { Swatch }

local byId: { [string]: Swatch } = {}
for _, swatch in ipairs(KitPaint.Palette) do
	byId[swatch.id] = swatch
end

function KitPaint.Get(id: unknown): Swatch?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

-- A real palette id (natural included).
function KitPaint.Valid(id: unknown): boolean
	return KitPaint.Get(id) ~= nil
end

-- What a save keeps: nil for natural, for anything not on the palette, and
-- for junk. A kept id is always a real colour.
function KitPaint.Clean(id: unknown): string?
	local swatch = KitPaint.Get(id)
	if swatch == nil or swatch.id == KitPaint.Natural then
		return nil
	end
	return swatch.id
end

-- The id a piece shows (natural when it has none).
function KitPaint.Of(item: { paint: string? }?): string
	if item == nil then
		return KitPaint.Natural
	end
	return KitPaint.Clean(item.paint) or KitPaint.Natural
end

function KitPaint.TakesPaint(role: unknown): boolean
	return type(role) == "string" and table.find(KitPaint.Roles, role) ~= nil
end

export type Blueprint = { kit: boolean?, id: string }

-- Whether this blueprint's pieces can be painted: kit pieces only.
function KitPaint.CanPaint(bp: Blueprint?): boolean
	return bp ~= nil and bp.kit == true
end

KitPaint.Reasons = { "piece", "color", "far", "same" } :: { string }

-- May `paintId` go on a piece of `bp`, painted from `distance` studs away?
-- (true, nil) or (false, reason). "same" is not an error to tell the player
-- about: the piece already wears it.
function KitPaint.Check(bp: Blueprint?, current: unknown, paintId: unknown, distance: number): (boolean, string?)
	if not KitPaint.CanPaint(bp) then
		return false, "piece"
	end
	if not KitPaint.Valid(paintId) then
		return false, "color"
	end
	if distance ~= distance or distance < 0 or distance > KitPaint.Reach then
		return false, "far"
	end
	local want = KitPaint.Clean(paintId) or KitPaint.Natural
	local have = KitPaint.Clean(current) or KitPaint.Natural
	if want == have then
		return false, "same"
	end
	return true, nil
end

function KitPaint.Message(reason: string?): string?
	if reason == "piece" then
		return "Only walls, floors, roofs and the other building pieces take paint."
	elseif reason == "color" then
		return "That isn't one of the paints."
	elseif reason == "far" then
		return "Too far from it to paint."
	end
	return nil
end

return KitPaint
