--!strict
-- NPCController: the townsfolk come alive on this client (NPCService builds
-- them; Shared/NPCData says who they are). Everything here is local: joints
-- move through Motor6D.Transform and walkers through their anchored root,
-- neither of which replicates, so it costs the server nothing.
--   * Idle: breathing, blinking, now and then a flourish of their own
--     (Murph sips his coffee, Millie checks her clipboard, Tink pushes his
--     glasses up, Dale wipes his brow, the others look around).
--   * They turn their head to look at you when you're near, and wave the
--     first time you come within WAVE_RANGE (again after you've wandered
--     off for a while), with a greeting.
--   * Walkers stroll their loop (NPCData.RouteState from the shared server
--     clock, so everyone sees them in the same place) swinging arms and
--     legs, and pause at their waypoints.
--   * The nearest NPC within TALK_RANGE says one of their lines in a speech
--     bubble every so often. Murph keeps quiet while your tutorial runs
--     (QuestUI owns his lines then); he still looks at you and waves.
--   * Beyond ANIMATE_RANGE they're left alone (joints reset), walkers just
--     keep their place on the route.
-- Streaming-tolerant: NPCs are found by the "NPC" tag as they stream in
-- and dropped as they stream out.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local NPCData = require(ReplicatedStorage.Shared.NPCData)
local SoundData = require(ReplicatedStorage.Shared.SoundData)

local NPCController = {}

local player = Players.LocalPlayer

local ANIMATE_RANGE = 120
local WALKER_RANGE = 300 -- walkers keep their place on the route this far out
local LOOK_RANGE = 22
local WAVE_RANGE = 14
local WAVE_RESET = 30 -- wander this far off and they'll wave again...
local WAVE_COOLDOWN = 45 -- ...but not more often than this
local TALK_RANGE = 16
local TALK_GAP = { 9, 16 } -- seconds between lines
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
	groundY: number,
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
}

local rigs: { [Model]: Rig } = {}

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

local function say(rig: Rig, text: string, now: number)
	closeBubble(rig, true)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SpeechBubble"
	gui.Size = UDim2.fromOffset(260, 140)
	gui.StudsOffset = Vector3.new(0, rig.topOffset + 0.4 * rig.scale, 0)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.MaxDistance = 70
	gui.LightInfluence = 0
	gui.Adornee = rig.head

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -14)
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
	label.TextSize = 16
	label.TextColor3 = INK
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = card
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(230, 400)
	limit.Parent = label
	-- The tail under the card.
	local tail = Instance.new("TextLabel")
	tail.Name = "Tail"
	tail.BackgroundTransparency = 1
	tail.AnchorPoint = Vector2.new(0.5, 0)
	tail.Position = UDim2.new(0.5, 0, 1, -17)
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
	rig.bubbleLength = math.min(8, 2.6 + #text * 0.045)
	rig.bubbleUntil = now + rig.bubbleLength
	SoundData.PlayAt("NPCChatter", rig.head.Position)
end

-- A line from the NPC's list, in a shuffled order that doesn't repeat until
-- all have been said.
local function nextLine(rig: Rig): string?
	local npc = rig.npc
	if not npc or #npc.lines == 0 then
		return nil
	end
	if #rig.bag == 0 then
		for i = 1, #npc.lines do
			table.insert(rig.bag, rig.rng:NextInteger(1, #rig.bag + 1), i)
		end
	end
	local i = table.remove(rig.bag)
	return if i then npc.lines[i] else nil
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
	local routeText = model:GetAttribute("Route")
	local route = if type(routeText) == "string" then NPCData.DecodeRoute(routeText) else nil
	local rootHeight = model:GetAttribute("RootHeight")
	local rh = if type(rootHeight) == "number" then rootHeight else 3
	local scaleAttr = model:GetAttribute("Scale")
	local topAttr = model:GetAttribute("TopOffset")
	local speed = model:GetAttribute("Speed")
	local offset = model:GetAttribute("RouteOffset")
	local seed = seedOf(model.Name)
	local tag = head:FindFirstChild("NameTag")
	local now = os.clock()
	local rng = Random.new(seed + math.floor(now * 1000) % 1000)
	rigs[model] = {
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
		tag = if tag and tag:IsA("BillboardGui") then tag else nil,
		route = if route and #route >= 2 then route else nil,
		speed = if type(speed) == "number" then speed else 4,
		offset = if type(offset) == "number" then offset else 0,
		rootHeight = rh,
		groundY = root.Position.Y - rh,
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
	}
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
	closeBubble(rig, true)
end

local function unbind(model: Instance)
	local rig = rigs[model :: Model]
	if rig then
		rigs[model :: Model] = nil
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

local function animate(rig: Rig, now: number, dt: number, focus: Vector3?, focusHead: Vector3?)
	local s = rig.scale
	local npc = rig.npc

	-- Walking: the route from the shared clock.
	local moving, walked = false, 0
	local route = rig.route
	if route then
		local x, z, heading, isMoving, dist =
			NPCData.RouteState(route, rig.speed, workspace:GetServerTimeNow() + rig.offset)
		rig.root.CFrame = CFrame.new(x, rig.groundY + rig.rootHeight, z) * CFrame.Angles(0, heading, 0)
		moving, walked = isMoving, dist
	end
	rig.walkBlend = approach(rig.walkBlend, if moving then 1 else 0, 8, dt)
	local w = rig.walkBlend
	local stride = 4.2 * s
	local phase = walked / stride * math.pi * 2
	local swing = math.sin(phase)

	-- Breathing.
	local breath = math.sin(now * 1.7 + rig.seed % 7)
	local bob = 0.03 * breath * s + math.abs(math.sin(phase)) * 0.12 * s * w

	-- Looking at you.
	local dist = if focus
		then (Vector3.new(focus.X, 0, focus.Z) - Vector3.new(rig.root.Position.X, 0, rig.root.Position.Z)).Magnitude
		else math.huge
	local wantYaw, wantPitch = 0, 0
	local neck = rig.neck
	if focusHead and neck and dist < LOOK_RANGE then
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
		if npc and not quiet(rig) and #npc.greetings > 0 then
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

	-- Arms and legs.
	local legSwing = 0.6 * swing * w
	local armSwing = 0.45 * swing * w
	local carried = if npc and npc.look.carry and npc.look.carry ~= "none" then 0.5 else 1
	local left = CFrame.Angles(-armSwing * carried, 0, -0.03 * breath * (1 - w))
	local right = CFrame.Angles(armSwing, 0, 0.03 * breath * (1 - w))
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

	-- A little nodding while they talk (the first second or two of a line).
	local talking = if rig.bubble then math.max(0, 1 - (now - (rig.bubbleUntil - rig.bubbleLength)) / 1.6) else 0
	local nod = 0.06 * math.sin(now * 11) * talking

	setTransform(rig.rootJoint, CFrame.new(0, bob, 0) * CFrame.Angles(0.04 * w, 0, 0))
	setTransform(rig.neck, CFrame.Angles(0, rig.yaw, 0) * CFrame.Angles(rig.pitch + nod, 0, 0.08 * wave))
	setTransform(rig.leftShoulder, left)
	setTransform(rig.rightShoulder, right)
	setTransform(rig.leftHip, CFrame.Angles(legSwing, 0, 0))
	setTransform(rig.rightHip, CFrame.Angles(-legSwing, 0, 0))

	-- Blinking.
	if now >= rig.blinkAt then
		rig.blinkUntil = now + BLINK_TIME
		rig.blinkAt = now + rig.rng:NextNumber(2.2, 5.5)
		for _, eye in ipairs(rig.eyes) do
			eye.part.Size = Vector3.new(eye.size.X, 0.04 * s, eye.size.Z)
			if eye.shine then
				eye.shine.Transparency = 1
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

local function step(dt: number)
	local now = os.clock()
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	local headPart = if char then char:FindFirstChild("Head") else nil
	local focus: Vector3? = if hrp and hrp:IsA("BasePart") then hrp.Position else nil
	local focusHead: Vector3? = if headPart and headPart:IsA("BasePart")
		then headPart.Position
		elseif focus then focus + Vector3.new(0, 1.5, 0)
		else nil
	local camera = workspace.CurrentCamera
	local eye = focus or (if camera then camera.CFrame.Position else Vector3.zero)

	-- Who gets to chat: the nearest NPC within TALK_RANGE.
	local speaker: Rig? = nil
	local speakerDist = TALK_RANGE
	for model, rig in pairs(rigs) do
		if not model.Parent then
			rigs[model] = nil
			continue
		end
		local d = (rig.root.Position - eye).Magnitude
		if d > ANIMATE_RANGE then
			if rig.active then
				rig.active = false
				rest(rig)
			end
			-- Far walkers keep their place on the route (cheap).
			local route = rig.route
			if route and d < WALKER_RANGE then
				local x, z, heading = NPCData.RouteState(route, rig.speed, workspace:GetServerTimeNow() + rig.offset)
				rig.root.CFrame = CFrame.new(x, rig.groundY + rig.rootHeight, z) * CFrame.Angles(0, heading, 0)
			end
			continue
		end
		rig.active = true
		animate(rig, now, dt, focus, focusHead)
		if d < speakerDist and not quiet(rig) then
			speaker, speakerDist = rig, d
		end
	end

	local who = speaker
	if who and not who.bubble and now >= who.nextLine then
		local line = nextLine(who)
		if line then
			say(who, line, now)
		end
		who.nextLine = now + who.rng:NextNumber(TALK_GAP[1], TALK_GAP[2])
	end
end

function NPCController.Start()
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
