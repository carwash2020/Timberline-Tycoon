--!strict
-- EventService: reserved client intents that do not have their own service
-- yet. Each remote is connected once. The handler budgets the call and
-- drops it. A later batch replaces that body and does not connect again.
--   ExpandLand     buy the next plot square
--   SpawnPadPress  the button on a vehicle pad (respawn reuses truck recall)
--   ChopSawSet     one step of a chop saw's cut (same shape as SawmillSet)

local RateLimiter = require(script.Parent.RateLimiter)

local EventService = {}

local expandBound = false
local padBound = false
local sawBound = false

function EventService.Init(remotes: {
	ExpandLand: RemoteEvent?,
	SpawnPadPress: RemoteEvent?,
	ChopSawSet: RemoteEvent?,
}?)
	if remotes == nil then
		return
	end
	if not expandBound and remotes.ExpandLand ~= nil then
		expandBound = true
		remotes.ExpandLand.OnServerEvent:Connect(function(player: Player)
			RateLimiter.Allow(player, "ExpandLand")
		end)
	end
	if not padBound and remotes.SpawnPadPress ~= nil then
		padBound = true
		remotes.SpawnPadPress.OnServerEvent:Connect(function(player: Player)
			RateLimiter.Allow(player, "SpawnPadPress")
		end)
	end
	if not sawBound and remotes.ChopSawSet ~= nil then
		sawBound = true
		remotes.ChopSawSet.OnServerEvent:Connect(function(player: Player)
			RateLimiter.Allow(player, "ChopSawSet")
		end)
	end
end

return EventService
