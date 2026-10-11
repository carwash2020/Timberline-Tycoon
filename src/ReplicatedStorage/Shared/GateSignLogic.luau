--!strict
-- GateSignLogic: what a gate sign's State label says to one player. Per
-- player, on the client (WorldUI): "Protected" or "Open" in SaleGreen when the
-- gate's requirement is met, and the requirement in words in StopRed when not.
-- Words come from BiomeData.Gate(id).words; the gates with none of their own
-- (snow, volcano, the Gloam Hollow) use the lines below. No prices on signs:
-- the price shows in prompts and hover.

local BiomeData = require(script.Parent.BiomeData)

local GateSignLogic = {}

GateSignLogic.Green = { 76, 195, 106 } -- SaleGreen #4CC36A
GateSignLogic.Red = { 217, 83, 79 } -- StopRed #D9534F

local FALLBACK_WORDS: { [string]: string } = {
	snow = "Cold hurts here. Coat protects.",
	volcano = "Heat hurts here. Boots protect.",
	grove = "Dark and deep. Bring a Lantern.",
}

export type State = { text: string, color: { number }, met: boolean }

-- `owned` is the set of gear ids the player owns (ShopLogic.DecodeSet of the
-- OwnedGear attribute; the Gondola Pass is a gear id too).
function GateSignLogic.State(gateId: string, owned: { [string]: boolean }): State
	local gate = BiomeData.Gate(gateId)
	local needs = gate.needs
	if needs == nil then
		return { text = "Open", color = GateSignLogic.Green, met = true }
	end
	if owned[needs] == true then
		return { text = "Protected", color = GateSignLogic.Green, met = true }
	end
	local words = if gate.words ~= "" then gate.words else FALLBACK_WORDS[gateId]
	return { text = words or "Gear needed", color = GateSignLogic.Red, met = false }
end

return GateSignLogic
