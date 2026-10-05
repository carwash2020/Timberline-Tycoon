--!strict
-- TreeUI: floating HP bars over trees and crystal nodes.
-- One BillboardGui per tree, listening to the server's HP attribute.
-- Bars show only while a tree is damaged: hidden at full HP and once felled.
-- The bar is a UITheme pill (Paper track, Ink stroke, a Green fill that
-- turns Amber at half HP and Danger at a quarter), a fixed size on screen,
-- unlit, and drawn on top: it floats inside the trunk you're chopping
-- (TreeArt.BarHeight puts it just over your head), which would hide it.

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")

local MenuPad = require(script.Parent.MenuPad)
local UITheme = require(script.Parent.UITheme)

local C = UITheme.Colors

local TreeUI = {}

TreeUI.MaxDistance = 60 -- studs; farther bars aren't drawn
TreeUI.Width = 110 -- the pill, in pixels
TreeUI.Height = 12
TreeUI.Stroke = 2

type Bar = { gui: BillboardGui, fill: Frame, focus: TextButton, conn: RBXScriptConnection }

local barOpen = false

-- A bar only takes the pad when nothing else has it and no tool is in
-- hand. Chopping means an axe in hand, and a selected bar would drop the
-- D-pad shortcuts and the side buttons mid-swing.
function TreeUI.ShouldFocus(selected: Instance?, toolHeld: boolean): boolean
	return selected == nil and not toolHeld
end

local function toolHeld(): boolean
	local char = Players.LocalPlayer and Players.LocalPlayer.Character
	return char ~= nil and char:FindFirstChildOfClass("Tool") ~= nil
end

function TreeUI._open(button: GuiObject?)
	if GuiService.SelectedObject ~= nil and button and GuiService.SelectedObject ~= button then
		return
	end
	barOpen = true
	MenuPad.Open(button)
end

function TreeUI._close(root: Instance?)
	barOpen = false
	MenuPad.Close(root)
end

function TreeUI.ApplyKey(key: Enum.KeyCode): string?
	if not barOpen or not MenuPad.Closes(key) then
		return nil
	end
	TreeUI._close(nil)
	return "close"
end

local bars: { [Model]: Bar } = {}

local function barOffset(model: Model): Vector3
	local offset = model:GetAttribute("BarOffset")
	return Vector3.new(0, if type(offset) == "number" then offset else 8, 0)
end

-- The fill's colour at this fraction of HP left.
function TreeUI.FillColor(frac: number): Color3
	if frac <= 0.25 then
		return C.Danger
	elseif frac <= 0.5 then
		return C.Amber
	end
	return C.Green
end

-- A hidden bar `offset` studs (world space) from its adornee's centre:
-- the BillboardGui and its fill.
function TreeUI.MakeBar(offset: Vector3): (BillboardGui, Frame)
	local w, h, stroke = TreeUI.Width, TreeUI.Height, TreeUI.Stroke
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TreeHP"
	-- Room for the stroke, which is drawn outside the track.
	billboard.Size = UDim2.fromOffset(w + stroke * 2, h + stroke * 2)
	billboard.StudsOffsetWorldSpace = offset -- world up, whatever the trunk's rotation
	billboard.MaxDistance = TreeUI.MaxDistance
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0 -- the same colours by night as by day
	billboard.Enabled = false

	local track = Instance.new("Frame")
	track.Name = "HPBg"
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.5)
	track.Size = UDim2.fromOffset(w, h)
	track.BackgroundColor3 = C.Paper
	track.BorderSizePixel = 0
	UITheme.corner(track, h / 2)
	UITheme.stroke(track, C.Ink, stroke)
	track.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "HPFill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = C.Green
	fill.BorderSizePixel = 0
	UITheme.corner(fill, h / 2)
	fill.Parent = track

	local focus = Instance.new("TextButton")
	focus.Name = "Focus"
	focus.Size = UDim2.fromScale(1, 1)
	focus.BackgroundTransparency = 1
	focus.Text = ""
	focus.Selectable = true
	focus.Parent = track
	return billboard, fill
end

local function refresh(model: Model)
	local bar = bars[model]
	if not bar then
		return
	end
	local hp = model:GetAttribute("HP")
	local maxHp = model:GetAttribute("MaxHP")
	local was = bar.gui.Enabled
	if type(hp) ~= "number" or type(maxHp) ~= "number" or maxHp <= 0 then
		bar.gui.Enabled = false
		if was then
			TreeUI._close(bar.gui)
		end
		return
	end
	local frac = math.clamp(hp / maxHp, 0, 1)
	bar.gui.Enabled = frac > 0 and frac < 1
	if bar.gui.Enabled and not was and TreeUI.ShouldFocus(GuiService.SelectedObject, toolHeld()) then
		TreeUI._open(bar.focus)
	elseif not bar.gui.Enabled and was then
		TreeUI._close(bar.gui)
	end
	bar.fill.Size = UDim2.fromScale(frac, 1)
	bar.fill.BackgroundColor3 = TreeUI.FillColor(frac)
end

local function attach(model: Model)
	if bars[model] then
		return
	end
	local adornee = model.PrimaryPart or model:FindFirstChild("Trunk")
	if not adornee or not adornee:IsA("BasePart") then
		return
	end

	local billboard, fill = TreeUI.MakeBar(barOffset(model))
	billboard.Adornee = adornee
	billboard.Parent = model
	local focus = billboard:FindFirstChild("Focus", true)
	bars[model] = {
		gui = billboard,
		fill = fill,
		focus = focus :: TextButton,
		conn = model:GetAttributeChangedSignal("HP"):Connect(function()
			refresh(model)
		end),
	}
	refresh(model)
end

local function detach(model: Model)
	local bar = bars[model]
	if bar then
		bar.conn:Disconnect()
		bar.gui:Destroy()
		bars[model] = nil
	end
end

function TreeUI.Start()
	-- Trees, and the crystal nodes on the Aether Isles (same HP attributes).
	for _, tag in ipairs({ "Tree", "Node" }) do
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			if inst:IsA("Model") then
				attach(inst)
			end
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
			if inst:IsA("Model") then
				attach(inst)
			end
		end)
		-- Fires when a model streams out of range, too.
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst)
			if inst:IsA("Model") then
				detach(inst)
			end
		end)
	end
end

return TreeUI
