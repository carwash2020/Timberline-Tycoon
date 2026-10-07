--!strict
-- JoinFlow: the rules for letting a player into the world (join race fix,
-- 7 October 2026). Pure, so the order is tested without Studio.
--
-- Studio (7 October, after the faster-load merge): the character appeared at
-- +6.5 s the moment MapBuilder finished the terrain, before GameServer had
-- started its services, before the save had loaded, before the Land Office
-- and the plot pads existed, and while the deferred build was about to put
-- the town's dressing and the townsfolk around the spawn. Nothing asked the
-- client to stream the spawn area first (StreamingEnabled with
-- PauseOutsideLoadedArea), and the client controllers (which now start at
-- +0.2 s) had not said they were listening, so one-shot signals could go
-- unheard. The player stood in a half-loaded, still-changing world.
--
-- Now MapBuilder never lets anyone in. GameServer's join flow does, in this
-- order (JoinFlow.Decide):
--   1. the first-player gates are open (JoinFlow.FirstPlayerGates),
--   2. the save is loaded,
--   3. the spawn area is streamed in (Player:RequestStreamAroundAsync),
--   4. the character is loaded,
--   5. it has stood on the ground for a moment (JoinFlow.Settled),
--   6. the client said ClientReady (its handlers are connected), or the wait
--      for that ran out,
--   7. only then ProfileLoaded is set and the player "can play".

local JoinFlow = {}

-- What the first minute needs to exist before the FIRST player is released:
-- the ground, the town (spawn, sawmill, shops, sell area), the world as a
-- whole, every service, the plot pads and the Land Office, and Murph (the
-- tutorial's first stop). Everything else may stay in the deferred build.
JoinFlow.FirstPlayerGates = { "terrain", "town", "world", "services", "plots", "murph" }

JoinFlow.GateWaitSeconds = 90 -- the longest the flow waits for the gates before it lets the player in anyway
JoinFlow.StreamSeconds = 8 -- the longest one RequestStreamAroundAsync may take
JoinFlow.GroundSeconds = 4 -- the longest to wait for the character to land
JoinFlow.SettleSeconds = 0.3 -- on the ground this long (no falling, no sliding) counts as standing
JoinFlow.ClientWaitSeconds = 12 -- the longest to wait for the client's ClientReady
JoinFlow.StreamLift = 3 -- studs above the spawn pad the stream is asked around
JoinFlow.MaxRespawnSeconds = 30

-- The first-player gates that are still shut. `isReady` answers one name.
function JoinFlow.Missing(isReady: (string) -> boolean): { string }
	local missing: { string } = {}
	for _, name in ipairs(JoinFlow.FirstPlayerGates) do
		if not isReady(name) then
			table.insert(missing, name)
		end
	end
	return missing
end

export type State = {
	worldReady: boolean, -- every first-player gate is open (or the wait ran out)
	saveLoaded: boolean,
	streamed: boolean, -- the spawn area was asked for (and arrived, or the ask timed out)
	spawned: boolean, -- the character was loaded
	grounded: boolean, -- it has settled on the ground (JoinFlow.Settled)
	clientReady: boolean, -- the client said ClientReady
	groundWaited: number, -- seconds since the character was loaded
	clientWaited: number, -- seconds since the player joined
}

export type Step = "waitWorld" | "waitSave" | "stream" | "spawn" | "waitGround" | "waitClient" | "release"

-- What the join flow does next for a player in `s`.
function JoinFlow.Decide(s: State): Step
	if not s.worldReady then
		return "waitWorld"
	end
	if not s.saveLoaded then
		return "waitSave"
	end
	if not s.streamed then
		return "stream"
	end
	if not s.spawned then
		return "spawn"
	end
	if not s.grounded and s.groundWaited < JoinFlow.GroundSeconds then
		return "waitGround"
	end
	if not s.clientReady and s.clientWaited < JoinFlow.ClientWaitSeconds then
		return "waitClient"
	end
	return "release"
end

-- Standing: on a floor and not moving up or down fast.
function JoinFlow.OnGround(onFloor: boolean, verticalSpeed: number): boolean
	return onFloor and math.abs(verticalSpeed) < 2
end

export type Tracker = {
	Update: (now: number, onFloor: boolean, verticalSpeed: number) -> boolean,
}

-- Feeds samples (a Heartbeat's worth each) and says when the character has
-- stood on the ground for JoinFlow.SettleSeconds without a break.
function JoinFlow.Settled(): Tracker
	local since: number? = nil
	local tracker = {} :: Tracker
	function tracker.Update(now: number, onFloor: boolean, verticalSpeed: number): boolean
		if not JoinFlow.OnGround(onFloor, verticalSpeed) then
			since = nil
			return false
		end
		if since == nil then
			since = now
		end
		return now - (since :: number) >= JoinFlow.SettleSeconds
	end
	return tracker
end

-- Seconds before a dead character is loaded again (Players.RespawnTime
-- clamped; the join flow owns spawning, so it owns respawning too).
function JoinFlow.RespawnDelay(respawnTime: unknown): number
	if type(respawnTime) ~= "number" or respawnTime ~= respawnTime then
		return 5
	end
	return math.clamp(respawnTime, 0, JoinFlow.MaxRespawnSeconds)
end

return JoinFlow
