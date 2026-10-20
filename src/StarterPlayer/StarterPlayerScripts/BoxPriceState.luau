--!strict
-- BoxPriceState: colours the price printed on every shop box for you. The server
-- builds the text on the box's PriceTag plate (Art/BoxArt: CoinGold) and tags the
-- plate "BoxPriceTag" with its price in the "Price" attribute; the box is shared by
-- every player, so whether YOU can pay is decided here: CoinGold when your cash
-- covers it, StopRed when not (BoxLogic.PriceColor). Display only: the server
-- still charges. Event driven: it recolours a plate when it is added and every
-- plate when your "Cash" attribute changes, never per frame.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BoxArt = require(ReplicatedStorage.Shared.Art.BoxArt)
local BoxLogic = require(ReplicatedStorage.Shared.BoxLogic)

local BoxPriceState = {}

local player = Players.LocalPlayer

-- Recolours one plate's price label for `cash`.
function BoxPriceState.Apply(plate: Instance, cash: number?)
	local price = plate:GetAttribute("Price")
	if type(price) ~= "number" then
		return
	end
	local color = BoxLogic.PriceColor(price, cash)
	for _, gui in ipairs(plate:GetChildren()) do
		if gui:IsA("SurfaceGui") then
			local label = gui:FindFirstChild(BoxArt.PriceLabelName)
			if label ~= nil and label:IsA("TextLabel") and label.TextColor3 ~= color then
				label.TextColor3 = color
			end
		end
	end
end

local function cashNow(): number?
	local cash = player:GetAttribute("Cash")
	return if type(cash) == "number" then cash else nil
end

function BoxPriceState.RefreshAll()
	local cash = cashNow()
	for _, plate in ipairs(CollectionService:GetTagged(BoxArt.PriceTagTag)) do
		BoxPriceState.Apply(plate, cash)
	end
end

function BoxPriceState.Start()
	CollectionService:GetInstanceAddedSignal(BoxArt.PriceTagTag):Connect(function(plate: Instance)
		BoxPriceState.Apply(plate, cashNow())
	end)
	player:GetAttributeChangedSignal("Cash"):Connect(BoxPriceState.RefreshAll)
	BoxPriceState.RefreshAll()
end

return BoxPriceState
