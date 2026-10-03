--!strict
-- PlotPickerUI: pick a homestead when you join. Next and Previous walk
-- the pads (taken ones included, labelled taken). Claim asks the server.
-- Give me one, or closing the panel, lets the server assign a free pad.
-- The camera frames the pad you're looking at. Buttons stay fingertip
-- sized, and nothing here depends on a mouse hover.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Net = require(ReplicatedStorage.Shared.Net)
local PlotPickerLogic = require(ReplicatedStorage.Shared.PlotPickerLogic)
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
local plots: { Plot } = {}
local index = 1
local open = false
local savedSpeed: number? = nil
local savedCamera: Enum.CameraType? = nil

local function humanoid(): Humanoid?
	local char = player.Character
	return if char then char:FindFirstChildOfClass("Humanoid") else nil
end

local function lock()
	local hum = humanoid()
	if hum and savedSpeed == nil then
		savedSpeed = hum.WalkSpeed
		hum.WalkSpeed = 0
	end
	local cam = workspace.CurrentCamera
	if cam and savedCamera == nil then
		savedCamera = cam.CameraType
		cam.CameraType = Enum.CameraType.Scriptable
	end
end

local function unlock()
	local hum = humanoid()
	if hum and savedSpeed ~= nil then
		hum.WalkSpeed = savedSpeed
	end
	savedSpeed = nil
	local cam = workspace.CurrentCamera
	if cam and savedCamera ~= nil then
		cam.CameraType = savedCamera
	end
	savedCamera = nil
end

local function hide()
	if not open then
		return
	end
	open = false
	local screen = gui
	if screen then
		screen.Enabled = false
	end
	unlock()
end

local function frame(plot: Plot)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local focus = Vector3.new(plot.x, plot.y + 4, plot.z)
	-- The pad has to be in memory before the camera arrives, or a phone
	-- shows an empty shelf for a moment.
	local ask = (player :: any).RequestStreamAroundAsync
	if type(ask) == "function" then
		pcall(function()
			ask(player, focus)
		end)
	end
	local from = Vector3.new(plot.x - 78, plot.y + 62, plot.z + 96)
	local goal = CFrame.lookAt(from, focus)
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	TweenService:Create(cam, TweenInfo.new(0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = goal })
		:Play()
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
		detail.Text = string.format("%s\nOpen", plot.region)
		claim.Text = "CLAIM"
		claim.BackgroundColor3 = C.Green
		claim.TextColor3 = C.Cream
	end
	frame(plot)
end

local function show(offer: Offer)
	local previous = plots[index]
	local lost = offer.notice == "taken"
	plots = offer.plots
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
	open = true
	lock()
	local screen = gui
	if screen then
		screen.Enabled = true
	end
	showCurrent()
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
	local screen = UITheme.Screen("PlotPicker", 80, "device")
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
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -32, 0, 28)
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
	detail.Position = UDim2.fromOffset(16, 28)
	detail.Size = UDim2.new(1, -32, 0, 36)
	detail.Font = UITheme.Fonts.Body
	detail.TextSize = 16
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.TextColor3 = C.Bark
	detail.Text = ""
	detail.Parent = panel
	detailLabel = detail

	local row = Instance.new("Frame")
	row.Name = "Choices"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(12, 68)
	row.Size = UDim2.new(1, -24, 0, 44)
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
		button.AutoButtonColor = true
		UITheme.corner(button, 8)
		button.Parent = row
		button.Activated:Connect(fn)
		return button
	end

	choice("Previous", "PREVIOUS", 0, C.Bark, C.Cream, function()
		step(-1)
	end)
	claimButton = choice("Claim", "CLAIM", 0.34, C.Green, C.Cream, claim)
	choice("Next", "NEXT", 0.68, C.Bark, C.Cream, function()
		step(1)
	end)

	local any = Instance.new("TextButton")
	any.Name = "Any"
	any.BackgroundTransparency = 1
	any.Position = UDim2.fromOffset(12, 112)
	any.Size = UDim2.new(1, -24, 0, 18)
	any.Font = UITheme.Fonts.Bold
	any.TextSize = 16
	any.TextColor3 = C.Blue
	any.Text = "Give me any open plot"
	any.Parent = panel
	any.Activated:Connect(pass)
end

function PlotPickerUI.Start()
	build()
	Net.Remote("PlotOffer").OnClientEvent:Connect(function(payload: Offer)
		show(payload)
	end)
	local function considerClose()
		if player:GetAttribute("Picking") ~= true or player:GetAttribute("PlotSlot") ~= nil then
			hide()
		end
	end
	player:GetAttributeChangedSignal("Picking"):Connect(considerClose)
	player:GetAttributeChangedSignal("PlotSlot"):Connect(considerClose)
	player.CharacterAdded:Connect(function()
		if open then
			savedSpeed = nil
			lock()
			local plot = plots[index]
			if plot then
				frame(plot)
			end
		end
	end)
end

return PlotPickerUI
