--!strict
-- QuestUI: Murph's tutorial, client side (steps in Shared/TutorialData).
--   * Tracker, on the left: the current objective with progress, and Skip
--     (tap twice).
--   * Murph's card under it: what he says when a step starts. "Talk" at
--     Murph (by the spawn) says it again.
--   * A beacon: a bouncing arrow over what to do next (the nearest tree or
--     log, your truck, the sell pad, the Tool Shed), with its distance.
-- The server owns progress: it sets the TutorialStep (0 = done) and
-- TutorialProgress attributes, and this redraws from them.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local TutorialData = require(ReplicatedStorage.Shared.TutorialData)

type Step = TutorialData.Step

local QuestUI = {}

local player = Players.LocalPlayer

local INK = Color3.fromRGB(60, 40, 20)
local CREAM = Color3.fromRGB(245, 235, 215)
local PAPER = Color3.fromRGB(240, 225, 195)
local BARK = Color3.fromRGB(88, 58, 34)
local AMBER = Color3.fromRGB(255, 184, 64)

local SPEECH_SECONDS = 12
local BEACON_REFRESH = 0.5

local tracker: Frame? = nil
local objectiveLabel: TextLabel? = nil
local stepLabel: TextLabel? = nil
local speech: GuiObject? = nil
local speechLabel: TextLabel? = nil
local beacon: BillboardGui? = nil
local distanceLabel: TextLabel? = nil
local speechToken = 0
local lastStep = -1
local skipped = false -- this player pressed Skip: no farewell speech

local function corner(parent: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function padding(parent: GuiObject, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.Parent = parent
end

local function text(parent: Instance, content: string, size: number, font: Enum.Font, order: number): TextLabel
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.fromScale(1, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = INK
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = content
	l.Parent = parent
	return l
end

local function currentStep(): (number, Step?)
	local index = (player:GetAttribute("TutorialStep") :: number?) or 0
	return index, TutorialData.Steps[index]
end

-- Shows one of Murph's lines for a while.
local function say(line: string)
	local card, label = speech, speechLabel
	if not card or not label then
		return
	end
	label.Text = line
	card.Visible = true
	speechToken += 1
	local token = speechToken
	task.delay(SPEECH_SECONDS, function()
		if speechToken == token then
			card.Visible = false
		end
	end)
end

---------------------------------------------------------------------------
-- Beacon
---------------------------------------------------------------------------

local function rootPosition(): Vector3?
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	return if hrp then hrp.Position else nil
end

local function nearestTagged(tag: string, from: Vector3, accept: (Model, BasePart) -> boolean): BasePart?
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		local pp = if inst:IsA("Model") then inst.PrimaryPart else nil
		if pp and accept(inst :: Model, pp) then
			local d = (pp.Position - from).Magnitude
			if d < bestDist then
				best, bestDist = pp, d
			end
		end
	end
	return best
end

local function findPart(path: { string }): BasePart?
	local node: Instance? = workspace:FindFirstChild("TimberlineMap")
	for _, name in ipairs(path) do
		node = if node then node:FindFirstChild(name) else nil
	end
	return if node and node:IsA("BasePart") then node else nil
end

-- The part the beacon should hang over for this step, if it's around.
local function beaconTarget(step: Step, from: Vector3): BasePart?
	local target = step.beacon
	if target == "tree" then
		return nearestTagged("Tree", from, function(model)
			return ((model:GetAttribute("HP") :: number?) or 0) > 0
		end)
	elseif target == "log" then
		-- Logs lying in the world have a "Pick up" prompt; carried ones don't.
		return nearestTagged("Log", from, function(_model, pp)
			return pp:FindFirstChildOfClass("ProximityPrompt") ~= nil
		end)
	elseif target == "truck" then
		return nearestTagged("Truck", from, function(model)
			return model:GetAttribute("OwnerId") == player.UserId
		end)
	elseif target == "sellPad" then
		return findPart({ "SellArea", "SellPad" })
	elseif target == "toolShed" then
		return findPart({ "ToolShed", "Counter" })
	end
	return nil
end

local function updateBeacon()
	local gui = beacon
	if not gui then
		return
	end
	local _, step = currentStep()
	local from = rootPosition()
	local target = if step and from then beaconTarget(step, from) else nil
	gui.Enabled = target ~= nil
	if target then
		gui.Adornee = target
	end
	local label = distanceLabel
	if target and from and label then
		local d = (target.Position - from).Magnitude
		label.Text = string.format("%d studs", math.floor(d + 0.5))
		label.Visible = d > 25
	end
end

---------------------------------------------------------------------------
-- Tracker
---------------------------------------------------------------------------

local function refresh()
	local index, step = currentStep()
	local frame = tracker
	if frame then
		frame.Visible = step ~= nil
	end
	if step then
		local progress = (player:GetAttribute("TutorialProgress") :: number?) or 0
		if objectiveLabel then
			objectiveLabel.Text = TutorialData.ObjectiveText(step, progress)
		end
		if stepLabel then
			stepLabel.Text = string.format("MURPH'S TUTORIAL · %d/%d", index, #TutorialData.Steps)
		end
	end
	-- A new step: Murph says his line. (Also on join, as a reminder.)
	if index ~= lastStep then
		if step then
			say(step.murph)
		elseif lastStep > 0 and not skipped then
			say(TutorialData.Farewell)
		end
		lastStep = index
	end
	updateBeacon()
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "QuestUI"
	gui.ResetOnSpawn = false

	local column = Instance.new("Frame")
	column.Name = "Column"
	-- Left edge, a third of the way down: under Roblox's chat window (top
	-- left) and above a phone's thumbstick.
	column.Position = UDim2.new(0, 12, 0.3, 0)
	column.Size = UDim2.fromOffset(280, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.BackgroundTransparency = 1
	column.Parent = gui
	local columnList = Instance.new("UIListLayout")
	columnList.SortOrder = Enum.SortOrder.LayoutOrder
	columnList.Padding = UDim.new(0, 6)
	columnList.Parent = column
	local maxWidth = Instance.new("UISizeConstraint") -- narrow phones
	maxWidth.MaxSize = Vector2.new(280, math.huge)
	maxWidth.Parent = column

	-- Tracker card.
	local card = Instance.new("Frame")
	card.Name = "Tracker"
	card.LayoutOrder = 1
	card.Size = UDim2.fromScale(1, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = PAPER
	card.BackgroundTransparency = 0.05
	card.Visible = false
	corner(card, 10)
	padding(card, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = BARK
	stroke.Thickness = 2
	stroke.Parent = card
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = card
	card.Parent = column
	tracker = card

	local header = text(card, "", 12, Enum.Font.GothamBold, 1)
	header.TextColor3 = BARK
	stepLabel = header
	objectiveLabel = text(card, "", 17, Enum.Font.GothamMedium, 2)

	local skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.LayoutOrder = 3
	skip.Size = UDim2.fromOffset(120, 26)
	skip.BackgroundColor3 = BARK
	skip.BackgroundTransparency = 0.2
	skip.Font = Enum.Font.Gotham
	skip.TextSize = 13
	skip.TextColor3 = CREAM
	skip.Text = "Skip tutorial"
	corner(skip, 6)
	skip.Parent = card
	local armed = false
	skip.Activated:Connect(function()
		if armed then
			skipped = true
			Net.Remote("SkipTutorial"):FireServer()
			return
		end
		armed = true
		skip.Text = "Tap again to skip"
		task.delay(3, function()
			armed = false
			skip.Text = "Skip tutorial"
		end)
	end)

	-- Murph's speech card (a button, so a tap dismisses it).
	local bubble = Instance.new("TextButton")
	bubble.Name = "Speech"
	bubble.Text = ""
	bubble.AutoButtonColor = false
	bubble.LayoutOrder = 2
	bubble.Size = UDim2.fromScale(1, 0)
	bubble.AutomaticSize = Enum.AutomaticSize.Y
	bubble.BackgroundColor3 = BARK
	bubble.BackgroundTransparency = 0.05
	bubble.Visible = false
	corner(bubble, 10)
	padding(bubble, 10)
	local bubbleList = Instance.new("UIListLayout")
	bubbleList.SortOrder = Enum.SortOrder.LayoutOrder
	bubbleList.Padding = UDim.new(0, 2)
	bubbleList.Parent = bubble
	bubble.Parent = column
	local who = text(bubble, "MURPH", 13, Enum.Font.GothamBold, 1)
	who.TextColor3 = AMBER
	local line = text(bubble, "", 15, Enum.Font.Gotham, 2)
	line.TextColor3 = CREAM
	speech = bubble
	speechLabel = line
	bubble.Activated:Connect(function()
		speechToken += 1
		bubble.Visible = false
	end)

	-- Beacon: lives in PlayerGui, drawn over whatever part it adorns.
	local b = Instance.new("BillboardGui")
	b.Name = "TutorialBeacon"
	b.Size = UDim2.fromOffset(80, 70)
	b.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	b.AlwaysOnTop = true
	b.LightInfluence = 0
	b.Enabled = false
	local arrow = Instance.new("TextLabel")
	arrow.Size = UDim2.fromScale(1, 0.7)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBold
	arrow.TextScaled = true
	arrow.TextColor3 = AMBER
	arrow.TextStrokeTransparency = 0.2
	arrow.Text = "▼"
	arrow.Parent = b
	local dist = Instance.new("TextLabel")
	dist.Position = UDim2.fromScale(0, 0.7)
	dist.Size = UDim2.fromScale(1, 0.3)
	dist.BackgroundTransparency = 1
	dist.Font = Enum.Font.GothamBold
	dist.TextScaled = true
	dist.TextColor3 = CREAM
	dist.TextStrokeTransparency = 0.3
	dist.Parent = b
	distanceLabel = dist
	beacon = b

	gui.Parent = player:WaitForChild("PlayerGui")
	b.Parent = gui

	-- Bob the arrow and re-aim it a couple of times a second.
	local sinceRefresh = 0
	RunService.RenderStepped:Connect(function(dt: number)
		if b.Enabled then
			b.StudsOffsetWorldSpace = Vector3.new(0, 7 + math.sin(os.clock() * 4) * 0.6, 0)
		end
		sinceRefresh += dt
		if sinceRefresh >= BEACON_REFRESH then
			sinceRefresh = 0
			updateBeacon()
		end
	end)
end

-- "Talk" on Murph repeats the current line (or a goodbye once done).
local function setupMurph()
	local map = workspace:WaitForChild("TimberlineMap")
	local murph = map:WaitForChild("Murph") -- a Persistent model: always streamed in
	local torso = murph:WaitForChild("Torso")
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = "Murph"
	prompt.MaxActivationDistance = 10
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = torso
	prompt.Triggered:Connect(function()
		local _, step = currentStep()
		say(if step then step.murph else TutorialData.Farewell)
	end)
end

function QuestUI.Start()
	build()
	player:GetAttributeChangedSignal("TutorialStep"):Connect(refresh)
	player:GetAttributeChangedSignal("TutorialProgress"):Connect(refresh)
	refresh()
	task.spawn(setupMurph)
end

return QuestUI
