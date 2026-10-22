--!strict
-- WireTool: wire a Wall Switch to a Spark Lamp or a Door without prompts.
-- Rules are in Shared/WireToolLogic and Shared/WireSupply; the server
-- (LogicService) decides.
--   * The Wire spool (a Tool, LogicService.GiveSpool) starts it when you take it
--     out and ends it when you put it away (T420: wiring is not on the hammer
--     any more). Lines between wired pieces on your own plot show while the
--     spool or the hammer is in hand, at most WireToolLogic.MaxLines thin Neon
--     parts, reused.
--   * Wire is a single-use item: pick an output, and a line stretches from it to
--     where you aim; its length, the wire it would use and what is left in your
--     box show as you go (WireToolLogic.Stretch). Tap an input to place it: up to
--     WireSupply.MaxLength studs, used up from the box. BUY gets what is missing
--     (Wire ("buy", amount)); the server sells, takes the cash and checks again.
--   * Phone: tap a piece. PC: click it. Xbox: aim the crosshair, RB picks,
--     X cuts, R3 (right stick press) buys, B puts the spool away (InputKit.WireBinds). Buttons are
--     48 px tall for touch and the help line is 18 px on a TV.
--   * Pick a switch, then tap lamps and doors to wire them (each tap is
--     Wire (fromUid, 1, toUid, 1)). Pick any wired piece and CUT sends
--     Wire ("cut", uid); cutting gives no wire back. World prompts are off while
--     the tool is up.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local InputKit = require(ReplicatedStorage.Shared.InputKit)
local Net = require(ReplicatedStorage.Shared.Net)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local WireLogic = require(ReplicatedStorage.Shared.WireLogic)
local WireSupply = require(ReplicatedStorage.Shared.WireSupply)
local WireToolLogic = require(ReplicatedStorage.Shared.WireToolLogic)
local BlueprintPlacer = require(script.Parent.BlueprintPlacer)
local HUD = require(script.Parent.HUD)
local LogicPanelUI = require(script.Parent.LogicPanelUI)
local PromptSwitch = require(script.Parent.PromptSwitch)
local UITheme = require(script.Parent.UITheme)

local WireTool = {}

local player = Players.LocalPlayer
local C = UITheme.Colors

local LINE = Color3.fromRGB(255, 196, 64)
local LINE_PICKED = Color3.fromRGB(120, 220, 255)
local LINE_WARN = C.WireShort -- a stretch the box cannot pay for yet (#FFC873)
local LINE_BAD = C.WireTooLong -- a stretch past the longest wire (#C8553D)
local ACTIONS = { "WirePick", "WireCut", "WireBuy", "WireDone" }

local active = false
local building = false
local picked: string? = nil
local conns: { RBXScriptConnection } = {}
local selection: SelectionBox? = nil
local folder: Folder? = nil
local pool: { Part } = {}
local bar: UITheme.Bar? = nil
local buyButton: UITheme.Button? = nil
local reticle: Frame? = nil
local spool: Tool? = nil -- the Wire tool in hand
local stretchLines: { Part } = {} -- the live run: one line per leg, from the picked output through its bends to where you aim
local bends: { WireLogic.Point } = {} -- corners tapped on the ground so far (plot-local), at most WireSupply.MaxBends
local stretch: WireToolLogic.Stretch = WireToolLogic.Stretch(0, nil, nil, nil)
local lastTap: Vector2? = nil
local session = 0 -- a new tool session cancels the preview loop of the last
local onStop: (() -> ())? = nil
-- 1..3 while the first-use hint is showing, 4 once this session has seen it.
local lessonStep = 1

function WireTool.Active(): boolean
	return active
end

-- Wire left in your box (the WireUnits attribute the server keeps).
local function stock(): number
	return WireSupply.Clean(player:GetAttribute("WireUnits"))
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
	if not (building or active) or not plot then
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
	local text: string
	if picked ~= nil and stretch.state ~= "start" then
		-- Stretching: the length, what it uses and what is left (WireToolLogic.Stretch).
		text = stretch.text
	else
		text = WireToolLogic.Help(picked, pieces)
		local lesson = WireToolLogic.Lesson(lessonStep)
		if lesson then
			text = lesson .. "  " .. text
		end
	end
	text ..= "  " .. WireToolLogic.BoxLine(stock())
	if UITheme.Device() == "console" then
		text ..= "  RB pick · X cut · R3 buy · B done"
	end
	b.label.Text = text
	local buy = buyButton
	if buy then
		local plan = WireToolLogic.BuyPlan(stock(), stretch)
		buy:SetText(plan.text)
		buy:SetStyle(if plan.amount > 0 then (if stretch.short > 0 then "buy" else "amber") else "locked")
	end
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

local function blueprintOf(pieces: { WireToolLogic.Piece }, uid: string): string?
	for _, piece in ipairs(pieces) do
		if piece.uid == uid then
			return piece.blueprintId
		end
	end
	return nil
end

-- Wires the client can see, including "@port" on an input that is not port 1.
local function detailedWires(wires: { [string]: string }): { WireLogic.Wire }
	local out: { WireLogic.Wire } = {}
	for from, text in pairs(wires) do
		for token in string.gmatch(text, "[^,]+") do
			local parsed = WireToolLogic.ParseToken(token)
			if parsed then
				table.insert(out, { from = from, to = parsed.uid, toPort = parsed.port })
			end
		end
	end
	return out
end

local function pieceOf(pieces: { WireToolLogic.Piece }, uid: string?): WireToolLogic.Piece?
	if uid == nil then
		return nil
	end
	for _, piece in ipairs(pieces) do
		if piece.uid == uid then
			return piece
		end
	end
	return nil
end

local function lastInputIsGamepad(): boolean
	return string.find(UserInputService:GetLastInputType().Name, "Gamepad") ~= nil
end

-- The screen point you are aiming at: the mouse, the last tap, or the crosshair.
local function aimPoint(): Vector2
	local camera = workspace.CurrentCamera
	local centre = if camera then camera.ViewportSize / 2 else Vector2.zero
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return lastTap or centre
	elseif string.find(last.Name, "Gamepad") then
		return centre
	end
	return UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
end

local function previewPart(i: number): Part?
	local f = folder
	if not f then
		return nil
	end
	local part = stretchLines[i]
	if part and part.Parent then
		return part
	end
	local p = Instance.new("Part")
	p.Name = "WireStretch"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Size = Vector3.new(WireToolLogic.LineThickness, WireToolLogic.LineThickness, 1)
	p.Parent = f
	stretchLines[i] = p
	return p
end

local function hideStretch()
	for _, part in ipairs(stretchLines) do
		part.Parent = nil
	end
end

-- Where a screen point meets the ground at `height` (plot-local x, z), or nil.
local function groundAt(x: number, y: number, height: number): Vector3?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local ray = camera:ViewportPointToRay(x, y)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil
	end
	local along = (height - ray.Origin.Y) / ray.Direction.Y
	if along <= 0 then
		return nil
	end
	return ray.Origin + ray.Direction * along
end

local TONE_COLOR: { [string]: Color3 } = { ok = LINE_PICKED, warn = LINE_WARN, bad = LINE_BAD }

-- The line stretching from the picked output to where you aim, and what it would
-- use and cost. A few times a second, only while something is picked.
local function updateStretch()
	local plot = BlueprintPlacer.PlotCFrame()
	local camera = workspace.CurrentCamera
	local pieces = mine()
	local from = pieceOf(pieces, picked)
	if not (active and plot and camera and from) or not WireLogic.IsSource(WireLogic.Role(from.blueprintId)) then
		stretch = WireToolLogic.Stretch(stock(), nil, nil, nil, nil)
		hideStretch()
		refreshBar()
		return
	end
	local at = aimPoint()
	-- What the aim is on: an input within a fingertip of it, or the crosshair's piece.
	local aimed: WireToolLogic.Piece? = nil
	if lastInputIsGamepad() then
		local eye = plot:PointToObjectSpace(camera.CFrame.Position)
		local look = plot:VectorToObjectSpace(camera.CFrame.LookVector)
		aimed = pieceOf(pieces, WireToolLogic.Aim(pieces, eye.X, eye.Y, eye.Z, look.X, look.Y, look.Z))
	else
		local points: { [string]: { number } } = {}
		for _, piece in ipairs(pieces) do
			local v, onScreen = camera:WorldToScreenPoint(worldPoint(plot, piece))
			if onScreen then
				points[piece.uid] = { v.X, v.Y }
			end
		end
		aimed = pieceOf(pieces, WireToolLogic.NearestOnScreen(pieces, points, at.X, at.Y))
	end
	-- The run so far (the tie of the output, then each bend), and where it ends.
	local start = worldPoint(plot, from)
	local path: { Vector3 } = { start }
	for _, bend in ipairs(bends) do
		table.insert(path, plot:PointToWorldSpace(Vector3.new(bend.x, start.Y - plot.Position.Y, bend.z)))
	end
	local last = path[#path]
	local endPoint = last
	local free = 0
	local onInput = aimed ~= nil and aimed.uid ~= from.uid
	if onInput then
		endPoint = worldPoint(plot, aimed :: WireToolLogic.Piece)
	else
		local ground = groundAt(at.X, at.Y, last.Y)
		if ground then
			endPoint = ground
			local a, b = plot:PointToObjectSpace(last), plot:PointToObjectSpace(ground)
			free = math.sqrt((b.X - a.X) ^ 2 + (b.Z - a.Z) ^ 2)
		end
	end
	stretch = WireToolLogic.Stretch(stock(), from, aimed, free, bends)
	table.insert(path, endPoint)
	local tone = TONE_COLOR[WireToolLogic.LineTone(stretch.state)] or LINE_PICKED
	for i = 1, #path - 1 do
		local part = previewPart(i)
		if part then
			local a, b = path[i], path[i + 1]
			part.Size =
				Vector3.new(WireToolLogic.LineThickness, WireToolLogic.LineThickness, math.max((b - a).Magnitude, 0.1))
			part.CFrame = CFrame.lookAt((a + b) / 2, b)
			part.Color = tone
			part.Parent = folder
		end
	end
	for i = #path, #stretchLines do
		stretchLines[i].Parent = nil
	end
	refreshBar()
end

-- Buys the wire the stretch is short of (or a top-up): an intent the server checks.
local function buy()
	local plan = WireToolLogic.BuyPlan(stock(), stretch)
	if plan.amount <= 0 then
		HUD.Toast(WireSupply.Message("full"))
		return
	end
	Net.Remote("Wire"):FireServer("buy", plan.amount)
end

-- A piece was picked (or nothing, for the ground).
local function pick(uid: string?)
	local pieces, _, wires = mine()
	local previous = picked
	local nextPick, action = WireToolLogic.Tap(picked, uid, pieces)
	if action and action.op == "link" then
		local list = detailedWires(wires)
		local toId = blueprintOf(pieces, action.to)
		action.toPort = WireToolLogic.NextIn(list, action.to, toId or "")
		if not (reachOk(pieces, action.from) and reachOk(pieces, action.to)) then
			HUD.Toast(WireLogic.Message("reach") or "Stand closer to wire that.")
		else
			local ok, why = WireLogic.Check(
				list,
				pieces :: any,
				action.from,
				action.to,
				WireLogic.Port,
				action.toPort,
				WireSupply.MaxLength
			)
			if ok then
				-- The wire's length against the longest wire and the box (the server decides again).
				local result =
					WireToolLogic.Stretch(stock(), pieceOf(pieces, action.from), pieceOf(pieces, action.to), nil, bends)
				action.via = if #bends > 0 then table.clone(bends) else nil
				if result.state == "far" then
					HUD.Toast(WireSupply.Message("far"))
				elseif result.state == "short" then
					HUD.Toast(WireSupply.Message("short", stock(), result.units))
				else
					fire(action)
					lessonStep = WireToolLogic.Advance(lessonStep, "link")
				end
			else
				HUD.Toast(WireLogic.Message(why) or "")
			end
		end
	elseif nextPick ~= nil and nextPick ~= previous then
		local id = blueprintOf(pieces, nextPick)
		if WireLogic.IsSource(WireLogic.Role(if id then id else "")) then
			lessonStep = WireToolLogic.Advance(lessonStep, "source")
		end
	end
	if nextPick ~= previous or action ~= nil then
		bends = {}
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

-- A tap on bare ground with an output picked bends the run there (at most
-- WireSupply.MaxBends; a fifth is refused). True when the tap was a bend.
local function bendAt(x: number, y: number): boolean
	local plot = BlueprintPlacer.PlotCFrame()
	local pieces = mine()
	local from = pieceOf(pieces, picked)
	if not plot or not from or not WireLogic.IsSource(WireLogic.Role(from.blueprintId)) then
		return false
	end
	local ground = groundAt(x, y, worldPoint(plot, from).Y)
	if not ground then
		return false
	end
	local local3 = plot:PointToObjectSpace(ground)
	local added, why = WireToolLogic.AddBend(bends, local3.X, local3.Z)
	if added then
		bends = added
		updateStretch()
	else
		HUD.Toast(WireSupply.Message(why or "bends"))
	end
	return true
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
	local hit = WireToolLogic.NearestOnScreen(pieces, points, x, y)
	if hit == nil and bendAt(x, y) then
		return
	end
	pick(hit)
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
	local hit = WireToolLogic.Aim(mine(), eye.X, eye.Y, eye.Z, look.X, look.Y, look.Z)
	if hit == nil and bendAt(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2) then
		return
	end
	pick(hit)
end

---------------------------------------------------------------------------
-- Start and stop
---------------------------------------------------------------------------

function WireTool.Stop()
	if not active then
		return
	end
	active = false
	session += 1
	lessonStep = WireToolLogic.Advance(lessonStep, "done")
	picked = nil
	bends = {}
	stretch = WireToolLogic.Stretch(0, nil, nil, nil, nil)
	hideStretch()
	for _, conn in ipairs(conns) do
		conn:Disconnect()
	end
	table.clear(conns)
	for _, name in ipairs(ACTIONS) do
		ContextActionService:UnbindAction(name)
	end
	PromptSwitch.Release("wire")
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
	PromptSwitch.Hold("wire")
	session += 1
	local thisSession = session
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		-- Dying ends it. Putting the spool away (or taking another tool, which puts it
		-- away) ends it too: WireTool.SetSpool.
		table.insert(
			conns,
			humanoid.Died:Connect(function()
				WireTool.Stop()
			end)
		)
	end
	-- The stretched wire follows your aim a few times a second, only while it runs.
	task.spawn(function()
		while active and session == thisSession do
			updateStretch()
			task.wait(0.1)
		end
	end)
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
				lastTap = position
				pickAt(position.X, position.Y)
			end
		end)
	)
	local binds = InputKit.WireBinds
	local pickBind, cutBind, buyBind, doneBind = binds[1], binds[2], binds[3], binds[4]
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
		"WireBuy",
		action(buy),
		false,
		top,
		buyBind.gamepad,
		buyBind.keyboard :: Enum.KeyCode
	)
	ContextActionService:BindActionAtPriority(
		"WireDone",
		action(WireTool.PutAway),
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

-- BUILD mode (the hammer) on or off. The lines show while it is on; putting the
-- hammer away ends the tool unless the spool is in hand (taking the spool out
-- puts the hammer away, and that must not end the session it just started).
function WireTool.SetBuilding(on: boolean)
	building = on
	if not on and spool == nil then
		WireTool.Stop()
	end
	drawLines()
end

-- Puts the spool away (DONE, B, Q): ends the tool and drops the tool from your hand.
function WireTool.PutAway()
	WireTool.Stop()
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		humanoid:UnequipTools()
	end
end

-- The Wire spool came into your hand (a Tool) or went away (nil).
function WireTool.SetSpool(tool: Tool?)
	spool = tool
	if tool then
		WireTool.Begin(nil)
	else
		WireTool.Stop()
	end
end

local function watchCharacter(char: Model)
	local function consider(child: Instance)
		if child:IsA("Tool") and child:GetAttribute("WireSpool") == true then
			WireTool.SetSpool(child :: Tool)
		end
	end
	for _, child in ipairs(char:GetChildren()) do
		consider(child)
	end
	char.ChildAdded:Connect(consider)
	char.ChildRemoved:Connect(function(child: Instance)
		-- Unequipped (back in the Backpack) or gone.
		if child == spool and child.Parent ~= char then
			WireTool.SetSpool(nil)
		end
	end)
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
	b.label.Size = UDim2.fromOffset(if console then 560 else 340, if console then 52 else 58)
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
	local buyIt = UITheme.Button({
		text = "BUY",
		size = Vector2.new(150, PlotLogic.LandTap),
		style = "amber",
		textSize = if console then 18 else nil,
	})
	buyIt.root.LayoutOrder = 2
	buyIt.root.Parent = b.row
	buyIt.face.Activated:Connect(buy)
	buyButton = buyIt
	local done = UITheme.Button({
		text = "DONE",
		size = Vector2.new(98, PlotLogic.LandTap),
		style = "skip",
		textSize = if console then 18 else nil,
	})
	done.root.LayoutOrder = 3
	done.root.Parent = b.row
	done.face.Activated:Connect(WireTool.PutAway)
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
	LogicPanelUI.Start()
	-- The spool in hand starts the tool; putting it away ends it.
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
	-- Keep the lines in step with the wires the server reports.
	task.spawn(function()
		while true do
			task.wait(0.25)
			if building or active then
				drawLines()
			end
		end
	end)
	-- The box count changes when you buy and when a wire is placed.
	player:GetAttributeChangedSignal("WireUnits"):Connect(function()
		if active then
			refreshBar()
		end
	end)
end

return WireTool
