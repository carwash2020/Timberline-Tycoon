--!strict
-- InputKit: the shared input contract for prompts, the placer, drag, and
-- menus. Pure. Callers pass binds, spots, and a ScreenInsets value; this
-- module does not read GuiService.
--
-- Keys are unique inside one context, not across the whole game. The four
-- contexts are world prompts, the placer, drag, and menus. ButtonX means
-- Interact, Talk, and Buy in every context. Open and the forest plant
-- prompt both use ButtonY, and they may share it only when no spot is
-- inside both ranges (OpenForestApart). Two other actions on one key in
-- the same context fail KeysUnique.
--
-- The placer rotates on DPadRight (keyboard R) and turns world prompts
-- off while it is up. Raise stays on E, and E is world Interact, Talk,
-- and Buy. PlacerSafe rejects a ButtonX bind or a keyboard E bind while
-- world prompts are on.
--
-- The console safe area is ScreenInsets.CoreUISafeInsets. It is not a
-- fraction of the screen.

local InputKit = {}

InputKit.MinTouchPx = 44
InputKit.MinTagPx = 14
InputKit.PhoneWidth = 667
InputKit.PhoneHeight = 375

-- Door prompt reach (PlotService's Open prompt, MaxActivationDistance).
InputKit.OpenRange = 10
-- Forest plant prompt reach (ForestUI sets ForestData.PlantRange - 2).
InputKit.ForestRange = 10

InputKit.SafeInsets = Enum.ScreenInsets.CoreUISafeInsets

export type Context = "world" | "placer" | "drag" | "menu"

export type ActionSpec = {
	keyboard: Enum.KeyCode,
	gamepad: Enum.KeyCode,
	lineOfSight: boolean,
}

export type Bind = {
	action: string,
	gamepad: Enum.KeyCode,
	keyboard: Enum.KeyCode?,
}

export type Spot = { x: number, z: number }
export type Pad = { x: number, z: number, half: number }

InputKit.ContextNames = { "world", "placer", "drag", "menu" } :: { Context }

-- One gamepad button. Interact, Talk, and Buy are that button everywhere.
InputKit.ButtonXActions = { "Interact", "Talk", "Buy" }

local BUTTON_X: { [string]: boolean } = { Interact = true, Talk = true, Buy = true }
-- These two may share ButtonY only while OpenForestApart is true.
local BUTTON_Y_PAIR: { [string]: boolean } = { Open = true, Forest = true }

local function action(keyboard: Enum.KeyCode, gamepad: Enum.KeyCode): ActionSpec
	return { keyboard = keyboard, gamepad = gamepad, lineOfSight = false }
end

-- lineOfSight is false on every world prompt: counters, hats, and streaming
-- would hide the prompt otherwise. PromptDefaults writes this map as-is.
InputKit.Actions = {
	Interact = action(Enum.KeyCode.E, Enum.KeyCode.ButtonX),
	Talk = action(Enum.KeyCode.E, Enum.KeyCode.ButtonX),
	Buy = action(Enum.KeyCode.E, Enum.KeyCode.ButtonX),
	Open = action(Enum.KeyCode.F, Enum.KeyCode.ButtonY),
	Forest = action(Enum.KeyCode.F, Enum.KeyCode.ButtonY),
	Cancel = action(Enum.KeyCode.Escape, Enum.KeyCode.ButtonB),
} :: { [string]: ActionSpec }

-- The target map. The placer rotates on DPadRight, not ButtonX.
InputKit.Target = {
	world = {
		{ action = "Interact", keyboard = Enum.KeyCode.E, gamepad = Enum.KeyCode.ButtonX },
		{ action = "Talk", keyboard = Enum.KeyCode.E, gamepad = Enum.KeyCode.ButtonX },
		{ action = "Buy", keyboard = Enum.KeyCode.E, gamepad = Enum.KeyCode.ButtonX },
		{ action = "Open", keyboard = Enum.KeyCode.F, gamepad = Enum.KeyCode.ButtonY },
		{ action = "Forest", keyboard = Enum.KeyCode.F, gamepad = Enum.KeyCode.ButtonY },
	},
	placer = {
		{ action = "Rotate", keyboard = Enum.KeyCode.R, gamepad = Enum.KeyCode.DPadRight },
		{ action = "Place", gamepad = Enum.KeyCode.ButtonR2 },
		{ action = "Cancel", keyboard = Enum.KeyCode.Q, gamepad = Enum.KeyCode.ButtonB },
		{ action = "Raise", keyboard = Enum.KeyCode.E, gamepad = Enum.KeyCode.ButtonR1 },
		{ action = "Lower", keyboard = Enum.KeyCode.C, gamepad = Enum.KeyCode.ButtonL1 },
	},
	drag = {
		{ action = "Grab", gamepad = Enum.KeyCode.ButtonR2 },
		{ action = "Yaw", keyboard = Enum.KeyCode.Q, gamepad = Enum.KeyCode.DPadLeft },
		{ action = "Yaw", keyboard = Enum.KeyCode.E, gamepad = Enum.KeyCode.DPadRight },
		{ action = "Pitch", gamepad = Enum.KeyCode.ButtonL1 },
		{ action = "Pitch", gamepad = Enum.KeyCode.ButtonR1 },
		{ action = "Further", gamepad = Enum.KeyCode.DPadUp },
		{ action = "Nearer", gamepad = Enum.KeyCode.DPadDown },
	},
	menu = {
		{ action = "Cancel", keyboard = Enum.KeyCode.Escape, gamepad = Enum.KeyCode.ButtonB },
		{ action = "Guide", gamepad = Enum.KeyCode.DPadLeft },
		{ action = "Settings", gamepad = Enum.KeyCode.DPadRight },
		{ action = "Daily", gamepad = Enum.KeyCode.DPadUp },
		{ action = "DropAxe", keyboard = Enum.KeyCode.Backspace, gamepad = Enum.KeyCode.DPadDown },
		{ action = "Recall", gamepad = Enum.KeyCode.ButtonY },
	},
} :: { [string]: { Bind } }

-- The wiring tool (WireTool, BUILD mode). Like the placer it turns world
-- prompts off while it is up, so X is free to mean Cut there. RT picks what
-- the crosshair is on (a tap or a click does it on phone and PC), B or Q
-- leaves. WireSafe checks the list has no key twice.
InputKit.WireBinds = {
	{ action = "Pick", gamepad = Enum.KeyCode.ButtonR2 },
	{ action = "Cut", keyboard = Enum.KeyCode.X, gamepad = Enum.KeyCode.ButtonX },
	{ action = "Done", keyboard = Enum.KeyCode.Q, gamepad = Enum.KeyCode.ButtonB },
} :: { Bind }

function InputKit.WireSafe(binds: { Bind }): boolean
	local seenPad: { [string]: boolean } = {}
	local seenKey: { [string]: boolean } = {}
	for _, bind in ipairs(binds) do
		if bind.gamepad then
			if seenPad[bind.gamepad.Name] then
				return false
			end
			seenPad[bind.gamepad.Name] = true
		end
		if bind.keyboard then
			if seenKey[bind.keyboard.Name] then
				return false
			end
			seenKey[bind.keyboard.Name] = true
		end
	end
	return true
end

function InputKit.IsButtonXAction(name: string): boolean
	return BUTTON_X[name] == true
end

function InputKit.TouchOk(px: number): boolean
	return px >= InputKit.MinTouchPx
end

function InputKit.TagOk(px: number): boolean
	return px >= InputKit.MinTagPx
end

function InputKit.UsesCoreSafeInsets(insets: Enum.ScreenInsets): boolean
	return insets == InputKit.SafeInsets
end

-- Writes the action's keyboard key, gamepad key, and line-of-sight flag.
-- Calling it again leaves the same three values.
function InputKit.PromptDefaults(prompt: ProximityPrompt, actionName: string?)
	local name = actionName or "Interact"
	local spec = InputKit.Actions[name]
	assert(spec, "[InputKit] unknown action " .. name)
	prompt.KeyboardKeyCode = spec.keyboard
	prompt.GamepadKeyCode = spec.gamepad
	prompt.RequiresLineOfSight = spec.lineOfSight
end

-- How far (x, z) is outside a homestead square. 0 when the point is inside.
function InputKit.GapToSquare(x: number, z: number, pad: Pad): number
	local dx = math.max(math.abs(x - pad.x) - pad.half, 0)
	local dz = math.max(math.abs(z - pad.z) - pad.half, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- True when no stump's forest disc meets any pad's open disc. A point on
-- the shared boundary counts: ProximityPrompt uses distance <= range.
function InputKit.OpenForestApart(stumps: { Spot }, pads: { Pad }, openRange: number, forestRange: number): boolean
	local need = openRange + forestRange
	for _, stump in ipairs(stumps) do
		for _, pad in ipairs(pads) do
			if InputKit.GapToSquare(stump.x, stump.z, pad) <= need then
				return false
			end
		end
	end
	return true
end

-- Grouped by KeyCode.Name. Two lookups of the same code compare equal and
-- still are not the same table key, so the name is the key.
local function actionSet(binds: { Bind }, keyOf: (Bind) -> Enum.KeyCode?): { [string]: { [string]: boolean } }
	local grouped: { [string]: { [string]: boolean } } = {}
	for _, bind in ipairs(binds) do
		local key = keyOf(bind)
		if key then
			local have = grouped[key.Name]
			if not have then
				have = {}
				grouped[key.Name] = have
			end
			have[bind.action] = true
		end
	end
	return grouped
end

local function namesOf(actions: { [string]: boolean }): { string }
	local names: { string } = {}
	for name in pairs(actions) do
		table.insert(names, name)
	end
	return names
end

-- Actions on one key. Interact/Talk/Buy may share ButtonX. Open and Forest
-- may share ButtonY only when `apart` is true. Anything else clashes.
local function compatible(actions: { [string]: boolean }, keyName: string, apart: boolean): boolean
	local names = namesOf(actions)
	if #names == 0 then
		return true
	end
	local allX = true
	local allY = true
	for _, name in ipairs(names) do
		if not BUTTON_X[name] then
			allX = false
		end
		if not BUTTON_Y_PAIR[name] then
			allY = false
		end
	end
	-- ButtonX means Interact, Talk, and Buy. Nothing else may sit on it.
	if keyName == "ButtonX" and not allX then
		return false
	end
	if #names == 1 then
		return true
	end
	if allX and (keyName == "ButtonX" or keyName == "E") then
		return true
	end
	-- Open and Forest share F and ButtonY only when their ranges are apart.
	if allY and apart and (keyName == "ButtonY" or keyName == "F") then
		return true
	end
	return false
end

-- `apart` is the Open/Forest proof. Nil and false both refuse that share.
function InputKit.KeysUnique(binds: { Bind }, apart: boolean?): boolean
	local proven = apart == true
	local pads = actionSet(binds, function(bind)
		return bind.gamepad
	end)
	for keyName, actions in pairs(pads) do
		if not compatible(actions, keyName, proven) then
			return false
		end
	end
	local keys = actionSet(binds, function(bind)
		return bind.keyboard
	end)
	for keyName, actions in pairs(keys) do
		if not compatible(actions, keyName, proven) then
			return false
		end
	end
	return true
end

-- While the placer is up and world prompts are on, a bind on ButtonX or on
-- keyboard E clashes with Interact, Talk, and Buy. Prompts off is safe.
function InputKit.PlacerSafe(binds: { Bind }, worldPromptsOn: boolean): boolean
	if not worldPromptsOn then
		return true
	end
	for _, bind in ipairs(binds) do
		if bind.gamepad == Enum.KeyCode.ButtonX or bind.keyboard == Enum.KeyCode.E then
			return false
		end
	end
	return true
end

return InputKit
