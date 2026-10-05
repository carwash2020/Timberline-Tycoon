--!strict
-- WireTool: wire a Wall Switch to a Spark Lamp or a Door without prompts.
-- Rules are in Shared/WireToolLogic; the server (LogicService) decides.
--   * PlotUI's WIRE button (BUILD mode) starts it. Lines between wired
--     pieces on your own plot show for the whole of BUILD mode, at most
--     WireToolLogic.MaxLines thin Neon parts, reused.
--   * Phone: tap a piece. PC: click it. Xbox: aim the crosshair, RT picks,
--     X cuts, B leaves (InputKit.WireBinds). Buttons CUT and DONE are 48 px
--     tall for touch and the help line is 18 px on a TV.
--   * Pick a switch, then tap lamps and doors to wire them (each tap is
--     Wire (fromUid, 1, toUid, 1)). Pick any wired piece and CUT sends
--     Wire ("cut", uid). World prompts are off while the tool is up.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local InputKit = require(ReplicatedStorage.Shared.InputKit)
local Net = require(ReplicatedStorage.Shared.Net)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local WireLogic = require(ReplicatedStorage.Shared.WireLogic)
local WireToolLogic = require(ReplicatedStorage.Shared.WireToolLogic)
local BlueprintPlacer = require(script.Parent.BlueprintPlacer)
local HUD = require(script.Parent.HUD)
local UITheme = require(script.Parent.UITheme)

local WireTool = {}

local player = Players.LocalPlayer
local C = UITheme.Colors

local LINE = Color3.fromRGB(255, 196, 64)
local LINE_PICKED = Color3.fromRGB(120, 220, 255)
local ACTIONS = { "WirePick", "WireCut", "WireDone" }

local active = false
local building = false
local picked: string? = nil
local promptsWere: boolean? = nil
local conns: { RBXScriptConnection } = {}
local selection: SelectionBox? = nil
local folder: Folder? = nil
local pool: { Part } = {}
local bar: UITheme.Bar? = nil
local reticle: Frame? = nil
local onStop: (() -> ())? = nil

function WireTool.Active(): boolean
	return active
end

-- Your pieces: their uid, blueprint and plot-local spot, the models, and
-- each switch's "Wires" attribute text.
local function mine(): ({ WireToolLogic.Piece }, { [string]: Model }, { [string]: string })
	local pieces: { WireToolLogic.Piece } = {}
	local models: { [string]: Model } = {}
	local wires: { [string]: string } = {}
	for _, inst in ipairs(CollectionService:GetTagged("PlacedItem")) do
		if inst:IsA("Model") and inst:GetAttribute("OwnerId") == player.UserId then
			local uid = inst:GetAttribute("Uid")
			local id = inst:GetAttribute("BlueprintId")
			local x, z = inst:GetAttribute("X"), inst:GetAttribute("Z")
			if type(uid) == "string" and type(id) == "string" and type(x) == "number" and type(z) == "number" then
				local y = inst:GetAttribute("Y")
				table.insert(
					pieces,
					{ uid = uid, blueprintId = id, x = x, y = if type(y) == "number" then y else nil, z = z }
				)
				models[uid] = inst
				local text = inst:GetAttribute("Wires")
				if type(text) == "string" and text ~= "" then
					wires[uid] = text
				end
			end
		end
	end
	return pieces, models, wires
end

local function worldPoint(plot: CFrame, piece: WireToolLogic.Piece): Vector3
	local role = WireLogic.Role(piece.blueprintId)
	local h = WireToolLogic.Height[role or ""] or 3
	return plot:PointToWorldSpace(Vector3.new(piece.x, (piece.y or 0) + h, piece.z))
end

---------------------------------------------------------------------------
-- The lines
---------------------------------------------------------------------------

local function linePart(i: number): Part
	local part = pool[i]
	if part and part.Parent then
		return part
	end
	local p = Instance.new("Part")
	p.Name = "WireLine"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Size = Vector3.new(WireToolLogic.LineThickness, WireToolLogic.LineThickness, 1)
	p.Parent = folder
	pool[i] = p
	return p
end

local function drawLines()
	local plot = BlueprintPlacer.PlotCFrame()
	if not building or not plot then
		for _, p in ipairs(pool) do
			p.Parent = nil
		end
		return
	end
	local pieces, _, wires = mine()
	local segments = WireToolLogic.Segments(pieces, wires)
	for i, seg in ipairs(segments) do
		local a = plot:PointToWorldSpace(Vector3.new(seg.ax, seg.ay, seg.az))
		local b = plot:PointToWorldSpace(Vector3.new(seg.bx, seg.by, seg.bz))
		local len = (b - a).Magnitude
		local part = linePart(i)
		part.Size = Vector3.new(WireToolLogic.LineThickness, WireToolLogic.LineThickness, math.max(len, 0.1))
		part.CFrame = CFrame.lookAt((a + b) / 2, b)
		part.Color = if active and (seg.from == picked or seg.to == picked) then LINE_PICKED else LINE
		part.Parent = folder
	end
	for i = #segments + 1, #pool do
		pool[i].Parent = nil
	end
end

---------------------------------------------------------------------------
-- Picking
---------------------------------------------------------------------------

local function refreshBar()
	local b = bar
	if not b then
		return
	end
	local pieces = mine()
	local text = WireToolLogic.Help(picked, pieces)
	if UITheme.Device() == "console" then
		text ..= "  RT pick · X cut · B done"
	end
	b.label.Text = text
end

local function highlight()
	if selection then
		selection:Destroy()
		selection = nil
	end
	local uid = picked
	if uid then
		local _, models = mine()
		local model = models[uid]
		if model then
			local box = Instance.new("SelectionBox")
			box.Name = "WireSelect"
			box.Adornee = model
			box.LineThickness = 0.06
			box.Color3 = LINE_PICKED
			box.SurfaceColor3 = LINE_PICKED
			box.SurfaceTransparency = 0.8
			box.Parent = model
			selection = box
		end
	end
	drawLines()
end

local function reachOk(pieces: { WireToolLogic.Piece }, uid: string): boolean
	local plot = BlueprintPlacer.PlotCFrame()
	local char = player.Character
	local root = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not plot or not root then
		return false
	end
	local p = plot:PointToObjectSpace(root.Position)
	for _, piece in ipairs(pieces) do
		if piece.uid == uid then
			return WireLogic.InReach(p.X, p.Y, p.Z, piece :: any)
		end
	end
	return false
end

local function fire(action: WireToolLogic.Action)
	local args = WireToolLogic.Args(action)
	Net.Remote("Wire"):FireServer(table.unpack(args))
end

-- A piece was picked (or nothing, for the ground).
local function pick(uid: string?)
	local pieces, _, wires = mine()
	local nextPick, action = WireToolLogic.Tap(picked, uid, pieces)
	if action and action.op == "link" then
		if not (reachOk(pieces, action.from) and reachOk(pieces, action.to)) then
			HUD.Toast(WireLogic.Message("reach") or "Stand closer to wire that.")
		else
			local ok, why = WireLogic.Check(WireToolLogic.WireList(wires), pieces :: any, action.from, action.to)
			if ok then
				fire(action)
			else
				HUD.Toast(WireLogic.Message(why) or "")
			end
		end
	end
	picked = nextPick
	highlight()
	refreshBar()
end

local function cut()
	local pieces = mine()
	local action = WireToolLogic.Cut(picked, pieces)
	if not action or not picked then
		HUD.Toast("Pick a switch or a wired piece first.")
		return
	end
	if not reachOk(pieces, picked) then
		HUD.Toast(WireLogic.Message("reach") or "Stand closer to wire that.")
		return
	end
	fire(action)
end

-- A tap or click at a screen point (GUI-inset space).
local function pickAt(x: number, y: number)
	local camera = workspace.CurrentCamera
	local plot = BlueprintPlacer.PlotCFrame()
	if not camera or not plot then
		return
	end
	local pieces = mine()
	local points: { [string]: { number } } = {}
	for _, piece in ipairs(pieces) do
		local v, onScreen = camera:WorldToScreenPoint(worldPoint(plot, piece))
		if onScreen then
			points[piece.uid] = { v.X, v.Y }
		end
	end
	pick(WireToolLogic.NearestOnScreen(pieces, points, x, y))
end

-- Gamepad: what the crosshair (screen centre) is on.
local function pickAimed()
	local camera = workspace.CurrentCamera
	local plot = BlueprintPlacer.PlotCFrame()
	if not camera or not plot then
		return
	end
	local eye = plot:PointToObjectSpace(camera.CFrame.Position)
	local look = plot:VectorToObjectSpace(camera.CFrame.LookVector)
	pick(WireToolLogic.Aim(mine(), eye.X, eye.Y, eye.Z, look.X, look.Y, look.Z))
end

---------------------------------------------------------------------------
-- Start and stop
---------------------------------------------------------------------------

function WireTool.Stop()
	if not active then
		return
	end
	active = false
	picked = nil
	for _, conn in ipairs(conns) do
		conn:Disconnect()
	end
	table.clear(conns)
	for _, name in ipairs(ACTIONS) do
		ContextActionService:UnbindAction(name)
	end
	if promptsWere ~= nil then
		ProximityPromptService.Enabled = promptsWere
		promptsWere = nil
	end
	if selection then
		selection:Destroy()
		selection = nil
	end
	if bar then
		bar.outer.Visible = false
	end
	if reticle then
		reticle.Visible = false
	end
	GuiService.SelectedObject = nil
	drawLines()
	local after = onStop
	if after then
		after()
	end
end

local function action(fn: () -> ())
	return function(_name: string, state: Enum.UserInputState): Enum.ContextActionResult
		if state == Enum.UserInputState.Begin then
			fn()
		end
		return Enum.ContextActionResult.Sink
	end
end

-- `stopped` runs when the tool ends, so PlotUI can bring its bar back.
function WireTool.Begin(stopped: (() -> ())?)
	if active or BlueprintPlacer.Active() then
		return
	end
	active = true
	picked = nil
	onStop = stopped
	if promptsWere == nil then
		promptsWere = ProximityPromptService.Enabled
	end
	ProximityPromptService.Enabled = false
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid:UnequipTools()
		table.insert(
			conns,
			humanoid.Died:Connect(function()
				WireTool.Stop()
			end)
		)
	end
	if char then
		table.insert(
			conns,
			char.ChildAdded:Connect(function(child: Instance)
				if child:IsA("Tool") then
					WireTool.Stop()
				end
			end)
		)
	end
	-- Mouse click. Touch taps arrive as TouchTapInWorld (a drag is the camera).
	table.insert(
		conns,
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			pickAt(input.Position.X, input.Position.Y)
		end)
	)
	table.insert(
		conns,
		UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processed: boolean)
			if not processed then
				pickAt(position.X, position.Y)
			end
		end)
	)
	local binds = InputKit.WireBinds
	local pickBind, cutBind, doneBind = binds[1], binds[2], binds[3]
	local top = Enum.ContextActionPriority.High.Value + 100
	ContextActionService:BindActionAtPriority("WirePick", action(pickAimed), false, top, pickBind.gamepad)
	ContextActionService:BindActionAtPriority(
		"WireCut",
		action(cut),
		false,
		top,
		cutBind.gamepad,
		cutBind.keyboard :: Enum.KeyCode
	)
	ContextActionService:BindActionAtPriority(
		"WireDone",
		action(WireTool.Stop),
		false,
		top,
		doneBind.gamepad,
		doneBind.keyboard :: Enum.KeyCode
	)
	if bar then
		bar.outer.Visible = true
	end
	if reticle then
		reticle.Visible = UITheme.Device() == "console"
	end
	refreshBar()
	drawLines()
end

-- BUILD mode on or off. Lines show while it is on; leaving ends the tool.
function WireTool.SetBuilding(on: boolean)
	building = on
	if not on then
		WireTool.Stop()
	end
	drawLines()
end

function WireTool.Start()
	local screen = UITheme.Screen("WireTool", UITheme.Layers.WireTool)
	local f = Instance.new("Folder")
	f.Name = "WireLines"
	f.Parent = workspace
	folder = f

	local b = UITheme.Bar(screen, "WireMode")
	local console = UITheme.Device() == "console"
	b.label.TextSize = if console then 18 else 15
	b.label.Size = UDim2.fromOffset(if console then 560 else 340, if console then 26 else 40)
	b.label.TextWrapped = true
	b.label.TextTruncate = Enum.TextTruncate.None
	local cutButton = UITheme.Button({
		text = "CUT",
		size = Vector2.new(96, PlotLogic.LandTap),
		style = "amber",
		textSize = if console then 18 else nil,
	})
	cutButton.root.LayoutOrder = 1
	cutButton.root.Parent = b.row
	cutButton.face.Activated:Connect(cut)
	local done = UITheme.Button({
		text = "DONE",
		size = Vector2.new(98, PlotLogic.LandTap),
		style = "skip",
		textSize = if console then 18 else nil,
	})
	done.root.LayoutOrder = 2
	done.root.Parent = b.row
	done.face.Activated:Connect(WireTool.Stop)
	bar = b

	-- A small crosshair for the gamepad's aim.
	local dot = Instance.new("Frame")
	dot.Name = "Crosshair"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(12, 12)
	dot.BackgroundColor3 = LINE_PICKED
	dot.BorderSizePixel = 0
	dot.Visible = false
	UITheme.corner(dot, 6)
	UITheme.stroke(dot, C.Ink, 2)
	dot.Parent = screen
	reticle = dot

	screen.Parent = player:WaitForChild("PlayerGui")
	-- Keep the lines in step with the wires the server reports.
	task.spawn(function()
		while true do
			task.wait(0.25)
			if building then
				drawLines()
			end
		end
	end)
end

return WireTool
