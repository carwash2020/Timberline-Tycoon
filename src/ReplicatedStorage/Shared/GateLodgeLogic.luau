--!strict
-- GateLodgeLogic: the Skyroot gate. The Sky Pass (saved as gondolaPass, the
-- old skyPass) opens it. There is no ride, no cabin and no fare.
-- Pure, so the spec can run it without Roblox.

local GateLodgeLogic = {}

GateLodgeLogic.SignText = "Sky Pass"
-- StopRed #D9534F when the bar is shut. SaleGreen #4CC36A on the edge only
-- once the pass is held. The bar itself stays iron.
GateLodgeLogic.ClosedEdge = { 217, 83, 79 }
GateLodgeLogic.OpenEdge = { 76, 195, 106 }

function GateLodgeLogic.MayEnter(hasPass: boolean): boolean
	return hasPass == true
end

function GateLodgeLogic.EdgeColor(hasPass: boolean): { number }
	if GateLodgeLogic.MayEnter(hasPass) then
		return GateLodgeLogic.OpenEdge
	end
	return GateLodgeLogic.ClosedEdge
end

return GateLodgeLogic
