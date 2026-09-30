--!strict
-- TreeUI: floating HP bars over trees.
-- One BillboardGui per tree, listening to the server's HP attribute.
-- Bars show only while a tree is damaged: hidden at full HP and once felled.

local CollectionService = game:GetService("CollectionService")

local TreeUI = {}

local BAR_MAX_DISTANCE = 80 -- studs; farther bars aren't drawn

type Bar = { gui: BillboardGui, fill: Frame, conn: RBXScriptConnection }

local bars: { [Model]: Bar } = {}

local function barOffset(model: Model): Vector3
	return Vector3.new(0, (model:GetAttribute("BarOffset") :: number?) or 8, 0)
end

local function refresh(model: Model)
	local bar = bars[model]
	if not bar then
		return
	end
	local hp = model:GetAttribute("HP") :: number?
	local maxHp = model:GetAttribute("MaxHP") :: number?
	if hp == nil or maxHp == nil or maxHp <= 0 then
		bar.gui.Enabled = false
		return
	end
	local frac = math.clamp(hp / maxHp, 0, 1)
	bar.gui.Enabled = frac > 0 and frac < 1
	bar.fill.Size = UDim2.fromScale(frac, 1)
	if frac > 0.5 then
		bar.fill.BackgroundColor3 = Color3.fromRGB(115, 185, 80)
	elseif frac > 0.25 then
		bar.fill.BackgroundColor3 = Color3.fromRGB(220, 170, 60)
	else
		bar.fill.BackgroundColor3 = Color3.fromRGB(200, 70, 50)
	end
end

local function attach(model: Model)
	if bars[model] then
		return
	end
	local adornee = model.PrimaryPart or model:FindFirstChild("Trunk")
	if not adornee or not adornee:IsA("BasePart") then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TreeHP"
	billboard.Size = UDim2.fromScale(4, 0.5)
	billboard.StudsOffsetWorldSpace = barOffset(model) -- world up, whatever the trunk's rotation
	billboard.MaxDistance = BAR_MAX_DISTANCE
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.Adornee = adornee

	local bg = Instance.new("Frame")
	bg.Name = "HPBg"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(40, 25, 15)
	bg.BorderSizePixel = 0
	bg.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "HPFill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(115, 185, 80)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	billboard.Parent = model
	bars[model] = {
		gui = billboard,
		fill = fill,
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
	for _, inst in ipairs(CollectionService:GetTagged("Tree")) do
		if inst:IsA("Model") then
			attach(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal("Tree"):Connect(function(inst)
		if inst:IsA("Model") then
			attach(inst)
		end
	end)
	-- Fires when a tree streams out of range, too.
	CollectionService:GetInstanceRemovedSignal("Tree"):Connect(function(inst)
		if inst:IsA("Model") then
			detach(inst)
		end
	end)
end

return TreeUI
