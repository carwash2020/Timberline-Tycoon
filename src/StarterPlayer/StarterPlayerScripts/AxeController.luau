--!strict
-- AxeController: dropping axes.
-- Every axe you own is in your hotbar; switch with the number keys or by
-- tapping it. A "Drop axe" side button shows while you hold an axe and
-- either carry another one or hold one better than the starter
-- (HudRules.DropAxe), so a new player with just the Rusty Axe never sees
-- it. Dropping takes two presses (HudRules.DropPress): the first turns the
-- button amber, "Confirm drop", for 3 seconds, and a second press in that
-- time drops the axe. The same goes for every way to press it: a tap, a
-- click, D-pad down on a gamepad (when no prompt is using it) and
-- Backspace on a keyboard. The server lays it on the ground, where a "Pick
-- up" prompt brings it back, and refuses to drop your last axe. Dropped
-- axes stay yours (AxeService). The same button drops a rolled plan you are
-- holding ("Drop plan", the DropBlueprint remote, BlueprintService): a plan
-- is an item like an axe, so it goes the same way, two presses, and stays
-- yours.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local HUD = require(script.Parent.HUD)
local HudRules = require(script.Parent.HudRules)
local UITheme = require(script.Parent.UITheme)

local AxeController = {}

local player = Players.LocalPlayer

local LABEL = "Drop axe"
local PLAN_LABEL = "Drop plan"
local CONFIRM_LABEL = "Confirm drop"
local STYLE = "bark"
local CONFIRM_STYLE = "amber"

local button: UITheme.Button? = nil
local armedAt: number? = nil -- when the press waiting for a second one was made
local armedUid: string? = nil -- and for which axe
local armToken = 0 -- bumped whenever the wait starts or ends

local function heldAxe(): Tool?
	local char = player.Character
	local tool = if char then char:FindFirstChildOfClass("Tool") else nil
	return if tool and type(tool:GetAttribute("AxeUid")) == "string" then tool else nil
end

-- A rolled plan in hand (BlueprintService's Tool).
local function heldPlan(): Tool?
	local char = player.Character
	local tool = if char then char:FindFirstChildOfClass("Tool") else nil
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

-- Whether "Drop axe" applies right now (HudRules.DropAxe): the axe in hand,
-- counted with the others in the Backpack.
local function canDrop(tool: Tool?): boolean
	local id = if tool then tool:GetAttribute("AxeId") else nil
	local carried = axesIn(player.Character) + axesIn(player:FindFirstChildOfClass("Backpack"))
	return HudRules.DropAxe(carried, if type(id) == "string" then id else nil)
end

local function disarm()
	armedAt, armedUid = nil, nil
	armToken += 1
	local b = button
	if b then
		b:SetText(if heldPlan() then PLAN_LABEL else LABEL)
		b:SetStyle(STYLE)
	end
end

-- One press, from any input: the first one waits for a second, which drops.
local function press()
	local plan = heldPlan()
	local tool = plan or heldAxe()
	local uid = if plan then plan:GetAttribute("BlueprintUid") elseif tool then tool:GetAttribute("AxeUid") else nil
	if not tool or type(uid) ~= "string" or (not plan and not canDrop(tool)) then
		disarm()
		return
	end
	local waiting = if armedUid == uid then armedAt else nil
	local drop, at = HudRules.DropPress(waiting, os.clock())
	if drop then
		disarm()
		Net.Remote(if plan then "DropBlueprint" else "DropAxe"):FireServer(uid)
	elseif at ~= waiting then
		-- A new wait: say so on the button, and give up after a while.
		armedAt, armedUid = at, uid
		armToken += 1
		local token = armToken
		local b = button
		if b then
			b:SetText(CONFIRM_LABEL)
			b:SetStyle(CONFIRM_STYLE)
		end
		task.delay(HudRules.DropConfirmSeconds, function()
			if armToken == token then
				disarm()
			end
		end)
	end
end

local function refresh()
	local plan = heldPlan()
	local tool = plan or heldAxe()
	local shown = plan ~= nil or canDrop(tool)
	local b = button
	if b then
		b.root.Visible = shown
		if armedUid == nil then
			b:SetText(if plan then PLAN_LABEL else LABEL)
		end
	end
	-- Switching items (or putting it away) ends a wait for the old one.
	local heldUid = if plan then plan:GetAttribute("BlueprintUid") elseif tool then tool:GetAttribute("AxeUid") else nil
	if armedUid ~= nil and (not shown or not tool or heldUid ~= armedUid) then
		disarm()
	end
end

local function watchContainer(container: Instance)
	container.ChildAdded:Connect(refresh)
	container.ChildRemoved:Connect(refresh)
	refresh()
end

function AxeController.Start()
	button = HUD.SideButton({
		name = "DropAxe",
		text = LABEL,
		style = STYLE,
		order = 3,
		key = Enum.KeyCode.DPadDown, -- not X: that's the pad's interact button
		onPress = press,
	})

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.Backspace then
			press()
		end
	end)
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
