--!strict
-- MiningUI: the pick chip and the Prospector shop. Colours and fonts come
-- from UITheme. The panel stays in the top half, clear of the thumbstick
-- and the jump button, with 44 px taps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PickaxeData = require(ReplicatedStorage.Shared.Mining.PickaxeData)
local GamepadNav = require(script.Parent.GamepadNav)
local UITheme = require(script.Parent.UITheme)

local MiningUI = {}

local C = UITheme.Colors
local F = UITheme.Fonts

export type Rect = { x: number, y: number, w: number, h: number }

function MiningUI.Thumbstick(w: number, h: number): Rect
	return { x = 0, y = h * 0.5, w = w * 0.4, h = h * 0.5 }
end

function MiningUI.Jump(w: number, h: number): Rect
	return { x = w - 120, y = h - 140, w = 120, h = 140 }
end

function MiningUI.Rects(w: number, h: number): { chip: Rect, panel: Rect }
	local margin = 12
	local chip: Rect = { x = w - margin - 248, y = margin, w = 248, h = 48 }
	local top = h * 0.5
	local panel: Rect = {
		x = margin,
		y = margin + 56,
		w = math.min(340, w - margin * 2),
		h = math.max(88, top - margin - 64),
	}
	return { chip = chip, panel = panel }
end

function MiningUI.Overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local screen: ScreenGui? = nil
local chipFrame: Frame? = nil
local chipLabel: TextLabel? = nil
local panel: Frame? = nil
local list: Frame? = nil
local open = false
local ready = true

local function priceColor(afford: boolean): Color3
	return if afford then C.Money else C.Danger
end

function MiningUI.PriceColor(afford: boolean): Color3
	return priceColor(afford)
end

local function build(viewport: Vector2): ScreenGui
	local gui = UITheme.Screen("MiningUI", UITheme.Layers.Shop)
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local rects = MiningUI.Rects(viewport.X, viewport.Y)
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.BackgroundColor3 = C.Bark
	chip.Visible = false
	chip.Position = UDim2.fromOffset(rects.chip.x, rects.chip.y)
	chip.Size = UDim2.fromOffset(rects.chip.w, rects.chip.h)
	chip.Parent = gui
	chipFrame = chip
	local label = UITheme.label(chip, "Rusty Pick  ·  Lv 1", F.Bold, 14, C.Cream)
	label.Name = "ChipText"
	label.Size = UDim2.fromScale(1, 1)
	chipLabel = label
	local shop = Instance.new("Frame")
	shop.Name = "Shop"
	shop.BackgroundColor3 = C.Paper
	shop.Position = UDim2.fromOffset(rects.panel.x, rects.panel.y)
	shop.Size = UDim2.fromOffset(rects.panel.w, rects.panel.h)
	shop.Visible = false
	shop.Parent = gui
	UITheme.padding(shop, 8, 8, 8, 8)
	local title = UITheme.label(shop, "Prospector", F.Heading, 18, C.Ink)
	title.Size = UDim2.new(1, -52, 0, 28)
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.Text = "Close"
	close.Font = F.Bold
	close.TextSize = 14
	close.TextColor3 = C.Cream
	close.BackgroundColor3 = C.Bark
	close.Size = UDim2.fromOffset(64, 44)
	close.Position = UDim2.new(1, -64, 0, 0)
	close.Parent = shop
	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.Position = UDim2.fromOffset(0, 48)
	rows.Size = UDim2.new(1, 0, 1, -52)
	rows.Parent = shop
	UITheme.list(rows, 8)
	panel = shop
	list = rows
	screen = gui
	return gui
end

function MiningUI.Ensure(viewport: Vector2): ScreenGui
	if screen then
		return screen
	end
	return build(viewport)
end

local function rowButton(text: string, afford: boolean): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Buy"
	button.Text = text
	button.Font = F.Bold
	button.TextSize = 14
	button.TextColor3 = C.Cream
	button.BackgroundColor3 = priceColor(afford)
	button.Size = UDim2.new(1, 0, 0, 44)
	button.Parent = list
	return button
end

function MiningUI.FillShop(cash: number, owned: { [string]: boolean })
	local rows = list
	if rows == nil then
		return
	end
	for _, child in ipairs(rows:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if not ready then
		local note = UITheme.label(rows, "Coming soon", F.Body, 14, C.Ink)
		note.Size = UDim2.new(1, 0, 0, 44)
		return
	end
	for _, pick in ipairs(PickaxeData.Shop()) do
		if pick.price > 0 and owned[pick.id] ~= true then
			local afford = cash >= pick.price
			local button = rowButton(string.format("%s  $%d", pick.name, pick.price), afford)
			button:SetAttribute("PickId", pick.id)
			button.Activated:Connect(function()
				MiningUI.Fire("buyPick", pick.id, nil)
			end)
		end
	end
	local price = GameConfig.DynamitePrice
	local bombs = rowButton(string.format("Bomb  $%d", price), cash >= price)
	bombs.Activated:Connect(function()
		MiningUI.Fire("buyBomb", nil, 1)
	end)
end

function MiningUI.SetChip(text: string)
	if chipLabel then
		chipLabel.Text = text
	end
end

function MiningUI.SetChipVisible(on: boolean)
	if chipFrame then
		chipFrame.Visible = on
	end
end

-- One line: the equipped pick, its level, bombs, and the lamp or hat.
function MiningUI.ChipLine(name: string, level: number, bombs: number, lamp: boolean, hat: boolean): string
	local text = string.format("%s  ·  Lv %d", name, level)
	if bombs > 0 then
		text ..= string.format("  ·  Bombs %d", bombs)
	end
	if lamp then
		text ..= "  ·  Lamp"
	end
	if hat then
		text ..= "  ·  Hat"
	end
	return text
end

function MiningUI.OwnedMap(raw: unknown): { [string]: boolean }
	local owned: { [string]: boolean } = {}
	if type(raw) ~= "string" then
		return owned
	end
	for id in string.gmatch(raw, "[^,]+") do
		owned[id] = true
	end
	return owned
end

function MiningUI.SetReady(flag: boolean)
	ready = flag
end

function MiningUI.RemoteReady(): boolean
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild("MineAction")
	return remote ~= nil and remote:IsA("RemoteEvent")
end

function MiningUI.Open()
	local gui = MiningUI.Ensure(Vector2.new(1920, 1080))
	if panel == nil then
		return
	end
	panel.Visible = true
	open = true
	local first = list and list:FindFirstChildWhichIsA("TextButton")
	GamepadNav.Focus(first, panel)
	gui.Enabled = true
end

function MiningUI.Close()
	if panel then
		panel.Visible = false
	end
	open = false
	GamepadNav.Restore(panel)
end

function MiningUI.ApplyKey(key: Enum.KeyCode): string?
	if not open then
		return nil
	end
	if key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Escape then
		MiningUI.Close()
		return "close"
	end
	return nil
end

function MiningUI.Fire(op: string, id: string?, n: number?)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild("MineAction")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(op, id, n)
	end
end

function MiningUI.Start(opts: { ready: boolean }?)
	ready = if opts then opts.ready else true
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	if viewport.X < 1 then
		viewport = Vector2.new(1920, 1080)
	end
	local gui = build(viewport)
	local playerGui = UITheme.PlayerGui()
	gui.Parent = playerGui
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		MiningUI.ApplyKey(input.KeyCode)
	end)
end

return MiningUI
