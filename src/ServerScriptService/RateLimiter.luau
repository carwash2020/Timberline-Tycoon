--!strict
-- RateLimiter: per-player, per-remote request budgets.
--
-- Requests over budget are dropped silently: mashing a button is normal
-- player behaviour and must never get anyone kicked. Only a burst far beyond
-- what a human can produce (ABUSE_MULTIPLIER x the limit inside one second)
-- earns a strike. Strikes expire after STRIKE_WINDOW seconds, and a player
-- is kicked only after STRIKES_TO_KICK strikes inside that window.

local RateLimiter = {}

local LIMITS: { [string]: number } = { -- max requests per second
	ChopTree = 4,
	PickupLog = 8,
	LoadToTruck = 4,
	SellLogs = 4,
	DropAxe = 2,
	PickUpAxe = 4,
	BuyItem = 3,
	SkipTutorial = 1,
	EquipItem = 2,
	CallTruck = 1,
	BuyRobuxItem = 2,
	MineNode = 4,
	Gondola = 1,
	PlaceBlueprint = 2,
	MoveBlueprint = 2,
	SellPlaced = 4,
	UpgradePlot = 1,
	PlantSeed = 3,
}
local ABUSE_MULTIPLIER = 5
-- Never strike for fewer than this many presses in a second: frantic
-- tapping on a 1-per-second button ("Truck to lot") is still human.
local ABUSE_FLOOR = 15
local STRIKE_WINDOW = 60
local STRIKES_TO_KICK = 5

type Bucket = { windowStart: number, count: number, struck: boolean }

local buckets: { [Player]: { [string]: Bucket } } = {}
local strikes: { [Player]: { number } } = {}

local function addStrike(player: Player, remoteName: string)
	local now = os.clock()
	local list = strikes[player] or {}
	local kept = {}
	for _, t in ipairs(list) do
		if now - t < STRIKE_WINDOW then
			table.insert(kept, t)
		end
	end
	table.insert(kept, now)
	strikes[player] = kept
	warn(
		string.format("[AntiExploit] %s flooded %s (%d strikes in %ds)", player.Name, remoteName, #kept, STRIKE_WINDOW)
	)
	if #kept >= STRIKES_TO_KICK then
		player:Kick("Disconnected: too many requests.")
	end
end

-- True if this request should be processed.
function RateLimiter.Allow(player: Player, remoteName: string): boolean
	local limit = LIMITS[remoteName]
	if limit == nil then
		return false
	end
	local perPlayer = buckets[player]
	if perPlayer == nil then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local now = os.clock()
	local bucket = perPlayer[remoteName]
	if bucket == nil or now - bucket.windowStart >= 1 then
		bucket = { windowStart = now, count = 0, struck = false }
		perPlayer[remoteName] = bucket
	end
	bucket.count += 1
	if bucket.count <= limit then
		return true
	end
	if not bucket.struck and bucket.count > math.max(limit * ABUSE_MULTIPLIER, ABUSE_FLOOR) then
		bucket.struck = true -- at most one strike per remote per second
		addStrike(player, remoteName)
	end
	return false
end

function RateLimiter.Forget(player: Player)
	buckets[player] = nil
	strikes[player] = nil
end

return RateLimiter
