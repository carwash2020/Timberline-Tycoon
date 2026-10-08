--!strict
-- AxeController: dropping axes (and rolled plans).
-- Every axe you own is in your hotbar; switch with the number keys or by
-- tapping it. There is no Drop button on screen (DropControls has the
-- rules): on a gamepad it is B, on a keyboard Q (Backspace too), and on a
-- phone a long press on the hotbar strip. It applies while you hold an axe
-- and either carry another one or hold one better than the starter
-- (HudRules.DropAxe), so a new player with just the Rusty Axe can't drop
-- it, or while you hold a rolled plan (BlueprintService's Tool).
-- Dropping takes two presses (HudRules.DropPress): the first says "Press B
-- again to drop the Steel Axe" in a toast, and a second press 0.3 to 3
-- seconds later drops it. The server lays it on the ground, where a "Pick
-- up" prompt brings it back, and refuses to drop your last axe. Dropped
-- axes stay yours (AxeService); a plan goes the same way
-- (DropBlueprint, BlueprintService).
--
-- B is back everywhere else (menus, dialogue, the placer, the wiring tool,
-- a held piece, a seat), so the drop is a ContextActionService action
-- below all of them (DropControls.Priority): whatever is open has sunk the
-- press before it gets here, and DropControls.Decide checks again that
-- nothing is open, so one press is never a close and a drop.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DropControls = require(ReplicatedStorage.Shared.DropControls)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local BlueprintPlacer = require(script.Parent.BlueprintPlacer)
local DialogueUI = require(script.Parent.DialogueUI)
local DragController = require(script.Parent.DragController)
local HUD = require(script.Parent.HUD)
local HudRules = require(script.Parent.HudRules)
local UITheme = require(script.Parent.UITheme)
local WireTool = require(script.Parent.WireTool)

local AxeController = {}

local player = Players.LocalPlayer

local ACTION = "DropHeld"

local armedAt: number? = nil -- when the press waiting for a second one was made
local armedUid: string? = nil -- and for which item
local armToken = 0 -- bumped whenever the wait starts or ends
local hintShown = false -- the "how to drop it" line is said once a session
-- What was in hand a moment ago (a phone's long press toggles the slot, so
-- the first of the two presses puts the item away).
local recent: { tool: Tool, plan: boolean, at: number }? = nil

local function heldTool(): Tool?
	local char = player.Character
	return if char then char:FindFirstChildOfClass("Tool") else nil
end

local function heldAxe(): Tool?
	local tool = heldTool()
	return if tool and type(tool:GetAttribute("AxeUid")) == "string" then tool else nil
end

-- A rolled plan in hand (BlueprintService's Tool).
local function heldPlan(): Tool?
	local tool = heldTool()
	return if tool and type(tool:GetAttribute("BlueprintUid")) == "string" then tool else nil
end

local function axesIn(container: Instance?): number
	local n = 0
	if container then
		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and type(child:GetAttribute("AxeUid")) == "string" then
				n += 1
			end
		end
	end
	return n
end

-- Whether the axe may be dropped right now (HudRules.DropAxe): the axe in
-- hand, counted with the others in the Backpack.
local function canDrop(tool: Tool?): boolean
	local id = if tool then tool:GetAttribute("AxeId") else nil
	local carried = axesIn(player.Character) + axesIn(player:FindFirstChildOfClass("Backpack"))
	return HudRules.DropAxe(carried, if type(id) == "string" then id else nil)
end

local function disarm()
	armedAt, armedUid = nil, nil
	armToken += 1
end

-- The item a press would drop: a plan in hand, else an axe that may go;
-- nil with nothing to drop. `phone` also takes what a long press just put
-- away (DropControls.RecentSeconds).
local function target(phone: boolean): (Tool?, boolean)
	local plan = heldPlan()
	if plan then
		return plan, true
	end
	local axe = heldAxe()
	if axe and canDrop(axe) then
		return axe, false
	end
	local last = recent
	if phone and last and os.clock() - last.at <= DropControls.RecentSeconds then
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack and last.tool.Parent == backpack and (last.plan or canDrop(last.tool)) then
			return last.tool, last.plan
		end
	end
	return nil, false
end

local function nameOf(tool: Tool, plan: boolean): string
	if plan then
		return "plan"
	end
	local id = tool:GetAttribute("AxeId")
	local def = if type(id) == "string" then ItemCatalog.GetAxe(id) else nil
	return if def then def.displayName else "axe"
end

-- What is going on that could own the press (DropControls.State).
local function stateOf(holding: boolean): DropControls.State
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return {
		holding = holding,
		typing = UserInputService:GetFocusedTextBox() ~= nil,
		menu = GuiService.SelectedObject ~= nil
			or GuiService.SelectedCoreObject ~= nil
			or GuiService.MenuIsOpen
			or UserInputService.ModalEnabled
			or HUD.Overlay(),
		dialogue = DialogueUI.IsOpen(),
		placing = BlueprintPlacer.Active() or WireTool.Active(),
		grabbing = DragController.Holding(),
		seated = humanoid ~= nil and humanoid.SeatPart ~= nil,
	}
end

-- One press, from any input: the first one waits for a second, which drops.
local function press(device: DropControls.Device)
	local tool, plan = target(device == "phone")
	local uid = if not tool then nil elseif plan then tool:GetAttribute("BlueprintUid") else tool:GetAttribute("AxeUid")
	if not tool or type(uid) ~= "string" then
		disarm()
		return
	end
	local waiting = if armedUid == uid then armedAt else nil
	local drop, at = HudRules.DropPress(waiting, os.clock())
	if drop then
		disarm()
		Net.Remote(if plan then "DropBlueprint" else "DropAxe"):FireServer(uid)
	elseif at ~= waiting then
		-- A new wait: say so, and give up after a while.
		armedAt, armedUid = at, uid
		armToken += 1
		local token = armToken
		HUD.Toast(DropControls.Confirm(device, nameOf(tool, plan)), HudRules.DropConfirmSeconds)
		task.delay(HudRules.DropConfirmSeconds, function()
			if armToken == token then
				disarm()
			end
		end)
	end
end

-- B, Q or Backspace. Sunk only when it is the drop's (DropControls.Decide);
-- otherwise it goes on to whatever else wants it.
local function onKey(_name: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local tool = target(false)
	if DropControls.Decide(input.KeyCode, stateOf(tool ~= nil)) ~= "drop" then
		return Enum.ContextActionResult.Pass
	end
	local device = DropControls.DeviceOf(input.KeyCode)
	if device then
		press(device :: DropControls.Device)
	end
	return Enum.ContextActionResult.Sink
end

-- A long press on a phone's hotbar strip.
local function onLongPress(positions: { Vector2 }, state: Enum.UserInputState)
	local at = positions[1]
	local camera = workspace.CurrentCamera
	if state ~= Enum.UserInputState.Begin or not at or not camera then
		return
	end
	local size = camera.ViewportSize
	local tool = target(true)
	if DropControls.TouchDrops(at.X, at.Y, size.X, size.Y, stateOf(tool ~= nil)) then
		press("phone")
	end
end

-- Remembers what is in hand, and tells you once how to drop it.
local function refresh()
	local plan = heldPlan()
	local tool = plan or heldAxe()
	if tool and (plan ~= nil or canDrop(tool)) then
		recent = { tool = tool, plan = plan ~= nil, at = os.clock() }
		if not hintShown then
			hintShown = true
			HUD.Toast(DropControls.Hint(UITheme.Device()), nil, { key = "DropHint", once = true })
		end
	end
	-- Switching to something else ends a wait for the old item. A phone's
	-- first long press puts the item away itself and the second follows
	-- within the wait, so the wait stays there.
	local heldUid = if plan then plan:GetAttribute("BlueprintUid") elseif tool then tool:GetAttribute("AxeUid") else nil
	if armedUid ~= nil and heldTool() ~= nil and heldUid ~= armedUid then
		disarm()
	end
end

local function watchContainer(container: Instance)
	container.ChildAdded:Connect(refresh)
	container.ChildRemoved:Connect(refresh)
	refresh()
end

function AxeController.Start()
	ContextActionService:BindActionAtPriority(
		ACTION,
		onKey,
		false,
		DropControls.Priority,
		DropControls.PadKey,
		table.unpack(DropControls.KeyboardKeys)
	)
	UserInputService.TouchLongPress:Connect(onLongPress)
	-- The axe in hand (the character) and the others (the Backpack, a new
	-- one each spawn).
	player.CharacterAdded:Connect(watchContainer)
	if player.Character then
		watchContainer(player.Character)
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
end

return AxeController
