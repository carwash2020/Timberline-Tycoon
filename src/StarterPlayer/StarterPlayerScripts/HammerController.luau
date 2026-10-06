--!strict
-- HammerController: the hammer and the rolled plans in your hands
-- (BUILD_SYSTEM.md; the decisions are in Shared/HammerLogic, the server side
-- in ServerScriptService/BlueprintService).
--   * Every player has a Hammer Tool (BlueprintService hands it over).
--     Using it, with a mouse click, RT or a tap (Tool.Activated, so there is
--     no per-device input code and no new key), does what HammerLogic.Use
--     says: open the blueprint list (PlotUI draws it), open the sheet of the
--     piece you aimed at (Move, Turn, Sell), or hand an unfilled kit ghost to
--     the BuilderTools bar. While a ghost is out or a panel is up it does
--     nothing: the click places the ghost.
--   * A rolled plan Tool, used, tells the server (UseBlueprint). The server
--     consumes it and teaches the building for good.
--   * Placing a piece swings the hammer (the grip tips back and strikes,
--     HammerLogic.Swing), knocks (a sound) and puffs dust. Other players
--     near the piece hear and see the knock through WorldFX "Hammer"; only
--     the swing of the arm is local.
--   * Nothing here decides anything: the server checks every place, move
--     and sale again.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local EditLogic = require(ReplicatedStorage.Shared.EditLogic)
local HammerArt = require(ReplicatedStorage.Shared.Art.HammerArt)
local HammerLogic = require(ReplicatedStorage.Shared.HammerLogic)
local Net = require(ReplicatedStorage.Shared.Net)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local BlueprintPlacer = require(script.Parent.BlueprintPlacer)
local BuilderTools = require(script.Parent.BuilderTools)
local HUD = require(script.Parent.HUD)
local Quality = require(script.Parent.Quality)
local ShopUI = require(script.Parent.ShopUI)

local HammerController = {}

local player = Players.LocalPlayer

local WOOD = Color3.fromHex("#8C6A45")
local USE_COOLDOWN = 0.4 -- seconds between uses of one plan (the server limits it too)

local held: Tool? = nil
local heldListeners: { (boolean) -> () } = {}
local opener: (() -> ())? = nil
local panelCheck: (() -> boolean)? = nil
local lastTap: Vector2? = nil -- where the last touch landed in the world
local swinging = false
local bound: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local lastPlanUse = -math.huge

---------------------------------------------------------------------------
-- Is the hammer in hand?
---------------------------------------------------------------------------

local function isHammer(tool: Instance): boolean
	return tool:IsA("Tool") and tool:GetAttribute("Hammer") == true
end

local function setHeld(tool: Tool?)
	local before = held ~= nil
	held = tool
	local after = tool ~= nil
	if before ~= after then
		for _, fn in ipairs(heldListeners) do
			fn(after)
		end
	end
end

function HammerController.Held(): boolean
	return held ~= nil
end

-- `fn(on)` runs when the hammer comes into your hand or goes away.
function HammerController.OnHeldChanged(fn: (boolean) -> ())
	table.insert(heldListeners, fn)
end

-- What a use opens when nothing is aimed at: PlotUI's blueprint list.
function HammerController.SetOpener(fn: () -> ())
	opener = fn
end

-- A panel besides the shop screen that should keep the click to itself
-- (the Land panel).
function HammerController.SetPanelCheck(fn: () -> boolean)
	panelCheck = fn
end

local function humanoid(): Humanoid?
	local char = player.Character
	return if char then char:FindFirstChildOfClass("Humanoid") else nil
end

local function hammerTool(): Tool?
	local char = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, container in ipairs({ char, backpack }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if isHammer(child) then
					return child :: Tool
				end
			end
		end
	end
	return nil
end

-- Takes the hammer out (the HAMMER button on a phone).
function HammerController.Equip()
	local h = humanoid()
	local tool = hammerTool()
	if h and tool and held == nil then
		h:EquipTool(tool)
	end
end

function HammerController.PutAway()
	local h = humanoid()
	if h then
		h:UnequipTools()
	end
end

---------------------------------------------------------------------------
-- The knock: sound and dust
---------------------------------------------------------------------------

local function dustAt(pos: Vector3)
	local part = Instance.new("Part")
	part.Name = "HammerDust"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.4, 0.4, 0.4)
	part.Position = pos + Vector3.new(0, 0.4, 0)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.45, 0.9)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(75, 75)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, -5, 0)
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 180, 144))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1.6),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = part
	part.Parent = workspace
	emitter:Emit(HammerLogic.DustCount(Quality.Budget().ChipCount))
	Debris:AddItem(part, 2)
end

-- The dust, as a field so a test can watch it without a world to put it in.
HammerController.Dust = dustAt

-- Sound and dust where a piece went down.
function HammerController.Knock(pos: Vector3)
	SoundData.PlayAt("HammerKnock", pos)
	HammerController.Dust(pos)
end

---------------------------------------------------------------------------
-- The swing (local: a Tool's grip is the one thing a client can pose)
---------------------------------------------------------------------------

-- Swings the hammer in hand and knocks at `at` on the strike (or at the
-- face of the hammer when no spot is given). With no hammer in hand it only
-- knocks.
function HammerController.Swing(at: Vector3?)
	local tool = held
	if not tool or swinging then
		if at then
			HammerController.Knock(at)
		end
		return
	end
	swinging = true
	local started = os.clock()
	local knocked = false
	local conn: RBXScriptConnection? = nil
	local function finish()
		swinging = false
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if tool.Parent then
			tool.Grip = HammerArt.Grip()
		end
	end
	conn = RunService.RenderStepped:Connect(function()
		if not tool.Parent then
			finish()
			return
		end
		local u = (os.clock() - started) / HammerLogic.SwingSeconds
		if not knocked and u >= HammerLogic.ImpactAt then
			knocked = true
			local spot = at
			if not spot then
				local handle = tool:FindFirstChild("Handle")
				spot = if handle and handle:IsA("BasePart")
					then (handle.CFrame * CFrame.new(HammerArt.StrikePoint)).Position
					else nil
			end
			if spot then
				HammerController.Knock(spot)
			end
		end
		if u >= 1 then
			finish()
			return
		end
		tool.Grip = HammerArt.Grip(HammerLogic.Swing(u))
	end)
end

---------------------------------------------------------------------------
-- Aiming and the piece sheet
---------------------------------------------------------------------------

local function screenCenter(): Vector2
	local camera = workspace.CurrentCamera
	return if camera then camera.ViewportSize / 2 else Vector2.zero
end

-- Where the use is aimed on screen: the mouse, the last tap, or the crosshair.
local function aimPoint(): Vector2
	local last = UserInputService:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return lastTap or screenCenter()
	elseif string.find(last.Name, "Gamepad") then
		return screenCenter()
	end
	return UserInputService:GetMouseLocation()
end

local function aimedPiece(): Model?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local at = aimPoint()
	return BuilderTools.Aim(camera, at.X, at.Y)
end

local function hitOf(model: Model?): HammerLogic.Hit?
	if not model then
		return nil
	end
	return {
		mine = model:GetAttribute("OwnerId") == player.UserId,
		ghost = model:GetAttribute("Kit") == true and model:GetAttribute("FillUnits") == 0,
	}
end

local function placedItem(uid: string): PlotLogic.Placed?
	for _, item in ipairs(BlueprintPlacer.MyPlaced()) do
		if item.uid == uid then
			return item
		end
	end
	return nil
end

local function worldSpot(item: PlotLogic.Placed): Vector3?
	local plot = BlueprintPlacer.PlotCFrame()
	return if plot then plot:PointToWorldSpace(Vector3.new(item.x, item.y or 0, item.z)) else nil
end

local function tier(): number
	return (player:GetAttribute("PlotTier") :: number?) or 1
end

-- Turn it a quarter where it stands (a free move with the next rot). Checked
-- here like BuilderTools does, and again by the server.
local function turn(bp: PlotData.Blueprint, item: PlotLogic.Placed)
	local rot = HammerLogic.Turn(item.rot)
	local shaped = EditLogic.Shape(bp, item)
	local ok, why = PlotLogic.Check(
		shaped,
		item.x,
		item.z,
		rot,
		tier(),
		BlueprintPlacer.MyPlaced(),
		item.uid,
		item.y or 0,
		BlueprintPlacer.MySquares()
	)
	if not ok then
		HUD.Toast((why or "Something's in the way") .. ".")
		return
	end
	Net.Remote("MoveBlueprint"):FireServer(item.uid, item.x, item.z, rot, item.y or 0)
	HammerController.Swing(worldSpot(item))
end

local function openSheet(model: Model)
	local uid = model:GetAttribute("Uid")
	local id = model:GetAttribute("BlueprintId")
	if type(uid) ~= "string" or type(id) ~= "string" then
		return
	end
	local bp = PlotLogic.Blueprint(id)
	local item = placedItem(uid)
	if not bp or not item then
		return
	end
	local function current(): PlotLogic.Placed
		return placedItem(uid) or item :: PlotLogic.Placed
	end
	local function action(actionId: string): HammerLogic.Action
		for _, a in ipairs(HammerLogic.PieceActions(bp, current())) do
			if a.id == actionId then
				return a
			end
		end
		return { id = actionId, label = actionId, enabled = false, why = nil }
	end
	local details: { [string]: string } = {
		move = "Pick it up and set it down somewhere else. Free.",
		turn = "A quarter turn where it stands. Free.",
		sell = "Take it off your plot for what it gives back.",
	}
	local shop: ShopUI.Shop = {
		building = nil,
		promptText = "",
		title = bp.displayName,
		subtitle = "Your hammer",
		ids = function()
			return { "move", "turn", "sell" }
		end,
		view = function(actionId: string): ShopUI.RowView
			local a = action(actionId)
			local ready = a.enabled
			return {
				name = a.label,
				detail = if ready or not a.why then details[actionId] or "" else a.why,
				color = WOOD,
				dim = not ready,
				button = if actionId == "sell" then "Sell" elseif actionId == "turn" then "Turn" else "Move",
				state = if not ready then "locked" elseif actionId == "sell" then "bark" else "buy",
				onClick = function()
					local now = action(actionId)
					if not now.enabled then
						HUD.Toast(now.why or "You can't do that to it.")
						return
					end
					ShopUI.Close()
					local live = current()
					if actionId == "move" then
						BlueprintPlacer.Begin(bp, { moveUid = uid })
					elseif actionId == "turn" then
						turn(bp, live)
					else
						Net.Remote("SellPlaced"):FireServer(uid)
						HammerController.Swing(worldSpot(live))
					end
				end,
			}
		end,
	}
	ShopUI.OpenCustom(shop)
end

---------------------------------------------------------------------------
-- A use of the hammer
---------------------------------------------------------------------------

function HammerController.Use()
	local model = aimedPiece()
	local panelOpen = ShopUI.IsOpen() or (panelCheck ~= nil and panelCheck())
	local result = HammerLogic.Use({
		placing = BlueprintPlacer.Active(),
		panelOpen = panelOpen,
		hit = hitOf(model),
	})
	if result == "plans" then
		local open = opener
		if open then
			open()
		end
	elseif result == "piece" and model then
		openSheet(model)
	elseif result == "kit" and model then
		-- A click or a tap already reached BuilderTools (it listens for those);
		-- RT does not, because it only listens with empty hands.
		if string.find(UserInputService:GetLastInputType().Name, "Gamepad") then
			BuilderTools.SelectModel(model)
		end
	end
end

---------------------------------------------------------------------------
-- Tools
---------------------------------------------------------------------------

local function bindTool(tool: Tool)
	if bound[tool] then
		return
	end
	if isHammer(tool) then
		bound[tool] = true
		tool.Activated:Connect(function()
			-- A tap's position is recorded by TouchTapInWorld; let it land first.
			task.defer(HammerController.Use)
		end)
		return
	end
	local uid = tool:GetAttribute("BlueprintUid")
	if type(uid) == "string" then
		bound[tool] = true
		tool.Activated:Connect(function()
			if os.clock() - lastPlanUse < USE_COOLDOWN then
				return
			end
			lastPlanUse = os.clock()
			Net.Remote("UseBlueprint"):FireServer(uid)
		end)
	end
end

local function watchContainer(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			bindTool(child)
		end
	end
	container.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			bindTool(child)
		end
	end)
end

local function watchCharacter(char: Model)
	setHeld(nil)
	for _, child in ipairs(char:GetChildren()) do
		if isHammer(child) then
			setHeld(child :: Tool)
		end
	end
	watchContainer(char)
	char.ChildAdded:Connect(function(child: Instance)
		if isHammer(child) then
			setHeld(child :: Tool)
		end
	end)
	char.ChildRemoved:Connect(function(child: Instance)
		-- Unequipped (now in the Backpack) or destroyed.
		if child == held and child.Parent ~= char then
			setHeld(nil)
		end
	end)
end

function HammerController.Start()
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
	player.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Backpack") then
			watchContainer(child)
		end
	end)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		watchContainer(backpack)
	end
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, _processedByUI: boolean)
		lastTap = position
	end)
	-- Other players' knocks.
	Net.Remote("WorldFX").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		if kind ~= "Hammer" or type(payload) ~= "table" then
			return
		end
		local pos = (payload :: { [string]: unknown }).pos
		if typeof(pos) == "Vector3" then
			HammerController.Knock(pos)
		end
	end)
	-- Placing a ghost swings the hammer at the spot.
	BlueprintPlacer.OnPlaced(function(pos: Vector3)
		HammerController.Swing(pos)
	end)
end

-- For tests and the HUD: the swing is on (so a second is ignored).
function HammerController.Swinging(): boolean
	return swinging
end

return HammerController
