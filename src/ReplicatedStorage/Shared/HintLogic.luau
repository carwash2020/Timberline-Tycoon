--!strict
-- HintLogic: the one-line control hint at the bottom of the screen (HUD),
-- worded for the device in use and for what the player is doing, and the
-- device words in Murph's lines (QuestUI). Pure, so it's tested.
--   * Pick(device, context): the hint line. Every line fits MaxLength
--     characters (the hint is one line, truncated past ~40).
--   * ContextFor(state): which context wins when several apply: driving,
--     then standing on the sell pad with something to sell there, then
--     carrying logs, else chopping. A mode a controller sets ("build"
--     while placing a blueprint: HUD.SetHintContext) wins over all of
--     them.
--   * SellCount(...): how many logs the pad would sell, as
--     CarryController's Sell prompt counts them (the hint says "Press E to
--     sell" only when that prompt is up).
--   * Expand(line, device): {click} (or {tap}) becomes the main action on
--     this device: "click", "tap", or "press RT" on a gamepad (the Tool's
--     Activated trigger). {press} is pressing a button on the screen:
--     "tap", "click", or "press" on a gamepad (A, on the selected button).
--     {unequip} is putting the axe away (the v2 loop drags wood only with
--     empty hands): "press 1" (the starter axe's hotbar key), "tap your
--     axe" (its hotbar button), "press LB + RB" (the default backpack
--     unequips on both bumpers). {grab} is starting a drag: "click and
--     hold", "tap and hold", "hold LT". Capitalised ({Click}, {Tap},
--     {Press}, {Unequip}, {Grab}) at a sentence start.
-- The v2 loop (V2_PLAN.md §4, Shared/CoreLoop) has its own hints:
-- PickV2(device, context) and ContextForV2(state), with TooLong and
-- TooHard for the rules behind two of them. The v1 ones above are
-- unchanged.

local FieldGuide = require(script.Parent.FieldGuide)
local GameConfig = require(script.Parent.GameConfig)

local HintLogic = {}

-- UITheme.Device: a touch screen, a mouse and keyboard, a gamepad.
export type Device = "phone" | "desktop" | "console"

export type Context = "chop" | "carrying" | "driving" | "sellPad" | "build"

-- What the HUD knows about the player right now.
export type State = {
	driving: boolean, -- in a vehicle's driver seat (Humanoid.Seated)
	inSellZone: boolean, -- standing in the sawmill's sell zone
	carrying: boolean, -- logs in hand (the CarriedLogs attribute)
	sellable: number, -- logs the pad would sell from there (SellCount)
}

HintLogic.MaxLength = 40
HintLogic.Devices = { "phone", "desktop", "console" } :: { Device }
HintLogic.Contexts = { "chop", "carrying", "driving", "sellPad", "build" } :: { Context }

local LINES: { [string]: { [string]: string } } = { -- [Context][Device]
	chop = {
		phone = "Tap a tree to swing your axe",
		desktop = "Click a tree to swing · E to interact",
		console = "RT to swing · X to interact",
	},
	carrying = {
		phone = "Take logs to your truck's tailgate",
		desktop = "Take logs to your truck's tailgate",
		console = "Take logs to your truck's tailgate",
	},
	driving = {
		phone = "Stick to drive · Jump to hop out",
		desktop = "WASD to drive · Space to hop out",
		console = "Left stick to drive · A to hop out",
	},
	sellPad = {
		phone = "Tap Sell to sell your logs",
		desktop = "Press E to sell your logs",
		console = "Press X to sell your logs",
	},
	build = {
		phone = "Tap where it goes, then PLACE",
		desktop = "Click to place · R to turn · Q to stop",
		console = "RT to place · X to turn · B to stop",
	},
}

-- The main action, per device ({click} in Murph's lines).
local ACTION: { [string]: string } = { -- [Device]
	phone = "tap",
	desktop = "click",
	console = "press RT",
}

-- Pressing a button on the screen, per device ({press}: "Tap again to
-- skip"). A gamepad presses the selected button with A, not RT.
local PRESS: { [string]: string } = { -- [Device]
	phone = "tap",
	desktop = "click",
	console = "press",
}

-- Putting the axe away, per device ({unequip}, Murph's drag beat while
-- the starter axe is the only one: it sits on hotbar key 1). On a gamepad
-- Roblox's backpack unequips when both bumpers are pressed together.
local UNEQUIP: { [string]: string } = { -- [Device]
	phone = "tap your axe",
	desktop = "press 1",
	console = "press LB + RB",
}

-- Starting a drag, per device ({grab}): the main button held down, or on
-- a gamepad the left trigger held at the reticle (V2_PLAN.md §4a).
local GRAB: { [string]: string } = { -- [Device]
	phone = "tap and hold",
	desktop = "click and hold",
	console = "hold LT",
}

-- The hint line for `context` on `device` (the chopping one for anything
-- unknown).
function HintLogic.Pick(device: Device, context: Context): string
	local lines = LINES[context] or LINES.chop
	return lines[device] or lines.desktop
end

-- How many logs selling on the pad would take right now, from what the
-- client knows (the Player attributes as read, any type; nil while the
-- save loads): the logs in your hands (CarriedLogs), your truck's bed
-- (BedCount) only if the truck stands within `sellRange` studs
-- (GameConfig.SellTruckRange) of the sell zone, measured flat
-- (`truckFromZone`; nil with no truck or one that isn't streamed in), and
-- your Sky Bin (SkyBin: logs sent down the Cloud Chute). The same sum
-- CarryController's Sell prompt shows (and the server sells).
function HintLogic.SellCount(
	carried: unknown,
	bedCount: unknown,
	truckFromZone: number?,
	skyBin: unknown,
	sellRange: number
): number
	local function count(value: unknown): number
		if type(value) ~= "number" or value ~= value or value <= 0 then
			return 0 -- not a number, NaN, or none
		end
		return math.floor(math.min(value, 999))
	end
	local truckHere = truckFromZone ~= nil and truckFromZone <= sellRange
	return count(carried) + (if truckHere then count(bedCount) else 0) + count(skyBin)
end

function HintLogic.ContextFor(state: State): Context
	if state.driving then
		return "driving"
	elseif state.inSellZone and state.sellable > 0 then
		return "sellPad"
	elseif state.carrying then
		return "carrying"
	end
	return "chop"
end

-- `line` with its {click} / {tap} / {press} tokens worded for `device`.
-- Other {words} are left as they are.
function HintLogic.Expand(line: string, device: Device): string
	local expanded = string.gsub(line, "{(%a+)}", function(token: string): string
		local lower = string.lower(token)
		local action: string
		if lower == "click" or lower == "tap" then
			action = ACTION[device] or ACTION.desktop
		elseif lower == "press" then
			action = PRESS[device] or PRESS.desktop
		elseif lower == "unequip" then
			action = UNEQUIP[device] or UNEQUIP.desktop
		elseif lower == "grab" then
			action = GRAB[device] or GRAB.desktop
		else
			return "{" .. token .. "}"
		end
		if string.sub(token, 1, 1) ~= string.sub(lower, 1, 1) then
			return string.upper(string.sub(action, 1, 1)) .. string.sub(action, 2)
		end
		return action
	end)
	return expanded
end

-- Whether `line` still has a token in it (for the specs).
function HintLogic.HasToken(line: string): boolean
	return string.find(line, "{%a+}") ~= nil
end

---------------------------------------------------------------------------
-- The v2 loop: wood is dragged with empty hands, cut to fit the bed and
-- sold by backing the truck onto the pad (V2_PLAN.md §4-§5).
---------------------------------------------------------------------------

-- "chop", "driving" and "build" read as in v1. The new ones:
--   * drag: no axe out (pointing at wood or not): how to drag.
--   * unequip: an axe out, pointing at a loose piece: put it away to drag.
--   * holding: dragging a piece: distance and turning.
--   * tooLong: dragging a piece longer than your truck's bed.
--   * tooHard: pointing at wood your axe needs too many hits for, or
--     whose v1 hardness (the amount taken off each hit) beats the axe's
--     listed damage. That field is wood.hardness, not wood.v2.hardness.
--   * thick: pointing at a thick face. A face twice as wide takes about
--     four times the swings.
--   * backUp: driving with wood on the bed, near the sell pad.
export type ContextV2 =
	"chop"
	| "drag"
	| "unequip"
	| "holding"
	| "tooLong"
	| "tooHard"
	| "thick"
	| "driving"
	| "backUp"
	| "build"

HintLogic.ContextsV2 = {
	"chop",
	"drag",
	"unequip",
	"holding",
	"tooLong",
	"tooHard",
	"thick",
	"driving",
	"backUp",
	"build",
} :: { ContextV2 }

-- A phone's v2 hint is at most this many bytes: the longest v1 phone hint,
-- which HudLayout.spec shows fits beside the load chip on a small phone.
HintLogic.PhoneMaxBytes = 34

local LINES_V2: { [string]: { [string]: string } } = { -- [ContextV2][Device]; others come from LINES
	drag = {
		phone = "Tap and hold wood to drag it",
		desktop = "Click and hold wood to drag it",
		console = "Hold LT on wood to drag it",
	},
	unequip = {
		phone = "Put your axe away to drag: tap it",
		desktop = "Put your axe away (its key) to drag",
		console = "LB + RB: put your axe away to drag",
	},
	holding = {
		phone = "+/- for distance · Turn to rotate",
		desktop = "Scroll for distance · Q/E to turn",
		console = "D-pad up/down: reach · LB/RB: turn",
	},
	tooLong = {
		phone = "Cut it shorter to fit your bed",
		desktop = "Cut it shorter to fit your bed",
		console = "Cut it shorter to fit your bed",
	},
	tooHard = {
		phone = "Too hard: get a better axe",
		desktop = "Too hard for this axe: get a better one",
		console = "Too hard for this axe: get a better one",
	},
	thick = {
		phone = "Thicker cuts take longer",
		desktop = "Thicker cuts take longer",
		console = "Thicker cuts take longer",
	},
	backUp = {
		phone = "Back onto the pad to sell the bed",
		desktop = "Back onto the pad to sell the bed",
		console = "Back onto the pad to sell the bed",
	},
}

-- The v2 hint line for `context` on `device` (the chopping one for
-- anything unknown).
function HintLogic.PickV2(device: Device, context: ContextV2): string
	local lines = LINES_V2[context] or LINES[context] or LINES.chop
	return lines[device] or lines.desktop
end

-- Hits per cut from which a wood counts as too hard for the axe: twice
-- the Field Guide's useful pace.
HintLogic.TooHardHits = 2 * FieldGuide.UsefulHitsV2

-- Whether `hits` per cut (FieldGuide.CutHits for the section you point
-- at, math.huge when the axe can't cut it) is too many for this axe. Not
-- a number (NaN) counts as not known: no hint.
function HintLogic.TooHard(hits: number): boolean
	return hits == hits and hits > HintLogic.TooHardHits
end

-- Listed axe damage against the wood's v1 `hardness` field: the amount
-- taken off each hit. One hit can't dent the wood when damage is under
-- that number (the same comparison as a v1 swing that deals 0). This is
-- not `v2.hardness`, the damage per square unit of the cut face; swapping
-- the two would call the tutorial oak too hard. The v2 swing still lands;
-- the HUD and the toast say to get a better axe. Not a number (NaN)
-- counts as not known: no hint.
function HintLogic.Underpowered(damage: number, hardness: number): boolean
	if damage ~= damage or hardness ~= hardness then
		return false
	end
	return damage < hardness
end

-- A square face this many studs across is a thick cut: pine's base is 2.6,
-- a tapered top of that trunk is under 2. Twice the width is four times
-- the swings (SectionLogic.Required).
HintLogic.ThickStuds = 2

function HintLogic.Thicker(width: number, depth: number): boolean
	if width ~= width or depth ~= depth then
		return false
	end
	return math.min(width, depth) >= HintLogic.ThickStuds
end

-- Whether a held piece `pieceLength` studs long (its longest side) is
-- longer than your truck's bed (`bedLength` studs; nil or 0 with no bed).
function HintLogic.TooLong(pieceLength: unknown, bedLength: unknown): boolean
	if type(pieceLength) ~= "number" or type(bedLength) ~= "number" then
		return false
	end
	if pieceLength ~= pieceLength or bedLength ~= bedLength or bedLength <= 0 then
		return false -- NaN, or no bed to fit
	end
	return pieceLength > bedLength
end

-- Whether your truck is near the sell pad: within GameConfig.SellTruckRange
-- studs of the sell zone (`truckFromZone`, measured flat; nil when there's
-- no truck or it isn't streamed in).
function HintLogic.NearPad(truckFromZone: number?): boolean
	return truckFromZone ~= nil and truckFromZone <= GameConfig.SellTruckRange
end

-- What the HUD knows about the player under v2.
export type StateV2 = {
	driving: boolean, -- in a vehicle's driver seat
	axeOut: boolean, -- an axe in hand
	holding: boolean, -- dragging a piece (its HeldBy is you)
	onWood: boolean, -- pointing at a loose piece (tag Wood) within reach
	tooHard: boolean, -- pointing at wood this axe finds too hard (TooHard, Underpowered)
	thick: boolean, -- pointing at a thick face (Thicker)
	tooLong: boolean, -- the held piece is longer than your bed (TooLong)
	bedVolume: number, -- u³ on your truck's bed (BedVolume)
	nearPad: boolean, -- your truck is near the sell pad (NearPad)
}

-- Which v2 context wins: driving (backUp with wood on the bed by the
-- pad), then a held piece (tooLong if it won't fit the bed), then an axe
-- out (unequip over loose wood, tooHard over wood it barely dents, else
-- chop), else drag. A controller's mode ("build") still wins over all of
-- them, as in v1.
function HintLogic.ContextForV2(state: StateV2): ContextV2
	if state.driving then
		local loaded = type(state.bedVolume) == "number" and state.bedVolume > 0
		return if loaded and state.nearPad then "backUp" else "driving"
	elseif state.holding then
		return if state.tooLong then "tooLong" else "holding"
	elseif state.axeOut then
		if state.onWood then
			return "unequip"
		end
		if state.tooHard then
			return "tooHard"
		end
		return if state.thick then "thick" else "chop"
	end
	return "drag"
end

return HintLogic
