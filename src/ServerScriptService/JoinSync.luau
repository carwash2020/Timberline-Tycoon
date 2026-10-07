--!strict
-- JoinSync: state the server sends a player more than once. A RemoteEvent
-- fired before the client has connected its handler is lost, and on a
-- fresh server the controllers now start at +0.2 s but may still be
-- connecting when the save lands. So the client fires ClientReady once its
-- controllers have started, and the server runs every registered resend for
-- that player (cash, the plot offer, the save slots, badges...). Each resend
-- must be harmless to hear twice: the client applies state, it does not
-- toggle it. Run also happens right after the player is released, so
-- whichever of the two comes last, the client hears it after it can listen.
-- No Roblox API in here: the specs drive it with a plain player table.

local JoinSync = {}

export type Resend = (player: any) -> ()

local resends: { { name: string, fn: Resend } } = {}
local readyAt: { [any]: number } = {}
local ran: { [any]: number } = {}

-- Adds (or replaces) a resend. Order of registration is the order of sending.
function JoinSync.Register(name: string, fn: Resend)
	for _, entry in ipairs(resends) do
		if entry.name == name then
			entry.fn = fn
			return
		end
	end
	table.insert(resends, { name = name, fn = fn })
end

function JoinSync.Names(): { string }
	local names: { string } = {}
	for _, entry in ipairs(resends) do
		table.insert(names, entry.name)
	end
	return names
end

-- Runs every resend for `player`. One that errors is reported through
-- `onError` and does not stop the rest. Returns how many ran cleanly.
function JoinSync.Run(player: any, onError: ((name: string, err: any) -> ())?): number
	local good = 0
	for _, entry in ipairs(resends) do
		local ok, err = (pcall :: any)(entry.fn, player)
		if ok then
			good += 1
		elseif onError then
			onError(entry.name, err)
		end
	end
	ran[player] = (ran[player] or 0) + 1
	return good
end

-- The client's handshake. Records when, and says whether this is the first.
function JoinSync.MarkReady(player: any, now: number): boolean
	if readyAt[player] ~= nil then
		return false
	end
	readyAt[player] = now
	return true
end

function JoinSync.IsReady(player: any): boolean
	return readyAt[player] ~= nil
end

function JoinSync.ReadyAt(player: any): number?
	return readyAt[player]
end

function JoinSync.Runs(player: any): number
	return ran[player] or 0
end

function JoinSync.Forget(player: any)
	readyAt[player] = nil
	ran[player] = nil
end

-- For specs.
function JoinSync.Reset()
	table.clear(resends)
	table.clear(readyAt)
	table.clear(ran)
end

return JoinSync
