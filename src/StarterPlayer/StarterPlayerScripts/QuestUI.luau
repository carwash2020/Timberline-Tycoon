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
-- Looks per the UI spec (03, 04): a kraft card with the step and Skip (tap
-- twice: it turns amber and asks again), Murph's wood card under it with
-- his portrait (a live view of the Murph by the spawn), and an amber arrow
-- with a distance pill that bobs over the target.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local TutorialData = require(ReplicatedStorage.Shared.TutorialData)
local UITheme = require(script.Parent.UITheme)

type Step = TutorialData.Step

local QuestUI = {}

local player = Players.LocalPlayer

local C = UITheme.Colors
local F = UITheme.Fonts

local SPEECH_SECONDS = 12
local BEACON_REFRESH = 0.5
local BEACON_HIDE_WITHIN = 8 -- studs: you're there

local tracker: Frame? = nil
local objectiveLabel: TextLabel? = nil
local stepLabel: TextLabel? = nil
local speech: Frame? = nil -- the holder in the column
local speechCard: Frame? = nil -- slides and fades inside it
local speechLabel: TextLabel? = nil
local beacon: BillboardGui? = nil
local distanceLabel: TextLabel? = nil
local speechToken = 0
local lastStep = -1
local skipped = false -- this player pressed Skip: no farewell speech

local function currentStep(): (number, Step?)
	local index = (player:GetAttribute("TutorialStep") :: number?) or 0
	return index, TutorialData.Steps[index]
end

-- Fades Murph's card (alpha 0 = shown, 1 = gone): every surface and text
-- in it, from the transparency each had when built.
local baseAlpha: { [Instance]: { [string]: number } } = {}
local function fadeCard(card: Frame, alpha: number, seconds: number)
	for _, inst in ipairs(card:GetDescendants()) do
		local props: { [string]: number } = baseAlpha[inst] or {}
		if not baseAlpha[inst] then
			if inst:IsA("TextLabel") then
				props.TextTransparency = inst.TextTransparency
				props.BackgroundTransparency = inst.BackgroundTransparency
			elseif inst:IsA("ViewportFrame") or inst:IsA("ImageLabel") then
				props.ImageTransparency = inst.ImageTransparency
				props.BackgroundTransparency = inst.BackgroundTransparency
			elseif inst:IsA("Frame") then
				props.BackgroundTransparency = inst.BackgroundTransparency
			elseif inst:IsA("UIStroke") then
				props.Transparency = inst.Transparency
			end
			baseAlpha[inst] = props
		end
		local goal: { [string]: number } = {}
		for prop, base in pairs(props) do
			goal[prop] = base + (1 - base) * alpha
		end
		if next(goal) then
			TweenService:Create(inst, TweenInfo.new(seconds), goal):Play()
		end
	end
	local own: { [string]: number } = baseAlpha[card] or { BackgroundTransparency = card.BackgroundTransparency }
	baseAlpha[card] = own
	TweenService:Create(card, TweenInfo.new(seconds), {
		BackgroundTransparency = own.BackgroundTransparency + (1 - own.BackgroundTransparency) * alpha,
	}):Play()
end

local function hideSpeech(animated: boolean)
	speechToken += 1
	local holder, card = speech, speechCard
	if not holder or not card then
		return
	end
	if not animated then
		holder.Visible = false
		return
	end
	local token = speechToken
	-- The spec: fade and slide up 6 px over 0.2 s.
	fadeCard(card, 1, 0.2)
	TweenService:Create(card, TweenInfo.new(0.2), { Position = UDim2.fromOffset(0, -6) }):Play()
	task.delay(0.2, function()
		if speechToken == token then
			holder.Visible = false
		end
	end)
end

-- Shows one of Murph's lines for a while.
local function say(line: string)
	local holder, card, label = speech, speechCard, speechLabel
	if not holder or not card or not label then
		return
	end
	label.Text = line
	card.Position = UDim2.fromOffset(0, 0)
	fadeCard(card, 0, 0)
	holder.Visible = true
	speechToken += 1
	local token = speechToken
	task.delay(SPEECH_SECONDS, function()
		if speechToken == token then
			hideSpeech(true)
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
			return ((model:GetAttribute("HP") :: number?) or 0) > 0 and model:GetAttribute("Dormant") ~= true
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
	local d = if target and from then (target.Position - from).Magnitude else 0
	gui.Enabled = target ~= nil and d > BEACON_HIDE_WITHIN
	if target then
		gui.Adornee = target
		gui.StudsOffsetWorldSpace = Vector3.new(0, target.Size.Y / 2 + 4, 0)
	end
	local label = distanceLabel
	if target and label then
		label.Text = string.format("%d studs", math.floor(d + 0.5))
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

-- Murph's portrait: his head and beard from the figure by the spawn, in a
-- little viewport (an empty circle until his model streams in).
local function portrait(parent: Instance): ViewportFrame
	local view = Instance.new("ViewportFrame")
	view.Name = "Portrait"
	view.Size = UDim2.fromOffset(40, 40)
	view.BackgroundColor3 = Color3.fromHex("#8A5A3A")
	view.Ambient = Color3.fromRGB(200, 190, 170)
	view.LightColor = Color3.fromRGB(255, 240, 220)
	UITheme.corner(view, 20)
	UITheme.stroke(view, C.Amber, 2)
	view.Parent = parent
	task.spawn(function()
		local map = workspace:WaitForChild("TimberlineMap")
		local murph = map:WaitForChild("Murph")
		local head = murph:WaitForChild("Head", 30)
		if not head or not head:IsA("BasePart") then
			return
		end
		for _, name in ipairs({ "Head", "Beard", "Beanie", "Torso", "LeftArm", "RightArm" }) do
			local part = murph:FindFirstChild(name)
			if part then
				part:Clone().Parent = view
			end
		end
		local camera = Instance.new("Camera")
		camera.FieldOfView = 30
		local eye = (head.CFrame * CFrame.new(0, 0.15, -4.2)).Position
		camera.CFrame = CFrame.lookAt(eye, head.Position - Vector3.new(0, 0.25, 0))
		camera.Parent = view
		view.CurrentCamera = camera
	end)
	return view
end

local function buildBeacon(playerGui: Instance)
	-- The spec's arrow: an amber triangle with an ink rim, over a distance
	-- pill. Drawn the same size at any distance; bobs 8 px.
	local b = Instance.new("BillboardGui")
	b.Name = "TutorialBeacon"
	b.Size = UDim2.fromOffset(64, 80)
	b.AlwaysOnTop = true
	b.LightInfluence = 0
	b.Enabled = false
	local bob = Instance.new("Frame")
	bob.Name = "Bob"
	bob.Size = UDim2.fromScale(1, 1)
	bob.BackgroundTransparency = 1
	bob.Parent = b
	local function arrow(color: Color3, size: number, y: number, z: number)
		local a = Instance.new("TextLabel")
		a.AnchorPoint = Vector2.new(0.5, 0)
		a.Position = UDim2.new(0.5, 0, 0, y)
		a.Size = UDim2.fromOffset(64, 40)
		a.BackgroundTransparency = 1
		a.Font = F.Black
		a.TextSize = size
		a.TextColor3 = color
		a.Text = "▼"
		a.ZIndex = z
		a.Parent = bob
	end
	arrow(C.Ink, 50, 6, 1)
	arrow(C.Amber, 36, 4, 2)
	local pill = Instance.new("TextLabel")
	pill.Name = "Distance"
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, -8)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromOffset(0, 20)
	pill.BackgroundColor3 = C.Ink
	pill.Font = F.Black
	pill.TextSize = 12
	pill.TextColor3 = C.Cream
	UITheme.corner(pill, 10)
	UITheme.stroke(pill, C.Amber, 2)
	UITheme.padding(pill, 0, 8, 0, 8)
	pill.Parent = bob
	distanceLabel = pill
	beacon = b
	b.Parent = playerGui
	TweenService:Create(
		bob,
		TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromOffset(0, -8) }
	):Play()
end

local function build()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = UITheme.Screen("QuestUI")

	local column = Instance.new("Frame")
	column.Name = "Column"
	column.Position = UITheme.LeftColumnPosition()
	column.Size = UDim2.fromOffset(280, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.BackgroundTransparency = 1
	column.Parent = gui
	UITheme.list(column, 6)

	-- The tracker: kraft paper, a bark rim, an ink edge.
	local card = UITheme.Card(C.Paper, C.Ink, 3, 12, false)
	card.outer.Name = "Tracker"
	card.outer.LayoutOrder = 1
	card.outer.Size = UDim2.fromOffset(280, 0)
	card.outer.AutomaticSize = Enum.AutomaticSize.Y
	card.face.Size = UDim2.fromScale(1, 0)
	card.face.AutomaticSize = Enum.AutomaticSize.Y
	UITheme.padding(card.outer, 0, 0, 3, 0)
	card.outer.Visible = false
	UITheme.stroke(card.face, C.Bark, 3)
	UITheme.padding(card.face, 8, 10, 10, 12)
	UITheme.list(card.face, 4)
	UITheme.texture(card.face, "Kraft", 12)
	card.outer.Parent = column
	tracker = card.outer

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.LayoutOrder = 1
	header.Size = UDim2.new(1, 0, 0, 31)
	header.BackgroundTransparency = 1
	header.Parent = card.face
	local step = UITheme.label(header, "", F.Black, 13, C.Bark)
	step.Size = UDim2.new(1, -120, 0, 28)
	step.TextScaled = true
	local stepFit = Instance.new("UITextSizeConstraint")
	stepFit.MaxTextSize = 13
	stepFit.MinTextSize = 9
	stepFit.Parent = step
	stepLabel = step

	local skip = UITheme.Button({
		name = "Skip",
		text = "Skip tutorial",
		size = Vector2.new(112, 28),
		style = "skip",
		textSize = 11,
		radius = 8,
	})
	skip.root.AnchorPoint = Vector2.new(1, 0)
	skip.root.Position = UDim2.fromScale(1, 0)
	skip.root.Parent = header
	local armed = 0
	skip.face.Activated:Connect(function()
		if armed > 0 then
			skipped = true
			Net.Remote("SkipTutorial"):FireServer()
			return
		end
		armed += 1
		local token = armed
		skip:SetText("Tap again to skip")
		skip:SetStyle("amber")
		task.delay(3, function()
			if armed == token then
				armed = 0
				skip:SetText("Skip tutorial")
				skip:SetStyle("skip")
			end
		end)
	end)

	local objective = UITheme.label(card.face, "", F.Black, 15, C.Ink)
	objective.LayoutOrder = 2
	objective.Size = UDim2.fromScale(1, 0)
	objective.AutomaticSize = Enum.AutomaticSize.Y
	objective.TextWrapped = true
	objectiveLabel = objective

	-- Murph's card: one big button (a tap dismisses it).
	local holder = Instance.new("Frame")
	holder.Name = "Speech"
	holder.LayoutOrder = 2
	holder.Size = UDim2.fromOffset(280, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = column
	local bubble = UITheme.Card(C.Bark, C.Ink, 3, 12, false)
	bubble.outer.Name = "Card"
	bubble.outer.Size = UDim2.fromOffset(280, 0)
	bubble.outer.AutomaticSize = Enum.AutomaticSize.Y
	bubble.face.Size = UDim2.fromScale(1, 0)
	bubble.face.AutomaticSize = Enum.AutomaticSize.Y
	UITheme.padding(bubble.outer, 0, 0, 3, 0)
	UITheme.stroke(bubble.face, C.Ink, 2)
	UITheme.padding(bubble.face, 8, 10, 8, 8)
	UITheme.texture(bubble.face, "Wood", 12)
	bubble.outer.Parent = holder
	portrait(bubble.face)
	local words = Instance.new("Frame")
	words.Name = "Words"
	words.Position = UDim2.fromOffset(50, 0)
	words.Size = UDim2.new(1, -50, 0, 0)
	words.AutomaticSize = Enum.AutomaticSize.Y
	words.BackgroundTransparency = 1
	UITheme.list(words, 3)
	words.Parent = bubble.face
	local who = UITheme.label(words, "MURPH", F.Black, 12, C.Amber)
	who.LayoutOrder = 1
	who.Size = UDim2.new(1, 0, 0, 12)
	local line = UITheme.label(words, "", F.Bold, 13, C.Cream)
	line.LayoutOrder = 2
	line.Size = UDim2.fromScale(1, 0)
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.TextWrapped = true
	line.LineHeight = 1.15
	local tap = Instance.new("TextButton")
	tap.Name = "Dismiss"
	tap.Size = UDim2.fromScale(1, 1)
	tap.BackgroundTransparency = 1
	tap.Text = ""
	tap.ZIndex = 5
	tap.Parent = bubble.outer
	speech, speechCard, speechLabel = holder, bubble.outer, line
	tap.Activated:Connect(function()
		hideSpeech(true)
	end)

	gui.Parent = playerGui
	buildBeacon(playerGui)

	-- Re-aim the beacon a couple of times a second.
	local sinceRefresh = 0
	RunService.Heartbeat:Connect(function(dt: number)
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
