--!strict
-- AdminLogic: who the owner is, and what the owner's chat commands mean.
-- Pure rules; AdminService (server only) does the acting. Nothing here is
-- trusted from a client: the server reads the speaker's UserId off the chat
-- source and asks IsOwner every single time.
--
-- The owner is, in this order:
--   * a UserId listed in AdminLogic.OwnerUserIds (paste yours between the
--     braces; this is the only place a name or id is ever typed in), or
--   * the experience's creator when a person (not a group) owns it.
-- Studio is allowed too: a Studio session is never a live server.
-- Nobody else, ever, whatever they type or fire.

local AdminLogic = {}

-- Paste Roblox UserIds here (a number each), e.g. { 123456789 }. Left empty,
-- only the experience's creator is the owner.
AdminLogic.OwnerUserIds = {} :: { number }

function AdminLogic.IsOwner(
	userId: unknown,
	creatorType: unknown,
	creatorId: unknown,
	studio: boolean,
	ownerIds: { number }?
): boolean
	if type(userId) ~= "number" or userId ~= userId or userId <= 0 or userId % 1 ~= 0 then
		return false
	end
	if studio then
		return true
	end
	for _, id in ipairs(ownerIds or AdminLogic.OwnerUserIds) do
		if id == userId then
			return true
		end
	end
	return creatorId == userId and tostring(creatorType) == "User"
end

-- Money limits: one command moves at most this much, and never past the
-- wallet cap (EconomyService clamps).
AdminLogic.MaxAmount = 2_000_000

-- What can be gifted for free, by kind (the shop's own kinds).
AdminLogic.GiftKinds = { "Axe", "Gear", "Sawmill", "Machine", "Blueprint" } :: { string }

export type Command = { name: string, args: { string }, rest: string }

-- "/give Bob 500" -> { name = "give", args = { "Bob", "500" }, rest = "Bob 500" }.
-- nil unless it starts with "/" and a word.
function AdminLogic.Parse(text: unknown): Command?
	if type(text) ~= "string" or #text > 200 then
		return nil
	end
	local name, found = string.match(text, "^%s*/([%a]+)%s*(.-)%s*$")
	if not name then
		return nil
	end
	local rest: string = found or ""
	local args: { string } = {}
	for word in string.gmatch(rest, "%S+") do
		table.insert(args, word)
	end
	return { name = string.lower(name), args = args, rest = rest }
end

-- A whole number from 1 to MaxAmount, or nil.
function AdminLogic.Amount(text: unknown): number?
	local n = if type(text) == "string" then tonumber(text) else nil
	if n == nil or n ~= n or n % 1 ~= 0 or n < 1 or n > AdminLogic.MaxAmount then
		return nil
	end
	return n
end

-- A player by name: exact (any case) wins, else a unique prefix. `names` are
-- the names of everyone online. Returns the name, or nil and why
-- ("none" or "many").
function AdminLogic.MatchName(query: unknown, names: { string }): (string?, string?)
	if type(query) ~= "string" or query == "" then
		return nil, "none"
	end
	local q = string.lower(query)
	local found: string? = nil
	local count = 0
	for _, name in ipairs(names) do
		local lower = string.lower(name)
		if lower == q then
			return name, nil
		end
		if string.sub(lower, 1, #q) == q then
			found = name
			count += 1
		end
	end
	if count == 1 then
		return found, nil
	elseif count == 0 then
		return nil, "none"
	end
	return nil, "many"
end

function AdminLogic.IsGiftKind(kind: unknown): boolean
	return type(kind) == "string" and table.find(AdminLogic.GiftKinds, kind) ~= nil
end

-- Ban length: "perm" or hours (1 to 8760), as seconds (-1 forever).
function AdminLogic.BanSeconds(text: unknown): number?
	if text == "perm" then
		return -1
	end
	local hours = if type(text) == "string" then tonumber(text) else nil
	if hours == nil or hours ~= hours or hours < 1 or hours > 8760 or hours % 1 ~= 0 then
		return nil
	end
	return hours * 3600
end

AdminLogic.Help = {
	"/give <player> <amount>: add cash",
	"/take <player> <amount>: remove cash",
	"/setcash <player> <amount>: set their cash",
	"/gift <player> <Axe|Gear|Sawmill|Machine|Blueprint> <id>: a free item",
	"/kick <player> [reason]",
	"/ban <player> <hours|perm> [reason], /unban <userId>",
	"/goto <player>, /bring <player>",
	"/superrun: toggle your own super run",
	"/announce <text>",
} :: { string }

return AdminLogic
