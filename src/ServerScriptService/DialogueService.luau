--!strict
-- DialogueService: shop talk (reserved in wave 0). One connection on
-- Dialogue. The handler budgets the call and drops it. A later batch
-- replaces this body and does not connect the remote again.

local RateLimiter = require(script.Parent.RateLimiter)

local DialogueService = {}

local bound = false

function DialogueService.Init(remoteEvent: RemoteEvent?)
	if bound or remoteEvent == nil then
		return
	end
	bound = true
	remoteEvent.OnServerEvent:Connect(function(player: Player)
		RateLimiter.Allow(player, "Dialogue")
	end)
end

return DialogueService
