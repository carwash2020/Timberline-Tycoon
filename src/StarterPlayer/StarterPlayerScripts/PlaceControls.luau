--!strict
-- PlaceControls: the placer's input and its on-screen bar for PC, phone and
-- Xbox (Lane F, Step 8; the rules are Shared/PlaceControlsLogic).
--
--   PC     left click places, R turns, PageUp / PageDown raise and lower
--          (E and C still work), Q cancels. The bar's buttons are also there.
--   Phone  tap or drag the ghost to aim, then the PLACE button. ROTATE, UP,
--          DOWN, CANCEL are buttons, 44 x 44 or more and 8 apart, in a narrow
--          grid between the thumbstick and the jump button, so neither
--          Builder's thumbstick nor the jump zone is covered.
--   Xbox   A places, D-pad right turns, D-pad up / down raise and lower, B
--          cancels; the crosshair aims; LT hangs the ghost so the left stick
--          flicks it; RB / LB slide it. The right trigger is never bound (the
--          hammer's Tool.Activated already carries RT).
--
-- Everything binds when the placer opens (Bind) and unbinds when it closes
-- (Unbind): there are no permanent binds. BlueprintPlacer owns what each
-- action does; this module only turns input into those calls.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local PlaceControlsLogic = require(ReplicatedStorage.Shared.PlaceControlsLogic)
local UITheme = require(script.Parent.UITheme)

local PlaceControls = {}

export type Handlers = {
	place: () -> (),
	rotate: () -> (),
	raise: () -> (),
	lower: () -> (),
	cancel: () -> (),
	lock: (on: boolean, pad: Enum.UserInputType?) -> (),
	-- The left stick while LT holds the ghost: true means it was used (and the
	-- stick walks nobody); false lets it walk you.
	stick: (x: number, y: number) -> boolean,
	push: (axis: number) -> (), -- +1 sliding out (RB), -1 in (LB), 0 stopped
	-- Phone: a touch dragging the ghost. `screen` is nil when it ends.
	drag: (screen: Vector2?) -> (),
	ghostOnScreen: () -> Vector2?,
}

local ACTIONS = {
	"PlacerRotate",
	"PlacerPlace",
	"PlacerCancel",
	"PlacerUp",
	"PlacerDown",
	"PlacerLock",
	"PlacerStick",
	"PlacerPush",
	"PlacerDrag",
}

local bar: Frame? = nil
local label: TextLabel? = nil
local buttonHost: Frame? = nil
local buttonRoots: { [string]: GuiObject } = {}
local bound = false
local lastDevice: string? = nil

-- Above the HUD's D-pad shortcuts (they bind at High). Returning Sink from a
-- handler keeps DPadRight from opening Settings and A from jumping.
function PlaceControls.Priority(): number
	return Enum.ContextActionPriority.High.Value + 100
end

local function codes(names: { string }): { Enum.KeyCode }
	local out: { Enum.KeyCode } = {}
	for _, name in ipairs(names) do
		local code = (Enum.KeyCode :: any)[name]
		if code ~= nil then
			table.insert(out, code)
		end
	end
	return out
end

-- Every key an action uses on any device (a player can swap between keyboard
-- and pad mid-session), minus anything forbidden (the right trigger).
local function allKeys(action: PlaceControlsLogic.Action): { Enum.KeyCode }
	local names: { string } = {}
	for _, device in ipairs({ "desktop", "console" }) do
		for _, key in ipairs(PlaceControlsLogic.KeysFor(device :: PlaceControlsLogic.Device, action)) do
			if table.find(names, key) == nil then
				table.insert(names, key)
			end
		end
	end
	return codes(names)
end

local function pressed(fn: () -> ()): (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
	return function(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
		if inputState == Enum.UserInputState.Begin then
			fn()
		end
		return Enum.ContextActionResult.Sink
	end
end

function PlaceControls.Bind(handlers: Handlers)
	PlaceControls.Unbind()
	bound = true
	local priority = PlaceControls.Priority()
	local function bindKeys(name: string, action: PlaceControlsLogic.Action, fn: () -> ())
		local list = allKeys(action)
		if #list > 0 then
			ContextActionService:BindActionAtPriority(name, pressed(fn), false, priority, table.unpack(list :: { any }))
		end
	end
	bindKeys("PlacerRotate", "rotate", handlers.rotate)
	bindKeys("PlacerPlace", "place", handlers.place)
	bindKeys("PlacerCancel", "cancel", handlers.cancel)
	bindKeys("PlacerUp", "raise", handlers.raise)
	bindKeys("PlacerDown", "lower", handlers.lower)
	local extras = PlaceControlsLogic.GamepadExtras
	ContextActionService:BindActionAtPriority(
		"PlacerLock",
		function(_name: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin then
				handlers.lock(true, input.UserInputType)
			elseif inputState ~= Enum.UserInputState.Change then
				handlers.lock(false, nil)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		priority,
		(Enum.KeyCode :: any)[extras.lock]
	)
	ContextActionService:BindActionAtPriority(
		"PlacerStick",
		function(_name: string, _inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			if handlers.stick(input.Position.X, input.Position.Y) then
				return Enum.ContextActionResult.Sink -- locked: it turns the ghost and walks nobody
			end
			return Enum.ContextActionResult.Pass -- not locked: it walks you, as always
		end,
		false,
		priority,
		(Enum.KeyCode :: any)[extras.stick]
	)
	ContextActionService:BindActionAtPriority(
		"PlacerPush",
		function(_name: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			local axis = if input.KeyCode == (Enum.KeyCode :: any)[extras.pushOut] then 1 else -1
			if inputState == Enum.UserInputState.Begin then
				handlers.push(axis)
			elseif inputState ~= Enum.UserInputState.Change then
				handlers.push(0)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		priority,
		(Enum.KeyCode :: any)[extras.pushOut],
		(Enum.KeyCode :: any)[extras.pushIn]
	)
	-- Phone: a finger that lands on the ghost drags it; a finger anywhere else
	-- is the camera's, as always (Pass).
	local dragging = false
	ContextActionService:BindActionAtPriority(
		"PlacerDrag",
		function(_name: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			local at = Vector2.new(input.Position.X, input.Position.Y)
			if inputState == Enum.UserInputState.Begin then
				local ghost = handlers.ghostOnScreen()
				if
					ghost ~= nil
					and PlaceControlsLogic.StartsDrag({ x = at.X, y = at.Y }, { x = ghost.X, y = ghost.Y })
				then
					dragging = true
					handlers.drag(at)
					return Enum.ContextActionResult.Sink
				end
				return Enum.ContextActionResult.Pass
			elseif not dragging then
				return Enum.ContextActionResult.Pass
			end
			if inputState == Enum.UserInputState.Change then
				handlers.drag(at)
			else
				dragging = false
				handlers.drag(nil)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		priority,
		Enum.UserInputType.Touch
	)
end

function PlaceControls.Unbind()
	if not bound then
		return
	end
	bound = false
	for _, name in ipairs(ACTIONS) do
		ContextActionService:UnbindAction(name)
	end
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------

local function currentDevice(): PlaceControlsLogic.Device
	local device = UITheme.Device()
	if device == "phone" then
		return "phone"
	elseif device == "console" then
		return "console"
	end
	return "desktop"
end

-- Lays the bar out for the device in use: a PC's row, a phone's narrow grid,
-- or an Xbox's label line only. Called when the placer opens and when the
-- player swaps between touch, keyboard and pad.
function PlaceControls.Refresh()
	local outer, host = bar, buttonHost
	if not outer or not host then
		return
	end
	local device = currentDevice()
	lastDevice = device
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	local scale = UITheme.Scale()
	local layout = PlaceControlsLogic.Layout(
		device :: PlaceControlsLogic.Device,
		{ x = viewport.X, y = viewport.Y },
		UITheme.Bottom() * scale,
		scale
	)
	for _, root in pairs(buttonRoots) do
		root.Visible = false
	end
	local anyButtons = false
	-- The layout's rectangles are relative to the whole bar; the buttons live in
	-- their own block under the label line, so measure from the block's corner.
	local left, top = math.huge, math.huge
	for _, rect in pairs(layout.buttons) do
		left, top = math.min(left, rect.x), math.min(top, rect.y)
	end
	for action, rect in pairs(layout.buttons) do
		local root = buttonRoots[action]
		if root then
			root.Visible = true
			root.Position = UDim2.fromOffset(rect.x - left, rect.y - top)
			root.Size = UDim2.fromOffset(rect.w, rect.h + UITheme.ButtonDrop) -- the face is rect.h; the drop edge sits in the gap
			anyButtons = true
		end
	end
	host.Visible = anyButtons
	host.Size = UDim2.fromOffset(layout.size.w, layout.size.h + UITheme.ButtonDrop)
	if label then
		label.Size =
			UDim2.fromOffset(if device == "phone" then layout.size.w else 320, if device == "phone" then 40 else 20)
		label.TextWrapped = device == "phone"
	end
	outer.AnchorPoint = Vector2.new(0.5, 1)
	outer.Position = UDim2.new(0.5, 0, 1, -(UITheme.Bottom()))
end

-- Builds the bar once. `handlers` are called by its buttons (the same calls
-- the keys make). Returns the label the placer writes its line into and the
-- bar's frame.
function PlaceControls.Build(gui: ScreenGui, handlers: { [string]: () -> () }): (Frame, TextLabel)
	local b = UITheme.Bar(gui, "Placing")
	bar = b.outer
	label = b.label
	-- The default row is an automatic left-to-right list; the layout places
	-- the buttons itself, so it is a plain frame the size of the block.
	b.row.AutomaticSize = Enum.AutomaticSize.None
	for _, child in ipairs(b.row:GetChildren()) do
		if child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
	buttonHost = b.row
	local styles = { place = "buy", cancel = "skip" }
	for _, action in ipairs(PlaceControlsLogic.Actions) do
		local text = PlaceControlsLogic.Labels[action]
		local button = UITheme.Button({
			name = text,
			text = text,
			size = Vector2.new(96, PlaceControlsLogic.MinButton),
			style = styles[action] or "bark",
			textSize = 14,
		})
		button.root.Parent = b.row
		button.face.Activated:Connect(handlers[action])
		buttonRoots[action] = button.root
	end
	-- A swap between touch, keyboard and pad changes the layout.
	UserInputService.LastInputTypeChanged:Connect(function()
		if bar and bar.Visible and currentDevice() ~= lastDevice then
			PlaceControls.Refresh()
		end
	end)
	return b.outer, b.label
end

-- Shows or hides the bar; showing re-lays it out for the device in use.
function PlaceControls.Show(on: boolean)
	local outer = bar
	if outer then
		outer.Visible = on
		if on then
			PlaceControls.Refresh()
		end
	end
end

-- The hint line for the device in use ("Click to place · R to turn ...").
function PlaceControls.Hint(): string
	return PlaceControlsLogic.Hints[currentDevice()]
end

return PlaceControls
