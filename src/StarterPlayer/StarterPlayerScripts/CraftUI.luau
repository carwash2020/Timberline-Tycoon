--!strict
-- CraftUI: the bench list. One Craft button per recipe, have/need counts,
-- disabled recipes read "Coming soon". Same safe-area rules as MiningUI.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CraftData = require(ReplicatedStorage.Shared.Mining.CraftData)
local GamepadNav = require(script.Parent.GamepadNav)
local MiningUI = require(script.Parent.MiningUI)
local UITheme = require(script.Parent.UITheme)

local CraftUI = {}

local C = UITheme.Colors
local F = UITheme.Fonts

local screen: ScreenGui? = nil
local panel: Frame? = nil
local list: GuiObject? = nil
local open = false
local ready = true

function CraftUI.Rects(w: number, h: number): MiningUI.Rect
	local margin = 12
	local top = h * 0.5
	return {
		x = margin,
		y = margin,
		w = math.min(420, w - margin * 2),
		h = math.max(96, top - margin * 2),
	}
end

local function build(viewport: Vector2): ScreenGui
	local gui = UITheme.Screen("CraftUI", UITheme.Layers.World)
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local rect = CraftUI.Rects(viewport.X, viewport.Y)
	local shop = Instance.new("Frame")
	shop.Name = "Bench"
	shop.BackgroundColor3 = C.Paper
	shop.Position = UDim2.fromOffset(rect.x, rect.y)
	shop.Size = UDim2.fromOffset(rect.w, rect.h)
	shop.Visible = false
	shop.Parent = gui
	UITheme.padding(shop, 8, 8, 8, 8)
	local title = UITheme.label(shop, "Craft", F.Heading, 18, C.Ink)
	title.Size = UDim2.new(1, -72, 0, 28)
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
	local rows = Instance.new("ScrollingFrame")
	rows.Name = "Rows"
	rows.BackgroundTransparency = 1
	rows.BorderSizePixel = 0
	rows.Position = UDim2.fromOffset(0, 48)
	rows.Size = UDim2.new(1, 0, 1, -52)
	rows.CanvasSize = UDim2.fromOffset(0, 0)
	rows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rows.ScrollBarThickness = 6
	rows.Parent = shop
	UITheme.list(rows, 8)
	panel = shop
	list = rows
	screen = gui
	return gui
end

export type Have = { [string]: number }

function CraftUI.SetReady(flag: boolean)
	ready = flag
end

function CraftUI.Ensure(viewport: Vector2): ScreenGui
	if screen then
		return screen
	end
	return build(viewport)
end

function CraftUI.RemoteReady(): boolean
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild("CraftAction")
	return remote ~= nil and remote:IsA("RemoteEvent")
end

-- Have/need from parts the server already stamped. The server still
-- decides the craft. A missing tag service counts as empty.
function CraftUI.CountWorld(userId: number): ({ ingots: Have, chunks: Have }, boolean)
	local ingots: Have = {}
	local chunks: Have = {}
	local function add(models: { Instance }, bag: Have)
		for _, model in ipairs(models) do
			if model:GetAttribute("OwnerId") == userId then
				local ore = model:GetAttribute("Ore")
				if type(ore) == "string" then
					bag[ore] = (bag[ore] or 0) + 1
				end
			end
		end
	end
	local function tagged(name: string): { Instance }
		local ok, found = pcall(function()
			return CollectionService:GetTagged(name)
		end)
		if ok and type(found) == "table" then
			return found
		end
		return {}
	end
	add(tagged("Ingot"), ingots)
	add(tagged("OreChunk"), chunks)
	local logOk = false
	for _, model in ipairs(tagged("Wood")) do
		if model:GetAttribute("Owner") == userId then
			local volume = model:GetAttribute("Volume")
			if type(volume) == "number" and volume >= CraftData.LogVolume then
				logOk = true
			end
		end
	end
	return { ingots = ingots, chunks = chunks }, logOk
end

function CraftUI.Fill(stock: { ingots: Have, chunks: Have }, logOk: boolean)
	local rows = list
	if rows == nil then
		return
	end
	for _, child in ipairs(rows:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, recipe in ipairs(CraftData.All()) do
		local block = Instance.new("Frame")
		block.Name = recipe.id
		block.BackgroundColor3 = C.PaperDark
		block.Size = UDim2.new(1, -8, 0, 44)
		block.Parent = rows
		local bits = {}
		for _, need in ipairs(recipe.needs) do
			if need.kind == "log" then
				table.insert(bits, string.format("Log %d/1", if logOk then 1 else 0))
			else
				local bag = if need.kind == "ingot" then stock.ingots else stock.chunks
				local have = bag[need.ore or ""] or 0
				table.insert(bits, string.format("%s %d/%d", need.ore or "", have, need.n or 0))
			end
		end
		local name = UITheme.label(block, recipe.name .. "  " .. table.concat(bits, "  "), F.Body, 14, C.Ink)
		name.Size = UDim2.new(1, -96, 1, 0)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local button = Instance.new("TextButton")
		button.Name = "Craft"
		button.Font = F.Bold
		button.TextSize = 14
		button.TextColor3 = C.Cream
		button.Size = UDim2.fromOffset(88, 44)
		button.Position = UDim2.new(1, -88, 0, 0)
		button.Parent = block
		if not ready or not recipe.enabled then
			button.Text = "Soon"
			button.BackgroundColor3 = C.Muted
			button.AutoButtonColor = false
		else
			button.Text = "Craft"
			button.BackgroundColor3 = C.Money
			button.Activated:Connect(function()
				CraftUI.Fire(recipe.id)
			end)
		end
	end
end

function CraftUI.Open()
	if screen == nil then
		CraftUI.Ensure(Vector2.new(1920, 1080))
	end
	if panel == nil or screen == nil then
		return
	end
	panel.Visible = true
	open = true
	local first = list and list:FindFirstChildWhichIsA("TextButton", true)
	GamepadNav.Focus(first, panel)
	screen.Enabled = true
end

function CraftUI.Close()
	if panel then
		panel.Visible = false
	end
	open = false
	GamepadNav.Restore(panel)
end

function CraftUI.ApplyKey(key: Enum.KeyCode): string?
	if not open then
		return nil
	end
	if key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Escape then
		CraftUI.Close()
		return "close"
	end
	return nil
end

function CraftUI.Fire(recipeId: string)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local remote = folder and folder:FindFirstChild("CraftAction")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer(recipeId)
	end
end

function CraftUI.Start(opts: { ready: boolean }?)
	ready = if opts then opts.ready else true
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	if viewport.X < 1 then
		viewport = Vector2.new(1920, 1080)
	end
	local gui = build(viewport)
	gui.Parent = UITheme.PlayerGui()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		CraftUI.ApplyKey(input.KeyCode)
	end)
end

return CraftUI
