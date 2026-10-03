--!strict
-- SawmillLogic: which logs a sawmill will take, and the planks it cuts
-- (V2_PLAN.md §2e, §7). Pure, so the server (SawmillService), the shop
-- and the economy model agree.
--   * A mill takes one straight chain: one root, no section with two
--     children, every section within 12° of the root, no longer than
--     maxLength u and no thicker than maxWidth u, and big enough for one
--     plank. Planks are refused (milling them again would mint money).
--   * The cut is settings.x by settings.y u across, stepped by PlankStep,
--     kept between the plank minimums and the mill's maxX / maxY. Length
--     runs along the plank, at most maxLength u, and the last plank takes
--     whatever volume is left. PlankYield is 1: the planks' volume is the
--     log's.
--   * Bought mills wait in a stock list (ids, duplicates allowed) until
--     they're placed. EncodeStock / DecodeStock is that list on a player
--     attribute.

local GameConfig = require(script.Parent.GameConfig)
local ItemCatalog = require(script.Parent.ItemCatalog)
local PlotData = require(script.Parent.PlotData)
local SellLogic = require(script.Parent.SellLogic)

local SawmillLogic = {}

export type Mill = ItemCatalog.SawmillDef

export type Settings = { x: number, y: number }

-- One section of a loose piece, in the shape Accepts reads.
export type Section = {
	length: number, -- studs, along the section
	sx: number,
	sz: number,
	dir: Vector3, -- unit along the length
	children: number,
	root: boolean,
}

export type PieceView = {
	kind: string,
	sections: { Section },
}

-- A plank's box in studs. sy is its length.
export type Plank = { sx: number, sy: number, sz: number }

export type Reason = "plank" | "branch" | "crooked" | "long" | "thick" | "small"

SawmillLogic.MaxLean = math.rad(12)

-- Why a log was refused, for a toast. A plank is silent (it just isn't a log).
SawmillLogic.RefuseText = {
	branch = "The mill only takes one straight log, no branches.",
	crooked = "That log is too crooked. Cut it into a straighter piece.",
	long = "Too long for this mill. Cut it shorter.",
	thick = "Too thick for this mill. A bigger mill takes it.",
	small = "That's too small to mill.",
} :: { [string]: string }

local function snap(v: number, lo: number, hi: number): number
	local step = GameConfig.PlankStep
	local n = math.floor(v / step + 0.5) * step
	n = math.floor(n * 1000 + 0.5) / 1000
	return math.clamp(n, lo, hi)
end

-- x and y in u, on the plank grid, inside this mill's cut.
function SawmillLogic.ClampSettings(mill: Mill, x: number, y: number): Settings
	return {
		x = snap(x, GameConfig.PlankMinX, mill.maxX),
		y = snap(y, GameConfig.PlankMinY, mill.maxY),
	}
end

-- A new mill starts at 1.0 by 0.6 u (V2_PLAN §7).
function SawmillLogic.DefaultSettings(mill: Mill): Settings
	return SawmillLogic.ClampSettings(mill, 1, 0.6)
end

-- One press of an X or Y button: `dir` is +1 or -1.
function SawmillLogic.Step(mill: Mill, settings: Settings, axis: string, dir: number): Settings
	local x, y = settings.x, settings.y
	if axis == "x" then
		x += dir * GameConfig.PlankStep
	elseif axis == "y" then
		y += dir * GameConfig.PlankStep
	end
	return SawmillLogic.ClampSettings(mill, x, y)
end

local function aligned(dir: Vector3, first: Vector3): boolean
	if dir.Magnitude < 1e-6 or first.Magnitude < 1e-6 then
		return true
	end
	return math.abs(dir.Unit:Dot(first.Unit)) >= math.cos(SawmillLogic.MaxLean) - 1e-6
end

-- The smallest plank the cut will make: PlankMinX by PlankStep by PlankMinY, in u³.
function SawmillLogic.MinPlankVolume(): number
	return GameConfig.PlankMinX * GameConfig.PlankStep * GameConfig.PlankMinY
end

function SawmillLogic.SectionVolume(section: Section): number
	return SellLogic.VolumeU3(section.sx, section.length, section.sz)
end

-- Whether `piece` may enter `mill`. The reason is nil when it may.
function SawmillLogic.Accepts(piece: PieceView, mill: Mill): (boolean, Reason?)
	if piece.kind == "plank" then
		return false, "plank"
	end
	if #piece.sections == 0 then
		return false, "small"
	end
	local u = GameConfig.WoodUnit
	local roots = 0
	local first: Vector3? = nil
	local length = 0
	local volume = 0
	for _, section in ipairs(piece.sections) do
		if section.children > 1 then
			return false, "branch"
		end
		if section.root then
			roots += 1
			first = section.dir
		end
		if math.max(section.sx, section.sz) > mill.maxWidth * u + 1e-3 then
			return false, "thick"
		end
		length += section.length
		volume += SawmillLogic.SectionVolume(section)
	end
	if roots ~= 1 then
		return false, "branch"
	end
	if length > mill.maxLength * u + 1e-3 then
		return false, "long"
	end
	for _, section in ipairs(piece.sections) do
		if first and not aligned(section.dir, first) then
			return false, "crooked"
		end
	end
	if volume + 1e-6 < SawmillLogic.MinPlankVolume() then
		return false, "small"
	end
	return true, nil
end

-- The planks a log of `volumeU3` becomes at `settings`. Volumes add back
-- to the log (dust under MinPieceVolume folds into the previous plank).
function SawmillLogic.Cut(volumeU3: number, settings: Settings, mill: Mill): { Plank }
	local u = GameConfig.WoodUnit
	local sx = settings.x * u
	local sz = settings.y * u
	local area = sx * sz
	if area <= 1e-8 or volumeU3 <= 0 then
		return {}
	end
	local remaining = volumeU3 * u * u * u
	local maxL = mill.maxLength * u
	local out: { Plank } = {}
	for _ = 1, 80 do
		if remaining <= 1e-4 then
			break
		end
		local length = math.min(maxL, remaining / area)
		if length < 1e-3 then
			break
		end
		local vol = SellLogic.VolumeU3(sx, length, sz)
		if vol < GameConfig.MinPieceVolume then
			local last = out[#out]
			if last and last.sy + length <= maxL + 1e-4 then
				last.sy += length
			end
			break
		end
		table.insert(out, { sx = sx, sy = length, sz = sz })
		remaining -= sx * length * sz
		if length < maxL - 1e-4 then
			break
		end
	end
	return out
end

function SawmillLogic.PlankVolume(planks: { Plank }): number
	local v = 0
	for _, plank in ipairs(planks) do
		v += SellLogic.VolumeU3(plank.sx, plank.sy, plank.sz)
	end
	return v
end

-- How long the blade takes, 1 s for a twig and 3 s by about 30 u³.
function SawmillLogic.ProcessSeconds(volumeU3: number): number
	return 1 + 2 * math.clamp(math.max(0, volumeU3) / 30, 0, 1)
end

-- "Logs up to 17 studs long and 2.2 thick."
function SawmillLogic.LimitText(mill: Mill): string
	local u = GameConfig.WoodUnit
	return string.format("Logs up to %.0f studs long and %.1f thick", mill.maxLength * u, mill.maxWidth * u)
end

function SawmillLogic.Detail(mill: Mill): string
	return SawmillLogic.LimitText(mill) .. "\nPlanks sell for more than logs."
end

-- A PlotLogic blueprint for a mill, so it places, moves and overlaps like
-- any other plot item. `priceCash` is what placing charges when you don't
-- already have one in stock.
function SawmillLogic.Blueprint(id: string): PlotData.Blueprint?
	local mill = ItemCatalog.GetSawmill(id)
	if not mill then
		return nil
	end
	return {
		id = mill.id,
		displayName = mill.displayName,
		category = "Sawmill",
		priceCash = mill.priceCash,
		tier = 1,
		footprint = Vector2.new(mill.width, mill.depth),
		boxes = {},
		note = SawmillLogic.LimitText(mill),
	}
end

function SawmillLogic.EncodeStock(ids: { string }): string
	return table.concat(ids, ",")
end

function SawmillLogic.DecodeStock(text: string): { string }
	local out: { string } = {}
	for id in string.gmatch(text, "[^,]+") do
		if ItemCatalog.GetSawmill(id) then
			table.insert(out, id)
		end
	end
	return out
end

function SawmillLogic.CountStock(ids: { string }, id: string): number
	local n = 0
	for _, have in ipairs(ids) do
		if have == id then
			n += 1
		end
	end
	return n
end

return SawmillLogic
