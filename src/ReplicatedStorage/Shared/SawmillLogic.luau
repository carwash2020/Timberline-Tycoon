--!strict
-- SawmillLogic: which wood a sawmill will take, and the planks it cuts
-- (V2_PLAN.md §2e, §7). Pure, so the server (SawmillService), the shop
-- and the economy model agree.
--   * A mill takes one straight chain: one root, no section with two
--     children, every section within 12° of the root, no longer than
--     maxLength u and no thicker than maxWidth u, and big enough for one
--     plank. A plank (kind "plank") is cut again the same way. The output
--     is always planks, so a plank never comes back as a log.
--   * The cut is settings.x by settings.y u across, stepped by PlankStep,
--     kept between the plank minimums and the mill's maxX / maxY. Length
--     runs along the plank, at most maxLength u, and the last plank takes
--     whatever volume is left. PlankYield is 1: the planks' volume is the
--     piece's, including a plank milled again.
--   * A cross-section thinner than the plank minimums is refused. The
--     server measures the parts at intake; a recorded volume that doesn't
--     match those parts is refused too.
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

export type Reason = "branch" | "crooked" | "long" | "thick" | "small" | "thin" | "size"

SawmillLogic.MaxLean = math.rad(12)

-- What a mill emits. Re-milling a plank stays on this kind.
SawmillLogic.OutputKind = "plank"

-- Faster than this (studs/s) the piece is still in flight. The conveyor
-- itself is slower (GameConfig.ConveyorSpeed).
SawmillLogic.RestSpeed = 20

-- The cut panel. Face is the button box in offset pixels, before any
-- screen scale, so a 667×375 phone (scale about 0.78, and never under
-- 0.7) still draws it at least 44 px. Text stays at least 14 px.
SawmillLogic.PanelFacePx = 64
SawmillLogic.PanelFaceTvPx = 96
SawmillLogic.PanelTextPx = 20

-- The board on the mill, in the surface canvas (PixelsPerStud below).
SawmillLogic.SurfaceButtonPx = 48
SawmillLogic.SurfacePixelsPerStud = 40
SawmillLogic.BlockageLabel = "BLOCKAGE"

-- How far the "Set the cut" prompt reaches. The server's own reach is
-- wider (SawmillService.ReachPad plus the mill); this is the prompt.
SawmillLogic.PromptRange = 12

-- Keys for the open cut panel. They are not world prompts: nothing here
-- is ButtonX or keyboard E, so a placer can stay up beside them
-- (InputKit.PlacerSafe). The D-pad literals live here, not in the client
-- controller, so the HUD's always-on shortcuts stay the only D-pad binds
-- in StarterPlayerScripts. The panel listens only while it is open.
SawmillLogic.PanelBinds = {
	{ action = "CutXMinus", gamepad = Enum.KeyCode.DPadLeft, keyboard = Enum.KeyCode.Left },
	{ action = "CutXPlus", gamepad = Enum.KeyCode.DPadRight, keyboard = Enum.KeyCode.Right },
	{ action = "CutYPlus", gamepad = Enum.KeyCode.DPadUp, keyboard = Enum.KeyCode.Up },
	{ action = "CutYMinus", gamepad = Enum.KeyCode.DPadDown, keyboard = Enum.KeyCode.Down },
	{ action = "CloseCut", gamepad = Enum.KeyCode.ButtonB, keyboard = Enum.KeyCode.Escape },
}

function SawmillLogic.PanelFace(tenFoot: boolean): number
	return if tenFoot then SawmillLogic.PanelFaceTvPx else SawmillLogic.PanelFacePx
end

-- One press on the open panel: axis and direction, or nothing if this key
-- doesn't change the cut.
function SawmillLogic.PadStep(key: Enum.KeyCode): (string?, number?)
	if key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.Left then
		return "x", -1
	elseif key == Enum.KeyCode.DPadRight or key == Enum.KeyCode.Right then
		return "x", 1
	elseif key == Enum.KeyCode.DPadDown or key == Enum.KeyCode.Down then
		return "y", -1
	elseif key == Enum.KeyCode.DPadUp or key == Enum.KeyCode.Up then
		return "y", 1
	end
	return nil, nil
end

function SawmillLogic.PanelCloses(key: Enum.KeyCode): boolean
	return key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Escape
end

-- The throat sign, for a piece the opening can't take.
function SawmillLogic.ShowsBlockage(reason: string): boolean
	return reason == "long" or reason == "thick" or reason == "thin"
end

-- Why a piece was refused, for a toast. `mill` names the limit on a piece
-- that doesn't fit the opening.
function SawmillLogic.Toast(reason: string, mill: Mill?): string?
	if reason == "thick" and mill then
		return string.format("Too big for this mill (max %.1f u wide)", mill.maxWidth)
	elseif reason == "long" and mill then
		return string.format("Too big for this mill (max %.1f u long)", mill.maxLength)
	elseif reason == "thin" then
		return "Too thin for this mill."
	elseif reason == "size" then
		return "That piece isn't the size the mill measured."
	elseif reason == "branch" then
		return "The mill only takes one straight log, no branches."
	elseif reason == "crooked" then
		return "That log is too crooked. Cut it into a straighter piece."
	elseif reason == "small" then
		return "That's too small to mill."
	end
	return nil
end

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

-- The parts' real volume in u³, or -1 when a section isn't a real box
-- (a zero, a negative, or a NaN). Callers cut this, not a cached number.
function SawmillLogic.MeasuredVolume(piece: PieceView): number
	local v = 0
	for _, section in ipairs(piece.sections) do
		local length, sx, sz = section.length, section.sx, section.sz
		if length ~= length or sx ~= sx or sz ~= sz or length <= 0 or sx <= 0 or sz <= 0 then
			return -1
		end
		v += SawmillLogic.SectionVolume(section)
	end
	return v
end

-- The server's recorded volume agrees with the parts measured at intake.
-- No record (0) trusts the parts. A mismatch is a resized piece.
function SawmillLogic.VolumeMatches(recorded: number, measured: number): boolean
	if measured ~= measured or measured < 0 then
		return false
	end
	if recorded <= 0 then
		return measured > 0
	end
	return math.abs(recorded - measured) <= 1e-3
end

-- True when the piece has come to rest. A fling stays above RestSpeed.
function SawmillLogic.Rested(speed: number): boolean
	return speed == speed and speed >= 0 and speed <= SawmillLogic.RestSpeed
end

-- The thinner cross-axis must clear the smaller plank minimum, and the
-- wider one the larger. A sheet or a rod under that is too thin to cut.
local function paper(sx: number, sz: number, u: number): boolean
	local lo = math.min(sx, sz)
	local hi = math.max(sx, sz)
	local floorLo = math.min(GameConfig.PlankMinX, GameConfig.PlankMinY) * u
	local floorHi = math.max(GameConfig.PlankMinX, GameConfig.PlankMinY) * u
	return lo + 1e-3 < floorLo or hi + 1e-3 < floorHi
end

-- Whether `piece` may enter `mill`. The reason is nil when it may.
-- `kind` "log" and "plank" both go through the same size checks. The
-- sizes are the caller's: the server passes the parts it measured.
function SawmillLogic.Accepts(piece: PieceView, mill: Mill): (boolean, Reason?)
	if piece.kind ~= "log" and piece.kind ~= "plank" then
		return false, "small"
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
		if section.length ~= section.length or section.sx ~= section.sx or section.sz ~= section.sz then
			return false, "size"
		end
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
		if paper(section.sx, section.sz, u) then
			return false, "thin"
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

-- The planks a piece of `volumeU3` becomes at `settings`. Volumes add
-- back to the piece (PlankYield is 1; dust under MinPieceVolume folds
-- into the previous plank). A plank cut again uses the same path.
function SawmillLogic.Cut(volumeU3: number, settings: Settings, mill: Mill): { Plank }
	local u = GameConfig.WoodUnit
	local sx = settings.x * u
	local sz = settings.y * u
	local area = sx * sz
	local yield = GameConfig.PlankYield
	if area <= 1e-8 or volumeU3 <= 0 or yield ~= yield or yield <= 0 then
		return {}
	end
	local remaining = volumeU3 * u * u * u * yield
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
