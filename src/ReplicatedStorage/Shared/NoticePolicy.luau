--!strict
-- NoticePolicy: which on-screen messages (toasts) a player sees, and when.
-- Pure rules, no Instances and no clock of its own: HUD.Toast asks it, and
-- tests drive it with a time. Playtesters said there were way too many
-- pop-ups, so:
--   * Three priorities. Critical is an error or a refusal the player caused
--     (too far, can't afford, bed full): always shown. Normal is the result
--     of what the player just did (bought, sold). Low is ambient news
--     (entering a region, a daily goal, a Field Guide entry, a tip).
--   * At most MaxVisible (2) toasts are up, and at most one that isn't
--     critical. A critical one makes room by pushing out the oldest
--     non-critical (else the oldest critical) rather than waiting.
--   * Non-critical ones wait for Cooldown seconds after the last shown.
--     The rest queue, at most QueueCap long; a full queue drops the oldest
--     Low first (a new Low is dropped itself when there's no room), and a
--     queued notice that waited past MaxWait is stale and goes.
--   * The same text isn't shown again within DedupeSeconds (critical: a
--     shorter CriticalDedupeSeconds, so a mashed button doesn't stack but a
--     repeated refusal still answers). Same text already queued: dropped.
--   * A notice with a `key` and `once` is shown once per session per key
--     (a tip that repeats: "put your axe away").
--   * `quiet` (the first-sale chopping flow, FlowQuiet) drops everything
--     that isn't critical, queued or not.
-- Classify(text) gives the priority of a message that arrives as plain
-- text (the server's Notify), by what it says; a caller that knows better
-- passes a priority.

local NoticePolicy = {}

export type Priority = "critical" | "normal" | "low"

NoticePolicy.MaxVisible = 2
NoticePolicy.MaxVisibleNonCritical = 1
NoticePolicy.Cooldown = 1.0 -- seconds between non-critical toasts
NoticePolicy.DedupeSeconds = 8
NoticePolicy.CriticalDedupeSeconds = 1.5
NoticePolicy.QueueCap = 4
NoticePolicy.MaxWait = 8 -- seconds a queued notice stays worth showing (Low: half)

local RANK: { [string]: number } = { critical = 3, normal = 2, low = 1 }

export type Notice = {
	text: string,
	priority: Priority?, -- nil: Classify(text)
	seconds: number?, -- how long it stays (the caller's own, else MinSeconds..)
	key: string?, -- identifies a repeated tip, with `once`
	once: boolean?,
}

type Entry = {
	id: number,
	text: string,
	priority: Priority,
	seconds: number,
	key: string?,
	once: boolean?,
	at: number, -- when it was offered (queued) or shown (visible)
	expires: number, -- visible only
}

export type State = {
	visible: { Entry },
	queue: { Entry },
	lastShown: number,
	lastText: { [string]: number }, -- text -> when it was last shown
	seen: { [string]: boolean }, -- once-keys
	nextId: number,
}

export type Decision = {
	action: "show" | "queue" | "drop",
	reason: string?, -- for a drop: "quiet", "duplicate", "once", "full", "empty"
	id: number?, -- show: the toast's id
	text: string?,
	seconds: number?,
	priority: Priority?,
	evict: { number }, -- ids of toasts to take down now to make room
}

-- The first-sale chopping flow: TutorialStep 1 through the first sale (the
-- step index of `sell`), on the tutorial's first minutes. Murph's card and
-- the arrow are the one objective; nothing but errors should add to it.
-- `step` is the TutorialStep attribute as read (any type); `lastStep` the
-- index of the sell step (TutorialData.RefresherLast). nil (the save is
-- loading) counts as quiet too: the first screen is the loading card.
function NoticePolicy.FlowQuiet(step: unknown, lastStep: number): boolean
	if type(step) ~= "number" or step ~= step then
		return true
	end
	return step >= 1 and step <= lastStep
end

local function lower(text: string): string
	return string.lower(text)
end

local function hasAny(text: string, needles: { string }): boolean
	for _, needle in ipairs(needles) do
		if string.find(text, needle, 1, true) then
			return true
		end
	end
	return false
end

-- Ambient news: nothing the player just did.
local LOW_PREFIX: { string } = {
	"⏱", -- the Studio stopwatch
	"new in your field guide",
	"new daily goals",
	"daily return",
	"day ", -- "Day 7 of your daily return"
	"you earned the",
	"your ", -- "Your 3 left-behind logs ...", "Your truck is back"
	"the elder ",
	"the skyroot",
	"tutorial skipped",
	"tutorial reset",
}
local LOW_FIND: { string } = { " goal done:", "left-behind" }

-- A refusal or error the player's own action caused.
local CRITICAL: { string } = {
	"too far",
	"too hard",
	"closer",
	"you need ",
	"more for the",
	"not enough",
	"can't",
	"cannot",
	"couldn't",
	"isn't for sale",
	"is full",
	"too full",
	"full.",
	"nothing to sell",
	"stand on",
	"walk back",
	"walk up",
	"nothing to undo",
	"opens at",
	"opens in",
	"shut",
	"closed",
	"storage is full",
	"in the way",
	"try again",
	"failed",
	"no instant",
	"already own",
	"already have",
	"you left your plot",
	"someone else's",
	"first.",
	"stronger axe",
}

-- The priority of a message that came as plain text. Ambient lines are low,
-- refusals critical, everything else (a purchase, a sale) normal. Checked
-- in that order: a "Your truck can't ..." is still a refusal, so critical
-- words win over the low prefixes that aren't exact.
function NoticePolicy.Classify(text: string): Priority
	local s = lower(text)
	if string.sub(text, 1, #"⏱") == "⏱" then
		return "low"
	end
	if hasAny(s, CRITICAL) then
		return "critical"
	end
	for _, prefix in ipairs(LOW_PREFIX) do
		if string.sub(s, 1, #prefix) == prefix then
			return "low"
		end
	end
	if hasAny(s, LOW_FIND) then
		return "low"
	end
	return "normal"
end

function NoticePolicy.New(): State
	return {
		visible = {},
		queue = {},
		lastShown = -math.huge,
		lastText = {},
		seen = {},
		nextId = 0,
	}
end

local function expire(state: State, now: number)
	local keep: { Entry } = {}
	for _, entry in ipairs(state.visible) do
		if entry.expires > now then
			table.insert(keep, entry)
		end
	end
	state.visible = keep
	-- Stale queued notices.
	local fresh: { Entry } = {}
	for _, entry in ipairs(state.queue) do
		local wait = if entry.priority == "low" then NoticePolicy.MaxWait / 2 else NoticePolicy.MaxWait
		if now - entry.at <= wait then
			table.insert(fresh, entry)
		end
	end
	state.queue = fresh
end

local function nonCriticalVisible(state: State): number
	local n = 0
	for _, entry in ipairs(state.visible) do
		if entry.priority ~= "critical" then
			n += 1
		end
	end
	return n
end

local function dedupeWindow(priority: Priority): number
	return if priority == "critical" then NoticePolicy.CriticalDedupeSeconds else NoticePolicy.DedupeSeconds
end

-- Takes the visible list down to MaxVisible - 1 (room for one more),
-- oldest non-critical first, then the oldest critical. Returns the ids.
local function makeRoom(state: State): { number }
	local evict: { number } = {}
	while #state.visible >= NoticePolicy.MaxVisible do
		local pick: Entry? = nil
		for _, entry in ipairs(state.visible) do
			if entry.priority ~= "critical" and (pick == nil or entry.at < pick.at) then
				pick = entry
			end
		end
		if pick == nil then
			for _, entry in ipairs(state.visible) do
				if pick == nil or entry.at < pick.at then
					pick = entry
				end
			end
		end
		if pick == nil then
			break
		end
		table.insert(evict, pick.id)
		table.remove(state.visible, table.find(state.visible, pick) :: number)
	end
	return evict
end

local function show(state: State, entry: Entry, now: number): Decision
	local evict = makeRoom(state)
	entry.at = now
	entry.expires = now + entry.seconds
	table.insert(state.visible, entry)
	state.lastShown = now
	state.lastText[entry.text] = now
	return {
		action = "show",
		id = entry.id,
		text = entry.text,
		seconds = entry.seconds,
		priority = entry.priority,
		evict = evict,
	}
end

local function dropped(reason: string): Decision
	return { action = "drop", reason = reason, evict = {} }
end

local function queued(): Decision
	return { action = "queue", evict = {} }
end

local function inQueue(state: State, text: string): boolean
	for _, entry in ipairs(state.queue) do
		if entry.text == text then
			return true
		end
	end
	return false
end

-- Orders the queue: higher priority first, then oldest first.
local function sortQueue(state: State)
	table.sort(state.queue, function(a: Entry, b: Entry): boolean
		local ra, rb = RANK[a.priority], RANK[b.priority]
		if ra ~= rb then
			return ra > rb
		end
		return a.id < b.id
	end)
end

-- Adds to the queue within QueueCap. Returns false when `entry` was the one
-- dropped (the queue held nothing of lower value).
local function enqueue(state: State, entry: Entry): boolean
	table.insert(state.queue, entry)
	while #state.queue > NoticePolicy.QueueCap do
		-- The oldest Low goes; else the oldest Normal. Never a critical one
		-- (those don't queue, so there are none).
		local victim: Entry? = nil
		for _, wanted in ipairs({ "low", "normal" }) do
			for _, e in ipairs(state.queue) do
				if e.priority == wanted and (victim == nil or e.id < victim.id) then
					victim = e
				end
			end
			if victim then
				break
			end
		end
		if victim == nil then
			break
		end
		table.remove(state.queue, table.find(state.queue, victim) :: number)
		if victim == entry then
			return false
		end
	end
	sortQueue(state)
	return true
end

-- A notice arrives at `now` (seconds). `quiet` is FlowQuiet's answer. The
-- decision says to show it (with the ids to take down first), queue it, or
-- drop it (reason). Showing marks its text and once-key.
function NoticePolicy.Offer(state: State, notice: Notice, now: number, quiet: boolean?): Decision
	expire(state, now)
	local text = notice.text
	if type(text) ~= "string" or text == "" then
		return dropped("empty")
	end
	local priority: Priority = notice.priority or NoticePolicy.Classify(text)
	local critical = priority == "critical"
	if notice.once and notice.key and state.seen[notice.key] then
		return dropped("once")
	end
	if quiet and not critical then
		return dropped("quiet")
	end
	local last = state.lastText[text]
	if last and now - last < dedupeWindow(priority) then
		return dropped("duplicate")
	end
	for _, entry in ipairs(state.visible) do
		if entry.text == text then
			return dropped("duplicate")
		end
	end
	if inQueue(state, text) then
		return dropped("duplicate")
	end
	local seconds = if type(notice.seconds) == "number" then notice.seconds else 3
	state.nextId += 1
	local entry: Entry = {
		id = state.nextId,
		text = text,
		priority = priority,
		seconds = seconds,
		key = notice.key,
		once = notice.once,
		at = now,
		expires = now,
	}
	if notice.once and notice.key then
		state.seen[notice.key] = true
	end
	if critical then
		return show(state, entry, now)
	end
	if
		nonCriticalVisible(state) >= NoticePolicy.MaxVisibleNonCritical
		or #state.visible >= NoticePolicy.MaxVisible
		or now - state.lastShown < NoticePolicy.Cooldown
	then
		if enqueue(state, entry) then
			return queued()
		end
		return dropped("full")
	end
	return show(state, entry, now)
end

-- Call a few times a second: the next queued notice, when one may show.
-- `quiet` drops what's queued (everything queued is non-critical).
function NoticePolicy.Tick(state: State, now: number, quiet: boolean?): Decision?
	expire(state, now)
	if quiet then
		state.queue = {}
		return nil
	end
	local first = state.queue[1]
	if not first then
		return nil
	end
	if
		nonCriticalVisible(state) >= NoticePolicy.MaxVisibleNonCritical
		or #state.visible >= NoticePolicy.MaxVisible
		or now - state.lastShown < NoticePolicy.Cooldown
	then
		return nil
	end
	table.remove(state.queue, 1)
	return show(state, first, now)
end

-- Whether anything is waiting (HUD keeps its pump running while so).
function NoticePolicy.Pending(state: State): boolean
	return #state.queue > 0
end

return NoticePolicy
