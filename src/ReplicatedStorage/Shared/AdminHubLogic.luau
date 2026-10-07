--!strict
-- AdminHubLogic: the rules behind the owner hub (StarterPlayerScripts/AdminUI):
-- the tabs and tools, which tools need a confirmation, how a request is built
-- from what is picked, the check the hub runs before it sends, the item
-- filter and recents, the pad's navigation order and the scroll that follows
-- it. Pure, so it is tested (tests/AdminHubLogic.spec).
--
-- None of this is a lock. The hub only asks: AdminService re-checks
-- AdminLogic.IsOwner on every request and AdminLogic.FromRequest whitelists
-- it. `Check` here only gives the owner a friendly reason before sending.

local AdminLogic = require(script.Parent.AdminLogic)
local PaidItems = require(script.Parent.PaidItems)
local WorldTime = require(script.Parent.WorldTime)

local Hub = {}

---------------------------------------------------------------------------
-- Layout rules (the UI reads these; a spec keeps them phone-safe)
---------------------------------------------------------------------------

Hub.Layout = {
	MinTouch = 44, -- the least anything you tap is tall
	Row = 48, -- a button row
	Chip = 44, -- a chip in a row of choices
	Gap = 8,
	Pad = 14,
	TabHeight = 44,
	PanelMaxW = 560,
	PanelMaxH = 660,
	HintText = 13, -- the 'what is this' line (a phone never reads below 12)
	MaxListRows = 40, -- item rows drawn at once; narrow the search for the rest
	PhoneWidth = 520, -- a panel narrower than this wraps its tabs onto two rows
	ConsoleRow = 64, -- a row on a pad: big enough to land on with a stick
	PhoneRow = 56, -- a row on a phone: a thumb
	ConsoleHint = 16,
}

-- How tall a list row is on this device ("console", "phone" or "desktop").
function Hub.RowHeight(device: string): number
	if device == "console" then
		return Hub.Layout.ConsoleRow
	elseif device == "phone" then
		return Hub.Layout.PhoneRow
	end
	return Hub.Layout.Row
end

function Hub.HintSize(device: string): number
	return if device == "console" then Hub.Layout.ConsoleHint else Hub.Layout.HintText
end

-- Tab buttons per row: all in one row on a roomy panel, two rows on a narrow
-- one, so the tabs never scroll sideways and never shrink below a thumb.
function Hub.TabColumns(panelWidth: number, count: number): number
	if count <= 0 then
		return 1
	end
	if panelWidth >= Hub.Layout.PhoneWidth or count <= 3 then
		return count
	end
	return math.ceil(count / 2)
end

function Hub.TabRows(panelWidth: number, count: number): number
	local cols = Hub.TabColumns(panelWidth, count)
	return math.ceil(math.max(count, 1) / cols)
end

---------------------------------------------------------------------------
-- Tabs and tools
---------------------------------------------------------------------------

export type Tab = { id: string, label: string, hint: string, always: boolean? }

-- The order is the owner's: who, what to give them, the world, who else may
-- help, then the log. LB / RB (and LT / RT) step through it.
Hub.Tabs = {
	{
		id = "players",
		label = "PLAYERS",
		hint = "Pick a player, then go to them, bring them, heal, freeze, kick or ban. Your own tools are here too.",
	},
	{ id = "gifts", label = "GIFTS", hint = "Cash and free items for the player you picked." },
	{
		id = "paid",
		label = "PAID ITEMS",
		hint = "Give or take back the things the Robux store sells: passes, boosters, the Lux Axe.",
	},
	{ id = "world", label = "WORLD", hint = "The clock, announcements and the server." },
	{ id = "roles", label = "ROLES", hint = "Give other people some powers, and take them back." },
	{
		id = "log",
		label = "LOG",
		hint = "What was done, and every chat command.",
		always = true,
	},
} :: { Tab }

export type Tool = {
	id: string, -- also the AdminLogic action
	tab: string,
	label: string,
	hint: string,
	style: string, -- UITheme button style
	confirm: boolean,
	words: string, -- extra search words
	needsPlayer: boolean,
}

local function tool(
	id: string,
	tab: string,
	label: string,
	hint: string,
	style: string,
	confirm: boolean,
	words: string,
	needsPlayer: boolean
): Tool
	return {
		id = id,
		tab = tab,
		label = label,
		hint = hint,
		style = style,
		confirm = confirm,
		words = words,
		needsPlayer = needsPlayer,
	}
end

Hub.Tools = {
	tool("goto", "players", "GO TO", "Teleport you next to them.", "bark", false, "teleport tp visit", true),
	tool("bring", "players", "BRING", "Teleport them next to you.", "bark", false, "teleport summon", true),
	tool("heal", "players", "HEAL", "Give them full health.", "bark", false, "health hp", true),
	tool(
		"freeze",
		"players",
		"FREEZE / UNFREEZE",
		"Hold them in place. Press again to let go.",
		"bark",
		false,
		"anchor stop",
		true
	),
	tool(
		"stats",
		"players",
		"STATS",
		"Read their cash, plot, tutorial step and items. Changes nothing.",
		"blue",
		false,
		"info view look",
		true
	),
	tool(
		"resettutorial",
		"players",
		"RESET TUTORIAL",
		"Start their tutorial over. They lose their place in it.",
		"bark",
		true,
		"murph quest",
		true
	),
	tool(
		"kick",
		"players",
		"KICK",
		"Remove them from this server. They can come back.",
		"skip",
		true,
		"remove boot",
		true
	),
	tool(
		"ban",
		"players",
		"BAN",
		"Keep them out of the whole game for the length you picked.",
		"skip",
		true,
		"block",
		true
	),
	tool(
		"give",
		"gifts",
		"GIVE CASH",
		"Add the amount to their wallet (the wallet cap still applies).",
		"buy",
		false,
		"money add",
		true
	),
	tool(
		"take",
		"gifts",
		"TAKE CASH",
		"Remove the amount, never more than they have.",
		"skip",
		true,
		"money remove",
		true
	),
	tool(
		"setcash",
		"gifts",
		"SET CASH",
		"Replace their wallet with exactly the amount.",
		"skip",
		true,
		"money exact",
		true
	),
	tool(
		"unlockbp",
		"gifts",
		"UNLOCK ALL BUILDINGS",
		"Teach them every building plan for good.",
		"bark",
		false,
		"blueprints plans",
		true
	),
	tool(
		"gift",
		"gifts",
		"GIFT ITEM",
		"Hand over the picked item for free.",
		"buy",
		false,
		"free item axe gear sawmill machine blueprint",
		true
	),
	tool(
		"timespeed",
		"world",
		"SET CLOCK SPEED",
		"Run the clock faster on this server only. Not saved.",
		"buy",
		false,
		"time fast",
		false
	),
	tool(
		"settime",
		"world",
		"SET HOUR",
		"Jump to the picked hour. Not saved.",
		"bark",
		false,
		"time day night noon",
		false
	),
	tool("timereset", "world", "RESET TIME", "Real time again.", "bark", false, "time normal", false),
	tool(
		"announce",
		"world",
		"ANNOUNCE",
		"Show your message to everyone on this server.",
		"buy",
		false,
		"message broadcast toast",
		false
	),
	tool(
		"shutdown",
		"world",
		"SHUT DOWN SERVER",
		"Kick everyone, you too. This server ends.",
		"skip",
		true,
		"restart stop close",
		false
	),
	tool(
		"delegate",
		"roles",
		"GRANT",
		"Give the picked player the role for the time you chose. Only you can do this.",
		"buy",
		false,
		"role helper moderator builder tester custom",
		true
	),
	tool(
		"undelegate",
		"roles",
		"REVOKE",
		"Take every power back from the picked player at once.",
		"skip",
		true,
		"remove role",
		true
	),
	tool(
		"delegates",
		"roles",
		"LIST DELEGATES",
		"Show who has powers and how long they last.",
		"blue",
		false,
		"roles",
		false
	),
	tool("superrun", "players", "SUPER RUN", "Toggle 4x walk speed for you.", "buy", false, "speed fast self", false),
	tool("god", "players", "GOD MODE", "Toggle no damage for you.", "bark", false, "invincible health self", false),
	tool(
		"tospawn",
		"players",
		"GO TO SPAWN",
		"Teleport you to the spawn point.",
		"bark",
		false,
		"teleport home self",
		false
	),
	tool(
		"unban",
		"players",
		"UNBAN",
		"Let a banned account back in. Type their numeric UserId.",
		"bark",
		true,
		"ban pardon userid",
		false
	),
	tool(
		"paidgive",
		"paid",
		"GIVE",
		"Give the picked paid item to the picked player. No Robux, no receipt.",
		"buy",
		true,
		"robux gamepass pass product 2x lux axe booster grant",
		true
	),
	tool(
		"paidrevoke",
		"paid",
		"REVOKE",
		"Take an owner grant back (or end a booster). A pass they bought stays.",
		"skip",
		true,
		"robux remove take back",
		true
	),
	tool(
		"paidlist",
		"paid",
		"REFRESH WHAT THEY OWN",
		"Read which paid items the picked player has. Changes nothing.",
		"blue",
		false,
		"owns inventory robux",
		true
	),
} :: { Tool }

function Hub.Tool(id: string): Tool?
	for _, t in ipairs(Hub.Tools) do
		if t.id == id then
			return t
		end
	end
	return nil
end

function Hub.ToolsFor(tabId: string): { Tool }
	local out: { Tool } = {}
	for _, t in ipairs(Hub.Tools) do
		if t.tab == tabId then
			table.insert(out, t)
		end
	end
	return out
end

-- Tabs wrap: +1 next, -1 previous.
function Hub.TabStep(index: number, dir: number, count: number?): number
	local n = count or #Hub.Tabs
	return ((index - 1 + dir) % n) + 1
end

-- `allowed` is the set of actions a delegate may use (nil: the owner, all).
function Hub.Allows(allowed: { [string]: boolean }?, id: string): boolean
	return allowed == nil or allowed[id] == true
end

-- The tabs a viewer sees: those with at least one tool they may use.
function Hub.VisibleTabs(allowed: { [string]: boolean }?): { Tab }
	local out: { Tab } = {}
	for _, tab in ipairs(Hub.Tabs) do
		if tab.always then
			table.insert(out, tab)
			continue
		end
		for _, t in ipairs(Hub.ToolsFor(tab.id)) do
			if Hub.Allows(allowed, t.id) then
				table.insert(out, tab)
				break
			end
		end
	end
	return out
end

-- Search over every tool (label, hint, tab name and words); every word typed
-- must appear. An empty query is nothing.
function Hub.FilterTools(query: unknown, allowed: { [string]: boolean }?): { Tool }
	local out: { Tool } = {}
	if type(query) ~= "string" then
		return out
	end
	local words: { string } = {}
	for w in string.gmatch(string.lower(query), "%S+") do
		table.insert(words, w)
	end
	if #words == 0 then
		return out
	end
	for _, t in ipairs(Hub.Tools) do
		if not Hub.Allows(allowed, t.id) then
			continue
		end
		local hay = string.lower(t.label .. " " .. t.hint .. " " .. t.words .. " " .. t.tab)
		local all = true
		for _, w in ipairs(words) do
			if not string.find(hay, w, 1, true) then
				all = false
				break
			end
		end
		if all then
			table.insert(out, t)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Confirmation: a second press within the window does it
---------------------------------------------------------------------------

Hub.ConfirmWindow = 4

function Hub.NeedsConfirm(id: string): boolean
	local t = Hub.Tool(id)
	return t ~= nil and t.confirm
end

export type Pending = { key: string, at: number }

-- One press of a tool. `key` names the tool and what it is aimed at (a new
-- player or amount is a new key), so changing either starts over. Returns
-- (fire, pending): fire is true when it should run now.
-- `force` asks for the second press even for a tool that does not always need it
-- (granting TESTER; a TESTER's destructive tools).
function Hub.Press(id: string, key: string, now: number, pending: Pending?, force: boolean?): (boolean, Pending?)
	if not force and not Hub.NeedsConfirm(id) then
		return true, nil
	end
	if pending and pending.key == key and now - pending.at <= Hub.ConfirmWindow and now >= pending.at then
		return true, nil
	end
	return false, { key = key, at = now }
end

-- Does this request need the second press for the one using the hub?
function Hub.NeedsConfirmFor(id: string, req: { [string]: any }, isTester: boolean): boolean
	if Hub.NeedsConfirm(id) then
		return true
	end
	if id == "delegate" and req.role == "TESTER" then
		return true
	end
	return isTester and AdminLogic.IsDestructive(id)
end

function Hub.StillPending(pending: Pending?, now: number): boolean
	return pending ~= nil and now - pending.at <= Hub.ConfirmWindow
end

-- The sure-prompt a destructive button shows while armed.
function Hub.SureText(id: string, who: string?): string
	if id == "shutdown" then
		return "SURE? PRESS AGAIN"
	end
	return if who then "SURE? " .. string.upper(id) .. " " .. who else "SURE?"
end

---------------------------------------------------------------------------
-- The player picker (one pick, shared by every player tool)
---------------------------------------------------------------------------

function Hub.SortNames(names: { string }, selfName: string): { string }
	local out = table.clone(names)
	table.sort(out, function(a, b)
		if (a == selfName) ~= (b == selfName) then
			return a == selfName -- you first
		end
		return string.lower(a) < string.lower(b)
	end)
	return out
end

-- Keeps the picked player by name while they are here; else the first other
-- player, else you. nil only when nobody is online.
function Hub.Pick(names: { string }, current: string?, selfName: string): string?
	local sorted = Hub.SortNames(names, selfName)
	if current and table.find(sorted, current) then
		return current
	end
	for _, name in ipairs(sorted) do
		if name ~= selfName then
			return name
		end
	end
	return sorted[1]
end

function Hub.StepName(names: { string }, current: string?, dir: number, selfName: string): string?
	local sorted = Hub.SortNames(names, selfName)
	if #sorted == 0 then
		return nil
	end
	local at = if current then table.find(sorted, current) else nil
	local nextIndex = if at then ((at - 1 + dir) % #sorted) + 1 else 1
	return sorted[nextIndex]
end

---------------------------------------------------------------------------
-- Amounts
---------------------------------------------------------------------------

Hub.Amounts = { 100, 1000, 10000, 100000, 1000000 } :: { number }

-- "2500", "$2,500", "10k", "1.5m" as a whole number from 0 to the cap, or nil.
function Hub.ParseAmount(text: unknown): number?
	if type(text) ~= "string" then
		return nil
	end
	local cleaned = string.lower((string.gsub(text, "[%s,$]", "")))
	local digits, suffix = string.match(cleaned, "^(%d+%.?%d*)([km]?)$")
	if not digits then
		return nil
	end
	local value = tonumber(digits)
	if value == nil then
		return nil
	end
	if suffix == "k" then
		value *= 1000
	elseif suffix == "m" then
		value *= 1000000
	end
	local whole = math.floor(value + 0.5)
	if math.abs(whole - value) > 1e-6 or whole > AdminLogic.MaxAmount then
		return nil
	end
	return whole
end

---------------------------------------------------------------------------
-- Ban lengths and announcement presets
---------------------------------------------------------------------------

Hub.BanChoices = {
	{ label = "1 HOUR", hours = 1 },
	{ label = "1 DAY", hours = 24 },
	{ label = "1 WEEK", hours = 168 },
	{ label = "FOREVER", hours = "perm" },
} :: { { label: string, hours: number | string } }

Hub.AnnouncePresets = {
	"The server will restart soon.",
	"An event is starting. Come join in!",
	"Thanks for playing!",
} :: { string }

-- Delegation choices for the DELEGATES tab.
Hub.ExpiryChoices = {
	{ id = "session", label = "SESSION" },
	{ id = "1h", label = "1 HOUR" },
	{ id = "24h", label = "24 HOURS" },
	{ id = "server", label = "UNTIL SERVER CLOSES" },
} :: { { id: string, label: string } }

-- The expiry choices a role may have (TESTER never lasts until the server closes).
function Hub.ExpiriesFor(role: string): { { id: string, label: string } }
	local out = {}
	for _, choice in ipairs(Hub.ExpiryChoices) do
		if AdminLogic.ExpiryAllowed(role, choice.id) then
			table.insert(out, choice)
		end
	end
	return out
end

-- Names for the power ticks.
Hub.PowerLabels = {
	["goto"] = "Go to players",
	bring = "Bring players",
	heal = "Heal",
	freeze = "Freeze",
	stats = "View stats",
	announce = "Announce",
	kick = "Kick",
	ban = "Ban (up to 1 hour)",
	gift = "Free items for themself",
	paidgive = "Gifts: paid items for themself",
	settime = "Set the hour",
	timespeed = "Clock speed",
	timereset = "Reset time",
	tospawn = "Go to spawn",
	god = "God mode",
} :: { [string]: string }

-- One line of help under each power tick (the CUSTOM role's list).
Hub.PowerHelp = {
	["goto"] = "Teleport next to a player.",
	bring = "Teleport a player next to them.",
	heal = "Give a player full health.",
	freeze = "Hold a player in place, or let go.",
	stats = "Read a player's cash, plot and items.",
	announce = "Show a message to everyone on the server.",
	kick = "Remove a player from this server.",
	ban = "Keep a player out for up to 1 hour.",
	gift = "Hand themself any free item from the shop.",
	paidgive = "Give themself any Robux-store item (Lux Axe, 2x Cash...). Never to others. Never take back.",
	settime = "Jump the clock to a named hour (this server).",
	timespeed = "Run the clock faster (this server).",
	timereset = "Put the clock back to real time.",
	tospawn = "Teleport themself to spawn.",
	god = "No damage for themself.",
} :: { [string]: string }

Hub.HourNames = { ["6am"] = "6 AM", noon = "Noon", ["6pm"] = "6 PM", midnight = "Midnight" } :: { [string]: string }

---------------------------------------------------------------------------
-- Requests and the check before sending
---------------------------------------------------------------------------

export type Context = {
	who: string?,
	amount: number?,
	kind: string?,
	itemId: string?,
	hours: (number | string)?,
	speed: number?,
	hour: string?,
	text: string?,
	role: string?,
	powers: { string }?,
	expiry: string?,
	paidId: string?, -- a PaidItems id
	paidHours: number?, -- a boost's length in hours (nil: the item's own)
	userId: number?, -- unban
}

-- The request a tool sends for what is picked (the server whitelists it again).
function Hub.Request(id: string, ctx: Context): { [string]: any }?
	local t = Hub.Tool(id)
	if not t then
		return nil
	end
	local req: { [string]: any } = { action = id }
	if t.needsPlayer then
		req.target = ctx.who
	end
	if id == "give" or id == "take" or id == "setcash" then
		req.amount = ctx.amount
	elseif id == "gift" then
		req.kind = ctx.kind
		req.itemId = ctx.itemId
	elseif id == "ban" then
		req.hours = ctx.hours
	elseif id == "timespeed" then
		req.speed = ctx.speed
	elseif id == "settime" then
		req.time = ctx.hour
	elseif id == "announce" then
		req.text = ctx.text
	elseif id == "delegate" then
		req.role = ctx.role
		req.powers = ctx.powers
		req.expiry = ctx.expiry
	elseif id == "paidgive" or id == "paidrevoke" then
		req.itemId = ctx.paidId
		if id == "paidgive" then
			req.hours = ctx.paidHours
		end
	elseif id == "unban" then
		req.userId = ctx.userId
	end
	return req
end

-- nil when the request can go, else a plain reason to show the owner.
function Hub.Check(req: { [string]: any }, selfName: string): string?
	local action = req.action
	local t = if type(action) == "string" then Hub.Tool(action) else nil
	if not t then
		return "That tool does not exist."
	end
	if t.needsPlayer then
		if type(req.target) ~= "string" or req.target == "" then
			return "Pick a player first."
		end
		if req.target == selfName and (action == "kick" or action == "ban" or action == "freeze") then
			return "You can't do that to yourself."
		end
	end
	if action == "give" or action == "take" then
		if type(req.amount) ~= "number" or AdminLogic.Amount(string.format("%d", req.amount)) == nil then
			return "Pick an amount from $1 to " .. string.format("$%d", AdminLogic.MaxAmount) .. "."
		end
	elseif action == "setcash" then
		if
			type(req.amount) ~= "number"
			or req.amount < 0
			or req.amount > AdminLogic.MaxAmount
			or req.amount % 1 ~= 0
		then
			return "Pick an amount from $0 to " .. string.format("$%d", AdminLogic.MaxAmount) .. "."
		end
	elseif action == "gift" then
		if not AdminLogic.IsGiftKind(req.kind) or type(req.itemId) ~= "string" or req.itemId == "" then
			return "Pick an item first."
		end
	elseif action == "ban" then
		if
			req.hours ~= "perm"
			and not (type(req.hours) == "number" and AdminLogic.BanSeconds(string.format("%d", req.hours)) ~= nil)
		then
			return "Pick how long to ban for."
		end
	elseif action == "timespeed" then
		if type(req.speed) ~= "number" or not WorldTime.IsSpeed(req.speed) then
			return "Pick a clock speed."
		end
	elseif action == "settime" then
		if type(req.time) ~= "string" or AdminLogic.TimePresets[req.time] == nil then
			return "Pick an hour."
		end
	elseif action == "delegate" then
		if type(req.role) ~= "string" or table.find(AdminLogic.RoleList, req.role) == nil then
			return "Pick a role."
		end
		if req.role == "CUSTOM" and AdminLogic.CleanPowers(req.powers) == nil then
			return "Tick at least one power."
		end
		if not AdminLogic.ExpiryAllowed(req.role, req.expiry) then
			return if req.role == "TESTER"
				then "TESTER can only last this session, 1 hour or 24 hours."
				else "Pick how long it lasts."
		end
		if req.target == selfName then
			return "You are the owner already."
		end
	elseif action == "announce" then
		if AdminLogic.AnnounceText(req.text) == nil then
			return "Type a message first (up to " .. AdminLogic.MaxAnnounce .. " letters)."
		end
	elseif action == "paidgive" or action == "paidrevoke" then
		if type(req.itemId) ~= "string" or req.itemId == "" then
			return "Pick a paid item first."
		end
		local hours = req.hours
		if
			action == "paidgive"
			and hours ~= nil
			and (type(hours) ~= "number" or hours % 1 ~= 0 or hours < 1 or hours > AdminLogic.MaxPaidHours)
		then
			return "Pick a boost length from 1 to " .. AdminLogic.MaxPaidHours .. " hours."
		end
	elseif action == "unban" then
		local id = req.userId
		if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 or id > 2 ^ 52 then
			return "Type the UserId (a number) of the account to unban."
		end
	end
	return nil
end

-- A result line: trimmed and short enough for two lines.
function Hub.StatusText(text: unknown): string
	local s = if type(text) == "string" then text else ""
	s = string.gsub(s, "[%c]+", " ")
	if #s > 160 then
		s = string.sub(s, 1, 157) .. "..."
	end
	return s
end

-- The on-screen audit list: newest first, capped.
Hub.AuditCap = 8
function Hub.PushAudit(list: { string }, line: string): { string }
	local out = { line }
	for i = 1, math.min(#list, Hub.AuditCap - 1) do
		out[i + 1] = list[i]
	end
	return out
end

---------------------------------------------------------------------------
-- Items: category filter, search, recents
---------------------------------------------------------------------------

export type Item = { id: string, name: string, kind: string }

Hub.Categories = { "All", "Recent", "Axe", "Gear", "Sawmill", "Machine", "Blueprint" } :: { string }

function Hub.NextCategory(category: string, dir: number): string
	local at = table.find(Hub.Categories, category) or 1
	return Hub.Categories[((at - 1 + dir) % #Hub.Categories) + 1]
end

local function key(item: Item): string
	return item.kind .. ":" .. item.id
end

-- `items` is every giftable item in catalog order. "Recent" shows `recents`
-- (newest first). The query must match the name or id (every word).
function Hub.Filter(items: { Item }, query: unknown, category: string, recents: { Item }?): { Item }
	local source = items
	if category == "Recent" then
		source = recents or {}
	end
	local words: { string } = {}
	if type(query) == "string" then
		for w in string.gmatch(string.lower(query), "%S+") do
			table.insert(words, w)
		end
	end
	local out: { Item } = {}
	for _, item in ipairs(source) do
		if category == "All" or category == "Recent" or item.kind == category then
			local hay = string.lower(item.name .. " " .. item.id)
			local all = true
			for _, w in ipairs(words) do
				if not string.find(hay, w, 1, true) then
					all = false
					break
				end
			end
			if all then
				table.insert(out, item)
			end
		end
	end
	return out
end

-- (the first `max` rows, how many were left off)
function Hub.Limit(list: { Item }, max: number): ({ Item }, number)
	if #list <= max then
		return list, 0
	end
	local out: { Item } = {}
	for i = 1, max do
		out[i] = list[i]
	end
	return out, #list - max
end

Hub.RecentCap = 6

function Hub.PushRecent(recents: { Item }, item: Item): { Item }
	local out: { Item } = { item }
	for _, other in ipairs(recents) do
		if key(other) ~= key(item) and #out < Hub.RecentCap then
			table.insert(out, other)
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Who you are, back one level, why a button is off
---------------------------------------------------------------------------

-- The persistent header line: your name and role, and how long it lasts.
-- `label` is the server's word ("OWNER", "TESTER (full power)", "DELEGATE").
function Hub.WhoText(name: string, label: string, grantRole: string?, secondsLeft: number?): string
	local text = string.format("%s  |  %s", name, label)
	if grantRole and grantRole ~= "" and not string.find(label, grantRole, 1, true) then
		text ..= " (" .. grantRole .. ")"
	end
	if secondsLeft then
		text ..= string.format("  |  %d min left", math.ceil(secondsLeft / 60))
	end
	return text
end

export type BackState = { pending: boolean, toolQuery: string, detail: string?, listQuery: string? }

-- What B (or Esc) does: one level back, and only when there is none left,
-- close. "cancel" drops a pending confirmation, "clearSearch" empties the
-- tool search, "leaveDetail" goes from an item back to its list, "clearFilter"
-- empties a list's filter, "close" shuts the hub.
function Hub.Back(state: BackState): string
	if state.pending then
		return "cancel"
	elseif state.toolQuery ~= "" then
		return "clearSearch"
	elseif state.detail ~= nil then
		return "leaveDetail"
	elseif state.listQuery ~= nil and state.listQuery ~= "" then
		return "clearFilter"
	end
	return "close"
end

-- Why a tool can't go right now (the button shows it), or nil. It is the
-- same check as before sending, so the reason is the one the server would
-- give. `selfOnly` (a delegate with the Gifts power): paid items only to you.
function Hub.ToolDisabled(id: string, ctx: Context, selfName: string, selfOnly: boolean?): string?
	local req = Hub.Request(id, ctx)
	if not req then
		return "That tool does not exist."
	end
	if selfOnly and (id == "paidgive" or id == "paidlist") and req.target ~= selfName then
		return "Your Gifts power only gives to you. Pick yourself."
	end
	return Hub.Check(req, selfName)
end

---------------------------------------------------------------------------
-- The player list: filter, recents first
---------------------------------------------------------------------------

Hub.RecentPlayerCap = 4

-- Adds a name to the recents (newest first, once each, capped).
function Hub.PushName(list: { string }, name: string): { string }
	local out: { string } = { name }
	for _, other in ipairs(list) do
		if other ~= name and #out < Hub.RecentPlayerCap then
			table.insert(out, other)
		end
	end
	return out
end

local function words(query: unknown): { string }
	local out: { string } = {}
	if type(query) == "string" then
		for w in string.gmatch(string.lower(query), "%S+") do
			table.insert(out, w)
		end
	end
	return out
end

local function matchesAll(hay: string, ws: { string }): boolean
	local lower = string.lower(hay)
	for _, w in ipairs(ws) do
		if not string.find(lower, w, 1, true) then
			return false
		end
	end
	return true
end

export type PlayerRow = { name: string, recent: boolean }

-- Who the list shows: recents (still online, not you) first, then everyone
-- else, you first among them (SortNames). `query` filters by name. With a
-- query the recents are not set apart: a search is one flat list.
function Hub.PlayerList(names: { string }, selfName: string, recents: { string }, query: unknown): { PlayerRow }
	local sorted = Hub.SortNames(names, selfName)
	local ws = words(query)
	local out: { PlayerRow } = {}
	local used: { [string]: boolean } = {}
	if #ws == 0 then
		for _, name in ipairs(recents) do
			if table.find(sorted, name) and name ~= selfName and not used[name] then
				used[name] = true
				table.insert(out, { name = name, recent = true })
			end
		end
	end
	for _, name in ipairs(sorted) do
		if not used[name] and matchesAll(name, ws) then
			table.insert(out, { name = name, recent = false })
		end
	end
	return out
end

-- Any list of lines (the chat commands) narrowed by every typed word.
function Hub.FilterLines(lines: { string }, query: unknown): { string }
	local ws = words(query)
	local out: { string } = {}
	for _, line in ipairs(lines) do
		if matchesAll(line, ws) then
			table.insert(out, line)
		end
	end
	return out
end

-- `list` with the recents moved to the front (their own order), the rest
-- after, none twice. Returns the new list and how many are recents.
function Hub.RecentsFirst(list: { Item }, recents: { Item }): ({ Item }, number)
	local out: { Item } = {}
	local used: { [string]: boolean } = {}
	for _, r in ipairs(recents) do
		for _, item in ipairs(list) do
			if item.kind == r.kind and item.id == r.id and not used[key(item)] then
				used[key(item)] = true
				table.insert(out, item)
			end
		end
	end
	local n = #out
	for _, item in ipairs(list) do
		if not used[key(item)] then
			table.insert(out, item)
		end
	end
	return out, n
end

---------------------------------------------------------------------------
-- Paid items: the hub's list, recents, and what the server says they own
---------------------------------------------------------------------------

Hub.PaidRecentCap = 4

function Hub.PushPaidRecent(list: { string }, id: string): { string }
	local out: { string } = { id }
	for _, other in ipairs(list) do
		if other ~= id and #out < Hub.PaidRecentCap then
			table.insert(out, other)
		end
	end
	return out
end

-- The paid items to list: filtered by the typed words, with the recents
-- (only when nothing is typed) first. Returns (items, how many are recents).
function Hub.PaidList(all: { PaidItems.Item }, query: unknown, recents: { string }): ({ PaidItems.Item }, number)
	local found = PaidItems.Filter(all, query)
	local ws = words(query)
	if #ws > 0 then
		return found, 0
	end
	local out: { PaidItems.Item } = {}
	local used: { [string]: boolean } = {}
	for _, id in ipairs(recents) do
		for _, item in ipairs(found) do
			if item.id == id and not used[id] then
				used[id] = true
				table.insert(out, item)
			end
		end
	end
	local n = #out
	for _, item in ipairs(found) do
		if not used[item.id] then
			table.insert(out, item)
		end
	end
	return out, n
end

-- What the server sent for one item (a row of the paidstate payload) as a
-- PaidItems.State, or nil when it has not arrived yet.
function Hub.PaidState(row: unknown): PaidItems.State?
	if type(row) ~= "table" then
		return nil
	end
	local r = row :: { [string]: any }
	return {
		owned = r.owned == true,
		bought = r.bought == true,
		granted = r.granted == true,
		count = if type(r.count) == "number" then r.count else 0,
		untilAt = 0,
		label = if type(r.label) == "string" then r.label else "",
	}
end

-- Why GIVE or REVOKE is off for this item and what they own, or nil when it
-- may go. `row` is what the server sent (nil while it is still coming).
-- `isRevoke` picks the action; `selfOnly` is a delegate's Gifts power.
function Hub.PaidDisabled(
	item: PaidItems.Item,
	row: unknown,
	who: string?,
	selfName: string,
	isRevoke: boolean,
	selfOnly: boolean?
): string?
	if who == nil or who == "" then
		return "Pick a player first."
	end
	if selfOnly and not isRevoke and who ~= selfName then
		return "Your Gifts power only gives to you. Pick yourself."
	end
	local st = Hub.PaidState(row)
	if not st then
		return "Loading what " .. who .. " owns..."
	end
	local ok, why
	if isRevoke then
		ok, why = PaidItems.CanRevoke(item, st)
	else
		ok, why = PaidItems.CanGrant(item, st, nil)
	end
	if ok then
		return nil
	end
	return why
end

---------------------------------------------------------------------------
-- Pad navigation and scrolling
---------------------------------------------------------------------------

export type Nav = { up: string?, down: string?, left: string?, right: string? }

local function across(row: { string }?, x: number): string?
	if row == nil or #row == 0 then
		return nil
	end
	return row[math.clamp(math.ceil(x * #row), 1, #row)]
end

-- rows: the focusable ids, top to bottom, left to right. Left and right stay
-- in the row; up and down land on the nearest column of the next row that
-- has anything (no wrap, so a held stick stops at the ends).
function Hub.NavGrid(rows: { { string } }): { [string]: Nav }
	local out: { [string]: Nav } = {}
	for r, row in ipairs(rows) do
		for c, id in ipairs(row) do
			local x = (c - 0.5) / #row
			local up: string? = nil
			for i = r - 1, 1, -1 do
				if #rows[i] > 0 then
					up = across(rows[i], x)
					break
				end
			end
			local down: string? = nil
			for i = r + 1, #rows do
				if #rows[i] > 0 then
					down = across(rows[i], x)
					break
				end
			end
			out[id] = { up = up, down = down, left = row[c - 1], right = row[c + 1] }
		end
	end
	return out
end

-- Where to scroll (canvas Y) so an item at `top` (canvas Y) and `height` is in
-- view with `margin` to spare. Unchanged when it already is.
function Hub.ScrollTarget(
	canvasY: number,
	viewH: number,
	top: number,
	height: number,
	margin: number,
	canvasH: number?
): number
	local target = canvasY
	if top - margin < canvasY then
		target = top - margin
	elseif top + height + margin > canvasY + viewH then
		target = top + height + margin - viewH
	end
	local maxY = if canvasH then math.max(0, canvasH - viewH) else math.huge
	return math.clamp(target, 0, maxY)
end

return Hub
