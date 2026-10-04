--!strict
-- PermissionService: who may visit and build (reserved in wave 0). One
-- connection on SetPermission. The handler budgets the call and drops it.
-- A later batch replaces this body and does not connect the remote again.

local RateLimiter = require(script.Parent.RateLimiter)

local PermissionService = {}

local bound = false

function PermissionService.Init(remoteEvent: RemoteEvent?)
	if bound or remoteEvent == nil then
		return
	end
	bound = true
	remoteEvent.OnServerEvent:Connect(function(player: Player)
		RateLimiter.Allow(player, "SetPermission")
	end)
end

return PermissionService
