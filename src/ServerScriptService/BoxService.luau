--!strict
-- BoxService: boxes a shop kept for you (reserved in wave 0). One connection
-- on BoxOpen. The handler budgets the call and drops it. A later batch
-- replaces this body and does not connect the remote again.
--
-- The Boxes collision group is registered here so parts can join it later.
-- Nothing is assigned to it yet, so play is unchanged.

local RateLimiter = require(script.Parent.RateLimiter)

local BoxService = {}

BoxService.Group = "Boxes"

local bound = false

local function registerGroup()
	local PhysicsService = game:GetService("PhysicsService")
	if not PhysicsService:IsCollisionGroupRegistered(BoxService.Group) then
		PhysicsService:RegisterCollisionGroup(BoxService.Group)
	end
end

function BoxService.Init(remoteEvent: RemoteEvent?)
	if not bound and remoteEvent ~= nil then
		bound = true
		remoteEvent.OnServerEvent:Connect(function(player: Player)
			RateLimiter.Allow(player, "BoxOpen")
		end)
	end
	local ok, err = pcall(function(): any
		registerGroup()
		return nil
	end)
	if not ok then
		warn("[BoxService] Boxes collision group was not registered: " .. tostring(err))
	end
end

return BoxService
