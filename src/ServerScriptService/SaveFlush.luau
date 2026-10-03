--!strict
-- SaveFlush: listeners that copy live per-player state into the profile
-- immediately before ProfileStore writes it.
--
-- ProfileStore fires OnSave, then OnLastSave, and only then copies
-- Profile.Data (Vendor/ProfileStore). Its BindToClose save does that for
-- every profile without waiting for PlayerRemoving, so a leave handler
-- that writes truck loads or playtime afterwards can miss the shutdown
-- save. ProfileService runs these listeners from both signals. They must
-- not yield. One that errors is warned and the rest still run.

local SaveFlush = {}

local listeners: { (Player) -> () } = {}

function SaveFlush.Add(fn: (Player) -> ())
	table.insert(listeners, fn)
end

function SaveFlush.Run(player: Player)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(function(): any
			fn(player)
			return nil
		end)
		if not ok then
			warn(string.format("[SaveFlush] %s: %s", player.Name, tostring(err)))
		end
	end
end

-- Test hook: how many listeners are registered.
function SaveFlush.Count(): number
	return #listeners
end

return SaveFlush
