--!strict
-- LeaderboardService: the opt-in lifetime-earnings board (rules in
-- Shared/LeaderboardLogic; the OrderedDataStore itself is behind
-- ProfileService.Board*, the only DataStore code).
--
--   * Only a player with settings.showOnBoard == true is ever written.
--     Turning it off stops the writes and removes their entry (best effort).
--   * A player's score (profile.totalEarned) is written at most once per
--     120 s, plus once when they leave.
--   * This server reads the top list at most once per 60 s and keeps it.
--     Clients ask at most once per 10 s and are answered from that cache,
--     never from the DataStore. The client never sends a score.
--   * Anyone on this server who is not opted in is hidden from the answer,
--     even if an old entry is still in the store.
--   * Every DataStore and name call is pcall'd; a failure keeps the old
--     cache and the client sees the "couldn't load" state.

local Players = game:GetService("Players")

local LeaderboardLogic = require(game:GetService("ReplicatedStorage").Shared.LeaderboardLogic)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

local LeaderboardService = {}

local TICK_SECONDS = 5
local NAME_CACHE_MAX = 500

local dataRemote: RemoteEvent? = nil

-- Who is here, and who of them is opted in (a per-server set of userIds).
local present: { [number]: Player? } = {}
local optedIn: { [number]: boolean } = {}
local lastWriteAt: { [number]: number } = {}
local lastRemoveAt: { [number]: number } = {}
local pendingRemove: { [number]: boolean } = {} -- opted out; the entry still has to go
local lastRequestAt: { [Player]: number } = {}

-- The top list as last read: raw entries (up to FetchSize) and the names.
local cache: { LeaderboardLogic.Entry }? = nil
local cacheFailed = false
local lastReadAt: number? = nil
local reading = false
local names: { [number]: string } = {}
local nameCount = 0
local refreshListeners: { () -> () } = {}

local function now(): number
	return os.clock()
end

local function scoreOf(player: Player): number?
	local profile = ProfileService.GetProfile(player)
	if profile == nil then
		return nil
	end
	return LeaderboardLogic.SanitizeScore(profile.totalEarned)
end

-- A display name for the board, cached. A failed lookup gives the fallback
-- (and is not cached, so a later refresh tries again).
local function nameFor(userId: number): string
	local cached = names[userId]
	if cached ~= nil then
		return cached
	end
	local here = present[userId]
	local ok, result = pcall(function(): any
		if here ~= nil then
			return here.Name
		end
		return Players:GetNameFromUserIdAsync(userId)
	end)
	if not ok or type(result) ~= "string" or result == "" then
		return LeaderboardLogic.FallbackName
	end
	if nameCount >= NAME_CACHE_MAX then
		table.clear(names)
		nameCount = 0
	end
	names[userId] = LeaderboardLogic.CleanName(result)
	nameCount += 1
	return names[userId]
end

-- Writes (or removes) this player's entry if their budget allows (a write
-- every 120 s, a removal every 10 s). `force` skips the interval: the
-- write on leave. Yields; run it in a thread.
local function sync(userId: number, score: number?, force: boolean)
	if optedIn[userId] then
		if score == nil or not (force or LeaderboardLogic.WriteDue(lastWriteAt[userId], now())) then
			return
		end
		lastWriteAt[userId] = now() -- also on failure: no hammering a down store
		pcall(ProfileService.BoardSet, userId, score) -- ProfileService pcalls the DataStore; this keeps the thread safe whatever happens
	elseif pendingRemove[userId] then
		if not (force or LeaderboardLogic.RemoveDue(lastRemoveAt[userId], now())) then
			return
		end
		lastRemoveAt[userId] = now()
		local ok, removed = pcall(ProfileService.BoardRemove, userId)
		if ok and removed == true then
			pendingRemove[userId] = nil
		end
	end
end

-- Reads the top list now if the budget allows. Yields.
local function refresh()
	if reading or not LeaderboardLogic.ReadDue(lastReadAt, now()) then
		return
	end
	reading = true
	lastReadAt = now()
	local ok, top = pcall(ProfileService.BoardTop, LeaderboardLogic.FetchSize)
	if not ok or top == nil then
		cacheFailed = true -- the old cache (if any) stays
	else
		local entries = LeaderboardLogic.CleanEntries(top)
		for _, e in ipairs(entries) do
			nameFor(e.userId)
		end
		cache = entries
		cacheFailed = false
	end
	reading = false
	-- Tell the listeners (the town board) after every read, good or not.
	for _, fn in ipairs(refreshListeners) do
		local called = pcall(fn)
		if not called then
			warn("[LeaderboardService] refresh listener failed")
		end
	end
end

-- A player is on the board here unless this server knows they opted out.
local function hidden(userId: number): boolean
	return present[userId] ~= nil and not optedIn[userId]
end

-- The top ten from the cache (opted-out players dropped as of now), ranked
-- and named, plus the ranked entries. nil while nothing has been read.
local function topRows(): ({ LeaderboardLogic.Row }?, { LeaderboardLogic.Ranked })
	local entries = cache
	if entries == nil then
		return nil, {}
	end
	local ranked = LeaderboardLogic.Rank(entries, hidden)
	local rows: { LeaderboardLogic.Row } = {}
	for _, r in ipairs(ranked) do
		table.insert(rows, { rank = r.rank, name = nameFor(r.userId), score = r.score })
	end
	return rows, ranked
end

-- The cached, opted-in, ranked top ten with names, for the town board. nil
-- while the first read is still loading or has failed (no cache to show).
-- A later failed read keeps the older cache, as the client answer does.
-- Reads no DataStore: refresh() is the only reader, at most every 60 s.
function LeaderboardService.Top(): { LeaderboardLogic.Row }?
	local rows = topRows()
	return rows
end

-- True when a read failed and there is no cache to fall back on.
function LeaderboardService.Failed(): boolean
	return cache == nil and cacheFailed
end

-- fn() runs after each read of the top list (success or failure), which is
-- at most once per LeaderboardLogic.ReadInterval.
function LeaderboardService.OnRefresh(fn: () -> ())
	table.insert(refreshListeners, fn)
end

-- What a client gets: the top ten (opted-out players dropped as of now),
-- and, if they're opted in, their own score and rank.
local function payloadFor(player: Player): LeaderboardLogic.Payload
	local rows, ranked = topRows()
	if rows == nil then
		return { ok = false, rows = {}, me = nil }
	end
	local me: LeaderboardLogic.Me? = nil
	if optedIn[player.UserId] then
		local score = scoreOf(player)
		if score ~= nil then
			me = { score = score, rank = LeaderboardLogic.RankOf(ranked, player.UserId) }
		end
	end
	return { ok = true, rows = rows, me = me }
end

local function answer(player: Player)
	local remote = dataRemote
	if remote == nil then
		return
	end
	if cache == nil and not cacheFailed then
		refresh() -- the first ask before the first read has finished
	end
	remote:FireClient(player, payloadFor(player))
end

-- One pass: refresh the list when due, and write what is due. The Init loop
-- calls this every few seconds.
function LeaderboardService.Tick()
	for userId, player in pairs(present) do
		if player ~= nil and (optedIn[userId] or pendingRemove[userId]) then
			task.spawn(sync, userId, scoreOf(player), false)
		end
	end
	if next(present) ~= nil then
		task.spawn(refresh)
	end
end

-- The BoardRequest remote. The client sends nothing we read.
local function onRequest(player: Player)
	if not RateLimiter.Allow(player, "BoardRequest") then
		return
	end
	local t = now()
	if not LeaderboardLogic.ClientDue(lastRequestAt[player], t) then
		return
	end
	lastRequestAt[player] = t
	task.spawn(answer, player)
end

-- `loop` false: no background ticking (the specs call Tick themselves).
function LeaderboardService.Init(request: RemoteEvent, data: RemoteEvent, loop: boolean?)
	dataRemote = data
	request.OnServerEvent:Connect(onRequest)
	if loop ~= false then
		task.spawn(function()
			while true do
				task.wait(TICK_SECONDS)
				LeaderboardService.Tick()
			end
		end)
	end
end

function LeaderboardService.PlayerJoined(player: Player, optIn: boolean)
	present[player.UserId] = player
	if optIn then
		optedIn[player.UserId] = true
	end
end

-- The showOnBoard setting changed (GameServer's SaveSetting handler, after
-- SettingsLogic accepted it).
function LeaderboardService.SettingChanged(player: Player, on: boolean)
	local userId = player.UserId
	if present[userId] == nil then
		return
	end
	if on then
		pendingRemove[userId] = nil
		if not optedIn[userId] then
			optedIn[userId] = true
			task.spawn(sync, userId, scoreOf(player), false)
		end
	elseif optedIn[userId] then
		optedIn[userId] = nil
		pendingRemove[userId] = true -- their entry goes now, or on the next tick if the budget says wait
		task.spawn(sync, userId, nil, false)
	end
end

-- Before the profile is released: the score is read now, the write follows.
function LeaderboardService.PlayerRemoving(player: Player)
	local userId = player.UserId
	if optedIn[userId] or pendingRemove[userId] then
		task.spawn(sync, userId, scoreOf(player), true)
	end
	present[userId] = nil
	optedIn[userId] = nil
	lastRequestAt[player] = nil
	-- lastWriteAt and pendingRemove stay until the thread above ends; both are tiny.
	task.delay(LeaderboardLogic.WriteInterval, function()
		if present[userId] == nil then
			lastWriteAt[userId] = nil
			lastRemoveAt[userId] = nil
			pendingRemove[userId] = nil
		end
	end)
end

return LeaderboardService
