--!strict
-- PromptUI: ProximityPrompts in the game's look (UI spec 05), when
-- GameConfig.CustomPrompts is on. Every prompt in the world is switched to
-- the Custom style on this client, and drawn here instead:
--   * a bark card with the action ("Browse axes") and, under it, what it's
--     on ("TOOL SHED") in amber;
--   * a paper key cap with the key (E, F); on a gamepad, the pad's glyph;
--     on a touch screen an amber TAP, and the whole card is the button;
--   * holding fills the key cap amber from the bottom over HoldDuration;
--   * a tap or a click on the card clicks (UITheme.Click) as it goes down.
-- The engine still decides when a prompt shows and handles keys and
-- buttons; touch and clicks go through InputHoldBegin / InputHoldEnd.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local NameFade = require(ReplicatedStorage.Shared.NameFade)
local TextAnchor = require(ReplicatedStorage.Shared.TextAnchor)
local UITheme = require(script.Parent.UITheme)

local PromptUI = {}

local C = UITheme.Colors
local F = UITheme.Fonts

local player = Players.LocalPlayer

local WIDTH, HEIGHT = 360, 72 -- the billboard; the card sits in its middle

-- Cards over a person's head (a Talk prompt): drawn in the scene, not on top
-- of it, so a wall hides them (a keeper behind a shop's wall, an NPC down a
-- hall), a ray from the camera at 4 Hz hides one a wall is in front of, and
-- a low ceiling brings its tail down so the roof does not clip it
-- (Shared/TextAnchor). Cards on a counter or a box stay on top: their anchor
-- is the object's own middle, which the object would hide.
type Watched = {
	gui: BillboardGui,
	head: BasePart,
	hidden: boolean,
	clear: number,
	k: number, -- the card's growth (a TV)
	covers: { [BasePart]: boolean }, -- other NPCs' heads whose nameplate is faded for this card
}
local watched: { [BillboardGui]: Watched } = {}
local sinceCheck = 0
local rayParams: RaycastParams? = nil
local rayParamsAt = -10

local function paramsNow(now: number): RaycastParams
	local cached = rayParams
	if cached and now - rayParamsAt < 1 then
		return cached
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local skip: { Instance } = {}
	for _, inst in ipairs(CollectionService:GetTagged("NPC")) do
		table.insert(skip, inst)
	end
	local char = player.Character
	if char then
		table.insert(skip, char)
	end
	params.FilterDescendantsInstances = skip
	rayParams = params
	rayParamsAt = now
	return params
end

-- The nameplate and the Talk card are both pixel-sized billboards on the same
-- head, so while a card shows its head's NameTag fades out (NameFade has the
-- rules: a show count per head, 0.15 s each way). The fade owns the labels'
-- TextTransparency and TextStrokeTransparency; NPCController.applyTag only
-- sets sizes and distances, so it never brings a hidden name back.
local fade = NameFade.new()
local tagBase: { [TextLabel]: { text: number, stroke: number } } = {}

local function tagLabels(head: Instance): { TextLabel }
	local out: { TextLabel } = {}
	local tag = head:FindFirstChild("NameTag")
	if tag then
		for _, child in ipairs(tag:GetChildren()) do
			if child:IsA("TextLabel") then
				table.insert(out, child)
			end
		end
	end
	return out
end

local function paintTag(head: Instance)
	local a = NameFade.Transparency(fade, head)
	for _, label in ipairs(tagLabels(head)) do
		local base = tagBase[label]
		if base == nil then
			base = { text = label.TextTransparency, stroke = label.TextStrokeTransparency }
			tagBase[label] = base
		end
		label.TextTransparency = base.text + (1 - base.text) * a
		label.TextStrokeTransparency = base.stroke + (1 - base.stroke) * a
	end
end

-- A card shows on `head`: its name fades out (kept out while any card shows).
function PromptUI.HideTag(head: Instance)
	for _, label in ipairs(tagLabels(head)) do
		if tagBase[label] == nil then
			tagBase[label] = { text = label.TextTransparency, stroke = label.TextStrokeTransparency }
		end
	end
	NameFade.Show(fade, head)
end

-- A card on `head` went away: the name comes back once none is left.
function PromptUI.ShowTag(head: Instance)
	NameFade.Hide(fade, head)
end

-- Advances every fade by `dt` seconds and paints the labels that moved.
function PromptUI.FadeStep(dt: number)
	for _, head in ipairs(NameFade.Step(fade, dt)) do
		paintTag(head)
	end
end

function PromptUI.TagTransparency(head: Instance): number
	return NameFade.Transparency(fade, head)
end

-- Other NPCs near a shown card whose nameplate would sit under it fade too.
local function coverOthers(w: Watched, camera: Camera)
	local viewH = camera.ViewportSize.Y
	local head = w.head.Position
	local spp = NameFade.StudsPerPixel((camera.CFrame.Position - head).Magnitude, viewH)
	local right, up = camera.CFrame.RightVector, camera.CFrame.UpVector
	local card = { x = WIDTH * w.k, y = HEIGHT * w.k }
	local now: { [BasePart]: boolean } = {}
	for _, model in ipairs(CollectionService:GetTagged("NPC")) do
		local other = model:FindFirstChild("Head")
		local tag = if other then other:FindFirstChild("NameTag") else nil
		if other and other:IsA("BasePart") and other ~= w.head and tag and tag:IsA("BillboardGui") then
			local v = other.Position - head
			if
				v.Magnitude < 12
				and NameFade.Covered(
					{ x = tag.Size.X.Offset, y = tag.Size.Y.Offset },
					tag.StudsOffset.Y,
					card,
					w.gui.StudsOffset.Y,
					spp,
					v:Dot(right),
					v:Dot(up)
				)
			then
				now[other] = true
			end
		end
	end
	for other in pairs(now) do
		if not w.covers[other] then
			PromptUI.HideTag(other)
		end
	end
	for other in pairs(w.covers) do
		if not now[other] then
			PromptUI.ShowTag(other)
		end
	end
	w.covers = now
end

local function checkWatched()
	local camera = workspace.CurrentCamera
	if camera == nil then
		return
	end
	local now = os.clock()
	local params = paramsNow(now)
	local from = camera.CFrame.Position
	for gui, w in pairs(watched) do
		local head = w.head.Position
		local above = head + Vector3.new(0, 1.0, 0)
		local blocked = workspace:Raycast(from, above - from, params) ~= nil
		w.hidden, w.clear = TextAnchor.NextHidden(w.hidden, blocked, w.clear)
		local up = workspace:Raycast(head, Vector3.new(0, PromptUI.HeadLift + TextAnchor.ProbeExtra, 0), params)
		local card = TextAnchor.CardStuds(HEIGHT, (from - head).Magnitude, camera.ViewportSize.Y)
		local lift = TextAnchor.Lift(0, PromptUI.HeadLift, if up then up.Distance else nil, card)
		gui.StudsOffset = Vector3.new(0, lift, 0)
		gui.Enabled = not w.hidden
		coverOthers(w, camera)
	end
end

-- How far above a Head (its centre) a Talk card's tail sits. The card
-- grows upward from there, so it clears the scalp instead of sitting on
-- the torso. A pixel UIOffset does not: up close it lands on the body.
-- (NPCData.promptLift is that pixel UIOffset: unused for a head adornee, kept
-- only for the prompt's own UIOffset on the rare part-adorned Talk.)
PromptUI.HeadLift = 1.55

-- Where a prompt's card is drawn. A model with a Head (an NPC) uses the
-- head and a studs offset above it; the second return is that offset.
-- Anything else is the part itself (or the model's PrimaryPart), and the
-- caller keeps the prompt's pixel UIOffset.
function PromptUI.Adornee(parent: Instance?): (Instance?, Vector3?)
	if parent and (parent:IsA("BasePart") or parent:IsA("Attachment")) then
		return parent, nil
	elseif parent and parent:IsA("Model") then
		local head = parent:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			return head, Vector3.new(0, PromptUI.HeadLift, 0)
		end
		return parent.PrimaryPart, nil
	end
	return nil, nil
end

local function keyName(key: Enum.KeyCode): string
	local names: { [string]: string } = { Return = "↵", Backspace = "⌫", Space = "␣" }
	return names[key.Name] or key.Name
end

-- How much a prompt card grows: on a TV by the screen's scale (1.5 at 1080p),
-- never under 1; everywhere else 1.
function PromptUI.Grow(console: boolean, scale: number): number
	return if console then math.max(1, scale) else 1
end

-- The card's touch and click press: down starts the prompt's hold, and a prompt
-- with no hold triggers right there (a phone tap is down and up within a
-- frame or two, so a hold never completes: playtest t351). Returns whether
-- the input was a press.
function PromptUI.PressDown(prompt: ProximityPrompt, input: InputObject): boolean
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
		UITheme.Click()
		prompt:InputHoldBegin()
		return true
	end
	return false
end

function PromptUI.PressUp(prompt: ProximityPrompt, input: InputObject): boolean
	local kind = input.UserInputType
	if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
		prompt:InputHoldEnd()
		return true
	end
	return false
end

function PromptUI.Show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	local adornee, studs = PromptUI.Adornee(prompt.Parent)
	if not adornee then
		return
	end
	local touch = inputType == Enum.ProximityPromptInputType.Touch
	local gamepad = inputType == Enum.ProximityPromptInputType.Gamepad

	-- A TV prompt grows with the screen (a billboard has no UIScale of its
	-- own): the card gets a UIScale of k and the billboard is k times bigger.
	local k = PromptUI.Grow(UITheme.Device() == "console", UITheme.Scale())

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Prompt"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = TextAnchor.OnTop(studs ~= nil)
	billboard.Active = true
	billboard.LightInfluence = 0
	billboard.ResetOnSpawn = false
	if studs then
		-- Tail at the head offset; the card grows up. Empty space below
		-- may cross the head. The pixel lift would not stay clear up close.
		billboard.Size = UDim2.fromOffset(WIDTH * k, HEIGHT * 2 * k)
		billboard.StudsOffset = studs
		billboard.SizeOffset = Vector2.zero
	else
		billboard.Size = UDim2.fromOffset(WIDTH * k, HEIGHT * k)
		billboard.SizeOffset = Vector2.new(prompt.UIOffset.X / (WIDTH * k), prompt.UIOffset.Y / (HEIGHT * k))
	end

	local card = UITheme.Card(C.Paper, C.AmberEdge, UITheme.Stroke, UITheme.Radius, true, "Panel")
	if studs then
		card.outer.AnchorPoint = Vector2.new(0.5, 1)
		card.outer.Position = UDim2.fromScale(0.5, 0.5)
	else
		card.outer.AnchorPoint = Vector2.new(0.5, 0.5)
		card.outer.Position = UDim2.fromScale(0.5, 0.5)
	end
	if k ~= 1 then
		local grow = Instance.new("UIScale")
		grow.Scale = k
		grow.Parent = card.outer
	end
	UITheme.padding(card.face, 8, 18, 8, 8)
	local row = UITheme.list(card.face, 12, true)
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	UITheme.texture(card.face, "Wood", 14)
	card.outer.Parent = billboard

	-- The key cap (or TAP on a touch screen).
	local cap =
		UITheme.Card(if touch then C.Amber else C.Paper, C.AmberEdge, UITheme.Stroke, UITheme.Radius, false, "Button")
	cap.outer.Name = "Key"
	cap.outer.LayoutOrder = 1
	cap.outer.Size = UDim2.fromOffset(40, 43)
	cap.face.ClipsDescendants = true
	cap.outer.Parent = card.face
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = C.Amber
	fill.BorderSizePixel = 0
	UITheme.corner(fill, UITheme.Radius)
	fill.Parent = cap.face
	if gamepad then
		local glyph = UITheme.Glyph(prompt.GamepadKeyCode, 30)
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.ZIndex = 2
		glyph.Parent = cap.face
	else
		local letter = UITheme.label(
			cap.face,
			if touch then "TAP" else keyName(prompt.KeyboardKeyCode),
			F.Heading,
			22,
			if touch then C.ConfirmInk else C.Ink
		)
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
	local action = UITheme.label(words, prompt.ActionText, F.Black, 16, C.Ink)
	action.LayoutOrder = 1
	action.Size = UDim2.new()
	action.AutomaticSize = Enum.AutomaticSize.XY
	local object =
		UITheme.label(words, string.upper(prompt.ObjectText), F.Black, UITheme.Sized("PromptObject").text, C.Bark)
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

	-- Holding: the cap fills from the bottom and swaps to the pressed skin.
	local holding: Tween? = nil
	local function setHeld(held: boolean)
		if holding then
			holding:Cancel()
			holding = nil
		end
		-- ButtonPressed is the same slice, sunk in the art, so the face stays
		-- put. Releasing always puts Button back; the pressed skin must not stick.
		UITheme.ApplySkin(cap.face, if held then "ButtonPressed" else "Button")
		if held then
			local tween = TweenService:Create(
				fill,
				TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear),
				{ Size = UDim2.fromScale(1, 1) }
			)
			tween:Play()
			holding = tween
		else
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
	-- It clicks as the press goes down, not on Activated (the release): a
	-- prompt it triggers (Pick up, Sell) is often hidden before the finger
	-- lifts, and that takes the card, and its Activated, with it.
	-- The key itself is PromptDefaults. This face stays out of the gamepad
	-- selection, or the thumbstick walks the UI and the D-pad shortcuts drop.
	local button = Instance.new("TextButton")
	button.Name = "Press"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.Selectable = false
	button.ZIndex = 5
	button.Parent = card.outer
	if touch or prompt.ClickablePrompt then
		on(button.InputBegan, function(input: InputObject)
			PromptUI.PressDown(prompt, input)
		end)
		on(button.InputEnded, function(input: InputObject)
			PromptUI.PressUp(prompt, input)
		end)
	end

	billboard.Parent = player:WaitForChild("PlayerGui")
	if studs and adornee:IsA("BasePart") then
		watched[billboard] = { gui = billboard, head = adornee, hidden = false, clear = 0, k = k, covers = {} }
		PromptUI.HideTag(adornee)
	end

	local gone = false
	local function cleanup()
		if gone then
			return
		end
		gone = true
		local w = watched[billboard]
		watched[billboard] = nil
		if w then
			PromptUI.ShowTag(w.head)
			for other in pairs(w.covers) do
				PromptUI.ShowTag(other)
			end
		end
		for _, conn in ipairs(conns) do
			conn:Disconnect()
		end
		billboard:Destroy()
	end
	table.insert(conns, prompt.PromptHidden:Once(cleanup))
	table.insert(conns, prompt.Destroying:Once(cleanup))
end

-- Only prompts are touched. (ClassName is a property read; IsA is a call per
-- instance, and the forest adds tens of thousands of parts after Start.)
local function restyle(inst: Instance)
	if inst.ClassName == "ProximityPrompt" then
		(inst :: ProximityPrompt).Style = Enum.ProximityPromptStyle.Custom
	end
end

-- How many instances the first scan looks at before it gives the frame back
-- (client audit leftover: it walked every descendant of the workspace in one go).
PromptUI.ScanPerFrame = 4000

-- Restyles the prompts in `list`, PromptUI.ScanPerFrame instances at a time,
-- calling `wait` between the slices. Returns how many it restyled.
function PromptUI.RestyleAll(list: { Instance }, perStep: number, wait: () -> ()): number
	local styled, looked = 0, 0
	for _, inst in ipairs(list) do
		if inst.ClassName == "ProximityPrompt" then
			(inst :: ProximityPrompt).Style = Enum.ProximityPromptStyle.Custom
			styled += 1
		end
		looked += 1
		if looked >= perStep then
			looked = 0
			wait()
		end
	end
	return styled
end

function PromptUI.Start()
	if not GameConfig.CustomPrompts then
		return
	end
	-- Connected first: a prompt that appears while the scan is still running is
	-- caught here, one the scan already passed is not missed.
	workspace.DescendantAdded:Connect(restyle)
	task.spawn(function()
		PromptUI.RestyleAll(workspace:GetDescendants(), PromptUI.ScanPerFrame, task.wait)
	end)
	RunService.Heartbeat:Connect(function(dt: number)
		PromptUI.FadeStep(dt)
		if next(watched) == nil then
			return
		end
		sinceCheck += dt
		if sinceCheck >= TextAnchor.CheckSeconds then
			sinceCheck = 0
			checkWatched()
		end
	end)
	ProximityPromptService.PromptShown:Connect(
		function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
			if prompt.Style == Enum.ProximityPromptStyle.Custom then
				PromptUI.Show(prompt, inputType)
			end
		end
	)
end

return PromptUI
