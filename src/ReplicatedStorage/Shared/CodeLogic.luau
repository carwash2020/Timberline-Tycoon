--!strict
-- CodeLogic: the rules of redeem codes. Pure, so CodeService, the Settings
-- Codes tab and the specs agree. The codes themselves live in Shared/CodeData.
--
--   * A code is typed by the player: Normalize trims it, upper-cases it and
--     keeps only letters, digits, - and _ (at most 32 characters).
--   * One use per player, ever: the used list is the save's onboarding table
--     ("Code:<id>"), so it holds across save slots.
--   * Expiry is a UTC date ("2026-12-31"), good through the end of that day
--     (23:59:59 UTC), compared on the SERVER's clock. The client never decides.
--   * Rewards are cash or a granted furniture piece, nothing else. Never
--     Robux, never a paid item: ValidReward refuses any other shape, so a
--     data mistake cannot hand one out.
--   * A run of wrong codes locks the box for a while (Locked / NoteMiss).

local FurnitureData = require(script.Parent.FurnitureData)

local CodeLogic = {}

CodeLogic.MaxLength = 32
CodeLogic.MaxCash = 50000 -- the most one code may pay (the wallet cap still clamps it)
CodeLogic.FlagPrefix = "Code:"

-- Wrong-code lockout: this many misses inside the window locks the box.
CodeLogic.MissLimit = 6
CodeLogic.MissWindow = 60 -- seconds
CodeLogic.LockSeconds = 30

export type Reward = { kind: "cash", amount: number } | { kind: "piece", id: string }
export type Entry = {
	id: string, -- a short stable name, used for the used-flag (never the code itself)
	code: string, -- what the player types
	enabled: boolean,
	expires: string, -- "YYYY-MM-DD", UTC, good through the end of that day
	reward: Reward,
	note: string?, -- for the owner, never shown
}

-- The typed text as a code, or nil when nothing usable is left.
function CodeLogic.Normalize(raw: unknown): string?
	if type(raw) ~= "string" or #raw > 200 then
		return nil
	end
	local stripped = string.gsub(raw, "[^%w%-_]", "")
	local clean = string.upper(stripped)
	if clean == "" or #clean > CodeLogic.MaxLength then
		return nil
	end
	return clean
end

-- Days since 1970-01-01 for a civil date (proleptic Gregorian).
local function daysFromCivil(y: number, m: number, d: number): number
	if m <= 2 then
		y -= 1
	end
	local era = (if y >= 0 then y else y - 399) // 400
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = (153 * mp + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

local DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

local function leap(y: number): boolean
	return (y % 4 == 0 and y % 100 ~= 0) or y % 400 == 0
end

-- The unix time of 23:59:59 UTC on "YYYY-MM-DD", or nil for anything else
-- (a bad month or day included).
function CodeLogic.ExpiryTime(date: unknown): number?
	if type(date) ~= "string" then
		return nil
	end
	local ys, ms, ds = string.match(date, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if ys == nil or ms == nil or ds == nil then
		return nil
	end
	local y, m, d = tonumber(ys) :: number, tonumber(ms) :: number, tonumber(ds) :: number
	if m < 1 or m > 12 or d < 1 then
		return nil
	end
	local last = DAYS[m]
	if m == 2 and leap(y) then
		last = 29
	end
	if d > last then
		return nil
	end
	return daysFromCivil(y, m, d) * 86400 + 86399
end

-- Whether the code has expired at `now` (unix seconds, the server's clock).
-- A date that can't be read counts as expired, never as forever.
function CodeLogic.Expired(entry: Entry, now: number): boolean
	local at = CodeLogic.ExpiryTime(entry.expires)
	return at == nil or now > at
end

-- True only for cash (a whole number from 1 to MaxCash) or one granted
-- furniture piece, with no other keys. Anything that smells of Robux or a
-- paid item has no shape that passes.
function CodeLogic.ValidReward(reward: unknown): boolean
	if type(reward) ~= "table" then
		return false
	end
	local r = reward :: { [any]: any }
	local count = 0
	for _ in pairs(r) do
		count += 1
	end
	if r.kind == "cash" then
		local a = r.amount
		return count == 2
			and type(a) == "number"
			and a == a
			and a >= 1
			and a <= CodeLogic.MaxCash
			and a == math.floor(a)
	elseif r.kind == "piece" then
		return count == 2 and FurnitureData.IsGranted(r.id)
	end
	return false
end

-- The entry whose code is `normalized`, or nil.
function CodeLogic.Find(list: { Entry }, normalized: string): Entry?
	for _, entry in ipairs(list) do
		if CodeLogic.Normalize(entry.code) == normalized then
			return entry
		end
	end
	return nil
end

function CodeLogic.FlagKey(entry: Entry): string
	return CodeLogic.FlagPrefix .. entry.id
end

export type Verdict = "ok" | "invalid" | "expired" | "used"

-- What a try at `entry` (nil: no such code) comes to. A disabled code and an
-- unknown one both read "invalid", so the box never confirms a code exists.
-- `onboarding` is the save's flag table.
function CodeLogic.Check(entry: Entry?, onboarding: { [string]: boolean }, now: number): Verdict
	if entry == nil or not entry.enabled or not CodeLogic.ValidReward(entry.reward) then
		return "invalid"
	end
	if CodeLogic.Expired(entry, now) then
		return "expired"
	end
	if onboarding[CodeLogic.FlagKey(entry)] == true then
		return "used"
	end
	return "ok"
end

CodeLogic.Messages = {
	invalid = "That code isn't valid.",
	expired = "That code has expired.",
	used = "You already used that code.",
	locked = "Too many tries. Wait a moment, then try again.",
	wallet = "Your wallet is full, so that code wasn't used. Spend some cash and try again.",
	stock = "Your hammer's list is full, so that code wasn't used. Place something first.",
	empty = "Type a code first.",
} :: { [string]: string }

-- Records a wrong code at `now` and returns the recent misses (a new list).
function CodeLogic.NoteMiss(misses: { number }, now: number): { number }
	local kept: { number } = {}
	for _, at in ipairs(misses) do
		if now - at < CodeLogic.MissWindow then
			table.insert(kept, at)
		end
	end
	table.insert(kept, now)
	return kept
end

-- Seconds the box stays locked at `now` (0 when it is open).
function CodeLogic.Locked(misses: { number }, now: number): number
	local recent, last = 0, 0
	for _, at in ipairs(misses) do
		if now - at < CodeLogic.MissWindow then
			recent += 1
			last = math.max(last, at)
		end
	end
	if recent < CodeLogic.MissLimit then
		return 0
	end
	return math.max(0, math.ceil(last + CodeLogic.LockSeconds - now))
end

-- One line saying what a reward is, for the toast.
function CodeLogic.RewardText(reward: Reward, displayName: string?): string
	if reward.kind == "cash" then
		return string.format("$%d", reward.amount)
	end
	return displayName or reward.id
end

return CodeLogic
