--!strict
-- GateService: the toll bridge (reserved in wave 0). One connection on
-- TollPay. The handler budgets the call and drops it. A later batch
-- replaces this body and does not connect the remote again.
--
-- tollPaidUntil is not a save field. It lives on the server, keyed by
-- UserId, and is cleared when that player leaves.

local RateLimiter = require(script.Parent.RateLimiter)

local GateService = {}

local tollPaidUntil: { [number]: number } = {}
GateService.TollPaidUntil = tollPaidUntil

local bound = false

function GateService.Init(remoteEvent: RemoteEvent?)
	if bound or remoteEvent == nil then
		return
	end
	bound = true
	remoteEvent.OnServerEvent:Connect(function(player: Player)
		RateLimiter.Allow(player, "TollPay")
	end)
end

function GateService.PlayerRemoving(player: Player)
	tollPaidUntil[player.UserId] = nil
end

return GateService
