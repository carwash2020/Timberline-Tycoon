--!strict
-- BlueprintPlacer: placing a blueprint on your plot (GAME_DESIGN §9).
--   * A ghost of the blueprint (Shared/BlueprintModels, the same model the
--     server builds) follows the mouse, the last tap on a touch screen, or
--     the middle of the screen on a gamepad, snapped to PlotData.Grid.
--   * Green where PlotLogic.Check allows it (and you can pay), red with the
--     reason where it doesn't. The server checks again: this is a preview.
--   * Click or PLACE (R2 on a gamepad) to place; R or ROTATE (X) for a
--     quarter turn; Q or CANCEL (B) to stop. After placing something new you
--     keep placing the same blueprint (fences!) until you cancel. A move
--     ends after one placement.
--   * Walking off your plot stops placing.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BlueprintModels = require(ReplicatedStorage.Shared.BlueprintModels)
local Net = require(ReplicatedStorage.Shared.Net)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local HUD = require(script.Parent.HUD)

local BlueprintPlacer = {}

local player = Players.LocalPlayer

local CREAM = Color3.fromRGB(245, 235, 215)
local BARK = Color3.fromRGB(88, 58, 34)
local GREEN = Color3.fromRGB(76, 140, 64)
local RED = Color3.fromRGB(190, 60, 45)
local VALID = Color3.fromRGB(90, 220, 110)
local INVALID = Color3.fromRGB(235, 70, 60)

local LEAVE_REACH = 40 -- studs past the plot's edge before placing stops (PlotService's BUILD_REACH)
local ACTIONS = { "PlacerRotate", "PlacerPlace", "PlacerCancel" }

export type Options = {
	moveUid: string?, -- moving this placed item instead of buying a new one
	onStop: (() -> ())?, -- called once placing ends, however it ends
}

type State = {
	bp: PlotData.Blueprint,
	options: Options,
	ghost: Model,
	highlight: Highlight,
	rot: number,
	x: number,
	z: number,
	valid: boolean,
	reason: string?,
	aim: Vector3?, -- the last tapped point in the world (touch)
	hidden: { BasePart }, -- the moved item's own parts, hidden while it moves
	conns: { RBXScriptConnection },
}

local state: State? = nil
local bar: Frame? = nil
local barLabel: TextLabel? = nil

function BlueprintPlacer.Active(): boolean
	return state ~= nil
end

-- Your plot's centre, if you have one.
function BlueprintPlacer.PlotCFrame(): CFrame?
	local index = player:GetAttribute("PlotSlot") :: number?
	local center = if index then PlotData.Slots[index] else nil
	return if center then CFrame.new(center.X, 0, center.Y) else nil
end

local function tier(): number
	return (player:GetAttribute("PlotTier") :: number?) or 1
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
			if uid and id and x and z and rot then
				table.insert(out, { uid = uid, blueprintId = id, x = x, z = z, rot = rot })
			end
		end
	end
	return out
end

local function rootPart(): BasePart?
	local char = player.Character
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Where a ray hits the ground plane (y = 0), where every plot sits.
local function onGround(ray: Ray): Vector3?
	if ray.Direction.Y >= -1e-3 then
		return nil
	end
	local t = -ray.Origin.Y / ray.Direction.Y
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
		local size = camera.ViewportSize
		return onGround(camera:ViewportPointToRay(size.X / 2, size.Y / 2))
	else
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
		l.TextColor3 = if ok then CREAM else Color3.fromRGB(255, 190, 170)
	end
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
		HUD.Toast("You left your plot.")
		BlueprintPlacer.Stop()
		return
	end
	local point = aimPoint(s)
	if point then
		local p = plotCFrame:PointToObjectSpace(point)
		s.x, s.z = PlotLogic.Snap(p.X), PlotLogic.Snap(p.Z)
	end
	BlueprintModels.Place(s.ghost, plotCFrame, s.x, s.z, s.rot)
	local ok, why = PlotLogic.Check(s.bp, s.x, s.z, s.rot, tier(), BlueprintPlacer.MyPlaced(), s.options.moveUid)
	if ok and not s.options.moveUid then
		local cash = (player:GetAttribute("Cash") :: number?) or 0
		if cash < s.bp.priceCash then
			ok, why = false, string.format("You need %s more", Util.formatCash(s.bp.priceCash - cash))
		end
	end
	s.valid, s.reason = ok, why
	s.highlight.FillColor = if ok then VALID else INVALID
	s.highlight.OutlineColor = s.highlight.FillColor
	local verb = if s.options.moveUid then "Move" else "Place"
	local price = if s.options.moveUid then "" else " · " .. Util.formatCash(s.bp.priceCash)
	setBarText(if ok then string.format("%s the %s%s", verb, s.bp.displayName, price) else (why or "Can't go here"), ok)
end

function BlueprintPlacer.Rotate()
	local s = state
	if s then
		s.rot = (s.rot + 1) % 4
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
		Net.Remote("MoveBlueprint"):FireServer(moveUid, s.x, s.z, s.rot)
		BlueprintPlacer.Stop()
	else
		Net.Remote("PlaceBlueprint"):FireServer(s.bp.id, s.x, s.z, s.rot)
	end
end

function BlueprintPlacer.Stop()
	local s = state
	if not s then
		return
	end
	state = nil
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
	local ghost = BlueprintModels.Build(bp, true)
	ghost.Name = "BlueprintGhost"
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.55
	highlight.OutlineTransparency = 0.2
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = ghost
	ghost.Parent = workspace

	local hidden: { BasePart } = {}
	local rot, x, z = 0, 0, 0
	if opts.moveUid then
		for _, inst in ipairs(CollectionService:GetTagged("PlacedItem")) do
			if inst:GetAttribute("Uid") == opts.moveUid then
				rot = (inst:GetAttribute("Rot") :: number?) or 0
				x, z = (inst:GetAttribute("X") :: number?) or 0, (inst:GetAttribute("Z") :: number?) or 0
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
		z = z,
		valid = false,
		reason = nil,
		aim = nil,
		hidden = hidden,
		conns = {},
	}
	state = s

	-- An axe in hand would swing at every click.
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid:UnequipTools()
	end

	ContextActionService:BindAction(
		"PlacerRotate",
		action(BlueprintPlacer.Rotate),
		false,
		Enum.KeyCode.R,
		Enum.KeyCode.ButtonX
	)
	ContextActionService:BindAction("PlacerPlace", action(BlueprintPlacer.Place), false, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction(
		"PlacerCancel",
		action(BlueprintPlacer.Stop),
		false,
		Enum.KeyCode.Q,
		Enum.KeyCode.ButtonB
	)
	table.insert(
		s.conns,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
				BlueprintPlacer.Place()
			end
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
		RunService.RenderStepped:Connect(function()
			if state == s then
				update(s)
			end
		end)
	)
	local b = bar
	if b then
		b.Visible = true
	end
	update(s)
end

local function button(parent: Instance, text: string, color: Color3, order: number, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Name = text
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(96, 36)
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = CREAM
	b.Text = text
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

function BlueprintPlacer.Start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "BlueprintPlacer"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 6

	local frame = Instance.new("Frame")
	frame.Name = "Bar"
	frame.AnchorPoint = Vector2.new(0.5, 1)
	frame.Position = UDim2.new(0.5, 0, 1, -44) -- above the control hint
	frame.Size = UDim2.fromOffset(340, 84)
	frame.BackgroundColor3 = BARK
	frame.BackgroundTransparency = 0.1
	frame.Visible = false
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = frame
	frame.Parent = gui

	local l = Instance.new("TextLabel")
	l.Name = "What"
	l.Position = UDim2.fromOffset(10, 6)
	l.Size = UDim2.new(1, -20, 0, 24)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 15
	l.TextColor3 = CREAM
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = frame
	barLabel = l

	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.Position = UDim2.fromOffset(0, 38)
	row.Size = UDim2.new(1, 0, 0, 36)
	row.BackgroundTransparency = 1
	row.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = row
	button(row, "ROTATE", BARK:Lerp(Color3.new(0, 0, 0), 0.25), 1, BlueprintPlacer.Rotate)
	button(row, "PLACE", GREEN, 2, BlueprintPlacer.Place)
	button(row, "CANCEL", RED, 3, BlueprintPlacer.Stop)

	bar = frame
	gui.Parent = player:WaitForChild("PlayerGui")
	player.CharacterRemoving:Connect(BlueprintPlacer.Stop)
end

return BlueprintPlacer
