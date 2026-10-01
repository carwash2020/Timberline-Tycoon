--!strict
-- ForestUI: the Living Forest on screen (GAME_DESIGN §16). The server
-- (ForestService) owns everything; this draws it.
--   * The Heartseed pouch: a small chip under the clock (never over the
--     cash) with your seed count; tap it for the count of each wood. It
--     bumps when seeds arrive.
--   * "Plant Heartseed (n)" on every stump you hold that wood's seed for
--     (tag "Stump", attributes WoodId / TreeUid; F or Y), and a little
--     glowing seed over the nearest plantable stumps so you can find them.
--   * Seeds popping out of a felled tree and flying to whoever felled it,
--     a sapling sprouting where someone planted, the sawmill's figure
--     reveal (a big colour-coded stamp per figure, rarer ones stay longer).
--   * Toasts: your planted tree harvested (the planter's share), lightning
--     striking a tree near you, Elders waking, falling and fading (with a
--     marker over the Elder you can see from afar), the Skyroot Bloom
--     (golden motes pouring off the Skyroot while it lasts).
-- Everything 3D is local, pooled and culled by distance; the streamed
-- world is only read through tags and attributes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local ForestData = require(ReplicatedStorage.Shared.ForestData)
local ForestLogic = require(ReplicatedStorage.Shared.ForestLogic)
local Net = require(ReplicatedStorage.Shared.Net)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local Util = require(ReplicatedStorage.Shared.Util)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local ForestArt = require(ReplicatedStorage.Shared.Art.ForestArt)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local CameraShake = require(script.Parent.CameraShake)
local HUD = require(script.Parent.HUD)
local UITheme = require(script.Parent.UITheme)

type FigureDef = ForestData.FigureDef

local ForestUI = {}

local C = UITheme.Colors
local F = UITheme.Fonts

local player = Players.LocalPlayer

local FX_RANGE = 180 -- studs from the camera: seed pops and sprouts farther away aren't drawn
local STRIKE_TOAST_RANGE = 260 -- lightning this close to you gets a toast
local MAX_ORBS = 16
local ORB_SECONDS = 0.95
local MARKERS = 3 -- plantable stumps marked at once
local MARKER_RANGE = 70
local LOOP_SECONDS = 0.4

local fxFolder: Folder? = nil
local pouchChip: TextButton? = nil
local pouchLabel: TextLabel? = nil
local pouchBump: UIScale? = nil
local pouchPopup: Frame? = nil
local pouchPopupText: TextLabel? = nil
local revealGui: ScreenGui? = nil

local function fx(): Folder
	local folder = fxFolder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "ForestFX"
	f.Parent = workspace
	fxFolder = f
	return f
end

local function rootPosition(): Vector3?
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	return if hrp then hrp.Position else nil
end

local function nearCamera(point: Vector3, range: number): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - point).Magnitude <= range
end

local function woodName(woodId: string): string
	local def = WoodData.Get(woodId)
	return if def then def.displayName else woodId
end

local function seedsOf(woodId: string): number
	local n = player:GetAttribute("Seeds_" .. woodId)
	return if type(n) == "number" then n else 0
end

-- Ink on light colours, cream on dark ones.
local function inkFor(color: Color3): Color3
	local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	return if luminance > 0.55 then C.Ink else C.Cream
end

---------------------------------------------------------------------------
-- The Heartseed pouch
---------------------------------------------------------------------------

local function refreshPouchPopup()
	local text = pouchPopupText
	if not text then
		return
	end
	local lines: { string } = {}
	for _, wood in ipairs(WoodData.All()) do
		local n = seedsOf(wood.id)
		if n > 0 then
			table.insert(
				lines,
				string.format(
					'<font color="#%s">●</font> %s  <b>%d</b>',
					wood.leafColor:ToHex(),
					UITheme.escape(wood.displayName),
					n
				)
			)
		end
	end
	if #lines == 0 then
		table.insert(lines, "No seeds yet. Fell a tree!")
	end
	local s = ForestData.Seeds
	table.insert(lines, string.format('<font size="11">Holds %d of a wood, %d in all</font>', s.maxPerWood, s.maxTotal))
	text.Text = table.concat(lines, "\n")
end

local popupToken = 0
local function showPouchPopup(show: boolean)
	local popup = pouchPopup
	if not popup then
		return
	end
	popupToken += 1
	popup.Visible = show
	if show then
		refreshPouchPopup()
		local token = popupToken
		task.delay(6, function()
			if popupToken == token and popup.Visible then
				popup.Visible = false
			end
		end)
	end
end

local lastTotal = 0
local function refreshPouch()
	local chip, label = pouchChip, pouchLabel
	if not chip or not label then
		return
	end
	local total = player:GetAttribute("Heartseeds")
	local n = if type(total) == "number" then total else 0
	chip.Visible = n > 0
	label.Text = tostring(n)
	local bump = pouchBump
	if bump and n > lastTotal then
		bump.Scale = 1.3
		TweenService:Create(bump, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
			:Play()
	end
	lastTotal = n
	local popup = pouchPopup
	if popup and popup.Visible then
		if n > 0 then
			refreshPouchPopup()
		else
			popup.Visible = false
		end
	end
end

local function buildPouch()
	local gui = UITheme.Screen("HeartseedPouch", 9)
	local side = UITheme.Margin()
	-- Under the clock (which sits left of the cash plaque), clear of the
	-- Daily Goals button under the cash.
	local chip = Instance.new("TextButton")
	chip.Name = "Pouch"
	chip.AnchorPoint = Vector2.new(1, 0)
	chip.Position = UDim2.new(1, -(side + 214), 0, 50)
	chip.Size = UDim2.fromOffset(84, 26)
	chip.BackgroundColor3 = C.Bark
	chip.AutoButtonColor = true
	chip.Text = ""
	chip.Visible = false
	UITheme.corner(chip, 13)
	UITheme.stroke(chip, C.Ink, 2)
	local bump = Instance.new("UIScale")
	bump.Parent = chip

	local seed = Instance.new("Frame")
	seed.Name = "Seed"
	seed.AnchorPoint = Vector2.new(0, 0.5)
	seed.Position = UDim2.new(0, 8, 0.5, 1)
	seed.Size = UDim2.fromOffset(15, 15)
	seed.BackgroundColor3 = ForestArt.HeartseedColor
	UITheme.corner(seed, 8)
	UITheme.stroke(seed, C.Ink, 1.5)
	seed.Parent = chip
	local leaf = Instance.new("Frame")
	leaf.Name = "Leaf"
	leaf.Position = UDim2.fromOffset(9, -6)
	leaf.Size = UDim2.fromOffset(6, 9)
	leaf.Rotation = 35
	leaf.BackgroundColor3 = Color3.fromRGB(96, 170, 70)
	UITheme.corner(leaf, 3)
	leaf.Parent = seed

	local label = UITheme.label(chip, "0", F.Black, 14, C.Cream)
	label.Position = UDim2.fromOffset(28, 0)
	label.Size = UDim2.new(1, -34, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left

	local card = UITheme.Card(C.Paper, C.Ink, 2, 12, true)
	card.outer.Name = "PouchList"
	card.outer.AnchorPoint = Vector2.new(1, 0)
	card.outer.Position = UDim2.new(1, -(side + 214), 0, 80)
	card.outer.Visible = false
	UITheme.stroke(card.face, C.Bark, 2)
	UITheme.padding(card.face, 6, 10, 6, 10)
	local text = UITheme.label(card.face, "", F.Bold, 13, C.Ink)
	text.RichText = true
	text.AutomaticSize = Enum.AutomaticSize.XY
	text.LineHeight = 1.15
	card.outer.Parent = gui

	chip.Parent = gui
	chip.Activated:Connect(function()
		showPouchPopup(not card.outer.Visible)
	end)
	gui.Parent = player:WaitForChild("PlayerGui")

	pouchChip, pouchLabel, pouchBump, pouchPopup, pouchPopupText = chip, label, bump, card.outer, text
	player:GetAttributeChangedSignal("Heartseeds"):Connect(refreshPouch)
	local total = player:GetAttribute("Heartseeds")
	lastTotal = if type(total) == "number" then total else 0
	refreshPouch()
end

---------------------------------------------------------------------------
-- Stumps: the planting prompt and the "plant here" markers
---------------------------------------------------------------------------

type StumpEntry = { model: Model, part: BasePart, prompt: ProximityPrompt, woodId: string, uid: string }

local stumps: { [Model]: StumpEntry } = {}
local sproutingUntil: { [string]: number } = {} -- tree uid -> os.clock() its sprout ends

local function plantable(entry: StumpEntry): boolean
	local busy = sproutingUntil[entry.uid]
	return seedsOf(entry.woodId) > 0
		and entry.part.Parent ~= nil
		and entry.part.Transparency < 1 -- hidden stumps (the Phantom Grove by day)
		and not (busy and os.clock() < busy)
end

local function refreshPrompt(entry: StumpEntry)
	local text = string.format("Plant Heartseed (%d)", seedsOf(entry.woodId))
	if entry.prompt.ActionText ~= text then
		entry.prompt.ActionText = text
	end
	local on = plantable(entry)
	if entry.prompt.Enabled ~= on then
		entry.prompt.Enabled = on
	end
end

local function refreshPrompts()
	for _, entry in pairs(stumps) do
		refreshPrompt(entry)
	end
end

local function addStump(inst: Instance)
	if not inst:IsA("Model") or stumps[inst] then
		return
	end
	local model = inst
	local woodId = model:GetAttribute("WoodId")
	local uid = model:GetAttribute("TreeUid")
	if type(woodId) ~= "string" or type(uid) ~= "string" then
		return
	end
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not part then
		-- Atomic models stream in whole, but be patient with a slow one.
		model.ChildAdded:Once(function()
			addStump(model)
		end)
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlantHeartseed"
	prompt.ObjectText = woodName(woodId) .. " stump"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = ForestData.PlantRange - 2 -- the server allows a little more
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	local entry: StumpEntry = { model = model, part = part, prompt = prompt, woodId = woodId, uid = uid }
	prompt.Triggered:Connect(function()
		Net.Remote("PlantSeed"):FireServer(uid)
	end)
	stumps[model] = entry
	refreshPrompt(entry)
end

local function removeStump(inst: Instance)
	local entry = if inst:IsA("Model") then stumps[inst] else nil
	if entry then
		stumps[inst :: Model] = nil
		entry.prompt:Destroy()
	end
end

-- Little glowing seeds bobbing over the nearest stumps you can plant in.
type Marker = { part: Part, gui: BillboardGui }
local markers: { Marker } = {}

local function buildMarkers()
	for i = 1, MARKERS do
		local part = Instance.new("Part")
		part.Name = "PlantMarker" .. i
		part.Anchored = true
		part.Transparency = 1
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		Kit.decor(part, false)
		part.Parent = fx()
		local gui = Instance.new("BillboardGui")
		gui.Name = "PlantHere"
		gui.Size = UDim2.fromOffset(34, 34)
		gui.LightInfluence = 0
		gui.AlwaysOnTop = true
		gui.MaxDistance = MARKER_RANGE
		gui.Enabled = false
		gui.Adornee = part
		gui.Parent = part
		local holder = Instance.new("Frame")
		holder.Size = UDim2.fromScale(1, 1)
		holder.BackgroundTransparency = 1
		holder.Parent = gui
		local seed = Instance.new("Frame")
		seed.Name = "Seed"
		seed.AnchorPoint = Vector2.new(0.5, 0.5)
		seed.Position = UDim2.fromScale(0.5, 0.6)
		seed.Size = UDim2.fromOffset(18, 18)
		seed.BackgroundColor3 = ForestArt.HeartseedColor
		UITheme.corner(seed, 9)
		UITheme.stroke(seed, C.Ink, 2)
		seed.Parent = holder
		local leaf = Instance.new("Frame")
		leaf.Position = UDim2.fromOffset(11, -7)
		leaf.Size = UDim2.fromOffset(7, 11)
		leaf.Rotation = 35
		leaf.BackgroundColor3 = Color3.fromRGB(96, 170, 70)
		UITheme.corner(leaf, 3)
		leaf.Parent = seed
		-- A gentle bob, forever (one tween per marker, made once).
		TweenService:Create(
			seed,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = UDim2.fromScale(0.5, 0.35) }
		):Play()
		table.insert(markers, { part = part, gui = gui })
	end
end

local function updateMarkers()
	local from = rootPosition()
	local best: { { entry: StumpEntry, d: number } } = {}
	if from then
		for _, entry in pairs(stumps) do
			if entry.prompt.Enabled then
				local d = (entry.part.Position - from).Magnitude
				if d <= MARKER_RANGE then
					table.insert(best, { entry = entry, d = d })
				end
			end
		end
		table.sort(best, function(a, b)
			return a.d < b.d
		end)
	end
	for i, marker in ipairs(markers) do
		local pick = best[i]
		if pick then
			local p = pick.entry.part
			marker.part.CFrame = CFrame.new(p.Position + Vector3.new(0, p.Size.X / 2 + 2.6, 0))
			-- Close enough to see the prompt: the prompt says it all.
			marker.gui.Enabled = pick.d > ForestData.PlantRange - 2
		else
			marker.gui.Enabled = false
		end
	end
end

---------------------------------------------------------------------------
-- Seeds flying to the feller
---------------------------------------------------------------------------

type Orb = {
	part: Part,
	from: Vector3,
	mid: Vector3,
	target: Player?,
	t: number,
	duration: number,
	last: boolean,
	mine: boolean,
}

local orbPool: { Part } = {}
local orbs: { Orb } = {}
local orbCount = 0 -- orbs that exist (pooled or flying)
local orbConn: RBXScriptConnection? = nil

local function targetOf(target: Player?): Vector3?
	local char = if target then target.Character else nil
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	return if hrp then hrp.Position + Vector3.new(0, 1, 0) else nil
end

local function stepOrbs(dt: number)
	for i = #orbs, 1, -1 do
		local o = orbs[i]
		o.t += dt
		local u = math.clamp(o.t / o.duration, 0, 1)
		local to = targetOf(o.target) or o.mid
		local e = u * u * (3 - 2 * u) -- ease in and out
		local a = o.from:Lerp(o.mid, e)
		local b = o.mid:Lerp(to, e)
		o.part.CFrame = CFrame.new(a:Lerp(b, e))
		if u >= 1 then
			o.part.Parent = nil
			table.insert(orbPool, o.part)
			table.remove(orbs, i)
			if o.mine and o.last then
				SoundData.Play("SeedPop")
			end
		end
	end
	local conn = orbConn
	if #orbs == 0 and conn then
		conn:Disconnect()
		orbConn = nil
	end
end

local function takeOrb(): Part?
	local part = table.remove(orbPool)
	if part then
		return part
	end
	if orbCount >= MAX_ORBS then
		return nil
	end
	orbCount += 1
	return ForestArt.SeedOrb()
end

local function popSeeds(from: Vector3, target: Player?, count: number, mine: boolean)
	local n = math.clamp(count, 1, 5)
	for i = 1, n do
		local part = takeOrb()
		if not part then
			break
		end
		local angle = math.random() * math.pi * 2
		local spread = 2 + math.random() * 2
		local start = from + Vector3.new(0, 1.5, 0)
		part.CFrame = CFrame.new(start)
		part.Parent = fx()
		table.insert(orbs, {
			part = part,
			from = start,
			mid = start + Vector3.new(math.cos(angle) * spread, 7 + math.random() * 2, math.sin(angle) * spread),
			target = target,
			t = -(i - 1) * 0.09, -- one after another
			duration = ORB_SECONDS,
			last = i == n,
			mine = mine,
		})
	end
	if #orbs > 0 and not orbConn then
		orbConn = RunService.Heartbeat:Connect(stepOrbs)
	end
end

local function onSeedPop(payload: { [string]: any })
	local pos, userId, woodId, count = payload.pos, payload.userId, payload.woodId, payload.count
	if typeof(pos) ~= "Vector3" or type(userId) ~= "number" or type(woodId) ~= "string" or type(count) ~= "number" then
		return
	end
	local mine = userId == player.UserId
	if nearCamera(pos, FX_RANGE) then
		popSeeds(pos, Players:GetPlayerByUserId(userId), count, mine)
	elseif mine then
		SoundData.Play("SeedPop")
	end
	if mine then
		local reasons = payload.reasons
		local words: { string } = {}
		if type(reasons) == "table" then
			for _, r in ipairs(reasons) do
				if type(r) == "string" then
					table.insert(words, r)
				end
			end
		end
		-- The flying seed and the pouch say it for a plain drop; toast the
		-- extras, and the very first seeds (so new players learn what they are).
		local firstSeeds = lastTotal <= count
		if #words == 0 and not firstSeeds then
			return
		end
		local why = if #words > 0 then " (" .. table.concat(words, ", ") .. ")" else ""
		if firstSeeds and #words == 0 then
			why = ": plant them in stumps"
		end
		HUD.Toast(string.format("+%d %s Heartseed%s%s", count, woodName(woodId), if count == 1 then "" else "s", why))
	end
end

---------------------------------------------------------------------------
-- A sapling sprouting on a stump
---------------------------------------------------------------------------

local function onSprout(payload: { [string]: any })
	local pos, woodId, uid, seconds = payload.pos, payload.woodId, payload.uid, payload.seconds
	if typeof(pos) ~= "Vector3" or type(woodId) ~= "string" or type(uid) ~= "string" or type(seconds) ~= "number" then
		return
	end
	sproutingUntil[uid] = os.clock() + seconds + 0.5
	refreshPrompts()
	task.delay(seconds + 0.6, function()
		sproutingUntil[uid] = nil
	end)
	local def = WoodData.Get(woodId)
	if not def or not nearCamera(pos, FX_RANGE) then
		return
	end
	local seed = if type(payload.seed) == "number" then payload.seed else 1
	local sprout = ForestArt.Sprout(def, seed)
	Kit.placeAt(sprout, CFrame.new(pos))
	sprout:ScaleTo(0.25) -- a seedling first
	sprout.Parent = fx()
	SoundData.PlayAt("Plant", pos)
	local heart = sprout:FindFirstChild("Heartseed")
	if heart and heart:IsA("BasePart") then
		local burst = Instance.new("ParticleEmitter")
		burst.Color = ColorSequence.new(ForestArt.HeartseedColor)
		burst.LightEmission = 1
		burst.LightInfluence = 0
		burst.Rate = 0
		burst.Lifetime = NumberRange.new(0.8, 1.6)
		burst.Speed = NumberRange.new(3, 6)
		burst.SpreadAngle = Vector2.new(60, 60)
		burst.EmissionDirection = Enum.NormalId.Top
		burst.Acceleration = Vector3.new(0, 2, 0)
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		burst.Parent = heart
		burst:Emit(24)
	end
	-- Grows from a seedling to a sapling, then the tree itself takes over.
	task.spawn(function()
		local t = 0
		while t < seconds and sprout.Parent do
			local u = t / seconds
			sprout:ScaleTo(0.25 + 0.95 * (1 - (1 - u) ^ 2))
			t += task.wait(0.05)
		end
		sprout:Destroy()
	end)
end

---------------------------------------------------------------------------
-- The sawmill's figure reveal
---------------------------------------------------------------------------

type Reveal = { figure: FigureDef, count: number }
local revealQueue: { Reveal } = {}
local revealing = false

local function confetti(gui: ScreenGui, color: Color3)
	for i = 1, 12 do
		local bit = Instance.new("Frame")
		bit.AnchorPoint = Vector2.new(0.5, 0.5)
		bit.Position = UDim2.fromScale(0.5, 0.34)
		bit.Size = UDim2.fromOffset(8, 14)
		bit.BackgroundColor3 = if i % 3 == 0 then C.Cream elseif i % 3 == 1 then color else C.Amber
		bit.BorderSizePixel = 0
		bit.Rotation = math.random(0, 180)
		bit.Parent = gui
		local angle = math.random() * math.pi * 2
		local reach = 160 + math.random() * 120
		local tween = TweenService:Create(bit, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(angle) * reach, 0.34, math.sin(angle) * reach * 0.6 + 40),
			Rotation = bit.Rotation + math.random(-260, 260),
			BackgroundTransparency = 1,
		})
		tween.Completed:Once(function()
			bit:Destroy()
		end)
		tween:Play()
	end
end

local function stamp(gui: ScreenGui, figure: FigureDef, count: number)
	local group = Instance.new("CanvasGroup")
	group.Name = "Stamp_" .. figure.id
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.34)
	group.Size = UDim2.fromOffset(400, 150)
	group.BackgroundTransparency = 1
	group.GroupTransparency = 1
	local scale = Instance.new("UIScale")
	scale.Scale = 2.3
	scale.Parent = group

	local ink = inkFor(figure.color)
	local card = UITheme.Card(figure.color, Kit.shade(figure.color, -0.35), 6, 20)
	card.outer.Name = "Card"
	card.outer.AnchorPoint = Vector2.new(0.5, 0.5)
	card.outer.Position = UDim2.fromScale(0.5, 0.5)
	card.outer.Size = UDim2.fromOffset(360, 112)
	card.outer.Rotation = -4
	UITheme.stroke(card.face, C.Ink, 4)
	local title = UITheme.label(
		card.face,
		string.format("%s  %s!", string.upper(figure.displayName), ForestLogic.MultiplierText(figure.multiplier)),
		F.Heading,
		40,
		ink
	)
	title.Position = UDim2.fromOffset(0, 10)
	title.Size = UDim2.new(1, 0, 0, 52)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextScaled = true
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = 40
	fit.Parent = title
	local sub = UITheme.label(
		card.face,
		string.format("%d figured log%s  ·  %s", count, if count == 1 then "" else "s", figure.clue),
		F.Bold,
		14,
		ink
	)
	sub.Position = UDim2.fromOffset(14, 64)
	sub.Size = UDim2.new(1, -28, 0, 34)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.TextWrapped = true
	card.outer.Parent = group
	group.Parent = gui

	SoundData.Play("FigureReveal")
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	TweenService:Create(group, TweenInfo.new(0.12), { GroupTransparency = 0 }):Play()
	task.delay(0.16, confetti, gui, figure.color)
	if figure.multiplier >= 3 then
		CameraShake.Shake(0.3, 0.3)
	end
	task.wait(figure.revealSeconds)
	local out = TweenService:Create(group, TweenInfo.new(0.25), { GroupTransparency = 1 })
	out:Play()
	TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 0.85 }):Play()
	out.Completed:Wait()
	group:Destroy()
end

local function runReveals()
	if revealing then
		return
	end
	revealing = true
	task.spawn(function()
		while #revealQueue > 0 do
			local gui = revealGui
			local item = table.remove(revealQueue, 1)
			if gui and item then
				local ok, err = pcall(function(): any
					stamp(gui, item.figure, item.count)
					return nil
				end)
				if not ok then
					warn("[ForestUI] reveal failed: " .. tostring(err))
				end
			end
		end
		revealing = false
	end)
end

local function onReveal(payload: { [string]: any })
	local list = payload.figures
	if type(list) ~= "table" then
		return
	end
	for _, entry in ipairs(list) do
		if type(entry) == "table" then
			local figure = ForestLogic.Figure(entry.figure)
			local count = entry.count
			if figure and type(count) == "number" and count > 0 and #revealQueue < 8 then
				table.insert(revealQueue, { figure = figure, count = count })
			end
		end
	end
	runReveals()
end

---------------------------------------------------------------------------
-- Storms, Elders, the Bloom
---------------------------------------------------------------------------

local function onStruck(payload: { [string]: any })
	local pos, woodId, seconds = payload.pos, payload.woodId, payload.seconds
	if typeof(pos) ~= "Vector3" or type(woodId) ~= "string" then
		return
	end
	local from = rootPosition()
	if from and (from - pos).Magnitude <= STRIKE_TOAST_RANGE then
		local minutes = if type(seconds) == "number" then math.max(1, math.floor(seconds / 60 + 0.5)) else 2
		HUD.Toast(
			string.format(
				"Lightning struck a %s nearby! Fell it within %d minute%s for Stormgrain.",
				string.lower(woodName(woodId)),
				minutes,
				if minutes == 1 then "" else "s"
			)
		)
	end
end

local function biomeName(biomeId: unknown): string
	local biome = if type(biomeId) == "string" then BiomeData.Get(biomeId) else nil
	return if biome then biome.displayName else "the forest"
end

-- The marker over the Elder, seen from anywhere (the tree itself may not
-- be streamed in that far away).
local elderMarker: Part? = nil
local elderLabel: TextLabel? = nil

local function makeElderMarker(): (Part, TextLabel)
	local part = Instance.new("Part")
	part.Name = "ElderMarker"
	part.Anchored = true
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	Kit.decor(part, false)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(170, 46)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 6000
	gui.Adornee = part
	gui.Parent = part
	local card = UITheme.Card(C.Amber, C.AmberEdge, 3, 12)
	card.outer.Size = UDim2.fromScale(1, 1)
	UITheme.stroke(card.face, C.Ink, 2)
	card.outer.Parent = gui
	local label = UITheme.label(card.face, "", F.Black, 13, C.Ink)
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextWrapped = true
	part.Parent = fx()
	elderMarker, elderLabel = part, label
	return part, label
end

local function refreshElderMarker()
	local pos = workspace:GetAttribute("ElderPos")
	local woodId = workspace:GetAttribute("ElderWood")
	if typeof(pos) ~= "Vector3" or type(woodId) ~= "string" or woodId == "" then
		local old = elderMarker
		if old then
			old:Destroy()
		end
		elderMarker, elderLabel = nil, nil
		return
	end
	local marker: Part, label: TextLabel
	local m, l = elderMarker, elderLabel
	if m and l then
		marker, label = m, l
	else
		marker, label = makeElderMarker()
	end
	marker.CFrame = CFrame.new(pos + Vector3.new(0, 48, 0))
	label.Text = string.format("ELDER %s", string.upper(woodName(woodId)))
end

local function updateElderDistance()
	local marker, label = elderMarker, elderLabel
	local from = rootPosition()
	local woodId = workspace:GetAttribute("ElderWood")
	if marker and label and from and type(woodId) == "string" then
		local d = (marker.Position - from).Magnitude
		label.Text = string.format("ELDER %s\n%d studs", string.upper(woodName(woodId)), math.floor(d / 10 + 0.5) * 10)
	end
end

local function onElder(payload: { [string]: any })
	local woodId = payload.woodId
	if type(woodId) ~= "string" then
		return
	end
	SoundData.Play("FigureReveal")
	HUD.Toast(
		string.format(
			"An Elder %s has woken in %s! Fell it together: everyone who chops a tenth of it shares the harvest.",
			woodName(woodId),
			biomeName(payload.biome)
		)
	)
end

local function onElderFallen(payload: { [string]: any })
	local woodId, helpers = payload.woodId, payload.helpers
	if type(woodId) ~= "string" then
		return
	end
	local n = if type(helpers) == "number" then helpers else 0
	HUD.Toast(
		string.format(
			"The Elder %s has fallen! %d helper%s shared the harvest.",
			woodName(woodId),
			n,
			if n == 1 then "" else "s"
		)
	)
end

local function onElderFaded(payload: { [string]: any })
	local woodId = payload.woodId
	if type(woodId) == "string" then
		HUD.Toast(string.format("The Elder %s faded back into the forest.", woodName(woodId)))
	end
end

local function onElderShare(payload: { [string]: any })
	local woodId, amount, seeds = payload.woodId, payload.amount, payload.seeds
	if type(woodId) ~= "string" or type(amount) ~= "number" then
		return
	end
	HUD.Toast(
		string.format(
			"You helped fell the Elder %s: +%s and %d Heartseeds!",
			woodName(woodId),
			Util.formatCash(amount),
			if type(seeds) == "number" then seeds else 0
		)
	)
end

local function onRoyalty(payload: { [string]: any })
	local woodId, feller, amount = payload.woodId, payload.feller, payload.amount
	if type(woodId) ~= "string" or type(feller) ~= "string" or type(amount) ~= "number" then
		return
	end
	SoundData.Play("Sell")
	HUD.Toast(
		string.format(
			"Your %s was harvested by %s: +%s",
			string.lower(woodName(woodId)),
			feller,
			Util.formatCash(amount)
		)
	)
end

-- Golden motes pouring off the Skyroot while it blooms.
local bloomEmitters: { ParticleEmitter } = {}
local bloomLight: PointLight? = nil

local function buildBloom()
	local ok, sky = pcall(WorldPlan.Sky)
	if not ok or not sky then
		return
	end
	local gold = ForestData.Figures[#ForestData.Figures].color
	local spots: { { at: Vector3, size: number } } = {
		{ at = sky.root + Vector3.new(0, sky.trunkHeight, 0), size = 70 }, -- the crown
		{ at = sky.root + Vector3.new(0, sky.trunkHeight * 0.55, 0), size = 40 }, -- down the trunk
	}
	for i, spot in ipairs(spots) do
		local anchor = Instance.new("Part")
		anchor.Name = "SkyrootBloom" .. i
		anchor.Anchored = true
		anchor.Transparency = 1
		anchor.Size = Vector3.new(spot.size, 4, spot.size)
		anchor.CFrame = CFrame.new(spot.at)
		Kit.decor(anchor, false)
		anchor.Parent = fx()
		local motes = Instance.new("ParticleEmitter")
		motes.Name = "BloomMotes"
		motes.Enabled = false
		motes.Color = ColorSequence.new(gold, Color3.fromRGB(255, 246, 210))
		motes.LightEmission = 1
		motes.LightInfluence = 0
		motes.Rate = if i == 1 then 40 else 18
		motes.Lifetime = NumberRange.new(9, 14)
		motes.Speed = NumberRange.new(3, 7)
		motes.SpreadAngle = Vector2.new(70, 70)
		motes.Acceleration = Vector3.new(0, -2.5, 0)
		motes.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.15, 2.2),
			NumberSequenceKeypoint.new(1, 0.4),
		})
		motes.Parent = anchor
		table.insert(bloomEmitters, motes)
		if i == 1 then
			local light = Instance.new("PointLight")
			light.Color = gold
			light.Range = 60
			light.Brightness = 3
			light.Enabled = false
			light.Parent = anchor
			bloomLight = light
		end
	end
end

local blooming = false
local function refreshBloom(announce: boolean)
	local on = workspace:GetAttribute("SkyrootBloom") == true
	for _, e in ipairs(bloomEmitters) do
		e.Enabled = on
	end
	local light = bloomLight
	if light then
		light.Enabled = on
	end
	if announce and on ~= blooming then
		if on then
			SoundData.Play("FigureReveal")
			HUD.Toast(
				string.format(
					"The Skyroot is blooming! Figured wood grows twice as often for %d minutes.",
					math.floor(ForestData.Bloom.seconds / 60)
				)
			)
		else
			HUD.Toast("The Skyroot's bloom has faded. Keep replanting and it'll bloom again.")
		end
	end
	blooming = on
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

local handlers: { [string]: ({ [string]: any }) -> () } = {
	SeedPop = onSeedPop,
	Sprout = onSprout,
	Reveal = onReveal,
	Struck = onStruck,
	Elder = onElder,
	ElderFallen = onElderFallen,
	ElderFaded = onElderFaded,
	ElderShare = onElderShare,
	Royalty = onRoyalty,
}

function ForestUI.Start()
	local playerGui = player:WaitForChild("PlayerGui")
	buildPouch()
	local reveal = UITheme.Screen("FigureReveal", 12, true)
	reveal.Parent = playerGui
	revealGui = reveal
	buildMarkers()
	buildBloom()

	-- Other kinds (lightning bolts, ...) belong to other controllers.
	Net.Remote("WorldFX").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		local handler = if type(kind) == "string" then handlers[kind] else nil
		if handler and type(payload) == "table" then
			handler(payload :: { [string]: any })
		end
	end)

	for _, inst in ipairs(CollectionService:GetTagged("Stump")) do
		addStump(inst)
	end
	CollectionService:GetInstanceAddedSignal("Stump"):Connect(addStump)
	CollectionService:GetInstanceRemovedSignal("Stump"):Connect(removeStump) -- regrown, or streamed out

	for _, wood in ipairs(WoodData.All()) do
		player:GetAttributeChangedSignal("Seeds_" .. wood.id):Connect(function()
			for _, entry in pairs(stumps) do
				if entry.woodId == wood.id then
					refreshPrompt(entry)
				end
			end
		end)
	end

	workspace:GetAttributeChangedSignal("ElderPos"):Connect(refreshElderMarker)
	workspace:GetAttributeChangedSignal("ElderWood"):Connect(refreshElderMarker)
	refreshElderMarker()
	workspace:GetAttributeChangedSignal("SkyrootBloom"):Connect(function()
		refreshBloom(true)
	end)
	refreshBloom(false)

	-- A slow loop for what can wait: markers, prompts (sprouts ending,
	-- stumps hiding), the Elder's distance.
	task.spawn(function()
		while true do
			task.wait(LOOP_SECONDS)
			refreshPrompts()
			updateMarkers()
			updateElderDistance()
		end
	end)
end

return ForestUI
