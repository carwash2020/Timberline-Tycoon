--!strict
-- StoreStandState: greys a store stand while its item is locked for you, and
-- shows the lock chip with what opens it ("NEEDS STEEL", "S3 BUILDER").
-- Display only: the server still decides every purchase. The rules are
-- Shared/StoreTier.IsLocked (the same ones ShopLogic and the stage rules
-- use); the stands are the parts ShopKit.TierStand tags "StoreStand", each
-- carrying StandKind / StandItem / StandRole ("base", "flag", "chip") and
-- StandOpen (its colour when open). A locked stand's plinth and flag turn
-- the locked grey with light text; an open one gets its tier colour back and
-- the chip is hidden. It follows the player's own "BestAxeTier" and
-- "StoreStage" attributes, so it updates the moment either one changes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StoreTier = require(ReplicatedStorage.Shared.StoreTier)

local StoreStandState = {}

local player = Players.LocalPlayer

local TAG = "StoreStand"

local function numberAttr(name: string, default: number): number
	local v = player:GetAttribute(name)
	return if type(v) == "number" then v else default
end

-- Whether the player is behind the lock of the item a stand part belongs to.
function StoreStandState.LockedFor(part: Instance, stage: number, bestAxeTier: number): boolean
	local kind = part:GetAttribute("StandKind")
	local item = part:GetAttribute("StandItem")
	if type(kind) ~= "string" or type(item) ~= "string" then
		return false
	end
	return StoreTier.IsLocked(kind, item, stage, bestAxeTier)
end

local function apply(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local locked = StoreStandState.LockedFor(part, numberAttr("StoreStage", 1), numberAttr("BestAxeTier", 1))
	local role = part:GetAttribute("StandRole")
	local open = part:GetAttribute("StandOpen")
	if role == "chip" then
		part.Transparency = if locked then 0 else 1
		for _, d in ipairs(part:GetChildren()) do
			if d:IsA("SurfaceGui") then
				d.Enabled = locked
			end
		end
		return
	end
	if typeof(open) ~= "Color3" then
		return
	end
	part.Color = if locked then StoreTier.LockedColor else open
	for _, d in ipairs(part:GetChildren()) do
		if d:IsA("SurfaceGui") then
			for _, label in ipairs(d:GetChildren()) do
				if label:IsA("TextLabel") then
					label.TextColor3 = if locked then StoreTier.LockedInk else StoreTier.InkOn(open)
				end
			end
		end
	end
end

local function refreshAll()
	for _, part in ipairs(CollectionService:GetTagged(TAG)) do
		apply(part)
	end
end

function StoreStandState.Start()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(apply)
	for _, name in ipairs({ "StoreStage", "BestAxeTier" }) do
		player:GetAttributeChangedSignal(name):Connect(refreshAll)
	end
	refreshAll()
end

return StoreStandState
