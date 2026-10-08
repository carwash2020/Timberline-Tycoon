--!strict
-- BlueprintPlacer: placing a blueprint on your plot (GAME_DESIGN §9). The
-- hammer starts it (HammerController, PlotUI's list) and stays in your hand
-- while it runs; putting the hammer away or taking out anything else ends it.
--   * A ghost of the blueprint (Shared/BlueprintModels, the same model the
--     server builds) follows the mouse, the last tap on a touch screen, or
--     the middle of the screen on a gamepad, snapped to PlotData.Grid.
--   * Green where PlotLogic.Check allows it (and you can pay), red with the
--     reason where it doesn't. The server checks again: this is a preview.
--   * Click or PLACE (R2 on a gamepad) to place; R or ROTATE (D-pad right)
--     for a quarter turn; Q or CANCEL (B) to stop. On a gamepad, hold LT to
--     lock the ghost and flick the LEFT (movement) stick: left or right
--     turns it a quarter, up or down raises or lowers it. The left stick
--     does not walk you while LT is held, and the right stick stays the
--     camera's. RB/LB slide the ghost further or nearer. After placing something new you
--     keep placing the same blueprint (fences!) until you cancel. A move
--     ends after one placement.
--   * Walking off your plot stops placing.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BlueprintModels = require(ReplicatedStorage.Shared.BlueprintModels)
local GrabLogic = require(ReplicatedStorage.Shared.GrabLogic)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local MachineArt = require(ReplicatedStorage.Shared.Art.MachineArt)
local Net = require(ReplicatedStorage.Shared.Net)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local PlanerLogic = require(ReplicatedStorage.Shared.PlanerLogic)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local PlotPlatform = require(ReplicatedStorage.Shared.PlotPlatform)
local SawmillLogic = require(ReplicatedStorage.Shared.SawmillLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local HUD = require(script.Parent.HUD)
local PromptSwitch = require(script.Parent.PromptSwitch)
local UITheme = require(script.Parent.UITheme)

local BlueprintPlacer = {}

local player = Players.LocalPlayer

local CREAM = UITheme.Colors.Cream
local VALID = UITheme.Colors.Green
local INVALID = Color3.fromRGB(255, 80, 80)

local LEAVE_REACH = 40 -- studs past the plot's edge before placing stops (PlotService's BUILD_REACH)
local ACTIONS = {
	"PlacerRotate",
	"PlacerPlace",
	"PlacerCancel",
	"PlacerUp",
	"PlacerDown",
	"PlacerLock",
	"PlacerStick",
	"PlacerPush",
}
local PUSH_MIN, PUSH_MAX = -25, 40 -- studs the gamepad can slide the ghost nearer or further than the crosshair
local PUSH_SPEED = 18 -- studs a second while RB or LB is held

export type Options = {
	moveUid: string?, -- moving this placed item instead of buying a new one
	boxUid: string?, -- placing the item out of this opened box (sawmill, planer, belt): one use, the box is spent on a successful place
	onStop: (() -> ())?, -- called once placing ends, however it ends
}

type State = {
	bp: PlotData.Blueprint,
	options: Options,
	ghost: Model,
	highlight: Highlight,
	rot: number,
	x: number,
	y: number,
	z: number,
	valid: boolean,
	reason: string?,
	aim: Vector3?, -- the last tapped point in the world (touch)
	push: number, -- gamepad: studs the ghost is slid along your view (D-pad up/down)
	pushAxis: number, -- +1 sliding out, -1 in, 0 still
	lockedAt: Vector3?, -- gamepad: LT is down, the ghost hangs here and the left stick turns and lifts it
	lockPad: Enum.UserInputType?, -- the gamepad whose LT started the lock
	stickX: number, -- the left stick's last reading, for flicks
	stickY: number,
	armedX: boolean,
	armedY: boolean,
	hidden: { BasePart }, -- the moved item's own parts, hidden while it moves
	conns: { RBXScriptConnection },
}

local state: State? = nil
local placedListeners: { (Vector3) -> () } = {}
local bar: Frame? = nil
local barLabel: TextLabel? = nil
-- The mouse is over the build bar: don't drag the ghost under the buttons
-- (pressing PLACE would build right there).
local overBar = false

function BlueprintPlacer.Active(): boolean
	return state ~= nil
end

-- `fn(worldPos)` runs each time a place or a move is sent (the hammer swings).
function BlueprintPlacer.OnPlaced(fn: (Vector3) -> ())
	table.insert(placedListeners, fn)
end

local function tellPlaced(s: State)
	local plot = BlueprintPlacer.PlotCFrame()
	if not plot then
		return
	end
	local pos = plot:PointToWorldSpace(Vector3.new(s.x, s.y, s.z))
	for _, fn in ipairs(placedListeners) do
		fn(pos)
	end
end

local function isHammer(inst: Instance): boolean
	return inst:IsA("Tool") and inst:GetAttribute("Hammer") == true
end

-- Above the HUD's D-pad shortcuts (they bind at High). Returning Sink
-- from the rotate handler keeps DPadRight from opening Settings.
function BlueprintPlacer.RotatePriority(): number
	return Enum.ContextActionPriority.High.Value + 100
end

function BlueprintPlacer.NextRot(rot: number): number
	return (rot + 1) % 4
end

local function hidePrompts()
	PromptSwitch.Hold("placer")
end

-- Lets go of this placer's hold (PromptSwitch brings prompts back when nobody
-- else holds them off: a dialogue box or a held piece still does).
local function restorePrompts()
	PromptSwitch.Release("placer")
end

-- Your plot's centre on the platform's top (plot-local y = 0), if you have
-- one: the same origin PlotService builds on. It used to sit at world y = 0,
-- which is only the ground on a plot that happens to be level with the sea.
function BlueprintPlacer.PlotCFrame(): CFrame?
	local index = player:GetAttribute("PlotSlot") :: number?
	return if index then PlotPlatform.Origin(index) else nil
end

local function tier(): number
	return (player:GetAttribute("PlotTier") :: number?) or 1
end

-- The land squares you bought, from the PlotSquares attribute ("x,z;x,z").
function BlueprintPlacer.MySquares(): { string }
	local raw = player:GetAttribute("PlotSquares")
	local out: { string } = {}
	if type(raw) == "string" then
		for key in string.gmatch(raw, "[^;]+") do
			table.insert(out, key)
		end
	end
	return out
end

-- Everything on your plot, from the placed item models' attributes.
function BlueprintPlacer.MyPlaced(): { PlotLogic.Placed }
	local out: { PlotLogic.Placed } = {}
	for _, inst in ipairs(CollectionService:GetTagged("PlacedItem")) do
		if inst:GetAttribute("OwnerId") == player.UserId then
			local uid = inst:GetAttribute("Uid") :: string?
			local id = inst:GetAttribute("BlueprintId") :: string?
			local x, z = inst:GetAttribute("X") :: number?, inst:GetAttribute("Z") :: number?
			local rot = inst:GetAttribute("Rot") :: number?
			local y = inst:GetAttribute("Y")
			local fillUnits = inst:GetAttribute("FillUnits")
			local len = inst:GetAttribute("Len")
			local lenX = inst:GetAttribute("LenX")
			local lenZ = inst:GetAttribute("LenZ")
			local paint = inst:GetAttribute("Paint")
			if uid and id and x and z and rot then
				table.insert(out, {
					uid = uid,
					blueprintId = id,
					x = x,
					z = z,
					rot = rot,
					y = if type(y) == "number" then y else nil,
					fill = if type(fillUnits) == "number" then { units = fillUnits } else nil,
					len = if type(len) == "number" then len else nil,
					lenX = if type(lenX) == "number" then lenX else nil,
					lenZ = if type(lenZ) == "number" then lenZ else nil,
					paint = if type(paint) == "string" then paint else nil,
				})
			end
		end
	end
	return out
end

local function rootPart(): BasePart?
	local char = player.Character
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Where a ray hits the plane of your plot's platform top (plot-local y = 0).
-- It used to be the world plane y = 0, which is only right on a plot whose
-- ground happens to be level with it, so the ghost slid sideways with the
-- camera angle on every other homestead.
local function onGround(ray: Ray): Vector3?
	if ray.Direction.Y >= -1e-3 then
		return nil
	end
	local plot = BlueprintPlacer.PlotCFrame()
	local planeY = if plot then plot.Position.Y else 0
	local t = (planeY - ray.Origin.Y) / ray.Direction.Y
	return if t > 0 and t < 1000 then ray.Origin + ray.Direction * t else nil
end

local function aimPoint(s: State): Vector3?
	local camera = workspace.CurrentCamera
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		if s.aim then
			return s.aim
		end
	elseif last == Enum.UserInputType.Gamepad1 then
		if s.lockedAt then
			return s.lockedAt
		end
		local size = camera.ViewportSize
		local point = onGround(camera:ViewportPointToRay(size.X / 2, size.Y / 2))
		if point and s.push ~= 0 then
			-- Slid along your view, flat: further or nearer than the crosshair.
			local look = camera.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 1e-3 then
				point += flat.Unit * s.push
			end
		end
		return point
	else
		if overBar then
			return nil -- keep the ghost where it was aimed
		end
		local mouse = UserInputService:GetMouseLocation()
		return onGround(camera:ViewportPointToRay(mouse.X, mouse.Y))
	end
	-- No tap yet: a few studs in front of you.
	local root = rootPart()
	return if root then root.Position + root.CFrame.LookVector * 10 else nil
end

local function setBarText(text: string, ok: boolean)
	local l = barLabel
	if l then
		l.Text = text
		l.TextColor3 = if ok then CREAM else UITheme.Colors.Amber
	end
end

-- " (Steam, tier 4 of 5)" for a sawmill or a planer: the tier on the placing bar
-- (Connor: a tier label in the placement UI). Empty for anything else.
local function tierWords(id: string): string
	local mill = ItemCatalog.GetSawmill(id)
	if mill then
		return " (" .. SawmillLogic.TierText(mill) .. ")"
	end
	local machine = PlanerLogic.Get(id)
	if machine then
		return " (" .. PlanerLogic.TierText(machine) .. ")"
	end
	return ""
end

local function update(s: State)
	local plotCFrame = BlueprintPlacer.PlotCFrame()
	local root = rootPart()
	if not plotCFrame or not root then
		BlueprintPlacer.Stop()
		return
	end
	local size = (PlotData.Tier(tier()) or PlotData.Tiers[1]).size
	local me = plotCFrame:PointToObjectSpace(root.Position)
	if math.max(math.abs(me.X), math.abs(me.Z)) > size / 2 + LEAVE_REACH then
		HUD.Toast(
			if s.options.boxUid
				then "Walk onto your plot, then open the box again. It is still yours."
				else "You left your plot."
		)
		BlueprintPlacer.Stop()
		return
	end
	local point = aimPoint(s)
	if point then
		local p = plotCFrame:PointToObjectSpace(point)
		s.x, s.z = PlotLogic.Snap(p.X), PlotLogic.Snap(p.Z)
	end
	BlueprintModels.Place(s.ghost, plotCFrame, s.x, s.z, s.rot, s.y)
	local ok, why = PlotLogic.Check(
		s.bp,
		s.x,
		s.z,
		s.rot,
		tier(),
		BlueprintPlacer.MyPlaced(),
		s.options.moveUid,
		s.y,
		BlueprintPlacer.MySquares()
	)
	-- Out of a box the item is already paid for: no price, no cash check.
	local price = if s.options.boxUid then 0 elseif s.bp.kit then PlotData.Price(s.bp) else s.bp.priceCash
	if ok and not s.options.moveUid and not s.options.boxUid then
		local cash = (player:GetAttribute("Cash") :: number?) or 0
		if cash < price then
			ok, why = false, string.format("You need %s more", Util.formatCash(price - cash))
		end
	end
	s.valid, s.reason = ok, why
	s.highlight.FillColor = if ok then VALID else INVALID
	s.highlight.OutlineColor = s.highlight.FillColor
	local verb = if s.options.moveUid then "Move" else "Place"
	local priceText = if s.options.moveUid
		then ""
		elseif s.options.boxUid then " · from your box (Q keeps it)"
		else " · " .. Util.formatCash(price)
	local height = if s.y ~= 0 then string.format(" · %.1f up", s.y) else ""
	setBarText(
		if ok
			then string.format("%s the %s%s%s%s", verb, s.bp.displayName, tierWords(s.bp.id), priceText, height)
			else (why or "Can't go here"),
		ok
	)
end

function BlueprintPlacer.Raise()
	local s = state
	if s then
		s.y = math.min(PlotData.MaxBuildY, PlotLogic.SnapY(s.y + PlotData.HeightStep))
		update(s)
	end
end

function BlueprintPlacer.Lower()
	local s = state
	if s then
		s.y = math.max(0, PlotLogic.SnapY(s.y - PlotData.HeightStep))
		update(s)
	end
end

-- Gamepad: LT hangs the ghost where it is (so it stops following the
-- crosshair), and the LEFT stick then flicks it: left or right turns it a
-- quarter, up raises it a step, down lowers it. While it hangs, the left
-- stick does not walk you (PlacerStick sinks it, and the frame step holds
-- the humanoid still); the lock ends the moment LT is up, a menu opens, the
-- window loses focus, the hammer goes away or the player dies
-- (GrabLogic.LockStays), so it can never leave you unable to walk.
function BlueprintPlacer.Lock(on: boolean, pad: Enum.UserInputType?)
	local s = state
	if not s then
		return
	end
	if on then
		local point = aimPoint(s)
		s.lockedAt = point
		s.lockPad = pad or Enum.UserInputType.Gamepad1
	else
		s.lockedAt = nil
		s.lockPad = nil
		s.stickX, s.stickY, s.armedX, s.armedY = 0, 0, true, true
	end
end

-- Whether the lock should still be on, from what is true right now.
local function lockStays(s: State): boolean
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local tool = if char then char:FindFirstChildOfClass("Tool") else nil
	local pad = s.lockPad
	return GrabLogic.LockStays({
		holding = state == s,
		triggerDown = pad ~= nil and UserInputService:IsGamepadButtonDown(pad, Enum.KeyCode.ButtonL2),
		alive = humanoid ~= nil and humanoid.Health > 0,
		seated = humanoid ~= nil and humanoid.SeatPart ~= nil,
		toolOut = tool ~= nil and not isHammer(tool), -- the hammer is what is placing
		panelOpen = GuiService.SelectedObject ~= nil,
		typing = UserInputService:GetFocusedTextBox() ~= nil,
		focused = nil,
	})
end

function BlueprintPlacer.Stick(x: number, y: number)
	local s = state
	if not s or not s.lockedAt then
		return
	end
	local flickX, armX = GrabLogic.StickFlick(s.stickX, x, s.armedX)
	local flickY, armY = GrabLogic.StickFlick(s.stickY, y, s.armedY)
	s.stickX, s.stickY, s.armedX, s.armedY = x, y, armX, armY
	if flickX ~= 0 then
		s.rot = if flickX > 0 then BlueprintPlacer.NextRot(s.rot) else (s.rot + 3) % 4
	end
	if flickY > 0 then
		BlueprintPlacer.Raise()
	elseif flickY < 0 then
		BlueprintPlacer.Lower()
	end
	update(s)
end

function BlueprintPlacer.Rotate()
	local s = state
	if s then
		s.rot = BlueprintPlacer.NextRot(s.rot)
		update(s)
	end
end

function BlueprintPlacer.Place()
	local s = state
	if not s then
		return
	end
	update(s)
	if not s.valid then
		HUD.Toast((s.reason or "Can't go here") .. ".")
		return
	end
	local moveUid = s.options.moveUid
	if moveUid then
		local kitGhost = false
		for _, inst in ipairs(CollectionService:GetTagged("PlacedItem")) do
			if
				inst:GetAttribute("Uid") == moveUid
				and inst:GetAttribute("Kit") == true
				and inst:GetAttribute("FillUnits") == 0
			then
				kitGhost = true
			end
		end
		if kitGhost then
			Net.Remote("BlueprintEdit"):FireServer({
				op = "move",
				uid = moveUid,
				x = s.x,
				z = s.z,
				rot = s.rot,
				y = s.y,
			})
		else
			Net.Remote("MoveBlueprint"):FireServer(moveUid, s.x, s.z, s.rot, s.y)
		end
		tellPlaced(s)
		BlueprintPlacer.Stop()
	else
		Net.Remote("PlaceBlueprint"):FireServer(s.bp.id, s.x, s.z, s.rot, s.y, s.options.boxUid)
		tellPlaced(s)
		if s.options.boxUid then
			-- One use: the box is spent by the server on this place. Nothing to repeat.
			BlueprintPlacer.Stop()
		end
	end
end

function BlueprintPlacer.Stop()
	local s = state
	if not s then
		return
	end
	state = nil
	restorePrompts()
	for _, conn in ipairs(s.conns) do
		conn:Disconnect()
	end
	for _, name in ipairs(ACTIONS) do
		ContextActionService:UnbindAction(name)
	end
	for _, p in ipairs(s.hidden) do
		p.LocalTransparencyModifier = 0
	end
	s.ghost:Destroy()
	local b = bar
	if b then
		b.Visible = false
	end
	HUD.SetHintContext(nil)
	if s.options.onStop then
		s.options.onStop()
	end
end

local function action(fn: () -> ())
	return function(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
		if inputState == Enum.UserInputState.Begin then
			fn()
		end
		return Enum.ContextActionResult.Sink
	end
end

-- Starts placing `bp` (or moving the placed item `options.moveUid`).
function BlueprintPlacer.Begin(bp: PlotData.Blueprint, options: Options?)
	BlueprintPlacer.Stop()
	local opts: Options = options or {}
	local ghost = MachineArt.BuildAny(bp.id, true) or BlueprintModels.Build(bp, true)
	ghost.Name = "BlueprintGhost"
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.55
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = ghost
	ghost.Parent = workspace

	local hidden: { BasePart } = {}
	local rot, x, y, z = 0, 0, 0, 0
	if opts.moveUid then
		for _, inst in ipairs(CollectionService:GetTagged("PlacedItem")) do
			if inst:GetAttribute("Uid") == opts.moveUid then
				rot = (inst:GetAttribute("Rot") :: number?) or 0
				x, z = (inst:GetAttribute("X") :: number?) or 0, (inst:GetAttribute("Z") :: number?) or 0
				y = (inst:GetAttribute("Y") :: number?) or 0
				for _, d in ipairs(inst:GetDescendants()) do
					if d:IsA("BasePart") then
						d.LocalTransparencyModifier = 1
						table.insert(hidden, d)
					end
				end
			end
		end
	end

	local s: State = {
		bp = bp,
		options = opts,
		ghost = ghost,
		highlight = highlight,
		rot = rot,
		x = x,
		y = y,
		z = z,
		valid = false,
		reason = nil,
		aim = nil,
		push = 0,
		pushAxis = 0,
		lockedAt = nil,
		lockPad = nil,
		stickX = 0,
		stickY = 0,
		armedX = true,
		armedY = true,
		hidden = hidden,
		conns = {},
	}
	state = s

	-- An axe in hand would swing at every click. The hammer stays: it is what
	-- is placing, and it ignores clicks while a ghost is out.
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	local inHand = if char then char:FindFirstChildOfClass("Tool") else nil
	if humanoid and not (inHand and isHammer(inHand)) then
		humanoid:UnequipTools()
	end
	hidePrompts()
	if humanoid then
		table.insert(
			s.conns,
			humanoid.Died:Connect(function()
				BlueprintPlacer.Stop()
			end)
		)
	end
	if char then
		table.insert(
			s.conns,
			char.ChildAdded:Connect(function(child: Instance)
				if child:IsA("Tool") and not isHammer(child) then
					BlueprintPlacer.Stop()
				end
			end)
		)
		-- Putting the hammer away ends placing too.
		table.insert(
			s.conns,
			char.ChildRemoved:Connect(function(child: Instance)
				if isHammer(child) and child.Parent ~= char then
					BlueprintPlacer.Stop()
				end
			end)
		)
	end

	ContextActionService:BindActionAtPriority(
		"PlacerRotate",
		action(BlueprintPlacer.Rotate),
		false,
		BlueprintPlacer.RotatePriority(),
		Enum.KeyCode.R,
		Enum.KeyCode.DPadRight
	)
	ContextActionService:BindAction("PlacerPlace", action(BlueprintPlacer.Place), false, Enum.KeyCode.ButtonR2)
	-- LT hangs the ghost; the LEFT (movement) stick flicks it round or up
	-- and down and, sunk while LT is held, walks nobody; the right stick
	-- stays the camera's. RB and LB slide it further or nearer. All gamepad
	-- only: they bind to nothing else.
	ContextActionService:BindActionAtPriority(
		"PlacerLock",
		function(_name: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin then
				BlueprintPlacer.Lock(true, input.UserInputType)
			elseif inputState ~= Enum.UserInputState.Change then
				BlueprintPlacer.Lock(false)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		BlueprintPlacer.RotatePriority(),
		Enum.KeyCode.ButtonL2
	)
	ContextActionService:BindActionAtPriority(
		"PlacerStick",
		function(_name: string, _inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			local current = state
			if not current or GrabLogic.StickWalks(current.lockedAt ~= nil) then
				return Enum.ContextActionResult.Pass -- not locked: it walks you, as always
			end
			BlueprintPlacer.Stick(input.Position.X, input.Position.Y)
			return Enum.ContextActionResult.Sink -- locked: it turns the ghost and walks nobody
		end,
		false,
		BlueprintPlacer.RotatePriority(),
		Enum.KeyCode.Thumbstick1
	)
	ContextActionService:BindActionAtPriority(
		"PlacerPush",
		function(_name: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			local current = state
			if current then
				local axis = if input.KeyCode == Enum.KeyCode.ButtonR1 then 1 else -1
				if inputState == Enum.UserInputState.Begin then
					current.pushAxis = axis
				elseif inputState ~= Enum.UserInputState.Change and current.pushAxis == axis then
					current.pushAxis = 0
				end
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		BlueprintPlacer.RotatePriority(),
		Enum.KeyCode.ButtonR1,
		Enum.KeyCode.ButtonL1
	)
	ContextActionService:BindAction(
		"PlacerCancel",
		action(BlueprintPlacer.Stop),
		false,
		Enum.KeyCode.Q,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:BindAction("PlacerUp", action(BlueprintPlacer.Raise), false, Enum.KeyCode.E)
	ContextActionService:BindAction("PlacerDown", action(BlueprintPlacer.Lower), false, Enum.KeyCode.C)
	table.insert(
		s.conns,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			-- A finger also reports a mouse click. On a touch screen the tap
			-- only aims (TouchTapInWorld); PLACE confirms. Treating that
			-- click as Place built wherever the ghost already sat.
			if
				not processed
				and input.UserInputType == Enum.UserInputType.MouseButton1
				and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch
			then
				BlueprintPlacer.Place()
			end
		end)
	)
	-- A window that loses focus never reports LT going up.
	table.insert(
		s.conns,
		UserInputService.WindowFocusReleased:Connect(function()
			BlueprintPlacer.Lock(false)
		end)
	)
	table.insert(
		s.conns,
		UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processedByUI: boolean)
			if not processedByUI then
				s.aim = onGround(workspace.CurrentCamera:ScreenPointToRay(position.X, position.Y))
			end
		end)
	)
	table.insert(
		s.conns,
		RunService.RenderStepped:Connect(function(dt: number)
			if state == s then
				if s.lockedAt ~= nil then
					if lockStays(s) then
						-- Held still here, after the controls' own Move this frame.
						local body = player.Character
						local walker = if body then body:FindFirstChildOfClass("Humanoid") else nil
						if walker then
							walker:Move(Vector3.zero, false)
						end
					else
						BlueprintPlacer.Lock(false) -- LT is up, or a menu has the pad: walking again
					end
				end
				if s.pushAxis ~= 0 then
					s.push = math.clamp(s.push + s.pushAxis * PUSH_SPEED * dt, PUSH_MIN, PUSH_MAX)
				end
				update(s)
			end
		end)
	)
	local b = bar
	if b then
		b.Visible = true
	end
	HUD.SetHintContext("build") -- the hint says how to place, turn and stop
	update(s)
end

-- Opening a sawmill, planer or belt box: the server says which (WorldFX
-- "PlaceBox") and the ghost starts. Cancelling keeps the box.
local function onWorldFx(kind: unknown, payload: unknown)
	if kind ~= "PlaceBox" or type(payload) ~= "table" then
		return
	end
	local data = payload :: { [string]: unknown }
	local uid, itemId = data.uid, data.itemId
	if type(uid) ~= "string" or type(itemId) ~= "string" then
		return
	end
	local bp = PlotLogic.Blueprint(itemId)
	if bp then
		BlueprintPlacer.Begin(bp, { boxUid = uid })
	end
end

function BlueprintPlacer.Start()
	Net.Remote("WorldFX").OnClientEvent:Connect(onWorldFx)
	local gui = UITheme.Screen("BlueprintPlacer", UITheme.Layers.World)
	local b = UITheme.Bar(gui, "Placing")
	barLabel = b.label
	local function add(text: string, style: string, order: number, onClick: () -> ())
		local button = UITheme.Button({ text = text, size = Vector2.new(96, 36), style = style })
		button.root.LayoutOrder = order
		button.root.Parent = b.row
		button.face.Activated:Connect(onClick)
	end
	add("ROTATE", "bark", 1, BlueprintPlacer.Rotate)
	add("UP", "bark", 2, BlueprintPlacer.Raise)
	add("DOWN", "bark", 3, BlueprintPlacer.Lower)
	add("PLACE", "buy", 4, BlueprintPlacer.Place)
	add("CANCEL", "skip", 5, BlueprintPlacer.Stop)
	bar = b.outer
	b.outer.MouseEnter:Connect(function()
		overBar = true
	end)
	b.outer.MouseLeave:Connect(function()
		overBar = false
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
	player.CharacterRemoving:Connect(BlueprintPlacer.Stop)
end

return BlueprintPlacer
