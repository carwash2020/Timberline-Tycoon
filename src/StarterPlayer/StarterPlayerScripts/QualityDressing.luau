--!strict
-- QualityDressing: the part of the Lower / Higher quality choice that lives
-- on the player's own client (Shared/QualityProfile picks the tier, Quality
-- hands out its budget):
--   * Shop boxes (tag ShopBox): on Lower the item copy in every window is
--     taken out and the glass tinted in the item's accent colour
--     (Shared/BoxWindows), on Higher the box stays exactly as the server built
--     it. The server builds one box for everyone; only this client's view of it
--     changes, so prices, hover tags, grabbing, opening and hitboxes are the
--     same on both. A box that streams in later, or gets its Contents late, is
--     dressed the same way.
--   * Shop lights (inside the shop models, tag ShopDoorModel): the budget's
--     LightScale shortens their reach and switches their shadows off below 1.
-- Both follow a change of choice at once (Quality.OnChange). The ground decor,
-- grass tufts, filler trees and motion budgets are the existing QualityBudgets
-- readers (AmbientLife, ForestFiller, WindSway ...).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoxWindows = require(ReplicatedStorage.Shared.BoxWindows)
local QualityBudgets = require(ReplicatedStorage.Shared.QualityBudgets)
local Quality = require(script.Parent.Quality)

local QualityDressing = {}

local BOX_TAG = "ShopBox"
local SHOP_TAG = "ShopDoorModel"

local lightBase: { [Instance]: { range: number, shadows: boolean } } = setmetatable({}, { __mode = "k" }) :: any
local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function dressBox(box: Instance)
	BoxWindows.Apply(box, Quality.Budget().BoxContents)
end

local function watchBox(box: Instance)
	dressBox(box)
	if watched[box] then
		return
	end
	watched[box] = true
	-- The item arrives with the box, but a streamed-in model may add its
	-- children after the tag: dress a late Contents too.
	box.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Contents" then
			dressBox(box)
		end
	end)
	-- Gone from the world: let go of the item copy taken out of it.
	box.AncestryChanged:Connect(function(_: Instance, parent: Instance?)
		if parent == nil then
			BoxWindows.Forget(box)
		end
	end)
end

local function dressLight(d: Instance, budget: QualityBudgets.Budget)
	local light = d :: any
	local base = lightBase[d]
	if base == nil then
		base = { range = light.Range, shadows = light.Shadows }
		lightBase[d] = base
	end
	light.Range = base.range * budget.LightScale
	light.Shadows = base.shadows and budget.LightScale >= 1
end

local function dressLights(shop: Instance, budget: QualityBudgets.Budget)
	for _, d in ipairs(shop:GetDescendants()) do
		if d:IsA("Light") then
			dressLight(d, budget)
		end
	end
end

local function redress(budget: QualityBudgets.Budget)
	for _, box in ipairs(CollectionService:GetTagged(BOX_TAG)) do
		BoxWindows.Apply(box, budget.BoxContents)
	end
	for _, shop in ipairs(CollectionService:GetTagged(SHOP_TAG)) do
		dressLights(shop, budget)
	end
end

-- Lights added to a shop later (a window lamp, a showroom spot) follow the same budget.
local function watchShop(shop: Instance)
	dressLights(shop, Quality.Budget())
	shop.DescendantAdded:Connect(function(added: Instance)
		if added:IsA("Light") then
			dressLight(added, Quality.Budget())
		end
	end)
end

function QualityDressing.Start()
	CollectionService:GetInstanceAddedSignal(BOX_TAG):Connect(watchBox)
	for _, box in ipairs(CollectionService:GetTagged(BOX_TAG)) do
		watchBox(box)
	end
	CollectionService:GetInstanceAddedSignal(SHOP_TAG):Connect(watchShop)
	for _, shop in ipairs(CollectionService:GetTagged(SHOP_TAG)) do
		watchShop(shop)
	end
	Quality.OnChange(redress)
end

return QualityDressing
