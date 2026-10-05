--!strict
-- AdminUI: the owner's menu, for a controller (a pad can't type chat
-- commands). Only the owner sees it: the server sets the IsOwner attribute
-- on the owner's player, and this module builds nothing without it. That is
-- a convenience, not the lock: every press fires the AdminRun remote with a
-- small request, and AdminService refuses it unless the sender is the owner
-- (and again for each command). A modified client gets nothing.
--
-- The OWNER side button, or both thumbsticks clicked at once (L3 + R3),
-- opens it. D-pad moves, A presses, B closes. Pick a player and an amount
-- and press Give, Take, Set cash, Go to, Bring or Kick (a second press
-- confirms), toggle Super run, or choose an item and Gift it for free.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local InputKit = require(ReplicatedStorage.Shared.InputKit)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local Util = require(ReplicatedStorage.Shared.Util)
local HUD = require(script.Parent.HUD)
local MenuPad = require(script.Parent.MenuPad)
local UITheme = require(script.Parent.UITheme)

local AdminUI = {}

local C = UITheme.Colors
local player = Players.LocalPlayer

local CLOSE_ACTION = "AdminClose"
local AMOUNTS = { 100, 1000, 10000, 100000, 1000000 }
local KINDS = { "Axe", "Gear", "Sawmill", "Machine", "Blueprint" }

type Item = { id: string, name: string }

local panel: Frame? = nil
local sideButton: UITheme.Button? = nil
local firstPick: GuiButton? = nil

local targetIndex = 1
local amountIndex = 2
local kindIndex = 1
local itemIndex = 1
local armedKick: number? = nil -- os.clock() of the first Kick press

local targetLabel: TextLabel? = nil
local amountLabel: TextLabel? = nil
local kindLabel: TextLabel? = nil
local itemLabel: TextLabel? = nil
local kickButton: UITheme.Button? = nil

local function isOwner(): boolean
	return player:GetAttribute("IsOwner") == true
end

local function names(): { string }
	local out: { string } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(out, p.Name)
	end
	table.sort(out)
	return out
end

local function target(): string?
	local all = names()
	if #all == 0 then
		return nil
	end
	targetIndex = ((targetIndex - 1) % #all) + 1
	return all[targetIndex]
end

local function items(kind: string): { Item }
	local out: { Item } = {}
	if kind == "Axe" then
		for _, axe in ipairs(ItemCatalog.AxeLadder()) do
			table.insert(out, { id = axe.id, name = axe.displayName })
		end
	elseif kind == "Gear" then
		for _, gear in ipairs(ItemCatalog.GearList()) do
			table.insert(out, { id = gear.id, name = gear.displayName })
		end
	elseif kind == "Sawmill" then
		for _, mill in ipairs(ItemCatalog.SawmillList()) do
			table.insert(out, { id = mill.id, name = mill.displayName })
		end
	elseif kind == "Machine" then
		for _, machine in ipairs(ItemCatalog.MachineList()) do
			table.insert(out, { id = machine.id, name = machine.displayName })
		end
	else
		for _, bp in ipairs(PlotData.Blueprints) do
			if bp.unlock == true then
				table.insert(out, { id = bp.id, name = bp.displayName })
			end
		end
	end
	return out
end

local function currentItem(): Item?
	local list = items(KINDS[kindIndex])
	if #list == 0 then
		return nil
	end
	itemIndex = ((itemIndex - 1) % #list) + 1
	return list[itemIndex]
end

local function refresh()
	local who = target()
	if targetLabel then
		targetLabel.Text = who or "(nobody)"
	end
	if amountLabel then
		amountLabel.Text = Util.formatCash(AMOUNTS[amountIndex])
	end
	if kindLabel then
		kindLabel.Text = KINDS[kindIndex]
	end
	if itemLabel then
		local item = currentItem()
		itemLabel.Text = if item then item.name else "(none)"
	end
end

local function send(request: { [string]: any })
	Net.Remote("AdminRun"):FireServer(request)
end

local function setOpen(on: boolean)
	local p = panel
	if not p then
		return
	end
	if on and not isOwner() then
		return
	end
	p.Visible = on
	if not on then
		ContextActionService:UnbindAction(CLOSE_ACTION)
		MenuPad.Close(p)
		return
	end
	refresh()
	ContextActionService:BindActionAtPriority(
		CLOSE_ACTION,
		function(_name, state)
			if state ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end
			setOpen(false)
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 30,
		InputKit.Actions.Cancel.keyboard,
		InputKit.Actions.Cancel.gamepad
	)
	if UITheme.Device() == "console" then
		MenuPad.Open(firstPick)
	end
end

local function toggle()
	local p = panel
	setOpen(not (p ~= nil and p.Visible))
end

-- One row: a caption, ‹ value ›. `step(+1 | -1)` changes it and refreshes.
local function stepper(parent: Frame, order: number, caption: string, step: (number) -> ()): TextLabel
	local row = Instance.new("Frame")
	row.Name = caption
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 44)
	row.Parent = parent
	local cap = UITheme.label(row, caption, UITheme.Fonts.Black, 15, C.Ink)
	cap.Size = UDim2.fromOffset(70, 44)
	local left =
		UITheme.Button({ text = "‹", size = Vector2.new(44, 38), style = "bark", textSize = 24, name = "Prev" })
	left.root.Position = UDim2.fromOffset(74, 0)
	left.root.Parent = row
	left.face.Activated:Connect(function()
		step(-1)
	end)
	local value = UITheme.label(row, "", UITheme.Fonts.Heading, 17, C.Ink)
	value.Position = UDim2.fromOffset(122, 0)
	value.Size = UDim2.new(1, -212, 0, 44)
	value.TextXAlignment = Enum.TextXAlignment.Center
	local right =
		UITheme.Button({ text = "›", size = Vector2.new(44, 38), style = "bark", textSize = 24, name = "Next" })
	right.root.AnchorPoint = Vector2.new(1, 0)
	right.root.Position = UDim2.fromScale(1, 0)
	right.root.Parent = row
	right.face.Activated:Connect(function()
		step(1)
	end)
	if not firstPick then
		firstPick = left.face
	end
	return value
end

local function actionRow(parent: Frame, order: number, specs: { { text: string, style: string, run: () -> () } })
	local row = Instance.new("Frame")
	row.Name = "Actions" .. order
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 46)
	row.Parent = parent
	UITheme.list(row, 8, true)
	local width = (360 - 8 * (#specs - 1)) / #specs
	for i, spec in ipairs(specs) do
		local b = UITheme.Button({
			text = spec.text,
			size = Vector2.new(width, 40),
			style = spec.style,
			textSize = 15,
			name = spec.text,
		})
		b.root.LayoutOrder = i
		b.root.Parent = row
		b.face.Activated:Connect(spec.run)
		if spec.text == "KICK" then
			kickButton = b
		end
	end
end

local function aim(action: string)
	local who = target()
	if who then
		send({ action = action, target = who, amount = AMOUNTS[amountIndex] })
	end
end

function AdminUI.Start()
	local gui = UITheme.Screen("AdminUI", UITheme.Layers.Admin)
	gui.Parent = UITheme.PlayerGui()

	local outer = Instance.new("Frame")
	outer.Name = "Owner"
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.Size = UDim2.fromOffset(392, 420)
	outer.BackgroundColor3 = C.Paper
	outer.BorderSizePixel = 0
	outer.Visible = false
	UITheme.corner(outer, 14)
	UITheme.stroke(outer, C.Bark, 3)
	outer.Parent = gui
	panel = outer

	local title = UITheme.label(outer, "Owner tools", UITheme.Fonts.Heading, 24, C.Ink)
	title.Position = UDim2.fromOffset(16, 10)
	title.Size = UDim2.new(1, -70, 0, 34)

	local close = UITheme.Button({ text = "X", size = Vector2.new(44, 44), style = "skip", textSize = 18 })
	close.root.Position = UDim2.new(1, -52, 0, 8)
	close.root.Parent = outer
	close.face.Activated:Connect(function()
		setOpen(false)
	end)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(16, 56)
	body.Size = UDim2.new(1, -32, 1, -68)
	body.Parent = outer
	UITheme.list(body, 6)

	targetLabel = stepper(body, 1, "Player", function(d)
		targetIndex += d
		refresh()
	end)
	amountLabel = stepper(body, 2, "Amount", function(d)
		amountIndex = ((amountIndex - 1 + d) % #AMOUNTS) + 1
		refresh()
	end)
	actionRow(body, 3, {
		{
			text = "GIVE",
			style = "buy",
			run = function()
				aim("give")
			end,
		},
		{
			text = "TAKE",
			style = "bark",
			run = function()
				aim("take")
			end,
		},
		{
			text = "SET CASH",
			style = "bark",
			run = function()
				local who = target()
				if who then
					send({ action = "setcash", target = who, amount = AMOUNTS[amountIndex] })
				end
			end,
		},
	})
	actionRow(body, 4, {
		{
			text = "GO TO",
			style = "bark",
			run = function()
				local who = target()
				if who then
					send({ action = "goto", target = who })
				end
			end,
		},
		{
			text = "BRING",
			style = "bark",
			run = function()
				local who = target()
				if who then
					send({ action = "bring", target = who })
				end
			end,
		},
		{
			text = "KICK",
			style = "skip",
			run = function()
				local now = os.clock()
				local who = target()
				if not who then
					return
				end
				local armed = armedKick
				if armed and now - armed < 4 then
					armedKick = nil
					if kickButton then
						kickButton.face.Text = "KICK"
					end
					send({ action = "kick", target = who })
				else
					armedKick = now
					if kickButton then
						kickButton.face.Text = "SURE?"
					end
					task.delay(4, function()
						if armedKick == now then
							armedKick = nil
							if kickButton then
								kickButton.face.Text = "KICK"
							end
						end
					end)
				end
			end,
		},
	})
	kindLabel = stepper(body, 5, "Item type", function(d)
		kindIndex = ((kindIndex - 1 + d) % #KINDS) + 1
		itemIndex = 1
		refresh()
	end)
	itemLabel = stepper(body, 6, "Item", function(d)
		itemIndex += d
		refresh()
	end)
	actionRow(body, 7, {
		{
			text = "GIFT IT FREE",
			style = "buy",
			run = function()
				local who, item = target(), currentItem()
				if who and item then
					send({ action = "gift", target = who, kind = KINDS[kindIndex], itemId = item.id })
				end
			end,
		},
		{
			text = "SUPER RUN",
			style = "bark",
			run = function()
				send({ action = "superrun" })
			end,
		},
	})

	Players.PlayerAdded:Connect(refresh)
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end)

	-- The side button and the L3 + R3 chord exist only for the owner.
	local function syncOwner()
		local owner = isOwner()
		if sideButton then
			sideButton.root.Visible = owner
		end
		if not owner then
			setOpen(false)
		end
	end
	local side = HUD.SideButton({
		name = "Owner",
		text = "OWNER",
		style = "bark",
		order = 0,
		onPress = toggle,
	})
	side.root.Visible = false
	sideButton = side
	player:GetAttributeChangedSignal("IsOwner"):Connect(syncOwner)
	syncOwner()

	UserInputService.InputBegan:Connect(function(input: InputObject)
		if
			isOwner()
			and (input.KeyCode == Enum.KeyCode.ButtonL3 or input.KeyCode == Enum.KeyCode.ButtonR3)
			and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonL3)
			and UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonR3)
		then
			toggle()
		end
	end)
end

return AdminUI
