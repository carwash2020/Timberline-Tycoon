--!strict
-- HintLogic: the one-line control hint at the bottom of the screen (HUD),
-- worded for the device in use and for what the player is doing, and the
-- device words in Murph's lines (QuestUI). Pure, so it's tested.
--   * Pick(device, context): the hint line. Every line fits MaxLength
--     characters (the hint is one line, truncated past ~40).
--   * ContextFor(state): which context wins when several apply: driving,
--     then standing on the sell pad, then carrying logs, else chopping. A
--     mode a controller sets ("build" while placing a blueprint:
--     HUD.SetHintContext) wins over all of them.
--   * Expand(line, device): {click} (or {tap}) becomes the main action on
--     this device: "click", "tap", or "press RT" on a gamepad (the Tool's
--     Activated trigger). Capitalised ({Click}, {Tap}) at a sentence start.

local HintLogic = {}

-- UITheme.Device: a touch screen, a mouse and keyboard, a gamepad.
export type Device = "phone" | "desktop" | "console"

export type Context = "chop" | "carrying" | "driving" | "sellPad" | "build"

-- What the HUD knows about the player right now.
export type State = {
	driving: boolean, -- in a vehicle's driver seat (Humanoid.Seated)
	inSellZone: boolean, -- standing in the sawmill's sell zone
	carrying: boolean, -- logs in hand (the CarriedLogs attribute)
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

-- The hint line for `context` on `device` (the chopping one for anything
-- unknown).
function HintLogic.Pick(device: Device, context: Context): string
	local lines = LINES[context] or LINES.chop
	return lines[device] or lines.desktop
end

function HintLogic.ContextFor(state: State): Context
	if state.driving then
		return "driving"
	elseif state.inSellZone then
		return "sellPad"
	elseif state.carrying then
		return "carrying"
	end
	return "chop"
end

-- `line` with its {click} / {tap} tokens worded for `device`. Other
-- {words} are left as they are.
function HintLogic.Expand(line: string, device: Device): string
	local action = ACTION[device] or ACTION.desktop
	local expanded = string.gsub(line, "{(%a+)}", function(token: string): string
		local lower = string.lower(token)
		if lower ~= "click" and lower ~= "tap" then
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
