--!strict
-- LeaderboardLogic: the rules of the opt-in lifetime-earnings board. Pure,
-- so the server (LeaderboardService) and the Settings tab (LeaderboardUI)
-- share one set of numbers and the specs can pin them.
--
-- Score = profile.totalEarned, floored and clamped. Ranking is score high
-- to low; a tie goes to the lower userId, so every server shows the same
-- order. DataStore budgets: a player's score is written at most once per
-- WriteInterval (and once on leave), a server reads the top list at most
-- once per ReadInterval, and a client asks at most once per ClientInterval.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputKit = require(ReplicatedStorage.Shared.InputKit)
local Util = require(ReplicatedStorage.Shared.Util)

local LeaderboardLogic = {}

LeaderboardLogic.Size = 10 -- rows shown
LeaderboardLogic.FetchSize = 25 -- rows read, so opted-out players can be dropped and ten still remain
LeaderboardLogic.MaxScore = 1e12 -- far past any real total (the wallet cap is 2,000,000); keeps the store sane
LeaderboardLogic.WriteInterval = 120 -- seconds between one player's writes
LeaderboardLogic.ReadInterval = 60 -- seconds between a server's reads of the top list
LeaderboardLogic.ClientInterval = 10 -- seconds between one client's requests
LeaderboardLogic.RemoveInterval = 10 -- seconds between one player's removals (opting out is quick, toggling is not a flood)
LeaderboardLogic.FallbackName = "Lumberjack"
LeaderboardLogic.Title = "Leaderboard"
LeaderboardLogic.ToggleText = "Show me on the leaderboard"
LeaderboardLogic.EmptyText = "No one is on the board yet"
LeaderboardLogic.FailedText = "Couldn't load the board. Try again soon."
LeaderboardLogic.LoadingText = "Loading the board..."

export type Entry = { userId: number, score: number }
export type Ranked = { rank: number, userId: number, score: number }

-- A whole number from 0 to MaxScore, or nil if `value` isn't a usable number.
function LeaderboardLogic.SanitizeScore(value: unknown): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	local n = value :: number
	if n == math.huge then
		return LeaderboardLogic.MaxScore
	elseif n == -math.huge then
		return 0
	end
	return math.clamp(math.floor(n), 0, LeaderboardLogic.MaxScore)
end

-- A userId is a positive whole number.
function LeaderboardLogic.ValidUserId(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 1 and value == math.floor(value) and value < 2 ^ 53
end

-- Raw rows (any shape) into clean entries: bad rows and repeated userIds
-- are dropped (the first one wins).
function LeaderboardLogic.CleanEntries(raw: unknown): { Entry }
	local out: { Entry } = {}
	if type(raw) ~= "table" then
		return out
	end
	local seen: { [number]: boolean } = {}
	for _, row in ipairs(raw :: { any }) do
		if type(row) == "table" then
			local userId = row.userId
			local score = LeaderboardLogic.SanitizeScore(row.score)
			if LeaderboardLogic.ValidUserId(userId) and score ~= nil and not seen[userId] then
				seen[userId] = true
				table.insert(out, { userId = userId, score = score })
			end
		end
	end
	return out
end

-- Highest first, ties by lower userId.
function LeaderboardLogic.Before(a: Entry, b: Entry): boolean
	if a.score ~= b.score then
		return a.score > b.score
	end
	return a.userId < b.userId
end

-- Cleans, sorts, drops what `hide` says to, trims to `limit` (default Size)
-- and numbers the rows from 1. Score 0 is not on the board.
function LeaderboardLogic.Rank(raw: unknown, hide: ((userId: number) -> boolean)?, limit: number?): { Ranked }
	local entries = LeaderboardLogic.CleanEntries(raw)
	table.sort(entries, LeaderboardLogic.Before)
	local out: { Ranked } = {}
	local cap = limit or LeaderboardLogic.Size
	for _, e in ipairs(entries) do
		if #out >= cap then
			break
		end
		if e.score > 0 and not (hide and hide(e.userId)) then
			table.insert(out, { rank = #out + 1, userId = e.userId, score = e.score })
		end
	end
	return out
end

-- The rank of `userId` in a ranked list, or nil.
function LeaderboardLogic.RankOf(ranked: { Ranked }, userId: number): number?
	for _, row in ipairs(ranked) do
		if row.userId == userId then
			return row.rank
		end
	end
	return nil
end

-- Throttles. `last` is nil when it never happened. A clock that went
-- backwards counts as due, so a bad stamp can't block a player for good.
local function due(last: number?, now: number, interval: number): boolean
	return last == nil or now < last or now - last >= interval
end

function LeaderboardLogic.WriteDue(lastWriteAt: number?, now: number): boolean
	return due(lastWriteAt, now, LeaderboardLogic.WriteInterval)
end

function LeaderboardLogic.ReadDue(lastReadAt: number?, now: number): boolean
	return due(lastReadAt, now, LeaderboardLogic.ReadInterval)
end

function LeaderboardLogic.RemoveDue(lastRemoveAt: number?, now: number): boolean
	return due(lastRemoveAt, now, LeaderboardLogic.RemoveInterval)
end

function LeaderboardLogic.ClientDue(lastRequestAt: number?, now: number): boolean
	return due(lastRequestAt, now, LeaderboardLogic.ClientInterval)
end

-- A display name, or the fallback.
function LeaderboardLogic.CleanName(name: unknown): string
	if type(name) ~= "string" or name == "" then
		return LeaderboardLogic.FallbackName
	end
	return string.sub(name :: string, 1, 40)
end

-- One row as the tab prints it. `rank` nil (you, outside the top ten) shows a dash.
export type RowText = { rank: string, name: string, cash: string }
function LeaderboardLogic.FormatRow(rank: number?, name: string, score: number): RowText
	return {
		rank = if rank then tostring(rank) else "-",
		name = LeaderboardLogic.CleanName(name),
		cash = Util.formatCash(LeaderboardLogic.SanitizeScore(score) or 0),
	}
end

-- What the server sends. rows: the top list; me: your own row when you
-- are opted in (rank is nil when you're outside the top ten).
export type Row = { rank: number, name: string, score: number }
export type Me = { score: number, rank: number? }
export type Payload = { ok: boolean, rows: { Row }, me: Me? }

local function goodRank(rank: unknown): boolean
	return type(rank) == "number" and rank >= 1 and rank <= 1000 and rank == math.floor(rank)
end

-- The client trusts nothing: whatever arrives is rebuilt field by field.
-- Returns nil for anything that isn't a payload.
function LeaderboardLogic.ParsePayload(raw: unknown): Payload?
	if type(raw) ~= "table" then
		return nil
	end
	local p = raw :: any
	if type(p.ok) ~= "boolean" then
		return nil
	end
	local rows: { Row } = {}
	if type(p.rows) == "table" then
		for _, r in ipairs(p.rows) do
			if #rows >= LeaderboardLogic.Size then
				break
			end
			if type(r) == "table" then
				local score = LeaderboardLogic.SanitizeScore(r.score)
				if score ~= nil and goodRank(r.rank) then
					table.insert(rows, { rank = r.rank, name = LeaderboardLogic.CleanName(r.name), score = score })
				end
			end
		end
	end
	local me: Me? = nil
	if type(p.me) == "table" then
		local score = LeaderboardLogic.SanitizeScore(p.me.score)
		if score ~= nil then
			me = { score = score, rank = if goodRank(p.me.rank) then p.me.rank else nil }
		end
	end
	return { ok = p.ok, rows = rows, me = me }
end

-- Which state the tab shows for a payload (nil = nothing yet: loading).
export type State = "loading" | "failed" | "empty" | "rows"
function LeaderboardLogic.State(payload: Payload?): State
	if payload == nil then
		return "loading"
	elseif not payload.ok then
		return "failed"
	elseif #payload.rows == 0 then
		return "empty"
	end
	return "rows"
end

-- Layout numbers for the tab, in pixels at the HUD's scale. TV text is 18
-- at the least (the ten-foot rule); a phone's is UITheme's 14.
function LeaderboardLogic.TextPx(tenFoot: boolean): number
	return if tenFoot then 18 else 14
end

function LeaderboardLogic.RowHeight(tenFoot: boolean): number
	return if tenFoot then 30 else 26
end

-- What you press (the toggle, Refresh): a fingertip tall on a phone, a bit
-- more with a pad.
function LeaderboardLogic.ButtonHeight(tenFoot: boolean): number
	return math.max(InputKit.MinTouchPx, if tenFoot then 48 else 44)
end

-- The Settings card is wider on this tab so $ amounts at 18 px fit a row.
function LeaderboardLogic.CardWidth(tenFoot: boolean): number
	return if tenFoot then 380 else 320
end

return LeaderboardLogic
