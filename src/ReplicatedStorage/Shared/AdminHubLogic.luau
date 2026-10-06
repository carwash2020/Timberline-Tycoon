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
}

---------------------------------------------------------------------------
-- Tabs and tools
---------------------------------------------------------------------------

export type Tab = { id: string, label: string, hint: string }

Hub.Tabs = {
	{
		id = "players",
		label = "PLAYERS",
		hint = "Pick a player, then go to them, bring them, heal, freeze, kick or ban.",
	},
	{ id = "give", label = "GIVE", hint = "Cash and free items for the player you picked." },
	{ id = "world", label = "WORLD", hint = "The clock, announcements and the server." },
	{ id = "self", label = "SELF", hint = "Things that only change you." },
	{ id = "delegates", label = "DELEGATES", hint = "Give other people some powers, and take them back." },
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
		"Start their tutorial over.",
		"bark",
		false,
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
		"give",
		"GIVE CASH",
		"Add the amount to their wallet (the wallet cap still applies).",
		"buy",
		false,
		"money add",
		true
	),
	tool(
		"take",
		"give",
		"TAKE CASH",
		"Remove the amount, never more than they have.",
		"skip",
		true,
		"money remove",
		true
	),
	tool(
		"setcash",
		"give",
		"SET CASH",
		"Replace their wallet with exactly the amount.",
		"skip",
		true,
		"money exact",
		true
	),
	tool(
		"unlockbp",
		"give",
		"UNLOCK ALL BUILDINGS",
		"Teach them every building plan for good.",
		"bark",
		false,
		"blueprints plans",
		true
	),
	tool(
		"gift",
		"give",
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
		"delegates",
		"GRANT",
		"Give the picked player the role for the time you chose. Only you can do this.",
		"buy",
		false,
		"role helper moderator builder tester custom",
		true
	),
	tool(
		"undelegate",
		"delegates",
		"REVOKE",
		"Take every power back from the picked player at once.",
		"skip",
		false,
		"remove role",
		true
	),
	tool(
		"delegates",
		"delegates",
		"LIST DELEGATES",
		"Show who has powers and how long they last.",
		"blue",
		false,
		"roles",
		false
	),
	tool("superrun", "self", "SUPER RUN", "Toggle 4x walk speed for you.", "buy", false, "speed fast", false),
	tool("god", "self", "GOD MODE", "Toggle no damage for you.", "bark", false, "invincible health", false),
	tool("tospawn", "self", "GO TO SPAWN", "Teleport you to the spawn point.", "bark", false, "teleport home", false),
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
	settime = "Set the hour",
	timespeed = "Clock speed",
	timereset = "Reset time",
	tospawn = "Go to spawn",
	god = "God mode",
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
