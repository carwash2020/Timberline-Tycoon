--!strict
-- CoreLoop: the live loop is v2 (section trees cut anywhere, wood dragged
-- and carried loose on beds, sold by volume). The v1 loop (whole trees
-- with HP, two logs carried, bed slots) is gone. MapBuilder still publishes
-- workspace attribute "CoreLoopActive" = 2 at boot. Active() is 2 even
-- before that attribute replicates, so a client never sits in the old
-- "wait, then maybe stay on v1" race. PlaceCheck still warns if a saved
-- place has a CoreLoop override attribute.

local CoreLoop = {}

CoreLoop.Attribute = "CoreLoop"
CoreLoop.ActiveAttribute = "CoreLoopActive"
CoreLoop.Loops = { 2 }

-- Always 2. The arguments stay so older call sites (GameConfig, a Studio
-- attribute, isStudio) still type-check; none of them select a loop.
function CoreLoop.Resolve(_configured: unknown, _override: unknown, _isStudio: boolean): number
	return 2
end

function CoreLoop.Active(): number
	return 2
end

function CoreLoop.V2(): boolean
	return true
end

return CoreLoop
