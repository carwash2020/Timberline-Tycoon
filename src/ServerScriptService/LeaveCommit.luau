--!strict
-- LeaveCommit: world state that has to be in the profile before the final
-- save (playtime, the truck's loose wood, logs left on the ground).
--
-- ProfileStore's shutdown hook saves and ends every session on its own,
-- without waiting for PlayerRemoving. OnLastSave fires at the start of
-- that save (and of a normal leave's save). Flush writes the state once,
-- synchronously, so whichever of those runs first captures it and the
-- second can't overwrite it with an empty world.

local LeaveCommit = {}

export type Step = (player: Player) -> ()

type Named = { name: string, fn: Step }

local steps: { Named } = {}
-- Weak keys: a player who has left can be collected. Keyed by the Player
-- instance, so a rejoin (a new instance) commits again.
local committed: { [Player]: { [string]: boolean } } = setmetatable({}, { __mode = "k" }) :: any

function LeaveCommit.Add(name: string, fn: Step)
	table.insert(steps, { name = name, fn = fn })
end

-- Run every step that hasn't run for `player` yet. A second call, from
-- PlayerRemoving after shutdown or from OnLastSave after PlayerRemoving,
-- does nothing. Steps must not yield: the save copies the profile as soon
-- as this returns.
function LeaveCommit.Flush(player: Player)
	local ran = committed[player]
	if ran == nil then
		ran = {}
		committed[player] = ran
	end
	for _, step in ipairs(steps) do
		if not ran[step.name] then
			ran[step.name] = true
			local ok, err = xpcall(function()
				step.fn(player)
			end, function(e: any): string
				return debug.traceback(tostring(e), 2)
			end)
			if not ok then
				warn(string.format("[LeaveCommit] %s failed:\n%s", step.name, tostring(err)))
			end
		end
	end
end

-- `onLastSave` is a profile's OnLastSave signal. The listener runs inside
-- the final save, before Profile.Data is written.
function LeaveCommit.Bind(onLastSave: any, player: Player)
	onLastSave:Connect(function(_reason: string)
		LeaveCommit.Flush(player)
	end)
end

return LeaveCommit
