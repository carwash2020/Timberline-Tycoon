--!strict
-- PromptUI: ProximityPrompts in the game's look (UI spec 05), when
-- GameConfig.CustomPrompts is on. Every prompt in the world is switched to
-- the Custom style on this client, and drawn here instead:
--   * a bark card with the action ("Browse axes") and, under it, what it's
--     on ("TOOL SHED") in amber;
--   * a paper key cap with the key (E, F); on a gamepad, the pad's glyph;
--     on a touch screen an amber TAP, and the whole card is the button;
--   * holding fills the key cap amber from the bottom over HoldDuration.
-- The engine still decides when a prompt shows and handles keys and
-- buttons; touch and clicks go through InputHoldBegin / InputHoldEnd.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local UITheme = require(script.Parent.UITheme)

local PromptUI = {}

local C = UITheme.Colors
local F = UITheme.Fonts

local player = Players.LocalPlayer

local WIDTH, HEIGHT = 360, 72 -- the billboard; the card sits in its middle

local function keyName(key: Enum.KeyCode): string
	local names: { [string]: string } = { Return = "↵", Backspace = "⌫", Space = "␣" }
	return names[key.Name] or key.Name
end

local function adorneeOf(prompt: ProximityPrompt): Instance?
	local parent = prompt.Parent
	if parent and (parent:IsA("BasePart") or parent:IsA("Attachment")) then
		return parent
	elseif parent and parent:IsA("Model") then
		return parent.PrimaryPart
	end
	return nil
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	local adornee = adorneeOf(prompt)
	if not adornee then
		return
	end
	local touch = inputType == Enum.ProximityPromptInputType.Touch
	local gamepad = inputType == Enum.ProximityPromptInputType.Gamepad

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Prompt"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.Active = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(WIDTH, HEIGHT)
	billboard.SizeOffset = Vector2.new(prompt.UIOffset.X / WIDTH, prompt.UIOffset.Y / HEIGHT)
	billboard.ResetOnSpawn = false

	local card = UITheme.Card(C.Bark, C.Ink, 3, 14, true)
	card.outer.AnchorPoint = Vector2.new(0.5, 0.5)
	card.outer.Position = UDim2.fromScale(0.5, 0.5)
	UITheme.stroke(card.face, C.Ink, 2)
	UITheme.padding(card.face, 8, 18, 8, 8)
	local row = UITheme.list(card.face, 12, true)
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	UITheme.texture(card.face, "Wood", 14)
	card.outer.Parent = billboard

	-- The key cap (or TAP on a touch screen).
	local cap = UITheme.Card(if touch then C.Amber else C.Paper, if touch then C.AmberEdge else C.Muted, 3, 10)
	cap.outer.Name = "Key"
	cap.outer.LayoutOrder = 1
	cap.outer.Size = UDim2.fromOffset(40, 43)
	if touch then
		UITheme.corner(cap.outer, 20)
		UITheme.corner(cap.face, 20)
	end
	cap.face.ClipsDescendants = true
	cap.outer.Parent = card.face
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = C.Amber
	fill.BorderSizePixel = 0
	UITheme.corner(fill, 10)
	fill.Parent = cap.face
	if gamepad then
		local glyph = UITheme.Glyph(prompt.GamepadKeyCode, 30)
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.ZIndex = 2
		glyph.Parent = cap.face
	else
		local letter =
			UITheme.label(cap.face, if touch then "TAP" else keyName(prompt.KeyboardKeyCode), F.Heading, 22, C.Ink)
		letter.Size = UDim2.fromScale(1, 1)
		letter.TextXAlignment = Enum.TextXAlignment.Center
		letter.ZIndex = 2
		if touch then
			letter.Font = F.Black
			letter.TextSize = 14
		elseif #letter.Text > 1 then
			letter.TextScaled = true
		end
	end

	-- The words.
	local words = Instance.new("Frame")
	words.Name = "Words"
	words.LayoutOrder = 2
	words.AutomaticSize = Enum.AutomaticSize.XY
	words.BackgroundTransparency = 1
	UITheme.list(words, 3)
	words.Parent = card.face
	local action = UITheme.label(words, prompt.ActionText, F.Black, 16, C.Cream)
	action.LayoutOrder = 1
	action.Size = UDim2.new()
	action.AutomaticSize = Enum.AutomaticSize.XY
	local object = UITheme.label(words, string.upper(prompt.ObjectText), F.Black, 12, C.Amber)
	object.LayoutOrder = 2
	object.Size = UDim2.new()
	object.AutomaticSize = Enum.AutomaticSize.XY
	object.Visible = prompt.ObjectText ~= ""

	local conns: { RBXScriptConnection } = {}
	local function on(signal: RBXScriptSignal, fn: (...any) -> ())
		table.insert(conns, signal:Connect(fn))
	end
	on(prompt:GetPropertyChangedSignal("ActionText"), function()
		action.Text = prompt.ActionText
	end)
	on(prompt:GetPropertyChangedSignal("ObjectText"), function()
		object.Text = string.upper(prompt.ObjectText)
		object.Visible = prompt.ObjectText ~= ""
	end)

	-- Holding: the cap fills from the bottom and sinks onto its edge.
	local holding: Tween? = nil
	local function setHeld(held: boolean)
		if holding then
			holding:Cancel()
			holding = nil
		end
		if held then
			cap.outer.BackgroundColor3 = C.AmberEdge
			cap.face.Position = UDim2.fromOffset(0, 2)
			local tween = TweenService:Create(
				fill,
				TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear),
				{ Size = UDim2.fromScale(1, 1) }
			)
			tween:Play()
			holding = tween
		else
			cap.outer.BackgroundColor3 = if touch then C.AmberEdge else C.Muted
			cap.face.Position = UDim2.fromOffset(0, 0)
			fill.Size = UDim2.fromScale(1, 0)
		end
	end
	on(prompt.PromptButtonHoldBegan, function()
		if prompt.HoldDuration > 0 then
			setHeld(true)
		end
	end)
	on(prompt.PromptButtonHoldEnded, function()
		setHeld(false)
	end)
	on(prompt.Triggered, function()
		setHeld(false)
	end)

	-- Touch (and clicks, if the prompt allows them): the card is the button.
	if touch or prompt.ClickablePrompt then
		local button = Instance.new("TextButton")
		button.Name = "Press"
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.ZIndex = 5
		button.Parent = card.outer
		on(button.InputBegan, function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldBegin()
			end
		end)
		on(button.InputEnded, function(input: InputObject)
			local t = input.UserInputType
			if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldEnd()
			end
		end)
	end

	billboard.Parent = player:WaitForChild("PlayerGui")

	local gone = false
	local function cleanup()
		if gone then
			return
		end
		gone = true
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		billboard:Destroy()
	end
	table.insert(conns, prompt.PromptHidden:Once(cleanup))
	table.insert(conns, prompt.Destroying:Once(cleanup))
end

local function restyle(inst: Instance)
	if inst:IsA("ProximityPrompt") then
		inst.Style = Enum.ProximityPromptStyle.Custom
	end
end

function PromptUI.Start()
	if not GameConfig.CustomPrompts then
		return
	end
	for _, inst in ipairs(workspace:GetDescendants()) do
		restyle(inst)
	end
	workspace.DescendantAdded:Connect(restyle)
	ProximityPromptService.PromptShown:Connect(
		function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
			if prompt.Style == Enum.ProximityPromptStyle.Custom then
				show(prompt, inputType)
			end
		end
	)
end

return PromptUI
