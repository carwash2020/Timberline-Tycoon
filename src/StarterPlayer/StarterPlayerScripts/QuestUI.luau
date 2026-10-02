--!strict
-- QuestUI: Murph's tutorial, client side (steps in Shared/TutorialData).
--   * Tracker, on the left: the current objective with progress, and Skip
--     (tap twice; from step 2 on, QuestUI.ShowSkip).
--   * Murph's card under it: what he says when a step starts. "Talk" at
--     Murph (by the spawn) says it again. A tap dismisses it, except with
--     touch controls: there it sits in the thumbstick's corner, so it lets
--     touches through and just fades after a while.
--   * A beacon: a bouncing arrow over what to do next (the nearest tree or
--     log, your truck, the sell pad, a stump to plant in or else a tree to
--     fell for one, the Tool Shed), with its distance. It never picks an
--     Elder (QuestUI.TutorialTree).
-- The server owns progress: it sets the TutorialStep (0 = done) and
-- TutorialProgress attributes, and this redraws from them.
-- The steps are TutorialData.ForLoop(CoreLoop.Active()), as the server's.
-- The v2 loop's beacons: "wood" (the nearest loose piece you own, else
-- the nearest anyone may take: QuestUI.WoodRank) and "truckBed" (your
-- truck's BedFloor: QuestUI.BedPart); "tree" looks for the step's
-- beaconWood first. Trees count as standing by their HP while they have
-- one (v1), else by Felled (QuestUI.TutorialTree), so the tree beacon
-- works for both loops' trees.
-- Looks per the UI spec (03, 04): a kraft card with the step and Skip (tap
-- twice: it turns amber and asks again), Murph's wood card under it with
-- his portrait (a live view of the Murph by the spawn), and an amber arrow
-- with a distance pill that bobs over the target.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local HintLogic = require(ReplicatedStorage.Shared.HintLogic)
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
local skipRoot: Frame? = nil -- the Skip button (QuestUI.ShowSkip says when it shows)
local skipWidth = 0 -- its width and gap: the step label ends left of it while it shows
local speech: Frame? = nil -- the holder in the column
local speechCard: Frame? = nil -- slides and fades inside it
local speechLabel: TextLabel? = nil
local speechTap: TextButton? = nil -- covers the card: a tap dismisses it
local beacon: BillboardGui? = nil
local distanceLabel: TextLabel? = nil
local speechToken = 0
local speechLine = "" -- the line on the card, before its device words (HintLogic.Expand)
local lastStep = -1
local skipped = false -- this player pressed Skip: no farewell speech

-- The tutorial's steps in the loop that runs.
local function steps(): { Step }
	return TutorialData.ForLoop(CoreLoop.Active())
end

local function currentStep(): (number, Step?)
	local index = (player:GetAttribute("TutorialStep") :: number?) or 0
	return index, steps()[index]
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

-- With touch controls the card sits where the dynamic thumbstick starts
-- (the left of the screen, below the top third): a button over it would
-- take the touch, so the stick wouldn't move. There it lets touches
-- through and goes on its own. Murph's words follow the device too
-- ("Tap" on a touch screen, "Click" with a mouse, "Press RT" on a gamepad).
local function refreshTap()
	local device: UITheme.Device = UITheme.Device()
	local tap = speechTap
	if tap then
		tap.Visible = device ~= "phone"
	end
	local label = speechLabel
	if label then
		local text = HintLogic.Expand(speechLine, device)
		if label.Text ~= text then
			label.Text = text
		end
	end
end

-- Shows one of Murph's lines for a while.
local function say(line: string)
	local holder, card, label = speech, speechCard, speechLabel
	if not holder or not card or not label then
		return
	end
	speechLine = line
	refreshTap() -- shows the line, worded for this device
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

-- Whether Skip shows on step `index` (the TutorialStep attribute): from
-- the second step on, so a new player's first second on the screen isn't
-- an invitation to skip (UI-19). It still takes two taps.
function QuestUI.ShowSkip(index: number): boolean
	return index >= 2
end

-- What Skip says after the first press, in the device's word
-- (HintLogic.Expand): "Tap again to skip", "Click again to skip", or
-- "Press again to skip" on a gamepad.
QuestUI.SkipArmed = "{Press} again to skip"

-- The beacons that hang over a fixed part: its path from TimberlineMap,
-- one direct child at a time. Both start in a Persistent model, so they're
-- always streamed in. The sell pad's beacon hangs over the sell zone, the
-- volume over the pad that the server sells from (the pad itself is art,
-- nested inside its model).
QuestUI.BeaconPaths = {
	sellPad = { "SellArea", "SellZone" },
	toolShed = { "ToolShed", "Counter" },
} :: { [string]: { string } }

-- The fixed part for the beacon `target` under `map` (TimberlineMap), if
-- it's there.
function QuestUI.FindBeaconPart(map: Instance?, target: string): BasePart?
	local path = QuestUI.BeaconPaths[target]
	if not path then
		return nil
	end
	local node = map
	for _, name in ipairs(path) do
		node = if node then node:FindFirstChild(name) else nil
	end
	return if node and node:IsA("BasePart") then node else nil
end

-- A tree standing (not felled, not hidden by day) that you could chop.
-- A v1 tree says so by its HP; a v2 section tree has none, and says it
-- by Felled (false while it stands; nil means its attributes haven't
-- arrived, so it doesn't count yet, as a v1 tree without HP doesn't).
local function standing(model: Model): boolean
	if model:GetAttribute("Dormant") == true then
		return false
	end
	local hp = model:GetAttribute("HP")
	if hp ~= nil then
		return type(hp) == "number" and hp > 0
	end
	return model:GetAttribute("Felled") == false
end

-- A tree the tutorial may point you at: standing, and not an Elder. An
-- Elder is a co-op giant that's gone for good once felled, so it leaves
-- no stump to plant in (the plant step), and it's no first tree for a new
-- player. Elders carry the Elder attribute; `elderUid` (the workspace's
-- ElderUid, "" when none is awake) names the one awake too, in case that
-- attribute hasn't reached this client yet.
function QuestUI.TutorialTree(model: Model, elderUid: unknown): boolean
	if not standing(model) or model:GetAttribute("Elder") == true then
		return false
	end
	local uid = model:GetAttribute("Uid")
	return not (type(elderUid) == "string" and elderUid ~= "" and uid == elderUid)
end

-- The drag step's pick among loose pieces (tag Wood): 1 for one you own,
-- 2 for one nobody owns (Owner 0: anyone may take it), nil for someone
-- else's, or one in someone else's hands (HeldBy).
function QuestUI.WoodRank(model: Model, userId: number): number?
	local heldBy = model:GetAttribute("HeldBy")
	if type(heldBy) == "number" and heldBy ~= 0 and heldBy ~= userId then
		return nil
	end
	local owner = model:GetAttribute("Owner")
	if owner == userId then
		return 1
	end
	return if owner == 0 then 2 else nil
end

-- Where the load step's beacon hangs on your truck: its bed floor, or its
-- PrimaryPart for a truck without a bed (the Scout ATV).
function QuestUI.BedPart(truck: Model): BasePart?
	local bed = truck:FindFirstChild("BedFloor")
	if bed and bed:IsA("BasePart") then
		return bed
	end
	return truck.PrimaryPart
end

-- How many Heartseeds of this tree's or stump's wood you hold.
local function seedsFor(model: Model): number
	local wood = model:GetAttribute("WoodId")
	local seeds = if type(wood) == "string" then player:GetAttribute("Seeds_" .. wood) else nil
	return if type(seeds) == "number" then seeds else 0
end

-- The part the beacon should hang over for this step, if it's around.
local function beaconTarget(step: Step, from: Vector3): BasePart?
	local target = step.beacon
	local elderUid = workspace:GetAttribute("ElderUid")
	local function choppable(model: Model): boolean
		return QuestUI.TutorialTree(model, elderUid)
	end
	if target == "tree" then
		local wood = step.beaconWood
		if wood then
			-- The step's wood first (v2: Murph's oaks), else any tree.
			local first = nearestTagged("Tree", from, function(model)
				return choppable(model) and model:GetAttribute("WoodId") == wood
			end)
			if first then
				return first
			end
		end
		return nearestTagged("Tree", from, choppable)
	elseif target == "wood" then
		-- Your own nearest loose piece, else the nearest anyone may take,
		-- else a tree to fell for some (a save that came into the v2 loop
		-- mid-tutorial had its logs bought back).
		local userId = player.UserId
		return nearestTagged("Wood", from, function(model)
			return QuestUI.WoodRank(model, userId) == 1
		end) or nearestTagged("Wood", from, function(model)
			return QuestUI.WoodRank(model, userId) == 2
		end) or nearestTagged("Tree", from, choppable)
	elseif target == "truckBed" then
		-- Nothing of yours to load (none lying about, none on the bed): a
		-- tree to fell first.
		local bedVolume = player:GetAttribute("BedVolume")
		local onBed = type(bedVolume) == "number" and bedVolume > 0
		local userId = player.UserId
		if
			not onBed
			and nearestTagged("Wood", from, function(model)
					return QuestUI.WoodRank(model, userId) == 1
				end)
				== nil
		then
			local tree = nearestTagged("Tree", from, choppable)
			if tree then
				return tree
			end
		end
		for _, inst in ipairs(CollectionService:GetTagged("Truck")) do
			if inst:IsA("Model") and inst:GetAttribute("OwnerId") == player.UserId then
				return QuestUI.BedPart(inst)
			end
		end
		return nil
	elseif target == "log" then
		-- Logs lying in the world have a "Pick up" prompt; carried ones don't.
		return nearestTagged("Log", from, function(_model, pp)
			return pp:FindFirstChildOfClass("ProximityPrompt") ~= nil
		end)
	elseif target == "truck" then
		return nearestTagged("Truck", from, function(model)
			return model:GetAttribute("OwnerId") == player.UserId
		end)
	elseif target == "stump" then
		-- The nearest stump you hold a Heartseed for (hidden Gloam Hollow
		-- stumps and ones already sprouting don't count).
		local stump = nearestTagged("Stump", from, function(model, pp)
			return seedsFor(model) > 0 and pp.Transparency < 1 and model:GetAttribute("Sprouting") ~= true
		end)
		if stump then
			return stump
		end
		-- None around (it grew back, or it's out of view): a tree to fell for
		-- a fresh stump, one of a wood you hold seeds for if there is one,
		-- else any (felling it drops its own seed). Never the Elder: it
		-- leaves no stump to plant in.
		return nearestTagged("Tree", from, function(model)
			return choppable(model) and seedsFor(model) > 0
		end) or nearestTagged("Tree", from, choppable)
	elseif target == "sellPad" and CoreLoop.V2() then
		-- The v2 loop with nothing of yours to sell (none on the bed, none
		-- lying about): a tree to fell first, as for the bed.
		local bedVolume = player:GetAttribute("BedVolume")
		local userId = player.UserId
		local hasWood = (type(bedVolume) == "number" and bedVolume > 0)
			or nearestTagged("Wood", from, function(model)
					return QuestUI.WoodRank(model, userId) == 1
				end)
				~= nil
		if not hasWood then
			local tree = nearestTagged("Tree", from, choppable)
			if tree then
				return tree
			end
		end
		return QuestUI.FindBeaconPart(workspace:FindFirstChild("TimberlineMap"), target)
	elseif target then
		return QuestUI.FindBeaconPart(workspace:FindFirstChild("TimberlineMap"), target)
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
		local showSkip = QuestUI.ShowSkip(index)
		if skipRoot then
			skipRoot.Visible = showSkip
		end
		if stepLabel then
			stepLabel.Text = string.format("TUTORIAL · %d/%d", index, #steps())
			stepLabel.Size = UDim2.new(1, if showSkip then -skipWidth else 0, 0, 28)
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
		-- Far enough back for the whole beanie and its pompom.
		local eye = (head.CFrame * CFrame.new(0, 0.35, -5.2)).Position
		camera.CFrame = CFrame.lookAt(eye, head.Position + Vector3.new(0, 0.05, 0))
		camera.Parent = view
		view.CurrentCamera = camera
	end)
	return view
end

-- The beacon's arrow, drawn from shapes so it's centred at any distance
-- (a glyph sits wherever its font puts it): an amber square turned 45
-- degrees with an ink rim, centred on the top edge of a frame that clips
-- off its upper half, leaving a downward triangle; an ink bar along that
-- edge closes the rim. 45 wide and 23 tall, centred along the top of the
-- beacon, 8 down.
QuestUI.ArrowHalf = 18 -- the square's half-diagonal: the triangle's height
QuestUI.ArrowRim = 3
function QuestUI.BeaconArrow(): Frame
	local rim = QuestUI.ArrowRim
	local side = math.floor(QuestUI.ArrowHalf * math.sqrt(2) + 0.5) -- whole pixels
	local half = side / math.sqrt(2) -- its real half-diagonal
	local reach = rim * math.sqrt(2) -- how far the rim stands out past a corner
	local clip = Instance.new("Frame")
	clip.Name = "Arrow"
	clip.AnchorPoint = Vector2.new(0.5, 0)
	clip.Position = UDim2.new(0.5, 0, 0, 8)
	clip.Size = UDim2.fromOffset(math.ceil(2 * (half + reach)), math.ceil(half + reach))
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	local square = Instance.new("Frame")
	square.Name = "Square"
	square.AnchorPoint = Vector2.new(0.5, 0.5)
	square.Position = UDim2.fromScale(0.5, 0) -- centred on the clip's top edge
	square.Size = UDim2.fromOffset(side, side)
	square.Rotation = 45
	square.BackgroundColor3 = C.Amber
	square.BorderSizePixel = 0
	UITheme.corner(square, 2)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Ink
	stroke.Thickness = rim
	stroke.Parent = square
	square.Parent = clip
	local top = Instance.new("Frame")
	top.Name = "Rim"
	top.Size = UDim2.new(1, 0, 0, rim)
	top.BackgroundColor3 = C.Ink
	top.BorderSizePixel = 0
	top.ZIndex = 2
	top.Parent = clip
	return clip
end

local function buildBeacon(playerGui: Instance)
	-- The spec's arrow: an amber triangle with an ink rim (BeaconArrow),
	-- over a distance pill. Drawn the same size at any distance; bobs 8 px.
	local b = Instance.new("BillboardGui")
	b.Name = "TutorialBeacon"
	b.ResetOnSpawn = false -- it lives in PlayerGui: a respawn would destroy it for good
	b.Size = UDim2.fromOffset(64, 80)
	b.AlwaysOnTop = true
	b.LightInfluence = 0
	b.Enabled = false
	local bob = Instance.new("Frame")
	bob.Name = "Bob"
	bob.Size = UDim2.fromScale(1, 1)
	bob.BackgroundTransparency = 1
	bob.Parent = b
	QuestUI.BeaconArrow().Parent = bob
	local pill = Instance.new("TextLabel")
	pill.Name = "Distance"
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, -8)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.fromOffset(0, 20)
	pill.BackgroundColor3 = C.Ink
	pill.Font = F.Black
	pill.TextSize = UITheme.Sized("Beacon").text
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

	local column = Instance.new("Frame")
	column.Name = "Tutorial"
	column.Size = UDim2.fromOffset(280, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.BackgroundTransparency = 1
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
	-- Skip: on a phone its face keeps the header's height, and a hit area
	-- round it (UITheme.HitPad) takes a whole fingertip.
	local skipSpec = UITheme.Sized("Skip")
	local skipSize = skipSpec.size or Vector2.new(112, 28)
	local step = UITheme.label(header, "", F.Black, UITheme.Sized("TrackerStep").text, C.Bark)
	step.Size = UDim2.new(1, -(skipSize.X + 8), 0, 28)
	step.TextTruncate = Enum.TextTruncate.AtEnd -- one line, never wrapped
	stepLabel = step

	local skip = UITheme.Button({
		name = "Skip",
		text = "Skip tutorial",
		size = skipSize,
		style = "skip",
		textSize = skipSpec.text,
		radius = 8,
	})
	skip.root.AnchorPoint = Vector2.new(1, 0)
	skip.root.Position = UDim2.fromScale(1, 0)
	skip.root.Visible = false -- until step 2 (refresh)
	skip.root.Parent = header
	skipRoot, skipWidth = skip.root, skipSize.X + 8
	local armed = 0
	local function onSkip()
		if armed > 0 then
			skipped = true
			Net.Remote("SkipTutorial"):FireServer()
			return
		end
		armed += 1
		local token = armed
		skip:SetText(HintLogic.Expand(QuestUI.SkipArmed, UITheme.Device())) -- "Tap" / "Click" / "Press again to skip"
		skip:SetStyle("amber")
		task.delay(3, function()
			if armed == token then
				armed = 0
				skip:SetText("Skip tutorial")
				skip:SetStyle("skip")
			end
		end)
	end
	skip.face.Activated:Connect(onSkip)
	if skipSpec.hit then
		UITheme.HitPad(skip.root, skipSpec.hit).Activated:Connect(onSkip)
	end

	local objective = UITheme.label(card.face, "", F.Black, 15, C.Ink)
	objective.LayoutOrder = 2
	objective.Size = UDim2.fromScale(1, 0)
	objective.AutomaticSize = Enum.AutomaticSize.Y
	objective.TextWrapped = true
	objectiveLabel = objective

	-- Murph's card: one big button (a tap dismisses it; not with touch
	-- controls, see refreshTap).
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
	local nameSize = UITheme.Sized("MurphName").text
	local who = UITheme.label(words, "MURPH", F.Black, nameSize, C.Amber)
	who.LayoutOrder = 1
	who.Size = UDim2.new(1, 0, 0, nameSize)
	local line = UITheme.label(words, "", F.Bold, UITheme.Sized("MurphLine").text, C.Cream)
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
	speech, speechCard, speechLabel, speechTap = holder, bubble.outer, line, tap
	tap.Activated:Connect(function()
		hideSpeech(true)
	end)
	UserInputService.LastInputTypeChanged:Connect(refreshTap)
	refreshTap()

	-- In the left column (under Roblox's chat window), under the Field
	-- Guide button: that shows up as Murph's farewell starts, and stacks
	-- above his card instead of under it.
	UITheme.LeftColumn(column, 2)
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
