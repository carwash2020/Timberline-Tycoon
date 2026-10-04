--!strict
-- FerryService: the island ferry (reserved in wave 0). One connection on
-- FerryBoard. The handler budgets the call and drops it. A later batch
-- replaces this body and does not connect the remote again.

local RateLimiter = require(script.Parent.RateLimiter)

local FerryService = {}

local bound = false

function FerryService.Init(remoteEvent: RemoteEvent?)
	if bound or remoteEvent == nil then
		return
	end
	bound = true
	remoteEvent.OnServerEvent:Connect(function(player: Player)
		RateLimiter.Allow(player, "FerryBoard")
	end)
end

return FerryService
