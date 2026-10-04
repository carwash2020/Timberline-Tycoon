--!strict
-- EventService: reserved client intents that do not have their own service
-- yet. Each remote is connected once. The handler budgets the call and
-- drops it. A later batch replaces that body and does not connect again.
--   ExpandLand     buy the next plot square
--   SpawnPadPress  the button on a vehicle pad (respawn reuses truck recall)
-- ChopSawSet lives on ChopSawService. It is not connected here, so a press
-- is not budgeted twice.

local RateLimiter = require(script.Parent.RateLimiter)

local EventService = {}

local expandBound = false
local padBound = false

function EventService.Init(remotes: {
	ExpandLand: RemoteEvent?,
	SpawnPadPress: RemoteEvent?,
}?)
	if remotes == nil then
		return
	end
	if not expandBound and remotes.ExpandLand ~= nil then
		expandBound = true
		remotes.ExpandLand.OnServerEvent:Connect(function(player: Player, x: unknown, z: unknown, expected: unknown)
			-- The only ExpandLand handler. Foundations counts this Allow once.
			if not RateLimiter.Allow(player, "ExpandLand") then
				return
			end
			-- Budget is spent before the arguments are read. A bare fire
			-- stops here, so the plot module is only loaded for a real tap.
			if type(x) ~= "number" or type(z) ~= "number" then
				return
			end
			local PlotService = require(script.Parent.PlotService)
			PlotService.Expand(player, x, z, expected)
		end)
	end
	if not padBound and remotes.SpawnPadPress ~= nil then
		padBound = true
		remotes.SpawnPadPress.OnServerEvent:Connect(function(player: Player)
			RateLimiter.Allow(player, "SpawnPadPress")
		end)
	end
end

return EventService
