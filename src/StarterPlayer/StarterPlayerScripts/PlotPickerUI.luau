--!strict
-- PlotPickerUI: pick a homestead. It opens from the Land Office counter
-- (the server sends the offer with the price) or, for a save that already
-- owns a plot, when you join. Next and Previous walk the pads (taken ones
-- included, labelled taken). Claim names a pad; the server charges the
-- price and assigns, or says why not. A buyer's Close (or B) just closes;
-- a returning owner's "any open plot" and Close take a free pad.
-- The camera frames the pad you're looking at: while the picker is open a
-- render-step loop keeps the camera Scriptable and glides it to the pad every
-- frame (a respawn, the default camera script or another screen cannot take
-- it back). Three things say which pad it is, none needing the world to be
-- streamed in: the camera, a client-made pillar and name tag at the pad's
-- coordinates, and a small map card with every pad (Shared/PlotPickerMap).
-- A claim fades through black with a "Claimed <pad>!" line before the plot
-- shows. Buttons stay fingertip sized, and nothing depends on a mouse hover.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local PickerSequence = require(ReplicatedStorage.Shared.PickerSequence)
local PlotPickerLogic = require(ReplicatedStorage.Shared.PlotPickerLogic)
local PlotPickerMap = require(ReplicatedStorage.Shared.PlotPickerMap)
local MenuPad = require(script.Parent.MenuPad)
local UITheme = require(script.Parent.UITheme)

local PlotPickerUI = {}

type Plot = PlotPickerLogic.OfferPlot
type Offer = PlotPickerLogic.Offer

local C = UITheme.Colors
local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local titleLabel: TextLabel? = nil
local detailLabel: TextLabel? = nil
local claimButton: TextButton? = nil
local previousButton: TextButton? = nil
local nextButton: TextButton? = nil
local plots: { Plot } = {}
local index = 1
local open = false
local savedSpeed: number? = nil
local savedCamera: Enum.CameraType? = nil
local price = 0 -- this player's price for a plot (0: a save that already owns one)
local anyButton: TextButton? = nil
local pendingOffer: Offer? = nil -- the newest offer, held while the quality screen has its turn
local sequence = PickerSequence.Shared()

local RENDER_NAME = "PlotPickerCamera"
local GLIDE_RATE = 6 -- per second: the camera covers most of the way in half a second
local RESTREAM_EVERY = 5 -- seconds: ask again for the area around the shot

local loadingLabel: TextLabel? = nil
local mapCard: Frame? = nil
local mapDots: { Frame } = {}
local fadeFrame: Frame? = nil
local fadeText: TextLabel? = nil
local bound = false
local camPos: Vector3? = nil -- where the camera is now
local camFocus: Vector3? = nil -- what it is looking at now
local goalPos: Vector3? = nil
local goalFocus: Vector3? = nil
local loadingToken = 0 -- the newest stream request; older ones may not clear the note
local lastAsk = 0
local marker: Part? = nil
local markerText: TextLabel? = nil
local fading = false
local destroyMarker: () -> () -- defined with the marker, below _close's reach
local unbindCamera: () -> ()

local function humanoid(): Humanoid?
	local char = player.Character
	return if char then char:FindFirstChildOfClass("Humanoid") else nil
end

local function currentCamera(): Camera?
	local ok, cam = pcall(function()
		return workspace.CurrentCamera
	end)
	if ok and typeof(cam) == "Instance" then
		return cam :: Camera
	end
	return nil
end

local function lock()
	local hum = humanoid()
	if hum and savedSpeed == nil then
		savedSpeed = hum.WalkSpeed
		hum.WalkSpeed = 0
	end
	local cam = currentCamera()
	if cam and savedCamera == nil then
		savedCamera = cam.CameraType
		cam.CameraType = Enum.CameraType.Scriptable
	end
end

local function unlock()
	local hum = humanoid()
	if hum and savedSpeed ~= nil then
		-- Never a stuck zero (PlotPickerLogic.SafeSpeed).
		hum.WalkSpeed = PlotPickerLogic.SafeSpeed(savedSpeed)
	end
	savedSpeed = nil
	local cam = currentCamera()
	if cam and savedCamera ~= nil then
		-- Never hand back Scriptable: nothing would move the camera again.
		cam.CameraType = if savedCamera == Enum.CameraType.Scriptable then Enum.CameraType.Custom else savedCamera
		if hum then
			cam.CameraSubject = hum
		end
	end
	savedCamera = nil
end

function PlotPickerUI._open(button: GuiObject?)
	open = true
	local screen = gui
	if screen then
		screen.Enabled = true
	end
	MenuPad.Open(button or claimButton)
end

function PlotPickerUI._close()
	pendingOffer = nil
	sequence.Done("plot") -- the next screen in line (if any) may open
	if open then
		open = false
		local screen = gui
		if screen then
			screen.Enabled = false
		end
		unbindCamera()
		destroyMarker()
		unlock()
	end
	MenuPad.Close(gui)
end

function PlotPickerUI.ApplyKey(key: Enum.KeyCode): string?
	if not open or not MenuPad.Closes(key) then
		return nil
	end
	PlotPickerUI._close()
	return "close"
end

local function hide()
	PlotPickerUI._close()
end

local function setLoading(loading: boolean)
	local label = loadingLabel
	if label then
		label.Text = PlotPickerMap.LoadingText(loading)
		label.Visible = loading
	end
end

-- Ask the engine to stream the pad's area in. Fire and forget for the
-- buttons (nothing waits on it); only the "Loading view…" note follows it.
local function requestStream(focus: Vector3, showNote: boolean)
	lastAsk = os.clock()
	local ask = (player :: any).RequestStreamAroundAsync
	if type(ask) ~= "function" then
		return
	end
	loadingToken += 1
	local token = loadingToken
	if showNote then
		setLoading(true)
	end
	task.spawn(function()
		pcall(function()
			ask(player, focus, 12)
		end)
		if token == loadingToken then
			setLoading(false)
		end
	end)
end

destroyMarker = function()
	if marker then
		marker:Destroy()
	end
	marker = nil
	markerText = nil
end

-- One pillar and name tag at the pad's coordinates. Made on this client, so
-- it needs neither the real pad nor the streamed area.
local function ensureMarker(): Part
	local existing = marker
	if existing and existing.Parent then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "PlotPickerMarker"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.45
	part.Size = Vector3.new(PlotPickerMap.PillarWidth, PlotPickerMap.PillarHeight, PlotPickerMap.PillarWidth)

	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0
	highlight.Parent = part

	local tag = Instance.new("BillboardGui")
	tag.Name = "Tag"
	tag.AlwaysOnTop = true
	tag.Size = UDim2.fromOffset(260, 56)
	-- Part of the pillar's height down from its middle: in the shot.
	tag.StudsOffsetWorldSpace = Vector3.new(0, 40 - PlotPickerMap.PillarHeight / 2, 0)
	tag.MaxDistance = math.huge
	tag.Adornee = part
	tag.Parent = part
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundColor3 = C.Ink
	text.BackgroundTransparency = 0.25
	text.TextColor3 = C.Cream
	text.Font = UITheme.Fonts.Black
	text.TextSize = 24
	text.TextScaled = false
	text.Text = ""
	UITheme.corner(text, 10)
	text.Parent = tag
	markerText = text

	part.Parent = workspace
	marker = part
	return part
end

local function showMarker(plot: Plot)
	local part = ensureMarker()
	part.CFrame = CFrame.new(plot.x, plot.y + PlotPickerMap.PillarHeight / 2, plot.z)
	local color = if plot.taken then C.Muted else C.Green
	part.Color = color
	local highlight = part:FindFirstChildOfClass("Highlight")
	if highlight then
		highlight.OutlineColor = if plot.taken then C.Cream else Color3.fromRGB(255, 214, 64)
	end
	local text = markerText
	if text then
		text.Text = if plot.taken then plot.name .. " (taken)" else plot.name
	end
end

-- The map card: one dot per pad, the chosen one big and gold, taken ones
-- grey, open ones green. Built from the offer; works with nothing streamed.
local MAP_COLORS = {
	selected = Color3.fromRGB(255, 214, 64),
	open = C.Green,
	taken = C.Muted,
}

local function refreshMap()
	local card = mapCard
	if not card then
		return
	end
	local dots = PlotPickerMap.Layout(plots, index)
	for i = #dots + 1, #mapDots do
		mapDots[i].Visible = false
	end
	for i, dot in ipairs(dots) do
		local found: Frame? = mapDots[i]
		local frame: Frame
		if found then
			frame = found
		else
			frame = Instance.new("Frame")
			frame.Name = "Dot" .. i
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.BorderSizePixel = 0
			UITheme.corner(frame, 9)
			UITheme.stroke(frame, C.Ink, 1)
			frame.Parent = card
			mapDots[i] = frame
		end
		local chosen = dot.state == "selected"
		local size = if chosen then PlotPickerMap.SelectedDotSize else PlotPickerMap.DotSize
		frame.Visible = true
		frame.Position = UDim2.fromScale(dot.fx, dot.fy)
		frame.Size = UDim2.fromOffset(size, size)
		frame.ZIndex = if chosen then 3 else 2
		frame.BackgroundColor3 = if chosen and plots[i].taken then C.Cream else MAP_COLORS[dot.state]
		local ring = frame:FindFirstChildOfClass("UIStroke")
		if ring then
			ring.Thickness = if chosen then 3 else 1
		end
	end
end

-- Every frame while the picker is open: keep the camera Scriptable, glide
-- toward the chosen pad, keep the shot's area asked for.
local function renderStep(dt: number)
	local cam = currentCamera()
	local goal = goalPos
	local look = goalFocus
	if not cam or not goal or not look then
		return
	end
	local pos = camPos or goal
	local focus = camFocus or look
	local k = PlotPickerMap.Ease(dt, GLIDE_RATE)
	pos = pos:Lerp(goal, k)
	focus = focus:Lerp(look, k)
	camPos = pos
	camFocus = focus
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	cam.CFrame = CFrame.lookAt(pos, focus)
	cam.Focus = CFrame.new(focus)
	if os.clock() - lastAsk > RESTREAM_EVERY then
		requestStream(look, false)
	end
end

local function bindCamera()
	if bound then
		return
	end
	local cam = currentCamera()
	if cam then
		-- Start the glide from wherever the camera is now.
		local cf = cam.CFrame
		camPos = cf.Position
		camFocus = cf.Position + cf.LookVector * 60
	end
	bound = true
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, renderStep)
end

unbindCamera = function()
	if bound then
		bound = false
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end
	camPos, camFocus, goalPos, goalFocus = nil, nil, nil, nil
	loadingToken += 1 -- a late stream answer must not touch the note
	setLoading(false)
end

local function frame(plot: Plot)
	local shot = PlotPickerMap.Shot(plot)
	goalPos = Vector3.new(shot.fromX, shot.fromY, shot.fromZ)
	goalFocus = Vector3.new(shot.atX, shot.atY, shot.atZ)
	showMarker(plot)
	requestStream(goalFocus :: Vector3, true)
	bindCamera()
end

local function showCurrent()
	local plot = plots[index]
	local title = titleLabel
	local detail = detailLabel
	local claim = claimButton
	if not plot or not title or not detail or not claim then
		return
	end
	title.Text = string.format("%s  ·  %d / %d", plot.name, index, #plots)
	if plot.taken then
		local who = if plot.owner ~= "" then plot.owner else "someone"
		detail.Text = string.format("%s\nTaken by %s", plot.region, who)
		claim.Text = "TAKEN"
		claim.AutoButtonColor = false
		claim.BackgroundColor3 = C.Muted
		claim.TextColor3 = C.Ink
	else
		detail.Text = PlotPickerLogic.OpenText(plot.region, price)
		claim.Text = PlotPickerLogic.ClaimLabel(price)
		claim.BackgroundColor3 = C.Green
		claim.TextColor3 = C.Cream
	end
	refreshMap()
	frame(plot)
end

local function apply(offer: Offer)
	local wasOpen = open
	local previous = plots[index]
	local lost = offer.notice == "taken"
	plots = offer.plots
	price = if type(offer.price) == "number" then offer.price else 0
	if anyButton then
		anyButton.Text = PlotPickerLogic.AnyText(price)
	end
	if #plots == 0 then
		hide()
		return
	end
	if not open then
		index = 1
		for i, plot in ipairs(plots) do
			if not plot.taken then
				index = i
				break
			end
		end
	else
		index = math.clamp(index, 1, #plots)
		local flipped = previous ~= nil and previous.taken ~= true and plots[index].taken == true
		if lost or flipped then
			index = PlotPickerLogic.NextOpen(plots, index)
		end
	end
	lock()
	showCurrent()
	PlotPickerUI._open(claimButton)
	if not wasOpen then
		-- It is on the screen now: the server's timeout that takes a free pad
		-- starts here, not when the save loaded (PlotService.Shown).
		Net.Remote("PlotShown"):FireServer()
	end
end

-- An offer arrived (or arrived again: the server sends it once the save has
-- loaded and once more when the client says ClientReady). It is kept as the
-- newest, and shown when it is the plot picker's turn: the quality screen
-- (QualityPickerUI) goes first on a first join, so the two never stack.
local function show(offer: Offer)
	pendingOffer = offer
	if not sequence.Request("plot") then
		return -- waiting for its turn; the sequence's OnChange applies it
	end
	apply(offer)
end

local function step(delta: number)
	if not open or #plots == 0 then
		return
	end
	index = PlotPickerLogic.Step(index, #plots, delta)
	showCurrent()
end

local function claim()
	local plot = plots[index]
	if not plot or not PlotPickerLogic.CanClaim(plot.taken) then
		return
	end
	Net.Remote("ClaimPlot"):FireServer(plot.index)
end

local function pass()
	Net.Remote("PlotPass"):FireServer()
end

local function build()
	local screen = UITheme.Screen("PlotPicker", UITheme.Layers.PlotPicker, "device")
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	-- Top of the screen, in both orientations: the thumbstick and the jump
	-- button live in the lower corners (PlotPickerLogic.ControlsClear).
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, PlotPickerLogic.PanelTop)
	panel.Size = UDim2.new(PlotPickerLogic.PanelWidthScale, 0, 0, PlotPickerLogic.PanelHeight)
	panel.BackgroundColor3 = C.Paper
	panel.BorderSizePixel = 0
	UITheme.corner(panel, 12)
	panel.Parent = screen

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(16, 6)
	title.Size = UDim2.new(1, -32 - PlotPickerMap.CardSize - 8, 0, 24)
	title.Font = UITheme.Fonts.Heading
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = C.Ink
	title.Text = ""
	title.Parent = panel
	titleLabel = title

	local detail = Instance.new("TextLabel")
	detail.Name = "Detail"
	detail.BackgroundTransparency = 1
	detail.Position = UDim2.fromOffset(16, 32)
	detail.Size = UDim2.new(1, -32 - PlotPickerMap.CardSize - 8, 0, 36)
	detail.Font = UITheme.Fonts.Body
	detail.TextSize = 15
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.TextColor3 = C.Bark
	detail.Text = ""
	detail.Parent = panel
	detailLabel = detail

	-- The map card, right side of the panel: every pad from the offer, the
	-- chosen one highlighted. A tap on it picks the nearest pad.
	local card = Instance.new("Frame")
	card.Name = "Map"
	card.AnchorPoint = Vector2.new(1, 0.5)
	card.Position = UDim2.new(1, -10, 0.5, 0)
	card.Size = UDim2.fromOffset(PlotPickerMap.CardSize, PlotPickerMap.CardSize)
	card.BackgroundColor3 = C.PaperDark
	card.BorderSizePixel = 0
	UITheme.corner(card, 8)
	UITheme.stroke(card, C.Muted, 1)
	card.Parent = panel
	mapCard = card
	local north = Instance.new("TextLabel")
	north.Name = "North"
	north.BackgroundTransparency = 1
	north.Position = UDim2.fromOffset(4, 2)
	north.Size = UDim2.fromOffset(16, 14)
	north.Font = UITheme.Fonts.Black
	north.TextSize = 12
	north.TextColor3 = C.Bark
	north.Text = "N"
	north.Parent = card
	card.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		local size = card.AbsoluteSize
		if size.X < 1 or size.Y < 1 then
			return
		end
		local at = input.Position
		local nearest = PlotPickerMap.Nearest(
			PlotPickerMap.Layout(plots, index),
			(at.X - card.AbsolutePosition.X) / size.X,
			(at.Y - card.AbsolutePosition.Y) / size.Y
		)
		if nearest and open and nearest ~= index then
			index = nearest
			showCurrent()
		end
	end)

	-- Under the panel: said while the view around the pad is still streaming.
	local loading = Instance.new("TextLabel")
	loading.Name = "Loading"
	loading.AnchorPoint = Vector2.new(0.5, 0)
	loading.Position = UDim2.new(0.5, 0, 0, PlotPickerLogic.PanelTop + PlotPickerLogic.PanelHeight + 8)
	loading.Size = UDim2.fromOffset(180, 28)
	loading.BackgroundColor3 = C.Ink
	loading.BackgroundTransparency = 0.3
	loading.TextColor3 = C.Cream
	loading.Font = UITheme.Fonts.Bold
	loading.TextSize = 16
	loading.Text = ""
	loading.Visible = false
	UITheme.corner(loading, 8)
	loading.Parent = screen
	loadingLabel = loading

	-- The claim fade: its own screen, over the picker, under the quality one.
	local fade = Instance.new("ScreenGui")
	fade.Name = "PlotPickerFade"
	fade.ResetOnSpawn = false
	fade.IgnoreGuiInset = true
	fade.DisplayOrder = UITheme.Layers.PlotPicker + 5
	fade.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local black = Instance.new("Frame")
	black.Name = "Black"
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.BorderSizePixel = 0
	black.Visible = false
	black.Parent = fade
	local toast = Instance.new("TextLabel")
	toast.Name = "Claimed"
	toast.AnchorPoint = Vector2.new(0.5, 0.5)
	toast.Position = UDim2.fromScale(0.5, 0.5)
	toast.Size = UDim2.fromOffset(360, 60)
	toast.BackgroundTransparency = 1
	toast.TextTransparency = 1
	toast.TextColor3 = C.Cream
	toast.Font = UITheme.Fonts.Black
	toast.TextSize = 32
	toast.Text = ""
	toast.Parent = black
	fade.Parent = player:WaitForChild("PlayerGui")
	fadeFrame = black
	fadeText = toast

	local row = Instance.new("Frame")
	row.Name = "Choices"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(12, 74)
	row.Size = UDim2.new(1, -24 - PlotPickerMap.CardSize - 8, 0, 44)
	row.Parent = panel

	local function choice(name: string, text: string, x: number, color: Color3, ink: Color3, fn: () -> ())
		local button = Instance.new("TextButton")
		button.Name = name
		button.Position = UDim2.fromScale(x, 0)
		button.Size = UDim2.new(0.32, -6, 1, 0)
		button.BackgroundColor3 = color
		button.TextColor3 = ink
		button.Font = UITheme.Fonts.Black
		button.TextSize = 18
		button.Text = text
		-- A phone's panel is narrow: "CLAIM FOR $2,500" shrinks to fit, never spills over its neighbours.
		button.TextScaled = true
		local fit = Instance.new("UITextSizeConstraint")
		fit.MaxTextSize = 18
		fit.MinTextSize = 10
		fit.Parent = button
		button.AutoButtonColor = true
		UITheme.corner(button, 8)
		button.Parent = row
		button.Activated:Connect(fn)
		return button
	end

	previousButton = choice("Previous", "PREVIOUS", 0, C.Bark, C.Cream, function()
		step(-1)
	end)
	claimButton = choice("Claim", PlotPickerLogic.ClaimLabel(price), 0.34, C.Green, C.Cream, claim)
	nextButton = choice("Next", "NEXT", 0.68, C.Bark, C.Cream, function()
		step(1)
	end)
	if previousButton and claimButton and nextButton then
		previousButton.NextSelectionRight = claimButton
		claimButton.NextSelectionLeft = previousButton
		claimButton.NextSelectionRight = nextButton
		nextButton.NextSelectionLeft = claimButton
	end

	local any = Instance.new("TextButton")
	any.Name = "Any"
	any.BackgroundTransparency = 1
	any.Position = UDim2.fromOffset(12, 122)
	any.Size = UDim2.new(1, -24 - PlotPickerMap.CardSize - 8, 0, 18)
	any.Font = UITheme.Fonts.Bold
	any.TextSize = 16
	any.TextColor3 = C.Blue
	any.Text = PlotPickerLogic.AnyText(price)
	anyButton = any
	any.Parent = panel
	any.Activated:Connect(pass)
end

-- The claim went through (PlotSlot is set; the server has already moved
-- you): fade through black with "Claimed <pad>!", close the picker while the
-- screen is black so the camera returns to the character unseen, fade back.
local function claimed(name: string)
	local black = fadeFrame
	local toast = fadeText
	if fading or not black or not toast then
		hide()
		return
	end
	fading = true
	local half = PlotPickerMap.FadeSeconds / 2
	toast.Text = PlotPickerMap.ClaimedText(name)
	black.Visible = true
	local info = TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(black, info, { BackgroundTransparency = 0 }):Play()
	TweenService:Create(toast, info, { TextTransparency = 0 }):Play()
	task.delay(half, function()
		hide()
		task.wait(0.4) -- long enough to read it
		local out = TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(black, out, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(toast, out, { TextTransparency = 1 }):Play()
		task.wait(half)
		black.Visible = false
		fading = false
	end)
end

function PlotPickerUI.Start()
	build()
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputState ~= Enum.UserInputState.Begin or not open then
			return
		end
		if MenuPad.Closes(input.KeyCode) then
			pass()
			PlotPickerUI.ApplyKey(input.KeyCode)
		end
	end)
	Net.Remote("PlotOffer").OnClientEvent:Connect(function(payload: Offer)
		show(payload)
	end)
	local function considerClose()
		local slot = player:GetAttribute("PlotSlot")
		if slot ~= nil and open then
			local name = "your plot"
			for _, plot in ipairs(plots) do
				if plot.index == slot then
					name = plot.name
				end
			end
			claimed(name)
		elseif player:GetAttribute("Picking") ~= true or slot ~= nil then
			hide()
		end
	end
	player:GetAttributeChangedSignal("Picking"):Connect(considerClose)
	player:GetAttributeChangedSignal("PlotSlot"):Connect(considerClose)
	sequence.OnChange(function(active: string?)
		local offer = pendingOffer
		if active == "plot" and offer ~= nil and not open then
			apply(offer)
		end
	end)
	player.CharacterAdded:Connect(function(char: Model)
		if open then
			savedSpeed = nil
			-- The humanoid can arrive a moment after the character.
			char:WaitForChild("Humanoid", 5)
			if not open then
				return -- closed while the humanoid was coming: locking now would never be undone
			end
			lock()
			local plot = plots[index]
			if plot then
				frame(plot)
			end
		end
	end)
end

return PlotPickerUI
