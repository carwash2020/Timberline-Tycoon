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
--     Capitalised ({Click}, {Tap}, {Press}) at a sentence start.

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

return HintLogic
