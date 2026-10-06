--!strict
-- BoxPoof: the empty box folds away. When the server opens a box it sets
-- Poof = true on the box model and destroys it BoxUnpack.PoofSeconds later;
-- here the box fades and puffs a little cloud in that time. Looks only.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local BoxUnpack = require(ReplicatedStorage.Shared.BoxUnpack)

local BoxPoof = {}

local started: { [Instance]: boolean } = {}

local function puff(model: Model)
	local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if body == nil then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "PoofCloud"
	emitter.Color = ColorSequence.new(Color3.fromRGB(240, 232, 215))
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime = NumberRange.new(0.4, 0.7)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Parent = body
	emitter:Emit(18)
end

local function fold(model: Model)
	if started[model] then
		return
	end
	started[model] = true
	puff(model)
	local info = TweenInfo.new(BoxUnpack.PoofSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			TweenService:Create(d, info, { Transparency = 1 }):Play()
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			(d :: any).Enabled = false
		end
	end
end

local function watch(model: Instance)
	if not model:IsA("Model") then
		return
	end
	model:GetAttributeChangedSignal("Poof"):Connect(function()
		if model:GetAttribute("Poof") == true then
			fold(model)
		end
	end)
	if model:GetAttribute("Poof") == true then
		fold(model)
	end
end

function BoxPoof.Start()
	CollectionService:GetInstanceAddedSignal("ShopBox"):Connect(watch)
	for _, model in ipairs(CollectionService:GetTagged("ShopBox")) do
		watch(model)
	end
end

return BoxPoof
