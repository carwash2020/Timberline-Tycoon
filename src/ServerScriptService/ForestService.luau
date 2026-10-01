--!strict
-- ForestService: the Living Forest (GAME_DESIGN §16): Heartseeds, replanting
-- stumps, the planter's share, Grove Vitality, figured grain, storm-struck
-- trees and Elder trees. (Stub: the forest workstream fills this in.)

local ProfileService = require(script.Parent.ProfileService)

local ForestService = {}

export type Remotes = { PlantSeed: RemoteEvent, WorldFX: RemoteEvent }

function ForestService.Init(_remotes: Remotes, _notify: (Player, string) -> ()) end

function ForestService.PlayerJoined(_player: Player, _profile: ProfileService.Profile) end

function ForestService.PlayerRemoving(_player: Player) end

-- After a sale: how many figured logs of each figure were just sold (the
-- reveal, stats and the Field Guide).
function ForestService.OnSale(_player: Player, _figures: { [string]: number }) end

-- Lightning struck near `position` (WeatherService): may strike a tree.
-- Returns the struck tree's uid, if any.
function ForestService.Strike(_position: Vector3): string?
	return nil
end

return ForestService
