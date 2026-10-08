--!strict
-- TalkLock: who an NPC is talking to, and who it turns to face. Pure, so the
-- server (NPCTalkService), the client (NPCController) and the specs agree.
--
-- A conversation opens the dialogue box (DialogueUI) and lasts until the box
-- is dismissed, the player walks off, goes down or leaves, or the NPC goes.
-- For that whole time the NPC:
--   * faces the player it is talking to (yaw only: no tipping, no sliding),
--     the head following as it does for any player nearby;
--   * stops wandering (a walker holds where it stands; its idle and talking
--     animations keep playing);
-- and when nobody is talking any more it goes back to its normal behaviour.
--
-- State lives on the server (NPCTalkService): a list of talkers per NPC,
-- published on the model as the attribute TalkLock.Attribute (the Roblox
-- UserId of the player to face, or absent). Every client turns the model
-- toward that player on its own screen, which is purely visual: the server
-- never moves an NPC (walkers follow the shared clock on each client), and a
-- release is only ever the attribute going away.
--
--   * Begin / End: the talk list, most recent last.
--   * Prune: who is still talking, given what the server can see.
--   * Target: the player to face (the most recent talker; nearest on a tie).
--   * Yaw / Turn: the heading toward them, and one smooth step toward it.

local DialogueFlow = require(script.Parent.DialogueFlow)
local FacingLogic = require(script.Parent.FacingLogic)
local NPCData = require(script.Parent.NPCData)

local TalkLock = {}

-- The model attribute: a UserId while someone is talking, absent otherwise.
TalkLock.Attribute = "TalkWith"
-- A talk starts only when the player is this far (studs) from the NPC: the
-- prompt's reach plus a little for lag.
TalkLock.BeginSlack = 6
-- The server lets go this far past the box's own walk-away distance, so the
-- NPC does not turn back a moment before the box closes.
TalkLock.CloseSlack = 6
-- And this long past the box's own timeout (a client that never says it ended).
TalkLock.TimeoutSlack = 10
-- Talkers kept per NPC: a crowd cannot grow the list without bound.
TalkLock.MaxTalkers = 8
-- Closer than this (studs, flat) the NPC keeps its heading: no spin when a
-- player stands on its toes.
TalkLock.MinFace = 0.5

export type Talker = {
	userId: number,
	since: number, -- when they started (os.clock on the server)
}

-- What the server sees of one talker, by UserId. A missing entry means the
-- player is gone.
export type Fact = {
	distance: number?, -- studs from the NPC; nil when unknown
	down: boolean?, -- no character, or a dead one
}

-- The farthest a player may be to open a talk.
function TalkLock.BeginReach(): number
	return NPCData.TalkDistance + TalkLock.BeginSlack
end

-- The talk list with `userId` added as the most recent (a repeat press just
-- moves them to the end). The list passed in is not changed.
function TalkLock.Begin(list: { Talker }, userId: number, now: number): { Talker }
	local out: { Talker } = {}
	for _, talker in ipairs(list) do
		if talker.userId ~= userId then
			table.insert(out, talker)
		end
	end
	table.insert(out, { userId = userId, since = now })
	while #out > TalkLock.MaxTalkers do
		table.remove(out, 1)
	end
	return out
end

-- The list without `userId`.
function TalkLock.End(list: { Talker }, userId: number): { Talker }
	local out: { Talker } = {}
	for _, talker in ipairs(list) do
		if talker.userId ~= userId then
			table.insert(out, talker)
		end
	end
	return out
end

-- The talkers still talking. `gone` (the NPC was removed) and `asleep` (the
-- keeper lay down) end everyone's talk at once; otherwise a talker ends when
-- they left the game, went down, walked past the box's close distance (plus
-- slack), or have been up longer than the box's own timeout (plus slack).
-- Returns the kept list and the UserIds that were let go.
function TalkLock.Prune(
	list: { Talker },
	facts: { [number]: Fact },
	now: number,
	gone: boolean?,
	asleep: boolean?
): ({ Talker }, { number })
	local kept: { Talker } = {}
	local released: { number } = {}
	for _, talker in ipairs(list) do
		local fact = facts[talker.userId]
		local drop = gone == true or asleep == true or fact == nil or fact.down == true
		if not drop and fact ~= nil then
			local distance = fact.distance
			if distance ~= nil and distance > DialogueFlow.CloseDistance + TalkLock.CloseSlack then
				drop = true
			end
		end
		if not drop and now - talker.since > DialogueFlow.MaxOpenSeconds + TalkLock.TimeoutSlack then
			drop = true
		end
		if drop then
			table.insert(released, talker.userId)
		else
			table.insert(kept, talker)
		end
	end
	return kept, released
end

-- The UserId to face: the most recent talker; when two began at the same
-- moment, the nearer one (`distances` by UserId), then the lower id so the
-- answer never flips between runs. nil when nobody is talking.
function TalkLock.Target(list: { Talker }, distances: { [number]: number }?): number?
	local best: Talker? = nil
	for _, talker in ipairs(list) do
		if best == nil or talker.since > best.since then
			best = talker
		elseif talker.since == best.since then
			local dn = if distances then distances[talker.userId] else nil
			local db = if distances then distances[best.userId] else nil
			local nearer = dn ~= nil and (db == nil or dn < db)
			local same = (dn == nil and db == nil) or (dn ~= nil and dn == db)
			if nearer or (same and talker.userId < best.userId) then
				best = talker
			end
		end
	end
	return if best then best.userId else nil
end

-- Whether anyone is talking: the NPC holds still and keeps facing.
function TalkLock.Held(list: { Talker }): boolean
	return #list > 0
end

-- The yaw (about Y only) that faces `to` from `from`; `current` when they
-- stand on top of each other.
function TalkLock.Yaw(current: number, from: Vector3, to: Vector3): number
	local dx, dz = to.X - from.X, to.Z - from.Z
	if math.sqrt(dx * dx + dz * dz) < TalkLock.MinFace then
		return current
	end
	return FacingLogic.Face(from, to)
end

-- One smooth step from `current` toward the heading that faces `to`, at the
-- NPCs' usual turn rate (`dt` seconds). Yaw only.
function TalkLock.Turn(current: number, from: Vector3, to: Vector3, dt: number): number
	local want = TalkLock.Yaw(current, from, to)
	return NPCData.TurnToward(current, want, NPCData.TurnRate * math.max(dt, 0))
end

-- The yaw a standing NPC should aim for this frame: toward the talk partner
-- when there is one (at any distance), else the usual nearest-player turn
-- (NPCData.FaceYaw within its range), else `home`.
function TalkLock.Want(home: number, pos: Vector3, partner: Vector3?, nearest: Vector3?): number
	if partner ~= nil then
		return TalkLock.Yaw(home, pos, partner)
	end
	return NPCData.FaceYaw(home, pos, nearest, NPCData.FaceRange)
end

-- Where a held walker stands: where it is now (`visual`), not where the
-- shared clock says its route has got to, so it never slides while talking.
-- With no hold it follows the clock. Positions only; returns x, z.
function TalkLock.HoldAt(
	held: boolean,
	visualX: number?,
	visualZ: number?,
	clockX: number,
	clockZ: number
): (number, number)
	if held and visualX ~= nil and visualZ ~= nil then
		return visualX, visualZ
	end
	return clockX, clockZ
end

return TalkLock
