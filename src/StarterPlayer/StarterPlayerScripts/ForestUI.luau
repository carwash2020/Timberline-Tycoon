--!strict
-- ForestUI: the Living Forest on screen (GAME_DESIGN §16). The server
-- (ForestService) owns everything; this draws it.
--   * The sawmill's figure reveal (a big colour-coded stamp per figure,
--     rarer ones stay longer).
--   * Toasts: lightning striking a tree near you, Elders waking, falling
--     and fading (with a marker over the Elder you can see from afar), the
--     Skyroot Bloom (golden motes pouring off the Skyroot while it lasts).
-- Everything 3D is local and culled by distance; the streamed world is
-- only read through tags and attributes.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local BiomeData = require(ReplicatedStorage.Shared.BiomeData)
local ForestData = require(ReplicatedStorage.Shared.ForestData)
local ForestLogic = require(ReplicatedStorage.Shared.ForestLogic)
local Net = require(ReplicatedStorage.Shared.Net)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local Util = require(ReplicatedStorage.Shared.Util)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local Kit = require(ReplicatedStorage.Shared.Art.Kit)
local WorldPlan = require(ReplicatedStorage.Shared.World.WorldPlan)
local CameraShake = require(script.Parent.CameraShake)
local HUD = require(script.Parent.HUD)
local MenuPad = require(script.Parent.MenuPad)
local UITheme = require(script.Parent.UITheme)

type FigureDef = ForestData.FigureDef

local ForestUI = {}

local stampOpen = false
local stampFocus: GuiObject? = nil
local stampGroup: Instance? = nil

function ForestUI.ElderTextPx(tenFoot: boolean): number
	return if tenFoot then 18 else 14
end

function ForestUI._open(button: GuiObject?)
	stampOpen = true
	stampFocus = button
	MenuPad.Open(button)
end

function ForestUI._close()
	stampOpen = false
	local group = stampGroup
	stampGroup = nil
	MenuPad.Close(stampFocus)
	stampFocus = nil
	if group then
		group:Destroy()
	end
end

function ForestUI.ApplyKey(key: Enum.KeyCode): string?
	if not stampOpen or not MenuPad.Closes(key) then
		return nil
	end
	ForestUI._close()
	return "close"
end

local C = UITheme.Colors
local F = UITheme.Fonts

local player = Players.LocalPlayer

local STRIKE_TOAST_RANGE = 260 -- lightning this close to you gets a toast
local LOOP_SECONDS = 0.4

local fxFolder: Folder? = nil
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

local function woodName(woodId: string): string
	local def = WoodData.Get(woodId)
	return if def then def.displayName else woodId
end

-- Ink on light colours, cream on dark ones.
local function inkFor(color: Color3): Color3
	local luminance = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
	return if luminance > 0.55 then C.Ink else C.Cream
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
	local dismiss = Instance.new("TextButton")
	dismiss.Name = "Dismiss"
	dismiss.AnchorPoint = Vector2.new(1, 0)
	dismiss.Position = UDim2.new(1, -8, 0, 6)
	dismiss.Size = UDim2.fromOffset(44, 44)
	dismiss.BackgroundTransparency = 1
	dismiss.Text = "X"
	dismiss.Font = F.Black
	dismiss.TextSize = 18
	dismiss.TextColor3 = ink
	dismiss.Parent = card.face
	dismiss.Activated:Connect(function()
		ForestUI.ApplyKey(Enum.KeyCode.ButtonB)
	end)
	card.outer.Parent = group
	group.Parent = gui
	stampGroup = group
	ForestUI._open(dismiss)

	SoundData.Play("FigureReveal")
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	TweenService:Create(group, TweenInfo.new(0.12), { GroupTransparency = 0 }):Play()
	task.delay(0.16, confetti, gui, figure.color)
	if figure.multiplier >= 3 then
		CameraShake.Shake(0.3, 0.3)
	end
	task.wait(figure.revealSeconds)
	if stampGroup ~= group then
		return
	end
	local out = TweenService:Create(group, TweenInfo.new(0.25), { GroupTransparency = 1 })
	out:Play()
	TweenService:Create(scale, TweenInfo.new(0.25), { Scale = 0.85 }):Play()
	out.Completed:Wait()
	if stampGroup == group then
		stampGroup = nil
		ForestUI._close()
	end
	if group.Parent then
		group:Destroy()
	end
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
				"Lightning struck %s nearby! Fell it within %d minute%s for Stormgrain.",
				Util.article(string.lower(woodName(woodId))),
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

function ForestUI.MakeElderMarker(tenFoot: boolean): (Part, TextLabel)
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
	local label = UITheme.label(card.face, "", F.Black, ForestUI.ElderTextPx(tenFoot), C.Ink)
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextWrapped = true
	return part, label
end

local function makeElderMarker(): (Part, TextLabel)
	local ten = false
	pcall(function()
		ten = GuiService:IsTenFootInterface() == true
	end)
	local part, label = ForestUI.MakeElderMarker(ten)
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
	local woodId, amount = payload.woodId, payload.amount
	if type(woodId) ~= "string" or type(amount) ~= "number" then
		return
	end
	HUD.Toast(string.format("You helped fell the Elder %s: +%s", woodName(woodId), Util.formatCash(amount)))
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
			HUD.Toast("The Skyroot's bloom has faded.")
		end
	end
	blooming = on
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

local handlers: { [string]: ({ [string]: any }) -> () } = {
	Reveal = onReveal,
	Struck = onStruck,
	Elder = onElder,
	ElderFallen = onElderFallen,
	ElderFaded = onElderFaded,
	ElderShare = onElderShare,
}

function ForestUI.Start()
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputState ~= Enum.UserInputState.Begin then
			return
		end
		ForestUI.ApplyKey(input.KeyCode)
	end)
	local playerGui = player:WaitForChild("PlayerGui")
	local reveal = UITheme.Screen("FigureReveal", 12, "device") -- centred in the safe area, clear of a notch
	reveal.Parent = playerGui
	revealGui = reveal
	buildBloom()

	-- Other kinds (lightning bolts, ...) belong to other controllers.
	Net.Remote("WorldFX").OnClientEvent:Connect(function(kind: unknown, payload: unknown)
		local handler = if type(kind) == "string" then handlers[kind] else nil
		if handler and type(payload) == "table" then
			handler(payload :: { [string]: any })
		end
	end)

	workspace:GetAttributeChangedSignal("ElderPos"):Connect(refreshElderMarker)
	workspace:GetAttributeChangedSignal("ElderWood"):Connect(refreshElderMarker)
	refreshElderMarker()
	workspace:GetAttributeChangedSignal("SkyrootBloom"):Connect(function()
		refreshBloom(true)
	end)
	refreshBloom(false)

	task.spawn(function()
		while true do
			task.wait(LOOP_SECONDS)
			updateElderDistance()
		end
	end)
end

return ForestUI
