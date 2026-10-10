--!strict
-- PlaceControlsLogic: how a player places a blueprint on PC, phone and Xbox
-- (Lane F, the brief's Step 8). Pure, so a spec can check every rule: which
-- keys do what, that no key is the right trigger, that the on-screen buttons
-- are at least 44 px with 8 px between, and that on a phone nothing sits in
-- the thumbstick or jump zones. PlaceControls (client) binds and draws from
-- this.
--
--   Device   Place          Rotate        Raise / lower      Cancel
--   PC       left click     R             PageUp / PageDown  Q
--   Phone    PLACE button   ROTATE        UP / DOWN buttons  CANCEL
--   Xbox     A              D-pad right   D-pad up / down    B
--   Aim      mouse          tap or drag the ghost            crosshair; LT lock
--                                                            + left stick flick;
--                                                            RB / LB slide
-- Bound only while the placer is open and unbound on close. The right trigger
-- is never bound: the hammer's Tool.Activated already carries click, tap and
-- RT, and binding it broke axe swinging on Xbox.

local PlaceControlsLogic = {}

export type Device = "desktop" | "phone" | "console"
export type Action = "rotate" | "raise" | "lower" | "place" | "cancel"

-- The bar's order, left to right (a phone grid reads the same order).
local ACTIONS: { Action } = { "rotate", "raise", "lower", "place", "cancel" }
PlaceControlsLogic.Actions = ACTIONS

PlaceControlsLogic.Labels = {
	rotate = "ROTATE",
	raise = "UP",
	lower = "DOWN",
	place = "PLACE",
	cancel = "CANCEL",
} :: { [string]: string }

-- Enum.KeyCode names. `place` on a PC is the left mouse button (an input
-- type, not a key), so it has no entry there. A phone has buttons only.
PlaceControlsLogic.Keys = {
	desktop = {
		rotate = { "R" },
		raise = { "PageUp", "E" },
		lower = { "PageDown", "C" },
		place = {},
		cancel = { "Q" },
	},
	console = {
		rotate = { "DPadRight" },
		raise = { "DPadUp" },
		lower = { "DPadDown" },
		place = { "ButtonA" },
		cancel = { "ButtonB" },
	},
	phone = {
		rotate = {},
		raise = {},
		lower = {},
		place = {},
		cancel = {},
	},
} :: { [string]: { [string]: { string } } }

-- Gamepad-only extras while placing: LT hangs the ghost, the left stick flicks
-- it round or up and down, RB and LB slide it further or nearer.
PlaceControlsLogic.GamepadExtras = {
	lock = "ButtonL2",
	stick = "Thumbstick1",
	pushOut = "ButtonR1",
	pushIn = "ButtonL1",
}

-- Never bound by the placer (see the header).
PlaceControlsLogic.Forbidden = { "ButtonR2" } :: { string }

-- The mouse button that places on a PC.
PlaceControlsLogic.PlaceMouse = "MouseButton1"

-- Every key name the placer binds on any device, once each.
function PlaceControlsLogic.AllKeys(): { string }
	local seen: { [string]: boolean } = {}
	local out: { string } = {}
	local function add(name: string)
		if not seen[name] then
			seen[name] = true
			table.insert(out, name)
		end
	end
	for _, device in ipairs({ "desktop", "console", "phone" }) do
		for _, action in ipairs(PlaceControlsLogic.Actions) do
			for _, key in ipairs(PlaceControlsLogic.Keys[device][action]) do
				add(key)
			end
		end
	end
	for _, key in pairs(PlaceControlsLogic.GamepadExtras) do
		add(key)
	end
	return out
end

-- The bindings a device uses for `action`, never including a forbidden key.
function PlaceControlsLogic.KeysFor(device: Device, action: Action): { string }
	local out: { string } = {}
	for _, key in ipairs(PlaceControlsLogic.Keys[device][action]) do
		if table.find(PlaceControlsLogic.Forbidden, key) == nil then
			table.insert(out, key)
		end
	end
	return out
end

-- Can every action be done on this device? A phone through its buttons; the
-- others through at least one key or the mouse. Returns the actions that can't.
function PlaceControlsLogic.Unreachable(device: Device): { Action }
	local missing: { Action } = {}
	for _, action in ipairs(ACTIONS) do
		local reachable = #PlaceControlsLogic.KeysFor(device, action :: Action) > 0
			or (device == "desktop" and action == "place")
			or device == "phone"
		if not reachable then
			table.insert(missing, action)
		end
	end
	return missing
end

---------------------------------------------------------------------------
-- The on-screen buttons
---------------------------------------------------------------------------

export type Rect = { x: number, y: number, w: number, h: number }

PlaceControlsLogic.MinButton = 44 -- px: a fingertip
PlaceControlsLogic.Gap = 8 -- px between buttons
PlaceControlsLogic.LabelHeight = 24 -- the line above the buttons ("Place the Wall · $32")
PlaceControlsLogic.PhoneLabelHeight = 40 -- two short lines: the phone's bar is only as wide as its buttons

-- The two parts of a phone screen the player's thumbs use (Roblox's thumbstick
-- bottom-left, the jump button bottom-right). Nothing of ours goes in them.
PlaceControlsLogic.ThumbZone = { w = 240, h = 220 }
PlaceControlsLogic.JumpZone = { w = 200, h = 200 }

function PlaceControlsLogic.Zones(viewport: { x: number, y: number }): { thumb: Rect, jump: Rect }
	local tw, th = PlaceControlsLogic.ThumbZone.w, PlaceControlsLogic.ThumbZone.h
	local jw, jh = PlaceControlsLogic.JumpZone.w, PlaceControlsLogic.JumpZone.h
	return {
		thumb = { x = 0, y = viewport.y - th, w = tw, h = th },
		jump = { x = viewport.x - jw, y = viewport.y - jh, w = jw, h = jh },
	}
end

function PlaceControlsLogic.Overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

export type Layout = {
	buttons: { [string]: Rect }, -- by action, in UI units relative to the bar's top-left
	size: { w: number, h: number }, -- the buttons' block, in UI units
	bar: Rect, -- the bar (label line and buttons) in screen px
	scale: number, -- UI units to px (UITheme.Scale())
	columns: number,
	rows: number,
}

-- Where the buttons go. Button sizes are UI units (44 is the UITheme tap size
-- on every device); the bar's place on screen is in px, so `viewport` and
-- `bottom` are px and `scale` is UITheme.Scale() (1 when unknown). `bottom` is
-- how far above the bottom edge the bar's foot sits (clear of the tool hotbar).
--   * Phone: a narrow grid, two columns by three rows, centred. Wide enough
--     for the words but narrow enough to stay between the thumbstick and jump
--     zones (spec).
--   * PC: one row of five, centred.
--   * Xbox: no buttons (the pad has every action); only the label line shows.
function PlaceControlsLogic.Layout(
	device: Device,
	viewport: { x: number, y: number },
	bottom: number,
	scale: number?
): Layout
	local k = if type(scale) == "number" and scale > 0 then scale else 1
	local min, gap = PlaceControlsLogic.MinButton, PlaceControlsLogic.Gap
	local buttons: { [string]: Rect } = {}
	local columns, rows, blockW, blockH = 0, 0, 0, 0
	if device == "phone" then
		local w = 80
		columns, rows = 2, 3
		blockW = columns * w + gap
		blockH = rows * min + (rows - 1) * gap
		buttons.rotate = { x = 0, y = 0, w = w, h = min }
		buttons.place = { x = w + gap, y = 0, w = w, h = min }
		buttons.raise = { x = 0, y = min + gap, w = w, h = min }
		buttons.lower = { x = w + gap, y = min + gap, w = w, h = min }
		buttons.cancel = { x = 0, y = 2 * (min + gap), w = blockW, h = min }
	elseif device == "desktop" then
		local w = 96
		columns, rows = #PlaceControlsLogic.Actions, 1
		blockW = columns * w + (columns - 1) * gap
		blockH = min
		for i, action in ipairs(PlaceControlsLogic.Actions) do
			buttons[action] = { x = (i - 1) * (w + gap), y = 0, w = w, h = min }
		end
	end
	local label = if device == "phone" then PlaceControlsLogic.PhoneLabelHeight else PlaceControlsLogic.LabelHeight
	local totalW = if device == "phone" then blockW else math.max(blockW, 320)
	local totalH = label + blockH
	local bar: Rect = {
		x = (viewport.x - totalW * k) / 2,
		y = viewport.y - bottom - totalH * k,
		w = totalW * k,
		h = totalH * k,
	}
	-- Buttons sit centred in the bar, under the label line.
	local offsetX = (totalW - blockW) / 2
	for _, rect in pairs(buttons) do
		rect.x += offsetX
		rect.y += label
	end
	return { buttons = buttons, size = { w = blockW, h = blockH }, bar = bar, scale = k, columns = columns, rows = rows }
end

-- A button's rectangle in screen px (the layout's are relative to the bar, in UI units).
function PlaceControlsLogic.ScreenRect(layout: Layout, action: string): Rect?
	local rect = layout.buttons[action]
	if rect == nil then
		return nil
	end
	local k = layout.scale
	return { x = layout.bar.x + rect.x * k, y = layout.bar.y + rect.y * k, w = rect.w * k, h = rect.h * k }
end

---------------------------------------------------------------------------
-- Hints and the phone's drag
---------------------------------------------------------------------------

PlaceControlsLogic.Hints = {
	desktop = "Click to place · R to turn · PgUp / PgDn raise and lower · Q to stop",
	phone = "Tap or drag where it goes, then PLACE",
	console = "A place · D-pad right turn · D-pad up/down raise · LT lock · B stop",
} :: { [string]: string }

-- A touch that starts this close (screen px) to the ghost's middle drags the
-- ghost; anywhere else it turns the camera as always.
PlaceControlsLogic.DragGrab = 90

function PlaceControlsLogic.StartsDrag(
	touch: { x: number, y: number },
	ghostOnScreen: { x: number, y: number }?
): boolean
	if ghostOnScreen == nil then
		return false
	end
	local dx, dy = touch.x - ghostOnScreen.x, touch.y - ghostOnScreen.y
	return dx * dx + dy * dy <= PlaceControlsLogic.DragGrab * PlaceControlsLogic.DragGrab
end

-- Validates the table: no forbidden key anywhere, no key doing two jobs on
-- one device, every action reachable. Returns true or the first problem.
function PlaceControlsLogic.Validate(): (boolean, string?)
	for _, key in ipairs(PlaceControlsLogic.AllKeys()) do
		if table.find(PlaceControlsLogic.Forbidden, key) ~= nil then
			return false, "binds " .. key
		end
	end
	for _, device in ipairs({ "desktop", "console", "phone" }) do
		local used: { [string]: string } = {}
		for _, action in ipairs(PlaceControlsLogic.Actions) do
			for _, key in ipairs(PlaceControlsLogic.Keys[device][action]) do
				if used[key] ~= nil then
					return false, string.format("%s binds %s to %s and %s", device, key, used[key], action)
				end
				used[key] = action
			end
		end
		local missing = PlaceControlsLogic.Unreachable(device :: Device)
		if #missing > 0 then
			return false, string.format("%s cannot reach %s", device, missing[1])
		end
	end
	return true, nil
end

return PlaceControlsLogic
