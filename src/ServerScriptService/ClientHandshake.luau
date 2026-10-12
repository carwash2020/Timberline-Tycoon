--!strict
-- ClientHandshake: the server's half of the join handshake (JoinSync). The
-- client fires ClientReady once its controllers are up and repeats it every
-- 3 s until its save is in. The listener used to be connected after every
-- service's Init (a long way down GameServer, with yields between), so a
-- handshake sent early was heard only on the client's next repeat, up to 3 s
-- later. Bind is called as soon as the remote exists: the first fire is
-- marked ready at once (the join flow stops waiting for it), and the resend
-- of state, which needs the services' registrations, runs as soon as
-- GameServer says it can (SetResend), for every player who already asked.
-- No Roblox API in here: the specs drive it with fakes.

local ClientHandshake = {}

export type Deps = {
	allow: (player: any) -> boolean, -- the rate limit
	markReady: (player: any) -> boolean, -- true the first time a player says it
	onFirst: (player: any) -> (), -- the log line for that first time
}

export type Handshake = {
	SetResend: (fn: (player: any) -> ()) -> (),
	Pending: () -> number,
}

function ClientHandshake.Bind(event: any, deps: Deps): Handshake
	local resend: ((player: any) -> ())? = nil
	local pending: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	event.OnServerEvent:Connect(function(player: any)
		if not deps.allow(player) then
			return
		end
		if deps.markReady(player) then
			deps.onFirst(player)
		end
		local send = resend
		if send then
			send(player)
		else
			pending[player] = true -- state to send again once the services are there
		end
	end)
	return {
		SetResend = function(fn: (player: any) -> ())
			resend = fn
			local waiting = {}
			for player in pairs(pending) do
				table.insert(waiting, player)
			end
			table.clear(pending)
			for _, player in ipairs(waiting) do
				fn(player)
			end
		end,
		Pending = function(): number
			local n = 0
			for _ in pairs(pending) do
				n += 1
			end
			return n
		end,
	}
end

return ClientHandshake
