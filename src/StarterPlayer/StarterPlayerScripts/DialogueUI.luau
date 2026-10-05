--!strict
-- DialogueUI: the shopkeeper's card, along the bottom of the safe area.
-- Yes and No are fingertip sized. On a gamepad the selection links move
-- between them, ButtonX confirms Yes, and ButtonB or Escape cancels. The
-- card never changes how the character walks. The HUD already owns the
-- D-pad shortcuts, so this card does not bind those keys.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogueData = require(ReplicatedStorage.Shared.DialogueData)
local Net = require(ReplicatedStorage.Shared.Net)
local UITheme = require(script.Parent.UITheme)

local DialogueUI = {}

local ACTION = "ShopChoice"
local BUTTON_W = 168

function DialogueUI.Start()
	local player = Players.LocalPlayer
	local C = UITheme.Colors
	local gui = UITheme.Screen("ShopTalk", UITheme.Layers.Dialogue)
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = gui

	local column = Instance.new("Frame")
	column.Name = "Card"
	column.AnchorPoint = Vector2.new(0.5, 1)
	column.Position = UDim2.new(0.5, 0, 1, -36)
	column.Size = UDim2.fromOffset(BUTTON_W * 2 + 12, 108)
	column.BackgroundColor3 = C.Bark
	column.BorderSizePixel = 0
	column.Parent = holder
	UITheme.corner(column, 12)

	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.BackgroundTransparency = 1
	line.Position = UDim2.fromOffset(12, 8)
	line.Size = UDim2.new(1, -24, 0, 40)
	line.Font = Enum.Font.GothamMedium
	line.TextSize = 16
	line.TextColor3 = C.Cream
	line.TextWrapped = true
	line.TextTruncate = Enum.TextTruncate.None
	line.TextXAlignment = Enum.TextXAlignment.Center
	line.TextYAlignment = Enum.TextYAlignment.Center
	line.Parent = column

	local function button(name: string, text: string, x: number, color: Color3): TextButton
		local face = Instance.new("TextButton")
		face.Name = name
		face.AutoButtonColor = true
		face.Position = UDim2.fromOffset(x, 52)
		face.Size = UDim2.fromOffset(BUTTON_W, DialogueData.ButtonPx)
		face.BackgroundColor3 = color
		face.BorderSizePixel = 0
		face.Font = Enum.Font.GothamBold
		face.Text = text
		face.TextSize = 18
		face.TextColor3 = C.Cream
		face.Selectable = true
		face.Parent = column
		UITheme.corner(face, 10)
		return face
	end

	local yes = button("Yes", "Yes", 0, C.Green)
	local no = button("No", "No", BUTTON_W + 12, C.Ink)
	yes.NextSelectionRight = no
	no.NextSelectionLeft = yes

	local boxUid: string? = nil
	local choosing = false
	local bound = false

	local function hide()
		holder.Visible = false
		choosing = false
		boxUid = nil
		if bound then
			ContextActionService:UnbindAction(ACTION)
			bound = false
		end
		local selected = GuiService.SelectedObject
		if selected == yes or selected == no then
			GuiService.SelectedObject = nil
		end
	end

	local function choose(which: string)
		local uid = boxUid
		local offer = choosing
		hide()
		if offer and uid ~= nil then
			Net.Remote("Dialogue"):FireServer("pick", which, uid)
		end
	end

	local function bind()
		if bound then
			return
		end
		bound = true
		ContextActionService:BindAction(ACTION, function(_name: string, state: Enum.UserInputState, input: InputObject)
			if not holder.Visible or state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			local key = input.KeyCode
			if key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Escape then
				choose("no")
				return Enum.ContextActionResult.Sink
			end
			if choosing and (key == Enum.KeyCode.ButtonX or key == Enum.KeyCode.E) then
				choose("yes")
				return Enum.ContextActionResult.Sink
			end
			return Enum.ContextActionResult.Pass
		end, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape, Enum.KeyCode.ButtonX, Enum.KeyCode.E)
	end

	local function show(payload: any)
		if type(payload) ~= "table" or type(payload.text) ~= "string" then
			return
		end
		line.Text = payload.text
		-- The Robux shelf's yes: ask Roblox for that pass or pack with the
		-- intent the Store screen sends. The server checks it again.
		local robux = payload.robux
		if type(robux) == "table" and type(robux.kind) == "string" and type(robux.key) == "string" then
			Net.Remote("BuyRobuxItem"):FireServer(robux.kind, robux.key)
		end
		choosing = payload.choice == true
		boxUid = if type(payload.boxUid) == "string" then payload.boxUid else nil
		yes.Visible = choosing
		local cancel = if type(payload.noLabel) == "string" then payload.noLabel else "No"
		no.Text = if choosing then cancel else "Close"
		no.Position = if choosing then UDim2.fromOffset(BUTTON_W + 12, 52) else UDim2.fromOffset(90, 52)
		holder.Visible = true
		bind()
		if choosing then
			GuiService.SelectedObject = yes
		end
	end

	yes.Activated:Connect(function()
		choose("yes")
	end)
	no.Activated:Connect(function()
		choose("no")
	end)

	Net.Remote("Dialogue").OnClientEvent:Connect(show)
	gui.Parent = player:WaitForChild("PlayerGui")
end

return DialogueUI
