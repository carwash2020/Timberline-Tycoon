--!strict
-- NPCController: the townsfolk come alive on this client (NPCService builds
-- them; Shared/NPCData says who they are). Everything here is local: joints
-- move through Motor6D.Transform and walkers through their anchored root,
-- neither of which replicates, so it costs the server nothing.
--   * Idle: breathing, blinking, now and then a flourish of their own
--     (Murph sips his coffee, Millie checks her clipboard, Tink pushes his
--     glasses up, Dale wipes his brow, the others look around).
--   * Work and a walk, from NPCAnim (these rigs aren't R15, so there's no
--     catalog animation to play): Millie saws, Hazel sweeps, Murph and Pip
--     and Tink chop, Rosa and Bram carry, the walkers stride their route.
--     A bubble adds a small talking gesture. All of it is Motor6D.Transform
--     on this client.
--   * They turn their head toward the nearest player, and wave the first
--     time you come within WAVE_RANGE (again after you've wandered off for
--     a while), with a greeting. A new player's first hello from Murph is
--     a short onboarding tip.
--   * Walkers stroll their loop (NPCData.RouteState from the shared server
--     clock, so everyone sees them in the same place) and pause at their
--     waypoints. The root stays anchored. NPCWalk eases it toward the
--     clock every rendered frame. At bind a ray samples the route; a miss
--     uses HeightAt and is retried a few times a second while the walker
--     is within StreamingMinRadius, in case the porch streams in later.
--     The server never moves them.
--   * The nearest NPC within TALK_RANGE says a line in a speech bubble
--     every so often (NPCDialogue: the hour, the weather, a first sale, a
--     better axe, a sawmill, or a general line). Talk (E, or a tap on the
--     prompt) asks for one sooner. A sleeping keeper says the server's
--     SleepLine and is not stood back up. Murph keeps quiet while your tutorial
--     runs (QuestUI owns his button); he still looks, waves, and gives
--     that one tip.
--   * The bubble is adorned to the head, so it follows the walk every
--     frame. Its tail sits BubbleClearance (1.5 studs) above TopOffset,
--     the hat top CharacterArt measured from the head centre. A phone
--     and a desktop use that same lift. Near the money plaque it steps
--     aside; it never drops into the hat.
--   * Beyond ANIMATE_RANGE they're left alone (joints reset). Walkers
--     still keep their place on the route. Who to look at is refreshed
--     a few times a second, not every frame.
--   * Idle poses follow Quality.Budget().CosmeticHz: every frame on
--     high, about 20 times a second on medium, about twice a second on
--     low. The walk and its legs do not: those run every rendered frame,
--     so a low tier is coarser blinking, not a teleport.
-- Streaming-tolerant: NPCs are found by the "NPC" tag as they stream in
-- and dropped as they stream out. Binding gives up after a few tries.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ClockOverride = require(ReplicatedStorage.Shared.ClockOverride)
local NPCAnim = require(ReplicatedStorage.Shared.NPCAnim)
local NPCData = require(ReplicatedStorage.Shared.NPCData)
local NPCDialogue = require(ReplicatedStorage.Shared.NPCDialogue)
local NPCWalk = require(ReplicatedStorage.Shared.NPCWalk)
local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local TerrainGen = require(ReplicatedStorage.Shared.World.TerrainGen)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local WorldTime = require(ReplicatedStorage.Shared.WorldTime)
local UITheme = require(script.Parent.UITheme)

local Quality = require(script.Parent.Quality)

local NPCController = {}

local player = Players.LocalPlayer

local ANIMATE_RANGE = 120
local WALKER_RANGE = 300 -- walkers keep their place on the route this far out
local LOOK_RANGE = 22
local WAVE_RANGE = 14
local WAVE_RESET = 30 -- wander this far off and they'll wave again...
local WAVE_COOLDOWN = 45 -- ...but not more often than this
local TALK_RANGE = 16
local WAVE_TIME = 1.9
local BLINK_TIME = 0.13

local INK = Color3.fromHex("#3C2814")
local CREAM = Color3.fromHex("#F5EBD7")

type Flourish = { kind: string, start: number, length: number }

type Rig = {
	model: Model,
	npc: NPCData.NPC?,
	root: BasePart,
	torso: BasePart,
	head: BasePart,
	rootJoint: Motor6D?,
	neck: Motor6D?,
	leftShoulder: Motor6D?,
	rightShoulder: Motor6D?,
	leftHip: Motor6D?,
	rightHip: Motor6D?,
	eyes: { { part: BasePart, size: Vector3, shine: BasePart? } },
	tag: BillboardGui?,
	route: { NPCData.Waypoint }?,
	speed: number,
	offset: number,
	rootHeight: number,
	ground: NPCWalk.Profile?,
	visual: NPCWalk.Pose?,
	moving: boolean,
	walked: number,
	phase: number,
	homeYaw: number, -- the way it faces when nobody's near (its spot's)
	bodyYaw: number, -- the way it faces now
	scale: number,
	topOffset: number,
	seed: number,
	rng: Random,
	-- State
	active: boolean,
	yaw: number,
	pitch: number,
	walkBlend: number,
	blinkAt: number,
	blinkUntil: number,
	waveStart: number,
	waved: boolean,
	lastWave: number,
	flourish: Flourish?,
	flourishAt: number,
	nextLine: number,
	bubble: BillboardGui?,
	bubbleUntil: number,
	bubbleLength: number,
	bag: { number },
	bagKind: string,
	met: boolean, -- heard the onboarding tip
	lastPrompt: number,
	promptConn: RBXScriptConnection?,
	working: boolean,
	workStart: number,
	workLength: number,
	nextWork: number,
}

local rigs: { [Model]: Rig } = {}

local phoneLayout: NPCDialogue.Layout = NPCDialogue.LayoutFor(false)
local layoutAt = -1

local function applyTag(tag: BillboardGui?, layout: NPCDialogue.Layout)
	if not tag then
		return
	end
	tag.MaxDistance = layout.tagDistance
	tag.Size = UDim2.fromOffset(layout.tagSize.X, layout.tagSize.Y)
	local name = tag:FindFirstChild("Name")
	if name and name:IsA("TextLabel") then
		name.TextSize = layout.tagName
		name.Size = UDim2.new(1, 0, 0, layout.tagName + 6)
	end
	local role = tag:FindFirstChild("Role")
	if role and role:IsA("TextLabel") then
		role.TextSize = layout.tagRole
		role.Position = UDim2.fromOffset(0, layout.tagName + 2)
		role.Size = UDim2.new(1, 0, 0, layout.tagRole + 4)
	end
end

local function refreshLayout(now: number)
	if now - layoutAt < 0.5 then
		return
	end
	layoutAt = now
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else nil
	local width = if viewport then viewport.X else 1920
	-- A dense phone is wider than NPCDialogue.IsPhone's cutoff. Compact
	-- selects this phone layout for those screens too.
	local phone = NPCDialogue.IsPhone(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled, width)
		or UITheme.IsCompact(viewport, UserInputService.TouchEnabled, UserInputService.KeyboardEnabled)
	local tenFoot = false
	pcall(function()
		tenFoot = GuiService:IsTenFootInterface() == true
	end)
	local layout = NPCDialogue.LayoutFor(phone, tenFoot)
	if layout.phone ~= phoneLayout.phone then
		for _, rig in pairs(rigs) do
			applyTag(rig.tag, layout)
		end
	end
	phoneLayout = layout
end

---------------------------------------------------------------------------
-- Little helpers
---------------------------------------------------------------------------

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- 0 -> 1 over `rise` seconds, holds, 1 -> 0 over the last `fall` seconds.
local function envelope(t: number, length: number, rise: number, fall: number): number
	if t <= 0 or t >= length then
		return 0
	end
	return math.min(smooth(t / rise), smooth((length - t) / fall))
end

local function approach(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function setTransform(motor: Motor6D?, cf: CFrame)
	if motor then
		motor.Transform = cf
	end
end

local function limb(pitch: number, yaw: number, roll: number): CFrame
	return CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll)
end

-- TutorialStep is 0 once the tutorial is done or skipped; until the profile
-- has loaded it isn't set yet, which counts as running (Murph stays quiet
-- rather than talking over QuestUI's first line).
local function tutorialRunning(): boolean
	local step = player:GetAttribute("TutorialStep")
	return type(step) ~= "number" or step > 0
end

local function quiet(rig: Rig): boolean
	local npc = rig.npc
	return npc ~= nil and npc.tutorialQuiet == true and tutorialRunning()
end

---------------------------------------------------------------------------
-- Speech bubbles
---------------------------------------------------------------------------

local function closeBubble(rig: Rig, instant: boolean?)
	local gui = rig.bubble
	if not gui then
		return
	end
	rig.bubble = nil
	if rig.tag then
		rig.tag.Enabled = true
	end
	if instant then
		gui:Destroy()
		return
	end
	local info = TweenInfo.new(0.25)
	for _, d in ipairs(gui:GetDescendants()) do
		if d:IsA("Frame") then
			TweenService:Create(d, info, { BackgroundTransparency = 1 }):Play()
		elseif d:IsA("TextLabel") then
			TweenService:Create(d, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		end
	end
	task.delay(0.3, function()
		gui:Destroy()
	end)
end

-- The tail's bottom is the billboard centre. Y is TopOffset plus the
-- clearance, from the head centre, on a phone and a desktop. Near the
-- money plaque the tail steps aside; the nudge never lowers it.
local function placeBubble(rig: Rig)
	local gui = rig.bubble
	if not gui then
		return
	end
	local nudge = false
	local camera = workspace.CurrentCamera
	if camera then
		local screen, visible = camera:WorldToViewportPoint(rig.head.CFrame.Position)
		local band = if phoneLayout.phone then 100 else 78
		if visible and screen.Y < band then
			nudge = true
		end
	end
	gui.StudsOffset = NPCDialogue.BubbleStudsOffset(rig.topOffset, phoneLayout.studsOffset.X, nudge)
	gui.StudsOffsetWorldSpace = Vector3.zero
end

local function say(rig: Rig, text: string, now: number)
	closeBubble(rig, true)
	refreshLayout(now)
	local layout = phoneLayout
	local gui = Instance.new("BillboardGui")
	gui.Name = "SpeechBubble"
	-- The billboard centre is the tail's bottom. The card grows upward
	-- from there, so nothing we draw hangs below TopOffset + clearance.
	gui.Size = UDim2.fromOffset(layout.width + 28, 220)
	gui.SizeOffset = Vector2.new(0, 0)
	gui.MaxDistance = layout.maxDistance
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Adornee = rig.head
	gui.StudsOffset = Vector3.new(layout.studsOffset.X, rig.topOffset + NPCDialogue.BubbleClearance, 0)
	gui.StudsOffsetWorldSpace = Vector3.zero

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 0.5, -14)
	card.Size = UDim2.fromOffset(0, 0)
	card.AutomaticSize = Enum.AutomaticSize.XY
	card.BackgroundColor3 = CREAM
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.PaddingTop = UDim.new(0, 7)
	pad.PaddingBottom = UDim.new(0, 7)
	pad.Parent = card
	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromOffset(0, 0)
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Font = Enum.Font.GothamMedium
	label.TextSize = layout.textSize
	label.TextColor3 = INK
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = card
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(layout.width, 96)
	limit.Parent = label
	-- The tail under the card.
	local tail = Instance.new("TextLabel")
	tail.Name = "Tail"
	tail.BackgroundTransparency = 1
	tail.AnchorPoint = Vector2.new(0.5, 1)
	tail.Position = UDim2.fromScale(0.5, 0.5)
	tail.Size = UDim2.fromOffset(24, 18)
	tail.Font = Enum.Font.GothamBlack
	tail.TextSize = 20
	tail.TextColor3 = CREAM
	tail.TextStrokeColor3 = INK
	tail.TextStrokeTransparency = 0
	tail.Text = "▼"
	tail.Parent = gui
	-- Pop in.
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = card
	gui.Parent = rig.head
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()

	if rig.tag then
		rig.tag.Enabled = false
	end
	rig.bubble = gui
	rig.bubbleLength = NPCDialogue.BubbleSeconds(text)
	rig.bubbleUntil = now + rig.bubbleLength
	placeBubble(rig)
	SoundData.PlayAt("NPCChatter", rig.head.Position)
end

local function hasPlacedSawmill(): boolean
	local slot = player:GetAttribute("PlotSlot")
	if type(slot) ~= "number" then
		return false
	end
	local map = workspace:FindFirstChild("TimberlineMap")
	local plots = if map then map:FindFirstChild("Plots") else nil
	local plot = if plots then plots:FindFirstChild("Plot_" .. tostring(slot)) else nil
	if not plot then
		return false
	end
	for _, child in ipairs(plot:GetChildren()) do
		local id = child:GetAttribute("BlueprintId")
		if type(id) == "string" and string.sub(id, 1, 7) == "Sawmill" then
			return true
		end
	end
	return false
end

local function playerContext(): NPCDialogue.Context
	local hour = ClockOverride.Apply(
		WorldTime.ClockTime(WorldTime.GameNow()),
		workspace:GetAttribute(ClockOverride.Attribute),
		RunService:IsStudio()
	)
	local weather = workspace:GetAttribute("Weather")
	return {
		band = NPCDialogue.BandOf(hour),
		weather = if type(weather) == "string" then weather else "Clear",
		progress = NPCDialogue.ProgressOf({
			loaded = player:GetAttribute("ProfileLoaded") == true,
			tutorialStep = player:GetAttribute("TutorialStep"),
			tutorialRefresher = player:GetAttribute("TutorialRefresher"),
			bestAxeTier = player:GetAttribute("BestAxeTier"),
			sawmillStock = player:GetAttribute("SawmillStock"),
			placedSawmill = hasPlacedSawmill(),
		}),
	}
end

-- A line for this moment. `firstMeet` lets Murph's onboarding tip win once.
local function takeLine(rig: Rig, firstMeet: boolean): (string?, string)
	local npc = rig.npc
	if not npc then
		return nil, ""
	end
	local pool = NPCDialogue.PoolFor(npc, playerContext(), rig.rng:NextNumber(), firstMeet and not rig.met)
	if pool.kind ~= rig.bagKind then
		rig.bagKind = pool.kind
		rig.bag = {}
	end
	local line, bag = NPCDialogue.Draw(pool.lines, rig.bag, rig.rng)
	rig.bag = bag
	if pool.kind == "tip" then
		rig.met = true
	end
	return line, pool.kind
end

-- Talk on the model. Murph's button belongs to QuestUI (it repeats the lesson).
local function onTalk(rig: Rig)
	local npc = rig.npc
	if not npc or npc.tutorialQuiet then
		return
	end
	local now = os.clock()
	if now < rig.lastPrompt + NPCDialogue.PromptCooldown then
		return
	end
	if rig.model:GetAttribute("Asleep") == true then
		local sleep = rig.model:GetAttribute("SleepLine")
		if type(sleep) == "string" and sleep ~= "" then
			say(rig, sleep, now)
			rig.lastPrompt = now
			return
		end
	end
	if quiet(rig) then
		return
	end
	local line, _kind = takeLine(rig, true)
	if not line then
		return
	end
	say(rig, line, now)
	rig.lastPrompt = now
	local gap = NPCDialogue.AmbientGap
	rig.nextLine = now + rig.rng:NextNumber(gap[1], gap[2])
end

---------------------------------------------------------------------------
-- Binding to models as they stream in
---------------------------------------------------------------------------

local function seedOf(text: string): number
	local h = 17
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 100003
	end
	return h
end

local function motorIn(parent: Instance?, name: string): Motor6D?
	local m = if parent then parent:FindFirstChild(name) else nil
	return if m and m:IsA("Motor6D") then m else nil
end

-- One ray per waypoint and per 4 studs along the route. NPCs, Wood, and
-- vehicles are excluded; a miss uses the terrain height. The same probe
-- retries those misses later, a few rays at a time.
local function groundProbe(): (number, number) -> number?
	local map = workspace:FindFirstChild("TimberlineMap")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = {}
	if map then
		for _, name in ipairs({ "Townsfolk", "Wood", "Murph" }) do
			local child = map:FindFirstChild(name)
			if child then
				table.insert(exclude, child)
			end
		end
	end
	for _, inst in ipairs(CollectionService:GetTagged("NPC")) do
		table.insert(exclude, inst)
	end
	for _, inst in ipairs(CollectionService:GetTagged("Truck")) do
		table.insert(exclude, inst)
	end
	params.FilterDescendantsInstances = exclude
	return function(x: number, z: number): number?
		local from = TerrainGen.HeightAt(x, z) + 8
		local hit = workspace:Raycast(Vector3.new(x, from, z), Vector3.new(0, -16, 0), params)
		if hit and NPCWalk.MapGround(hit.Instance, map) then
			return hit.Position.Y
		end
		return nil
	end
end

local function sampleGround(route: { NPCData.Waypoint }): NPCWalk.Profile
	return NPCWalk.Sample(route, groundProbe(), TerrainGen.HeightAt)
end

local function bind(model: Instance, tries: number?)
	if not model:IsA("Model") or rigs[model] then
		return
	end
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	local torso = model:FindFirstChild("Torso")
	local head = model:FindFirstChild("Head")
	if not (root and root:IsA("BasePart") and torso and torso:IsA("BasePart") and head and head:IsA("BasePart")) then
		-- Not all here yet (shouldn't happen with Atomic models): try again.
		local n = tries or 0
		if n < 5 then
			task.delay(1, function()
				if model.Parent then
					bind(model, n + 1)
				end
			end)
		end
		return
	end
	local id = model:GetAttribute("NPCId")
	local npc = if type(id) == "string" then NPCData.Get(id) else nil
	local eyes = {}
	-- A head mesh brings its own eyes. Leave the part eyes hidden and
	-- don't blink them back on.
	if head:GetAttribute("MeshEyes") ~= true then
		for _, d in ipairs(head:GetChildren()) do
			if d:IsA("BasePart") and d.Name == "Eye" then
				local shine = d:FindFirstChild("EyeShine")
				table.insert(eyes, {
					part = d,
					size = d.Size,
					shine = if shine and shine:IsA("BasePart") then shine else nil,
				})
			end
		end
	end
	local routeText = model:GetAttribute("Route")
	local decoded = if type(routeText) == "string" then NPCData.DecodeRoute(routeText) else nil
	local route = if decoded and #decoded >= 2 then decoded else nil
	local rootHeight = model:GetAttribute("RootHeight")
	local rh = if type(rootHeight) == "number" then rootHeight else 3
	local scaleAttr = model:GetAttribute("Scale")
	local topAttr = model:GetAttribute("TopOffset")
	local speed = model:GetAttribute("Speed")
	local offset = model:GetAttribute("RouteOffset")
	local seed = seedOf(model.Name)
	local tag = head:FindFirstChild("NameTag")
	local nameTag = if tag and tag:IsA("BillboardGui") then tag else nil
	applyTag(nameTag, phoneLayout)
	local now = os.clock()
	local rng = Random.new(seed + math.floor(now * 1000) % 1000)
	local prompt = model:FindFirstChild("Talk")
	local rig: Rig = {
		model = model,
		npc = npc,
		root = root,
		torso = torso,
		head = head,
		rootJoint = motorIn(root, "RootJoint"),
		neck = motorIn(torso, "Neck"),
		leftShoulder = motorIn(torso, "LeftShoulder"),
		rightShoulder = motorIn(torso, "RightShoulder"),
		leftHip = motorIn(torso, "LeftHip"),
		rightHip = motorIn(torso, "RightHip"),
		eyes = eyes,
		tag = nameTag,
		route = route,
		speed = if type(speed) == "number" then speed else 4,
		offset = if type(offset) == "number" then offset else 0,
		rootHeight = rh,
		ground = if route then sampleGround(route) else nil,
		visual = nil,
		moving = false,
		walked = 0,
		phase = 0,
		homeYaw = NPCData.YawOf(root.CFrame.LookVector.X, root.CFrame.LookVector.Z),
		bodyYaw = NPCData.YawOf(root.CFrame.LookVector.X, root.CFrame.LookVector.Z),
		scale = if type(scaleAttr) == "number" then scaleAttr else 1,
		topOffset = if type(topAttr) == "number" then topAttr else 1,
		seed = seed,
		rng = rng,
		active = false,
		yaw = 0,
		pitch = 0,
		walkBlend = 0,
		blinkAt = now + rng:NextNumber(1, 4),
		blinkUntil = 0,
		waveStart = -100,
		waved = false,
		lastWave = -100,
		flourish = nil,
		flourishAt = now + rng:NextNumber(4, 10),
		nextLine = now + rng:NextNumber(2, 5),
		bubble = nil,
		bubbleUntil = 0,
		bubbleLength = 1,
		bag = {},
		bagKind = "",
		met = false,
		lastPrompt = -100,
		promptConn = nil,
		working = false,
		workStart = 0,
		workLength = 1,
		nextWork = now + rng:NextNumber(2, 6),
	}
	if prompt and prompt:IsA("ProximityPrompt") then
		rig.promptConn = prompt.Triggered:Connect(function()
			onTalk(rig)
		end)
	end
	rigs[model] = rig
end

local function rest(rig: Rig)
	for _, m in ipairs({ rig.rootJoint, rig.neck, rig.leftShoulder, rig.rightShoulder, rig.leftHip, rig.rightHip }) do
		setTransform(m, CFrame.identity)
	end
	for _, eye in ipairs(rig.eyes) do
		eye.part.Size = eye.size
		if eye.shine then
			eye.shine.Transparency = 0
		end
	end
	rig.yaw, rig.pitch, rig.walkBlend = 0, 0, 0
	rig.flourish = nil
	if not rig.route and rig.bodyYaw ~= rig.homeYaw and rig.model:GetAttribute("Asleep") ~= true then
		rig.bodyYaw = rig.homeYaw
		rig.root.CFrame = CFrame.new(rig.root.Position) * CFrame.Angles(0, rig.homeYaw, 0)
	end
	closeBubble(rig, true)
end

local function unbind(model: Instance)
	local rig = rigs[model :: Model]
	if rig then
		rigs[model :: Model] = nil
		if rig.promptConn then
			rig.promptConn:Disconnect()
		end
		closeBubble(rig, true)
	end
end

---------------------------------------------------------------------------
-- Animating
---------------------------------------------------------------------------

-- How long each idle flourish lasts, and how often it comes round.
local FLOURISHES: { [string]: { length: number, gap: { number } } } = {
	sip = { length = 3.2, gap = { 9, 15 } },
	clipboard = { length = 2.6, gap = { 7, 12 } },
	glasses = { length = 1.6, gap = { 9, 14 } },
	wipe = { length = 2.2, gap = { 10, 16 } },
	lookAround = { length = 2.8, gap = { 6, 11 } },
}

local function animate(rig: Rig, now: number, dt: number, focus: Vector3?, focusHead: Vector3?, selfDist: number)
	local s = rig.scale
	local npc = rig.npc

	-- The server laid the keeper down. Don't stand them back up, and don't
	-- play a chop or a wave over the lie.
	if rig.model:GetAttribute("Asleep") == true then
		local pose = NPCAnim.Sleep()
		setTransform(rig.rootJoint, CFrame.Angles(pose.rootPitch, pose.rootYaw, 0))
		setTransform(rig.neck, CFrame.Angles(pose.neckPitch, pose.neckYaw, pose.neckRoll))
		setTransform(rig.leftShoulder, limb(pose.leftPitch, pose.leftYaw, pose.leftRoll))
		setTransform(rig.rightShoulder, limb(pose.rightPitch, pose.rightYaw, pose.rightRoll))
		if not rig.route then
			setTransform(rig.leftHip, CFrame.Angles(pose.leftHip, 0, 0))
			setTransform(rig.rightHip, CFrame.Angles(pose.rightHip, 0, 0))
		end
		return
	end

	-- Walkers are placed every frame in presentWalkers (the clock, eased).
	-- Standing townsfolk still turn here, on the cosmetic tick.
	local moving = false
	local route = rig.route
	if route then
		moving = rig.moving
	else
		local want = NPCData.FaceYaw(rig.homeYaw, rig.root.Position, focus, NPCData.FaceRange)
		local turned = NPCData.TurnToward(rig.bodyYaw, want, NPCData.TurnRate * dt)
		if turned ~= rig.bodyYaw then
			rig.bodyYaw = turned
			rig.root.CFrame = CFrame.new(rig.root.Position) * CFrame.Angles(0, turned, 0)
		end
	end
	if not route then
		rig.walkBlend = approach(rig.walkBlend, if moving then 1 else 0, 8, dt)
	end
	local w = rig.walkBlend
	local phase = if route then rig.phase else 0

	-- Breathing (the walk's bob lives in the pose).
	local breath = math.sin(now * 1.7 + rig.seed % 7)

	-- Looking at the nearest player. Waving and bubbles follow you.
	local dist = selfDist
	local lookDist = if focus
		then (Vector3.new(focus.X, 0, focus.Z) - Vector3.new(rig.root.Position.X, 0, rig.root.Position.Z)).Magnitude
		else math.huge
	local wantYaw, wantPitch = 0, 0
	local neck = rig.neck
	if focusHead and neck and lookDist < LOOK_RANGE then
		local pivot = rig.torso.CFrame * neck.C0
		local rel = pivot:PointToObjectSpace(focusHead)
		local dx, dy, dz = rel.X, rel.Y - 0.7 * s, rel.Z
		local yaw = math.atan2(-dx, -dz)
		if math.abs(yaw) < 1.9 then
			wantYaw = math.clamp(yaw, -1.15, 1.15)
			wantPitch = math.clamp(math.atan2(dy, math.sqrt(dx * dx + dz * dz)), -0.45, 0.45)
		end
	end

	-- Waving hello.
	if dist > WAVE_RESET then
		rig.waved = false
	end
	if dist < WAVE_RANGE and not rig.waved and now - rig.lastWave > WAVE_COOLDOWN then
		rig.waved = true
		rig.lastWave = now
		rig.waveStart = now
		-- A new player's first hello from Murph is one short tip. Everyone
		-- else waves with a greeting, unless the tutorial has Murph quiet.
		local tipped = false
		local progress = playerContext().progress
		if npc and npc.tips and not rig.met and progress.loaded and progress.newPlayer then
			local line, kind = takeLine(rig, true)
			if kind == "tip" and line then
				say(rig, line, now)
				rig.nextLine = math.max(rig.nextLine, now + 6)
				tipped = true
			end
		end
		if not tipped and npc and not quiet(rig) and #npc.greetings > 0 then
			say(rig, npc.greetings[rig.rng:NextInteger(1, #npc.greetings)], now)
			rig.nextLine = math.max(rig.nextLine, now + 4.5)
		end
	end
	local wave = envelope(now - rig.waveStart, WAVE_TIME, 0.3, 0.35)

	-- Idle flourishes (not while walking or waving).
	local fl = rig.flourish
	if fl and now - fl.start > fl.length then
		rig.flourish = nil
		fl = nil
	end
	local idleKind = if npc then npc.idle else nil
	local def = if idleKind then FLOURISHES[idleKind] else nil
	if def and idleKind and not fl and now >= rig.flourishAt then
		rig.flourishAt = now + def.length + rig.rng:NextNumber(def.gap[1], def.gap[2])
		if w < 0.1 and wave <= 0 then
			fl = { kind = idleKind, start = now, length = def.length }
			rig.flourish = fl
		end
	end
	local f, ft, flLength = 0, 0, 1
	if fl then
		ft = now - fl.start
		flLength = fl.length
		f = envelope(ft, flLength, 0.35, 0.4)
	end
	local kind = if fl then fl.kind else ""

	-- Head: looking at you beats looking around.
	if kind == "lookAround" and wantYaw == 0 then
		wantYaw = 0.65 * math.sin(ft / flLength * math.pi * 2) * f
	elseif kind == "clipboard" then
		wantYaw, wantPitch = wantYaw * (1 - f) + 0.25 * f, wantPitch * (1 - f) - 0.4 * f
	elseif kind == "sip" then
		wantPitch = wantPitch * (1 - f) + 0.22 * f
	end
	rig.yaw = approach(rig.yaw, wantYaw, 6, dt)
	rig.pitch = approach(rig.pitch, wantPitch, 6, dt)

	-- Walk, a held prop, a work clip, and a talking gesture (NPCAnim).
	-- Flourishes and the wave still win the arms, below.
	local work = if npc then npc.work else nil
	local timed = work == "chop" or work == "saw" or work == "sweep"
	if rig.working and now - rig.workStart > rig.workLength then
		rig.working = false
	end
	if timed and work and not rig.working and now >= rig.nextWork and w < 0.15 and wave <= 0 and not fl then
		local loops = if npc and npc.workLoops and npc.workLoops > 0 then npc.workLoops else 1
		local length = NPCAnim.Length(work) * loops
		if length > 0 then
			rig.working = true
			rig.workStart = now
			rig.workLength = length
			rig.nextWork = now + length + rig.rng:NextNumber(6, 12)
		end
	end
	local workWeight = 0
	local workU = 0
	local workTime = 0
	if rig.working and work then
		local elapsed = now - rig.workStart
		workWeight = envelope(elapsed, rig.workLength, 0.18, 0.25)
		local clip = NPCAnim.Length(work)
		workU = if clip > 0 then (elapsed % clip) / clip else 0
		workTime = elapsed
	end
	local spokenFor = if rig.bubble then now - (rig.bubbleUntil - rig.bubbleLength) else 0
	local talking = if rig.bubble then math.max(0, 1 - spokenFor / 1.6) else 0
	local carry = if npc and NPCAnim.Holds(npc.look.carry) then npc.look.carry else nil
	local sample = NPCAnim.Sample({
		phase = phase,
		walk = w,
		carry = carry,
		work = work,
		workU = workU,
		workTime = workTime,
		workWeight = if fl then 0 else workWeight,
		talkTime = spokenFor,
		talkWeight = if fl or wave > 0 then 0 else talking,
		breath = breath,
	})

	-- Arms and legs. Flourishes pose over the sample.
	local left = limb(sample.leftPitch, sample.leftYaw, sample.leftRoll)
	local right = limb(sample.rightPitch, sample.rightYaw, sample.rightRoll)
	if kind == "sip" then
		-- The mug up to the mouth: raise forward, swing in.
		left = CFrame.Angles(0, -0.55 * f, 0) * CFrame.Angles(1.85 * f, 0, 0)
	elseif kind == "clipboard" then
		left = CFrame.Angles(0, -0.3 * f, 0) * CFrame.Angles(0.55 * f, 0, 0)
	elseif kind == "glasses" then
		right = CFrame.Angles(0, 0.62 * f, 0) * CFrame.Angles(2.35 * f, 0, 0)
	elseif kind == "wipe" then
		local rub = math.sin(ft * 9) * 0.18 * f
		right = CFrame.Angles(0, (0.75 + rub) * f, 0) * CFrame.Angles(2.45 * f, 0, 0)
		rig.pitch = approach(rig.pitch, -0.12 * f, 6, dt)
	end
	if wave > 0 then
		local wiggle = math.sin((now - rig.waveStart) * 13) * 0.3 * smooth((now - rig.waveStart - 0.25) / 0.2)
		right = right:Lerp(CFrame.Angles(0.15, 0, 2.75 + wiggle), wave)
	end

	setTransform(
		rig.rootJoint,
		CFrame.new(0, (sample.bob + 0.03 * breath) * s, 0) * CFrame.Angles(sample.rootPitch, sample.rootYaw, 0)
	)
	setTransform(
		rig.neck,
		CFrame.Angles(0, rig.yaw + sample.neckYaw, 0)
			* CFrame.Angles(rig.pitch + sample.neckPitch, 0, sample.neckRoll + 0.08 * wave)
	)
	setTransform(rig.leftShoulder, left)
	setTransform(rig.rightShoulder, right)
	-- Walker legs are posed every frame in presentWalkers. Idle hips stay here.
	if not route then
		setTransform(rig.leftHip, CFrame.Angles(sample.leftHip, 0, 0))
		setTransform(rig.rightHip, CFrame.Angles(sample.rightHip, 0, 0))
	end

	-- Blinking.
	if now >= rig.blinkAt then
		rig.blinkUntil = now + BLINK_TIME
		rig.blinkAt = now + rig.rng:NextNumber(2.2, 5.5)
		-- A coarse quality step outlasts a blink, which would leave the
		-- eyes shut until the next sample. Reschedule and skip the pose.
		if dt < BLINK_TIME then
			for _, eye in ipairs(rig.eyes) do
				eye.part.Size = Vector3.new(eye.size.X, 0.04 * s, eye.size.Z)
				if eye.shine then
					eye.shine.Transparency = 1
				end
			end
		end
	elseif rig.blinkUntil > 0 and now >= rig.blinkUntil then
		rig.blinkUntil = 0
		for _, eye in ipairs(rig.eyes) do
			eye.part.Size = eye.size
			if eye.shine then
				eye.shine.Transparency = 0
			end
		end
	end

	-- Bubbles time out (or close when you walk away).
	if rig.bubble and (now >= rig.bubbleUntil or dist > TALK_RANGE * 2.5) then
		closeBubble(rig)
	end
end

-- Nearby players, refreshed a few times a second (12 of them is still cheap,
-- and the head lerp covers the gap).
local bodies: { Vector3 } = {}
local bodyHeads: { Vector3 } = {}
local bodiesAt = -1

local function nearbyBodies(now: number)
	if now - bodiesAt < 0.15 then
		return
	end
	bodiesAt = now
	table.clear(bodies)
	table.clear(bodyHeads)
	for _, other in ipairs(Players:GetPlayers()) do
		local char = other.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if root and root:IsA("BasePart") then
			table.insert(bodies, root.Position)
			local head = char:FindFirstChild("Head")
			table.insert(
				bodyHeads,
				if head and head:IsA("BasePart") then head.Position else root.Position + Vector3.new(0, 1.5, 0)
			)
		end
	end
end

local function walkerOnScreen(pos: Vector3): boolean
	local camera = workspace.CurrentCamera
	if camera == nil then
		return true
	end
	if (pos - camera.CFrame.Position).Magnitude > WALKER_RANGE then
		return false
	end
	local point, visible = camera:WorldToViewportPoint(pos)
	return visible and point.Z > 0
end

-- Every rendered frame, ahead of the cosmetic gate: the shared-clock pose,
-- eased, on the sampled ground. Legs swing with it so a 2 Hz cosmetic
-- tier does not teleport the stride.
local function presentWalkers(dt: number)
	nearbyBodies(os.clock())
	for model, rig in pairs(rigs) do
		local route = rig.route
		local ground = rig.ground
		if not route or not ground or not model.Parent then
			continue
		end
		local x, z, heading, isMoving, walked =
			NPCData.RouteState(route, rig.speed, workspace:GetServerTimeNow() + rig.offset)
		local feet = NPCWalk.FeetAt(ground, route, x, z)
		local target: NPCWalk.Pose = {
			x = x,
			y = NPCWalk.RootY(feet, rig.rootHeight),
			z = z,
			yaw = heading,
			moving = isMoving,
			walked = walked,
		}
		local visual, snapped = NPCWalk.Follow(rig.visual, target, dt, rig.speed, walkerOnScreen(rig.root.Position))
		rig.visual = visual
		if snapped then
			rig.bodyYaw = visual.yaw
		end
		local yaw = visual.yaw
		if isMoving then
			rig.bodyYaw = visual.yaw
		else
			local at = Vector3.new(visual.x, visual.y, visual.z)
			local index = NPCData.NearestIndex(at, bodies, NPCData.FaceRange)
			local focus = if index then bodies[index] else nil
			local want = NPCData.FaceYaw(visual.yaw, at, focus, NPCData.FaceRange)
			rig.bodyYaw = NPCData.TurnToward(rig.bodyYaw, want, NPCData.TurnRate * dt)
			yaw = rig.bodyYaw
		end
		rig.root.CFrame = CFrame.new(visual.x, visual.y, visual.z) * CFrame.Angles(0, yaw, 0)
		rig.moving = isMoving
		rig.walked = visual.walked
		rig.walkBlend = approach(rig.walkBlend, if isMoving then 1 else 0, 8, dt)
		rig.phase = NPCWalk.Phase(visual.walked, rig.scale)
		if isMoving or rig.walkBlend > 0.01 then
			local leftHip, rightHip = NPCAnim.Walk(rig.phase, rig.walkBlend)
			setTransform(rig.leftHip, CFrame.Angles(leftHip, 0, 0))
			setTransform(rig.rightHip, CFrame.Angles(rightHip, 0, 0))
		end
	end
end

local sinceCosmetic = 0

-- While a walker is inside StreamingMinRadius, give missed ground another
-- look. One pass a second, a few rays, and never from the per-frame walk.
local lastGroundRetry = -1e9
local function retryGround(now: number)
	if now - lastGroundRetry < NPCWalk.RetryGap then
		return
	end
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end
	local mine = hrp.Position
	local near = false
	for _, rig in pairs(rigs) do
		local ground = rig.ground
		if ground and #ground.misses > 0 and (rig.root.Position - mine).Magnitude <= NPCWalk.RetryRadius then
			near = true
			break
		end
	end
	if not near then
		return
	end
	lastGroundRetry = now
	local probe = groundProbe()
	for _, rig in pairs(rigs) do
		local ground = rig.ground
		if ground and (rig.root.Position - mine).Magnitude <= NPCWalk.RetryRadius then
			NPCWalk.Retry(ground, probe)
		end
	end
end

local function step(dt: number)
	sinceCosmetic += dt
	local elapsed = sinceCosmetic
	local cosmetic = QualityBudgets.CosmeticDue(Quality.Budget().CosmeticHz, sinceCosmetic)
	if cosmetic then
		sinceCosmetic = 0
		local now = os.clock()
		refreshLayout(now)
		nearbyBodies(now)
		local char = player.Character
		local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
		local mine: Vector3? = if hrp and hrp:IsA("BasePart") then hrp.Position else nil
		local camera = workspace.CurrentCamera
		local eye = mine or (if camera then camera.CFrame.Position else Vector3.zero)

		-- Who gets to chat: the nearest NPC within TALK_RANGE of you.
		local speaker: Rig? = nil
		local speakerDist = TALK_RANGE
		for model, rig in pairs(rigs) do
			if not model.Parent then
				if rig.promptConn then
					rig.promptConn:Disconnect()
				end
				rigs[model] = nil
				continue
			end
			local d = (rig.root.Position - eye).Magnitude
			if d > ANIMATE_RANGE then
				if rig.active then
					rig.active = false
					rest(rig)
				end
				continue
			end
			local index = NPCData.NearestIndex(rig.root.Position, bodies, LOOK_RANGE)
			local focus = if index then bodies[index] else nil
			local focusHead = if index then bodyHeads[index] else nil
			rig.active = true
			animate(rig, now, elapsed, focus, focusHead, d)
			if rig.bubble then
				placeBubble(rig)
			end
			local wantsTip = rig.npc ~= nil and rig.npc.tips ~= nil and not rig.met
			if d < speakerDist and (wantsTip or not quiet(rig)) then
				speaker, speakerDist = rig, d
			end
		end

		local who = speaker
		if who and not who.bubble and now >= who.nextLine then
			local wantsTip = who.npc ~= nil and who.npc.tips ~= nil and not who.met
			if wantsTip or not quiet(who) then
				local loaded = player:GetAttribute("ProfileLoaded") == true
				if wantsTip and not loaded then
					who.nextLine = now + 1 -- the save isn't here yet; don't burn the tip
				else
					local line, kind = takeLine(who, true)
					if line and (kind == "tip" or not quiet(who)) then
						say(who, line, now)
					end
					local gap = NPCDialogue.AmbientGap
					who.nextLine = now + who.rng:NextNumber(gap[1], gap[2])
				end
			end
		end
	end
	presentWalkers(dt)
	retryGround(os.clock())
end

function NPCController.Start()
	refreshLayout(os.clock())
	for _, model in ipairs(CollectionService:GetTagged("NPC")) do
		bind(model)
	end
	CollectionService:GetInstanceAddedSignal("NPC"):Connect(function(model: Instance)
		bind(model)
	end)
	CollectionService:GetInstanceRemovedSignal("NPC"):Connect(unbind)
	-- Before physics, so the joints' Transforms are in place for this frame.
	RunService.PreSimulation:Connect(step)
end

return NPCController
