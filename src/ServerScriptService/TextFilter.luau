--!strict
-- TextFilter: the one server door for player-typed text that other players
-- will see (a save name today; a sign, a plot name or a blueprint note the
-- day one exists). Nothing typed goes to another client unless it came back
-- from here.
--
--   * Broadcast(text, fromUserId): one string everyone may read, from
--     GetNonChatStringForBroadcastAsync. For names and labels on shared
--     things.
--   * ForUser(text, fromUserId, toUserId): the string filtered for one
--     reader (GetChatForUserAsync). For anything chat-like, where Roblox
--     filters by who is reading.
--   * ForEach(text, fromUserId, readers): one filter call, one string per
--     reader.
--
-- Every call is pcall'd and fails closed: an error, a missing service or an
-- answer that is not a string gives the placeholder ("####"), never the raw
-- text. TryBroadcast / TryForUser return nil instead, for a caller that
-- would rather keep a default than show the placeholder (SaveSlotService).
-- The calls yield; run them in a handler that can wait. Rules and wording:
-- Shared/TextFilterLogic.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TextFilterLogic = require(ReplicatedStorage.Shared.TextFilterLogic)

local TextFilter = {}

TextFilter.Placeholder = TextFilterLogic.Placeholder

local function service(): any?
	local ok, found = pcall(function()
		return game:GetService("TextService")
	end)
	if not ok or (typeof(found) ~= "Instance" and type(found) ~= "table") then
		return nil
	end
	return found
end

-- The TextFilterResult for `text`, or nil when the call failed.
local function prepare(text: unknown, fromUserId: unknown, maxChars: number?): any?
	local cleaned = TextFilterLogic.Clean(text, maxChars)
	if not cleaned or type(fromUserId) ~= "number" then
		return nil
	end
	local svc = service()
	if svc == nil or type(svc.FilterStringAsync) ~= "function" then
		return nil
	end
	local ok, result = pcall(function()
		return svc:FilterStringAsync(cleaned, fromUserId, Enum.TextFilterContext.PublicChat)
	end)
	if not ok or result == nil then
		warn("[TextFilter] FilterStringAsync failed: " .. tostring(result))
		return nil
	end
	return result
end

local function broadcastOf(result: any): string?
	if type(result.GetNonChatStringForBroadcastAsync) ~= "function" then
		return nil
	end
	local ok, text = pcall(function()
		return result:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		warn("[TextFilter] broadcast filter failed: " .. tostring(text))
		return nil
	end
	return TextFilterLogic.Strict(text)
end

local function userOf(result: any, toUserId: number): string?
	if type(result.GetChatForUserAsync) ~= "function" then
		return nil
	end
	local ok, text = pcall(function()
		return result:GetChatForUserAsync(toUserId)
	end)
	if not ok then
		warn("[TextFilter] per-reader filter failed: " .. tostring(text))
		return nil
	end
	return TextFilterLogic.Strict(text)
end

-- The text every player may read, or nil when it could not be filtered.
function TextFilter.TryBroadcast(text: unknown, fromUserId: unknown, maxChars: number?): string?
	local result = prepare(text, fromUserId, maxChars)
	if result == nil then
		return nil
	end
	return broadcastOf(result)
end

-- The text one reader may read, or nil when it could not be filtered.
function TextFilter.TryForUser(text: unknown, fromUserId: unknown, toUserId: unknown, maxChars: number?): string?
	if type(toUserId) ~= "number" then
		return nil
	end
	local result = prepare(text, fromUserId, maxChars)
	if result == nil then
		return nil
	end
	return userOf(result, toUserId)
end

-- Fail closed: the placeholder when anything went wrong.
function TextFilter.Broadcast(text: unknown, fromUserId: unknown, maxChars: number?): string
	return TextFilterLogic.Resolve(TextFilter.TryBroadcast(text, fromUserId, maxChars))
end

function TextFilter.ForUser(text: unknown, fromUserId: unknown, toUserId: unknown, maxChars: number?): string
	return TextFilterLogic.Resolve(TextFilter.TryForUser(text, fromUserId, toUserId, maxChars))
end

-- One filter call, then one string per reader (keyed by Player). A reader
-- whose own filter failed gets the placeholder; if the first call failed
-- everyone gets it.
function TextFilter.ForEach(
	text: unknown,
	fromUserId: unknown,
	readers: { Player },
	maxChars: number?
): { [Player]: string }
	local out: { [Player]: string } = {}
	local result = prepare(text, fromUserId, maxChars)
	for _, reader in ipairs(readers) do
		local shown: string? = nil
		if result ~= nil then
			shown = userOf(result, reader.UserId)
		end
		out[reader] = TextFilterLogic.Resolve(shown)
	end
	return out
end

return TextFilter
