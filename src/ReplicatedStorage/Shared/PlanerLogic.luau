--!strict
-- PlanerLogic: the Planer line (V2_PLAN.md §2h), a plot machine that turns a
-- plank into a finished board. Pure, so the server (PlanerService), the
-- shop, the client panel and the specs agree.
--
--   * Four tiers (Hand, Bench, Steam, Industrial), each dearer and each with
--     a bigger boardBonus: the multiplier on the sale value of a board it
--     finishes. The bonus is stamped on the piece when it is planed (a board
--     keeps the bonus of the planer that finished it, like a plank keeps its
--     mill's) and SellLogic.PieceValue applies it, server-side only.
--   * The planer has a setting, x by y u, in steps on its tier's grid and
--     inside its tier's range. A plank wider or thicker than the setting
--     is planed down to it (the shavings are lost, so the board is smaller);
--     a plank smaller than the setting is refused, never grown.
--   * One whole plank at a time (one section, no branches). A board that is
--     already finished is refused: planing twice never stacks the bonus.
--   * Boxed, sold at the Tool Shed, opened into a one-time placement ghost on
--     YOUR plot. The owner only. MaxPerPlot planers on a plot: they are the
--     late-game sink, and a plot with more than two lines of planers stops
--     being a plot you tend and becomes a factory floor. The shop refuses a
--     box past the cap (ShopRefusal) and the placer refuses to place past it
--     (PlaceRefusal), whichever comes first.

local GameConfig = require(script.Parent.GameConfig)
local ItemCatalog = require(script.Parent.ItemCatalog)
local PlotData = require(script.Parent.PlotData)
local SellLogic = require(script.Parent.SellLogic)

local PlanerLogic = {}

export type Def = ItemCatalog.PlanerDef
export type Settings = { x: number, y: number }

PlanerLogic.MaxPerPlot = 2
PlanerLogic.Tag = "Planer"
PlanerLogic.PromptRange = 12
-- A plank rests this long in the intake before the rollers take it.
PlanerLogic.Settle = 0.3

-- A plank's box in studs. sy is its length.
export type Plank = { sx: number, sy: number, sz: number }

export type Reason = "kind" | "branch" | "done" | "long" | "thick" | "small" | "size"

function PlanerLogic.IsPlaner(id: unknown): boolean
	if type(id) ~= "string" then
		return false
	end
	local machine = ItemCatalog.GetMachine(id)
	return machine ~= nil and machine.planer ~= nil
end

-- The machine and its tier numbers, or nil for anything that is not a planer.
function PlanerLogic.Get(id: unknown): (ItemCatalog.MachineDef?, Def?)
	if type(id) ~= "string" then
		return nil, nil
	end
	local machine = ItemCatalog.GetMachine(id)
	if machine and machine.planer then
		return machine, machine.planer
	end
	return nil, nil
end

-- Every planer, cheapest first (tier order).
function PlanerLogic.List(): { ItemCatalog.MachineDef }
	local out: { ItemCatalog.MachineDef } = {}
	for _, machine in ipairs(ItemCatalog.MachineList()) do
		if machine.planer then
			table.insert(out, machine)
		end
	end
	table.sort(out, function(a, b)
		return (a.planer :: Def).tier < (b.planer :: Def).tier
	end)
	return out
end

local function snap(v: number, lo: number, hi: number, step: number): number
	local n = math.floor(v / step + 0.5) * step
	n = math.floor(n * 1000 + 0.5) / 1000
	return math.clamp(n, lo, hi)
end

-- x and y in u, on this tier's grid and inside its range.
function PlanerLogic.Clamp(def: Def, x: number, y: number): Settings
	local nx = if x == x then x else 1
	local ny = if y == y then y else 0.6
	return { x = snap(nx, def.minX, def.maxX, def.step), y = snap(ny, def.minY, def.maxY, def.step) }
end

-- A new planer starts at 1.0 by 0.6 u, the sawmill's own start, so a
-- default plank passes through at its own size.
function PlanerLogic.Default(def: Def): Settings
	return PlanerLogic.Clamp(def, 1, 0.6)
end

-- One press: `dir` is +1 or -1; anything else changes nothing.
function PlanerLogic.Step(def: Def, settings: Settings, axis: string, dir: number): Settings
	local x, y = settings.x, settings.y
	if axis == "x" and (dir == 1 or dir == -1) then
		x += dir * def.step
	elseif axis == "y" and (dir == 1 or dir == -1) then
		y += dir * def.step
	end
	return PlanerLogic.Clamp(def, x, y)
end

-- What a piece view needs for planing: the one section's size and the
-- piece kind (SawmillLogic's PieceView shape, so SawmillService's reader is shared).
export type View = {
	kind: string,
	finished: boolean?,
	sections: { { length: number, sx: number, sz: number, children: number } },
}

local EPS = 1e-3

-- Whether `view` may go through a planer set to `settings`, and the size it
-- comes out at (studs, same orientation, same length). A bigger plank is
-- planed down; a smaller one is refused. Sizes are measured by the server.
function PlanerLogic.Plane(view: View, def: Def, settings: Settings): (boolean, Reason?, Plank?)
	if view.kind ~= "plank" then
		return false, "kind", nil
	end
	if view.finished == true then
		return false, "done", nil
	end
	if #view.sections ~= 1 or view.sections[1].children > 0 then
		return false, "branch", nil
	end
	local section = view.sections[1]
	local sx, sy, sz = section.sx, section.length, section.sz
	if sx ~= sx or sy ~= sy or sz ~= sz or sx <= 0 or sy <= 0 or sz <= 0 then
		return false, "size", nil
	end
	local u = GameConfig.WoodUnit
	if sy > def.maxLength * u + EPS then
		return false, "long", nil
	end
	local big, small = math.max(sx, sz), math.min(sx, sz)
	if big > math.max(def.maxX, def.maxY) * u + EPS or small > math.min(def.maxX, def.maxY) * u + EPS then
		return false, "thick", nil
	end
	local wantBig = math.max(settings.x, settings.y) * u
	local wantSmall = math.min(settings.x, settings.y) * u
	if big + EPS < wantBig or small + EPS < wantSmall then
		return false, "small", nil
	end
	-- Keep the plank's own orientation: its wider side stays its wider side.
	local out: Plank
	if sx >= sz then
		out = { sx = wantBig, sy = sy, sz = wantSmall }
	else
		out = { sx = wantSmall, sy = sy, sz = wantBig }
	end
	return true, nil, out
end

-- u³ of a plank size.
function PlanerLogic.Volume(p: Plank): number
	return SellLogic.VolumeU3(p.sx, p.sy, p.sz)
end

-- How long the rollers take, 1 s for a twig and 2.5 s by about 30 u³.
function PlanerLogic.ProcessSeconds(volumeU3: number): number
	return 1 + 1.5 * math.clamp(math.max(0, volumeU3) / 30, 0, 1)
end

-- The bonus a planer stamps, clamped like a save would be.
function PlanerLogic.Bonus(def: Def): number
	return SellLogic.Bonus(def.boardBonus)
end

-- The bonus a finished board ends up with: the planer's, or the board's own
-- if it was somehow higher. Never lowers a stamp.
function PlanerLogic.Stamp(existing: number?, def: Def): number
	return math.max(SellLogic.Bonus(existing), PlanerLogic.Bonus(def))
end

---------------------------------------------------------------------------
-- Words
---------------------------------------------------------------------------

function PlanerLogic.BonusText(def: Def): string
	return string.format("+%d%%", math.floor((PlanerLogic.Bonus(def) - 1) * 100 + 0.5))
end

-- "Steam (tier 3 of 4)".
function PlanerLogic.TierText(machine: ItemCatalog.MachineDef): string
	local def = machine.planer :: Def
	return string.format("%s (tier %d of %d)", machine.tierName or machine.displayName, def.tier, #PlanerLogic.List())
end

function PlanerLogic.SizeText(settings: Settings): string
	return string.format("%.2f × %.2f u", settings.x, settings.y)
end

function PlanerLogic.RangeText(def: Def): string
	return string.format("up to %.1f × %.1f u, steps of %s", def.maxX, def.maxY, tostring(def.step))
end

function PlanerLogic.Detail(machine: ItemCatalog.MachineDef): string
	local def = machine.planer :: Def
	return string.format(
		"%s planer. Planks in, finished boards out. Boards sell for %s more.\nPlanes down to %s.",
		machine.tierName or machine.displayName,
		PlanerLogic.BonusText(def),
		PlanerLogic.RangeText(def)
	)
end

function PlanerLogic.Toast(reason: string, def: Def?): string?
	if reason == "kind" then
		return "The planer only takes planks, not logs."
	elseif reason == "branch" then
		return "The planer takes one whole plank at a time."
	elseif reason == "done" then
		return "That board is already finished."
	elseif reason == "long" and def then
		return string.format("Too long for this planer (max %.1f u).", def.maxLength)
	elseif reason == "thick" and def then
		return string.format("Too big for this planer (max %.1f × %.1f u).", def.maxX, def.maxY)
	elseif reason == "small" then
		return "That plank is smaller than the planer's setting. Lower the setting."
	elseif reason == "size" then
		return "That plank isn't the size the planer measured."
	end
	return nil
end

---------------------------------------------------------------------------
-- Limits per plot
---------------------------------------------------------------------------

PlanerLogic.OnlyOwnerLine = "Only the plot's owner can put a planer down."

function PlanerLogic.CapLine(): string
	return string.format("A plot has room for %d planers. Take one apart first.", PlanerLogic.MaxPerPlot)
end

function PlanerLogic.CapShopLine(): string
	return string.format(
		"You already have %d planers (placed or waiting in a box). A plot only has room for that many.",
		PlanerLogic.MaxPerPlot
	)
end

-- How many planers are in a list of placed items.
function PlanerLogic.CountPlaced(placed: { any }?): number
	local n = 0
	if type(placed) == "table" then
		for _, item in ipairs(placed) do
			if type(item) == "table" and PlanerLogic.IsPlaner(item.blueprintId) then
				n += 1
			end
		end
	end
	return n
end

-- Whether a placing is refused: not the owner, or the plot is full.
function PlanerLogic.PlaceRefusal(blueprintId: string, isOwner: boolean, placed: { any }?): string?
	if not PlanerLogic.IsPlaner(blueprintId) then
		return nil
	end
	if not isOwner then
		return PlanerLogic.OnlyOwnerLine
	end
	if PlanerLogic.CountPlaced(placed) >= PlanerLogic.MaxPerPlot then
		return PlanerLogic.CapLine()
	end
	return nil
end

export type Holdings = {
	placed: { any }?, -- the plot's placed items
	stock: { any }?, -- profile.sawmillStock (legacy ids waiting)
	storage: { any }?, -- profile.storage (boxes kept in the save): { itemId }
	boxed: number?, -- unopened planer boxes held in the world right now
}

-- Planers a player has: placed, waiting, or in a box.
function PlanerLogic.Held(h: Holdings): number
	local n = PlanerLogic.CountPlaced(h.placed)
	if type(h.stock) == "table" then
		for _, id in ipairs(h.stock :: { any }) do
			if PlanerLogic.IsPlaner(id) then
				n += 1
			end
		end
	end
	if type(h.storage) == "table" then
		for _, entry in ipairs(h.storage :: { any }) do
			if type(entry) == "table" and PlanerLogic.IsPlaner(entry.itemId) then
				n += 1
			end
		end
	end
	return n + math.max(0, h.boxed or 0)
end

-- Why the shop won't sell another planer, or nil.
function PlanerLogic.ShopRefusal(itemId: string, h: Holdings): string?
	if not PlanerLogic.IsPlaner(itemId) then
		return nil
	end
	if PlanerLogic.Held(h) >= PlanerLogic.MaxPerPlot then
		return PlanerLogic.CapShopLine()
	end
	return nil
end

-- A PlotLogic blueprint so a planer overlaps, moves and turns like any plot
-- item. It is never in the blueprint book: it is placed from its box.
function PlanerLogic.Blueprint(id: string): PlotData.Blueprint?
	local machine, def = PlanerLogic.Get(id)
	if not machine or not def then
		return nil
	end
	return {
		id = machine.id,
		displayName = machine.displayName,
		category = "Machine",
		priceCash = machine.priceCash,
		tier = 1,
		footprint = Vector2.new(def.width, def.depth),
		boxes = {
			{
				size = Vector3.new(def.width, 6, def.depth),
				offset = Vector3.new(0, 3, 0),
				color = "#8C8680",
				material = "Wood",
			},
		},
		note = PlanerLogic.Detail(machine),
	}
end

return PlanerLogic
