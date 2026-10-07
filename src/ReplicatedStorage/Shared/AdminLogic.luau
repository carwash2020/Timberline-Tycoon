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

-- Time control. Speeds are WorldTime.Speeds (1, 4, 20, 60). The menu offers
-- these hours by name (TimePresets, id -> hour); chat also takes "6:30pm",
-- "18:30", "7am" or a bare hour 0-23.
AdminLogic.TimePresets = { midnight = 0, ["6am"] = 6, noon = 12, ["6pm"] = 18 } :: { [string]: number }
AdminLogic.TimePresetOrder = { "6am", "noon", "6pm", "midnight" } :: { string }

-- "1", "4", "20" or "60" (an optional trailing x: "20x"), as a number, or nil.
function AdminLogic.Speed(text: unknown): number?
	local WorldTime = require(script.Parent.WorldTime)
	local raw = if type(text) == "string" then string.match(text, "^(%d+)x?$") else nil
	local n = if raw then tonumber(raw) else nil
	if n ~= nil and WorldTime.IsSpeed(n) then
		return n
	end
	return nil
end

-- A time of day as an hour 0 to under 24 (minutes as a fraction), or nil.
-- "midnight", "noon", "6am", "6:30 pm", "18:30", "18". 12am is 0, 12pm is 12.
function AdminLogic.TimeOfDay(text: unknown): number?
	if type(text) ~= "string" or #text > 12 then
		return nil
	end
	local squeezed = string.gsub(text, "%s+", "")
	local lower = string.lower(squeezed)
	local preset = AdminLogic.TimePresets[lower]
	if preset then
		return preset
	end
	local h, m, suffix = string.match(lower, "^(%d%d?):?(%d?%d?)([ap]?m?)$")
	if not h then
		return nil
	end
	local hour = tonumber(h) :: number
	local minute = if m == "" then 0 else tonumber(m) :: number
	if minute > 59 or (m ~= "" and #(m :: string) ~= 2) then
		return nil
	end
	if suffix == "am" or suffix == "pm" then
		if hour < 1 or hour > 12 then
			return nil
		end
		hour = hour % 12 + (if suffix == "pm" then 12 else 0)
	elseif suffix ~= "" then
		return nil
	elseif hour > 23 then
		return nil
	end
	return hour + minute / 60
end

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

-- The owner menu (a controller can't type): a request is a small table, and
-- the server turns it into the same command line the chat takes, so there is
-- one set of rules and one lock. `request` is whatever a client sent (any
-- type); nothing is trusted. Returns the line, or nil for anything off the
-- list. Names are plain letters, digits and underscores (a Roblox name).
local function word(value: unknown, max: number): string?
	if type(value) == "string" and #value >= 1 and #value <= max and string.match(value, "^[%w_]+$") then
		return value
	end
	return nil
end

AdminLogic.MenuActions = {
	"give",
	"take",
	"setcash",
	"gift",
	"kick",
	"goto",
	"bring",
	"superrun",
	"timespeed",
	"settime",
	"timereset",
	"ban",
	"announce",
	"god",
	"heal",
	"freeze",
	"stats",
	"resettutorial",
	"unlockbp",
	"tospawn",
	"shutdown",
	"delegate",
	"undelegate",
	"delegates",
} :: { string }

-- Requests with no arguments, and requests that take only a player.
AdminLogic.PlainActions = { "superrun", "timereset", "god", "tospawn", "shutdown", "delegates" } :: { string }
AdminLogic.TargetActions = {
	"kick",
	"goto",
	"bring",
	"heal",
	"freeze",
	"stats",
	"resettutorial",
	"unlockbp",
} :: { string }

AdminLogic.MaxAnnounce = 120

-- Announcement text: 1 to MaxAnnounce printable characters, no control codes.
function AdminLogic.AnnounceText(text: unknown): string?
	if type(text) ~= "string" then
		return nil
	end
	local trimmed = string.match(text, "^%s*(.-)%s*$") or ""
	if trimmed == "" or #trimmed > AdminLogic.MaxAnnounce or string.find(trimmed, "%c") then
		return nil
	end
	return trimmed
end

---------------------------------------------------------------------------
-- Delegation: roles, powers, expiry. The OWNER (IsOwner) is the only one who
-- can grant or revoke anything; none of this ever applies to the owner. The
-- server holds the table of grants (AdminService) and asks these functions on
-- every request; a role named by a client is never read.
---------------------------------------------------------------------------

-- What a delegate may be given one by one (CUSTOM) or through a role. Cash,
-- permanent bans, shutdown, super run, profile changes (reset tutorial,
-- unlock buildings) and delegation itself are not on it.
AdminLogic.DelegablePowers = {
	"goto",
	"bring",
	"heal",
	"freeze",
	"stats",
	"announce",
	"kick",
	"ban",
	"gift",
	"settime",
	"timespeed",
	"timereset",
	"tospawn",
	"god",
} :: { string }

-- Owner only: no role (TESTER too) holds the first list, and nobody but the
-- owner holds the second. "sample" builds free test buildings on the owner's
-- own plot (SampleBuilds); it is not a power anyone can be given.
AdminLogic.NeverDelegable = {
	"give",
	"take",
	"setcash",
	"superrun",
	"shutdown",
	"resettutorial",
	"unlockbp",
	"unban",
	"sample",
} :: { string }
AdminLogic.OwnerOnly = { "delegate", "undelegate", "delegates" } :: { string }

-- Everything TESTER holds: every owner power except delegation.
AdminLogic.AllPowers = {
	"give",
	"take",
	"setcash",
	"gift",
	"kick",
	"ban",
	"unban",
	"goto",
	"bring",
	"superrun",
	"timespeed",
	"settime",
	"timereset",
	"announce",
	"god",
	"heal",
	"freeze",
	"stats",
	"resettutorial",
	"unlockbp",
	"tospawn",
	"shutdown",
} :: { string }

-- A TESTER's destructive actions need an extra confirmation, and the owner
-- is shown each one on screen.
AdminLogic.Destructive = { "ban", "unban", "kick", "shutdown", "take", "setcash", "resettutorial" } :: { string }

AdminLogic.MaxDelegateBanHours = 1

AdminLogic.RoleList = { "HELPER", "MODERATOR", "BUILDER", "TESTER", "CUSTOM" } :: { string }

AdminLogic.Roles = {
	HELPER = { "goto", "bring", "freeze", "stats", "announce" },
	MODERATOR = { "goto", "bring", "freeze", "stats", "announce", "kick", "ban" },
	BUILDER = { "gift", "settime", "timespeed", "timereset", "tospawn", "god" },
} :: { [string]: { string } }

AdminLogic.RoleHints = {
	HELPER = "Go to and bring players, freeze, stats, announce.",
	MODERATOR = "Helper powers plus kick and bans up to 1 hour.",
	BUILDER = "Free items for themself, the clock, god mode, spawn.",
	TESTER = "FULL OWNER POWER except delegation: cash, bans, shutdown.",
	CUSTOM = "Tick the individual powers below.",
} :: { [string]: string }

-- Expiry words. "session" ends when they leave or the server closes;
-- "server" is memory only, until the server closes. Nothing is saved.
AdminLogic.Expiries = { "session", "1h", "24h", "server" } :: { string }

function AdminLogic.ExpirySeconds(expiry: unknown): number?
	if expiry == "1h" then
		return 3600
	elseif expiry == "24h" then
		return 86400
	end
	return nil
end

-- TESTER may not be 'until the server closes' (it is short on purpose).
function AdminLogic.ExpiryAllowed(role: unknown, expiry: unknown): boolean
	if type(expiry) ~= "string" or table.find(AdminLogic.Expiries, expiry) == nil then
		return false
	end
	return not (role == "TESTER" and expiry == "server")
end

export type Grant = { role: string, powers: { string }, expiresAt: number?, session: boolean? }

function AdminLogic.Expired(grant: Grant, now: number): boolean
	return grant.expiresAt ~= nil and now >= grant.expiresAt
end

-- CUSTOM powers: a non-empty list of delegable powers, each once. Returns the
-- clean list, or nil and what is wrong (the first power that may not be given).
function AdminLogic.CleanPowers(list: unknown): ({ string }?, string?)
	if type(list) ~= "table" then
		return nil, "none"
	end
	local out: { string } = {}
	for _, power in ipairs(list :: { unknown }) do
		if type(power) ~= "string" or table.find(AdminLogic.DelegablePowers, power) == nil then
			return nil, tostring(power)
		end
		if table.find(out, power) == nil then
			table.insert(out, power)
		end
	end
	if #out == 0 then
		return nil, "none"
	end
	return out, nil
end

-- The powers a role carries (TESTER: everything but delegation), or nil.
function AdminLogic.PowersOf(role: unknown, custom: { string }?): { string }?
	if role == "TESTER" then
		return table.clone(AdminLogic.AllPowers)
	elseif role == "CUSTOM" then
		return custom
	elseif type(role) == "string" then
		return AdminLogic.Roles[role]
	end
	return nil
end

export type Ctx = { selfTarget: boolean?, banHours: number? }

-- May a delegate holding `grant` run `action`? (true, nil) or (false, why).
-- `ctx.selfTarget`: the target is the delegate themself; `ctx.banHours`: the
-- ban length in hours, nil for permanent. Never says yes to delegation.
function AdminLogic.GrantAllows(grant: Grant?, action: unknown, ctx: Ctx?): (boolean, string?)
	if grant == nil or type(action) ~= "string" then
		return false, "You have no powers here."
	end
	if table.find(AdminLogic.OwnerOnly, action) then
		return false, "Only the owner can do that."
	end
	if action == "admin" then
		return true, nil
	end
	if grant.role == "TESTER" then
		if table.find(AdminLogic.AllPowers, action) then
			return true, nil
		end
		return false, "That is not a power."
	end
	if table.find(AdminLogic.NeverDelegable, action) then
		return false, "Only the owner can do that."
	end
	if table.find(grant.powers, action) == nil then
		return false, "You were not given that power."
	end
	local c: Ctx = ctx or {}
	if action == "ban" then
		local hours = c.banHours
		if hours == nil or hours > AdminLogic.MaxDelegateBanHours then
			return false, "You can ban for up to " .. AdminLogic.MaxDelegateBanHours .. " hour only."
		end
	elseif action == "gift" and c.selfTarget ~= true then
		return false, "You can only gift to yourself."
	end
	return true, nil
end

-- The menu actions a grant may show (for the delegate's hub). Ban counts as
-- allowed here; it is limited to the cap when used.
function AdminLogic.AllowedActions(grant: Grant): { string }
	local out: { string } = {}
	for _, action in ipairs(AdminLogic.MenuActions) do
		local ok = AdminLogic.GrantAllows(grant, action, { selfTarget = true, banHours = 1 })
		if ok then
			table.insert(out, action)
		end
	end
	return out
end

function AdminLogic.IsDestructive(action: unknown): boolean
	return type(action) == "string" and table.find(AdminLogic.Destructive, action) ~= nil
end

export type Delegation = {
	target: string,
	userId: number?,
	role: string,
	powers: { string }?,
	expiry: string,
	confirmed: boolean,
}

-- The words after "/delegate <player|userId> <role> [powers] [expiry]
-- [confirm]"; powers (comma separated) only for CUSTOM. Returns the parsed
-- grant, or nil and a reason.
function AdminLogic.ParseDelegate(args: { string }): (Delegation?, string?)
	local target, roleWord = args[1], args[2]
	if not target or not roleWord then
		return nil,
			"Usage: /delegate <player|userId> <helper|moderator|builder|tester|custom> [powers] [session|1h|24h|server]"
	end
	local role = string.upper(roleWord)
	if table.find(AdminLogic.RoleList, role) == nil then
		return nil, "Roles: helper, moderator, builder, tester, custom."
	end
	local at = 3
	local powers: { string }? = nil
	if role == "CUSTOM" then
		local list: { string } = {}
		for power in string.gmatch(string.lower(args[3] or ""), "[^,]+") do
			table.insert(list, power)
		end
		local clean, bad = AdminLogic.CleanPowers(list)
		if not clean then
			return nil,
				if bad == "none"
					then "Custom needs powers, e.g. kick,goto."
					else tostring(bad) .. " can't be delegated."
		end
		powers = clean
		at = 4
	end
	local expiry = string.lower(args[at] or "session")
	local confirmed = false
	if expiry == "confirm" then
		expiry = "session"
		confirmed = true
	elseif string.lower(args[at + 1] or "") == "confirm" then
		confirmed = true
	end
	if not AdminLogic.ExpiryAllowed(role, expiry) then
		return nil,
			if role == "TESTER"
				then "TESTER ends with the session, 1h or 24h."
				else "Expiry: session, 1h, 24h or server."
	end
	local id = if string.match(target, "^%d+$") then tonumber(target) else nil
	return {
		target = target,
		userId = id,
		role = role,
		powers = powers,
		expiry = expiry,
		confirmed = confirmed,
	},
		nil
end

AdminLogic.TesterWarning =
	"TESTER has full owner power: cash, bans, save resets, shutdown. Only give it to someone you trust completely."

function AdminLogic.FromRequest(request: unknown): string?
	if type(request) ~= "table" then
		return nil
	end
	local req = request :: { [unknown]: unknown }
	local action = req.action
	if type(action) ~= "string" or table.find(AdminLogic.MenuActions, action) == nil then
		return nil
	end
	if table.find(AdminLogic.PlainActions, action) then
		return "/" .. action
	end
	if action == "announce" then
		local text = AdminLogic.AnnounceText(req.text)
		return if text then "/announce " .. text else nil
	end
	-- Time: a speed off the whitelist, or one of the named hours, never free text.
	if action == "timespeed" then
		local speed = req.speed
		if type(speed) ~= "number" or not require(script.Parent.WorldTime).IsSpeed(speed) then
			return nil
		end
		return string.format("/timespeed %d", speed)
	end
	if action == "settime" then
		local at = req.time
		if type(at) ~= "string" or AdminLogic.TimePresets[at] == nil then
			return nil
		end
		return "/settime " .. at
	end
	local target = word(req.target, 20)
	if not target then
		return nil
	end
	if action == "undelegate" then
		return "/undelegate " .. target
	end
	if action == "delegate" then
		local role, expiry = req.role, req.expiry
		if type(role) ~= "string" or table.find(AdminLogic.RoleList, role) == nil then
			return nil
		end
		if not AdminLogic.ExpiryAllowed(role, expiry) then
			return nil
		end
		local line = string.format("/delegate %s %s", target, string.lower(role))
		if role == "CUSTOM" then
			local powers = AdminLogic.CleanPowers(req.powers)
			if not powers then
				return nil
			end
			line ..= " " .. table.concat(powers, ",")
		end
		line ..= " " .. (expiry :: string)
		if role == "TESTER" and req.confirmed == true then
			line ..= " confirm"
		end
		return line
	end
	if table.find(AdminLogic.TargetActions, action) then
		return string.format("/%s %s", action, target)
	end
	if action == "ban" then
		local hours = req.hours
		local text = if hours == "perm"
			then "perm"
			elseif type(hours) == "number" then string.format("%d", hours)
			else nil
		if not text or AdminLogic.BanSeconds(text) == nil or (type(hours) == "number" and hours % 1 ~= 0) then
			return nil
		end
		return string.format("/ban %s %s", target, text)
	end
	if action == "gift" then
		local kind, itemId = req.kind, word(req.itemId, 40)
		if not AdminLogic.IsGiftKind(kind) or not itemId then
			return nil
		end
		return string.format("/gift %s %s %s", target, kind :: string, itemId)
	end
	-- give, take, setcash: a whole amount (setcash may be 0).
	local amount = req.amount
	if type(amount) ~= "number" or amount ~= amount or amount % 1 ~= 0 then
		return nil
	end
	if amount == 0 and action == "setcash" then
		return string.format("/setcash %s 0", target)
	end
	local text = AdminLogic.Amount(string.format("%d", amount))
	if not text then
		return nil
	end
	return string.format("/%s %s %d", action, target, text)
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
	"/timespeed <1|4|20|60>: speed up the clock (this server only)",
	"/settime <6am|noon|6pm|midnight|7:30pm|18:30>: set the hour",
	"/timereset: back to normal time",
	"/announce <text>",
	"/god: toggle no damage for you",
	"/heal <player>: full health",
	"/tospawn: teleport you to spawn",
	"/freeze <player>: freeze or unfreeze them",
	"/stats <player>: cash, plot, tutorial, items",
	"/resettutorial <player>: start their tutorial over",
	"/unlockbp <player>: every building plan",
	"/sample <modern|shop|barn>: a free test building on your plot, in front of you. /sample clear takes them down",
	"/shutdown: kick everyone, this server ends",
	"/delegate <player|userId> <helper|moderator|builder|tester|custom> [powers] [session|1h|24h|server]",
	"/undelegate <player|userId>, /delegates",
} :: { string }

return AdminLogic
