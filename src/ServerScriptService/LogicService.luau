--!strict
-- LogicService: wires between machines (reserved in wave 0). One connection
-- on Wire. The handler budgets the call and drops it. A later batch
-- replaces this body and does not connect the remote again.

local RateLimiter = require(script.Parent.RateLimiter)

local LogicService = {}

local bound = false

function LogicService.Init(remoteEvent: RemoteEvent?)
	if bound or remoteEvent == nil then
		return
	end
	bound = true
	remoteEvent.OnServerEvent:Connect(function(player: Player)
		RateLimiter.Allow(player, "Wire")
	end)
end

return LogicService
