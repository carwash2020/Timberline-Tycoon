--!strict
-- PickupGrace: who may pick up a log lying in the world, and when (PLAY-15).
--   * A felled (or dropped) log is its owner's alone for
--     GameConfig.PickupGraceSec after fellTime: long enough to walk two
--     logs to the truck and come back for the rest of the tree.
--   * A load left behind by a truck (TreeService's graceUntil) stays its
--     owner's until graceUntil instead.
--   * After that, anyone may take it. The owner always may.
-- Pure: GameServer's pickup handler asks it with os.time().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)

local PickupGrace = {}

-- What it reads of a TreeService log record.
export type Log = {
	ownerId: number,
	fellTime: number, -- os.time() it was felled or dropped
	graceUntil: number?, -- a load left behind: its owner's until this os.time()
}

-- When the owner's exclusive window ends, in os.time().
function PickupGrace.EndsAt(log: Log): number
	return log.graceUntil or (log.fellTime + GameConfig.PickupGraceSec)
end

-- Seconds `userId` still has to wait, at `now`, before picking `log` up
-- (0: go ahead).
function PickupGrace.WaitFor(log: Log, userId: number, now: number): number
	if log.ownerId == userId then
		return 0
	end
	return math.max(0, PickupGrace.EndsAt(log) - now)
end

-- The toast for someone who has `seconds` left to wait.
function PickupGrace.Message(log: Log, seconds: number): string
	if log.graceUntil then
		return "Someone left this load here. It's theirs for a while yet."
	end
	local n = math.max(1, math.ceil(seconds))
	return string.format(
		"Someone else felled this tree. Their logs are up for grabs in %d second%s.",
		n,
		if n == 1 then "" else "s"
	)
end

return PickupGrace
