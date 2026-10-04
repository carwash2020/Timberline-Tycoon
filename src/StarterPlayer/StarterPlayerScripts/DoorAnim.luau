--!strict
-- DoorAnim: tweens a door or gate leaf on this client. The server has
-- already moved the collider and set Open. Only ItemVisual parts move here.

local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local DoorLogic = require(game:GetService("ReplicatedStorage").Shared.DoorLogic)

local DoorAnim = {}

local INFO = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function swing(model: Model, open: boolean)
	local pivot = model:GetPivot()
	for _, child in ipairs(model:GetDescendants()) do
		if
			child:IsA("BasePart")
			and child:GetAttribute("Swing") == true
			and child:GetAttribute("ItemVisual") == true
		then
			local ox = child:GetAttribute("OX")
			local oy = child:GetAttribute("OY")
			local oz = child:GetAttribute("OZ")
			local hinge = child:GetAttribute("HingeX")
			local offset = Vector3.new(
				if type(ox) == "number" then ox else 0,
				if type(oy) == "number" then oy else 0,
				if type(oz) == "number" then oz else 0
			)
			local goal =
				DoorLogic.WorldCF(pivot, offset, if type(hinge) == "number" then hinge else DoorLogic.HingeX, open)
			TweenService:Create(child, INFO, { CFrame = goal }):Play()
		end
	end
end

function DoorAnim.Start()
	CollectionService:GetInstanceAddedSignal("PlacedItem"):Connect(function(model: Instance)
		if not model:IsA("Model") then
			return
		end
		model:GetAttributeChangedSignal("Open"):Connect(function()
			swing(model, model:GetAttribute("Open") == true)
		end)
	end)
	for _, model in ipairs(CollectionService:GetTagged("PlacedItem")) do
		if model:IsA("Model") then
			model:GetAttributeChangedSignal("Open"):Connect(function()
				swing(model, model:GetAttribute("Open") == true)
			end)
		end
	end
end

return DoorAnim
