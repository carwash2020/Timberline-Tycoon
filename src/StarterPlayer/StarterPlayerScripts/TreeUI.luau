-- TreeUI: floating HP bars over trees.
-- One BillboardGui per living tree, listening to the server's HP attribute.
-- Bars hide on full HP and when the tree is felled.

local CollectionService = game:GetService("CollectionService")

local TreeUI = {}

local guis: { [string]: BillboardGui } = {}

local function buildGui(model: Model): BillboardGui
	local bg = Instance.new("Frame")
	bg.Name = "HPBg"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(40, 25, 15)
	bg.BorderSizePixel = 0
	bg.Parent = nil

	local fill = Instance.new("Frame")
	fill.Name = "HPFill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(115, 185, 80)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TreeHP"
	billboard.Size = UDim2.new(4, 0, 0.5, 0)
	billboard.StudsOffset = Vector3.new(0, (model:GetAttribute("BarOffset") :: number?) or 8, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	bg.Parent = billboard
	return billboard
end

local function refresh(model: Model)
	local uid = model:GetAttribute("Uid")
	if uid == nil then
		return
	end
	local gui = guis[uid :: string]
	if not gui then
		return
	end
	local hp = model:GetAttribute("HP") :: number?
	local maxHp = model:GetAttribute("MaxHP") :: number?
	if hp == nil or maxHp == nil or maxHp <= 0 then
		gui.Enabled = false
		return
	end
	local frac = math.clamp(hp / maxHp, 0, 1)
	gui.Enabled = frac < 1
	local fill = gui:FindFirstChild("HPBg", true)
	if fill then
		local f = fill:FindFirstChild("HPFill")
		if f and f:IsA("Frame") then
			f.Size = UDim2.new(frac, 0, 1, 0)
			if frac > 0.5 then
				f.BackgroundColor3 = Color3.fromRGB(115, 185, 80)
			elseif frac > 0.25 then
				f.BackgroundColor3 = Color3.fromRGB(220, 170, 60)
			else
				f.BackgroundColor3 = Color3.fromRGB(200, 70, 50)
			end
		end
	end
end

local function attach(model: Model)
	local uid = model:GetAttribute("Uid")
	if uid == nil or guis[uid :: string] then
		return
	end
	local adornee = model.PrimaryPart or model:FindFirstChild("Trunk")
	if not adornee then
		return
	end
	local gui = buildGui(model)
	gui.Adornee = adornee
	gui.Parent = model
	guis[uid :: string] = gui
	model:GetAttributeChangedSignal("HP"):Connect(function()
		refresh(model)
	end)
	model:GetAttributeChangedSignal("BarOffset"):Connect(function()
		gui.StudsOffset = Vector3.new(0, (model:GetAttribute("BarOffset") :: number?) or 8, 0)
	end)
	refresh(model)
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
	CollectionService:GetInstanceRemovedSignal("Tree"):Connect(function(inst)
		local uid = inst:GetAttribute("Uid")
		if uid ~= nil then
			guis[uid :: string] = nil
		end
	end)
end

return TreeUI
