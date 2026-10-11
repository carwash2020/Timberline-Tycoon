--!strict
-- Backoff: the wait between tries of a flaky call (a DataStore write), as
-- plain numbers so a spec can check it without a clock or a DataStore.
-- The delay doubles each try from `base`, never passes `cap`, and a retry
-- loop also stops after `maxTries` tries or once `budget` seconds of waiting
-- have been spent, whichever comes first. ProfileService uses it for
-- retrying a save that did not land; ProfileStore has its own loop for the
-- first load and the final save.

local Backoff = {}

export type Options = {
	base: number?, -- seconds to wait after the first failure (default 1)
	cap: number?, -- longest single wait (default 20)
	maxTries: number?, -- total tries, the first included (default 5)
	budget: number?, -- most seconds of waiting in all (default 60)
}

local DEFAULTS = { base = 1, cap = 20, maxTries = 5, budget = 60 }

local function pick(options: Options?, key: string): number
	local given = if options then (options :: any)[key] else nil
	if type(given) == "number" and given > 0 then
		return given
	end
	return (DEFAULTS :: any)[key]
end

-- Seconds to wait after `failures` failed tries (1 = the first failure).
function Backoff.Delay(failures: number, options: Options?): number
	local base, cap = pick(options, "base"), pick(options, "cap")
	if failures < 1 then
		return 0
	end
	-- 2^(failures-1) past 2^30 is far over any cap; avoid inf.
	local steps = math.min(failures - 1, 30)
	return math.min(cap, base * 2 ^ steps)
end

-- The waits between tries, in order: one fewer than maxTries, cut short where
-- the budget runs out (the last wait is trimmed to what is left of it).
function Backoff.Schedule(options: Options?): { number }
	local maxTries, budget = pick(options, "maxTries"), pick(options, "budget")
	local waits: { number } = {}
	local spent = 0
	for failure = 1, maxTries - 1 do
		local wait = Backoff.Delay(failure, options)
		if spent + wait > budget then
			wait = budget - spent
		end
		if wait <= 0 then
			break
		end
		table.insert(waits, wait)
		spent += wait
	end
	return waits
end

-- Runs `attempt(tryNumber)` until it returns true or the schedule is spent,
-- calling `sleep(seconds)` between tries. Returns (succeeded, tries made).
-- An `attempt` that errors counts as a failure. `giveUp`, when it returns
-- true (the player left, the server is closing), stops the loop at once.
function Backoff.Retry(
	attempt: (number) -> boolean,
	sleep: (number) -> (),
	options: Options?,
	giveUp: (() -> boolean)?
): (boolean, number)
	local waits = Backoff.Schedule(options)
	local tries = 0
	while true do
		if giveUp ~= nil and giveUp() then
			return false, tries
		end
		tries += 1
		local ok, result = pcall(attempt, tries)
		if ok and result == true then
			return true, tries
		end
		local wait = waits[tries]
		if wait == nil then
			return false, tries
		end
		sleep(wait)
	end
end

return Backoff
