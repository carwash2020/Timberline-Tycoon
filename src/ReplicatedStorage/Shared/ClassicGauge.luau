--!strict
-- ClassicGauge: the Timber Classic's dashboard estimate.
-- The number is what SellService would pay for the same pieces at the
-- Wood Dropoff (SellLogic.Payout, 2x Cash once on the total). Welded and
-- loose pieces are the same list: nothing on the bed is left out.

local SellLogic = require(script.Parent.SellLogic)
local Util = require(script.Parent.Util)

local ClassicGauge = {}

-- The pass description and the gauge both use these words.
ClassicGauge.Phrase = "estimate at the Wood Dropoff"

function ClassicGauge.Estimate(pieceValues: { number }, saleMultiplier: number): number
	local total = 0
	for _, value in ipairs(pieceValues) do
		if type(value) == "number" and value == value and value > -math.huge and value < math.huge then
			total += math.max(0, value)
		end
	end
	return SellLogic.Payout(total, saleMultiplier)
end

function ClassicGauge.Readout(dollars: number): string
	return Util.formatCash(dollars) .. "\n" .. ClassicGauge.Phrase
end

-- On only while you sit in the driver seat of your own Classic.
-- Passengers, other trucks and other players' Classics stay hidden.
function ClassicGauge.Show(truckId: string, ownerId: number, driverUserId: number?): boolean
	return truckId == "TimberClassic" and driverUserId ~= nil and driverUserId == ownerId
end

function ClassicGauge.Apply(model: Instance, dollars: number)
	local part = model:FindFirstChild("LoadGauge", true)
	local gui = if part then part:FindFirstChild("GaugeGui") else nil
	local label = if gui then gui:FindFirstChild("Readout") else nil
	if label and label:IsA("TextLabel") then
		label.Text = ClassicGauge.Readout(dollars)
	end
	if model:IsA("Model") then
		model:SetAttribute("LoadEstimate", dollars)
	end
end

return ClassicGauge
