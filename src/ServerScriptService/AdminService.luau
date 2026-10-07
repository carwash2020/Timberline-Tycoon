--!strict
-- AdminService: the owner's chat commands (AdminLogic.Help). Server only,
-- locked to the owner: every command runs through `run`, which reads the
-- speaker's UserId off the chat source (not from anything a client sends)
-- and asks AdminLogic.IsOwner first. Anyone else gets no reply at all, and
-- the attempt is logged. Cash goes through EconomyService, items through
-- ShopService.ChargeAndGrant with `free` (only this file sets it), kicks and
-- bans through Players. Nothing here is reachable from a remote.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local AdminLogic = require(ReplicatedStorage.Shared.AdminLogic)
local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)
local ShopService = require(script.Parent.ShopService)
local BlueprintBook = require(ReplicatedStorage.Shared.BlueprintBook)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local PaidItems = require(ReplicatedStorage.Shared.PaidItems)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local Util = require(ReplicatedStorage.Shared.Util)
local WorldTime = require(ReplicatedStorage.Shared.WorldTime)

local AdminService = {}

local deliver: (Player, string) -> () = function(_player: Player, _message: string) end
-- Where the menu's result line goes (GameServer wires the AdminResult remote).
local reply: (Player, boolean, string) -> () = function(_player: Player, _ok: boolean, _text: string) end

-- Services that GameServer wires in (no require cycle).
export type Hooks = {
	resetTutorial: ((Player) -> ())?,
	publishBlueprints: ((Player) -> ())?,
	placeSample: ((Player, string) -> (boolean, string))?, -- PlotService.PlaceSample
	clearSamples: ((Player) -> number)?, -- PlotService.ClearSamples
	-- The paid-item hooks (MonetizationService.OwnerGrant, OwnerRevoke, OwnerState).
	paidGrant: ((Player, string, { userId: number, name: string }, number?) -> (boolean, string))?,
	paidRevoke: ((Player, string, { userId: number, name: string }) -> (boolean, string))?,
	paidState: ((Player) -> { [string]: any })?,
}
local hooks: Hooks = {}

-- While a menu request runs, what the owner would be told is collected for
-- the result line instead of a toast, and `failed` says whether it refused.
local capture: { player: Player, lines: { string }, failed: boolean }? = nil

local function notify(player: Player, message: string)
	local c = capture
	if c and c.player == player then
		table.insert(c.lines, message)
	else
		deliver(player, message)
	end
end

-- A refusal: the same as notify, and the menu's result turns red.
local function refuse(player: Player, message: string)
	if capture and capture.player == player then
		capture.failed = true
	end
	notify(player, message)
end

-- The experience's creator: ("User" or "Group", id). Replaceable for tests.
function AdminService.Creator(): (string, number)
	local creatorType = game.CreatorType
	return if creatorType then creatorType.Name else "", game.CreatorId
end

-- Who is the owner: this speaker, this server.
function AdminService.IsOwner(userId: number): boolean
	local typeName, creatorId = AdminService.Creator()
	return AdminLogic.IsOwner(userId, typeName, creatorId, RunService:IsStudio(), AdminLogic.OwnerUserIds)
end

-- For tests: where toasts go.
function AdminService.SetNotify(fn: (Player, string) -> ())
	deliver = fn
end

-- Where the owner menu's result line goes: (owner, ok, text).
function AdminService.SetReply(fn: (Player, boolean, string) -> ())
	reply = fn
end

function AdminService.SetHooks(newHooks: Hooks)
	hooks = newHooks
end

local function names(): { string }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		table.insert(out, p.Name)
	end
	return out
end

-- The online player the owner named, or nil after telling the owner why.
local function target(owner: Player, query: string?): Player?
	local name, why = AdminLogic.MatchName(query, names())
	if not name then
		refuse(owner, if why == "many" then "More than one player starts with that." else "No player by that name.")
		return nil
	end
	return Players:FindFirstChild(name) :: Player?
end

-- Another owner (never kicked or banned). In Studio everyone counts as the
-- owner, so only the speaker themself is protected there.
local function isOtherOwner(who: Player): boolean
	return not RunService:IsStudio() and AdminService.IsOwner(who.UserId)
end

---------------------------------------------------------------------------
-- Delegation. The table lives in server memory only (nothing is saved: a
-- grant ends when the server closes). Only an owner can change it, and the
-- role of whoever speaks is always worked out here from this table and
-- AdminLogic.IsOwner, never from anything a client sent or an attribute.
---------------------------------------------------------------------------

type Grant = {
	role: string,
	powers: { string },
	grantedBy: number,
	grantedByName: string,
	expiresAt: number?,
	session: boolean,
	name: string,
}

local delegates: { [number]: Grant } = {}
local clock: () -> number = os.time
local throttleGap = 0.75 -- seconds between a delegate's requests (the owner has the remote's own limit)
local lastDelegateAt: { [number]: number } = {}
local accessSend: (Player, { [string]: any }) -> () = function(_player: Player, _payload: { [string]: any }) end
-- Who is running the command right now (set by Run around the handler).
local actor: { role: string, grant: Grant?, command: string? } = { role = "owner", grant = nil, command = nil }
-- True only while a hub request that carried "I pressed twice" runs.
local confirmedFlag = false

-- Commands whose first word is a player: a delegate may never aim them at an owner.
local aimsAtPlayer: { [string]: boolean } = {
	kick = true,
	ban = true,
	["goto"] = true,
	bring = true,
	heal = true,
	freeze = true,
	stats = true,
	resettutorial = true,
	unlockbp = true,
	give = true,
	take = true,
	setcash = true,
	gift = true,
	paidgive = true,
	paidrevoke = true,
	paidlist = true,
}

function AdminService.SetClock(fn: () -> number)
	clock = fn
end

function AdminService.SetThrottle(seconds: number)
	throttleGap = seconds
end

-- Where AdminAccess payloads go (GameServer wires the remote).
function AdminService.SetAccessSend(fn: (Player, { [string]: any }) -> ())
	accessSend = fn
end

-- A copy of the grants, for tests.
function AdminService.Delegates(): { [number]: Grant }
	return table.clone(delegates)
end

-- The real owner: the listed ids or the creator, never "Studio".
local function strictOwner(userId: number): boolean
	local typeName, creatorId = AdminService.Creator()
	return AdminLogic.IsOwner(userId, typeName, creatorId, false, AdminLogic.OwnerUserIds)
end

local revoke: (number, string) -> ()

local function activeGrant(userId: number): Grant?
	local g = delegates[userId]
	if g and AdminLogic.Expired(g, clock()) then
		revoke(userId, "expired")
		return nil
	end
	return g
end

-- ("owner" | "delegate" | nil, grant). A grant wins over Studio's "everyone is
-- the owner", so a Test client with a grant has exactly the grant.
function AdminService.RoleOf(userId: number): (string?, Grant?)
	if strictOwner(userId) then
		return "owner", nil
	end
	local g = activeGrant(userId)
	if g then
		return "delegate", g
	end
	if AdminService.IsOwner(userId) then
		return "owner", nil
	end
	return nil, nil
end

local function eachOwner(fn: (Player) -> ())
	for _, p in ipairs(Players:GetPlayers()) do
		if AdminService.RoleOf(p.UserId) == "owner" then
			fn(p)
		end
	end
end

local function delegateRows(): { { [string]: any } }
	local rows: { { [string]: any } } = {}
	for userId, g in pairs(delegates) do
		table.insert(rows, {
			userId = userId,
			name = g.name,
			role = g.role,
			powers = g.powers,
			session = g.session,
			secondsLeft = if g.expiresAt then math.max(0, g.expiresAt - clock()) else nil,
		})
	end
	table.sort(rows, function(a, b)
		return a.name < b.name
	end)
	return rows
end

-- Tells each owner's hub the current delegates.
local function sendOwners()
	eachOwner(function(p)
		accessSend(p, { kind = "access", role = "owner", label = "OWNER", delegates = delegateRows() })
	end)
end

-- What a player's hub may show: everything for an owner, the grant's tools for
-- a delegate, nothing otherwise. The client builds its menu from this; the
-- server still re-checks every request against the table above.
local function sendAccess(p: Player)
	local role, g = AdminService.RoleOf(p.UserId)
	if role == "owner" then
		accessSend(p, { kind = "access", role = "owner", label = "OWNER", delegates = delegateRows() })
	elseif role == "delegate" and g then
		g.name = p.Name
		p:SetAttribute("IsOwner", nil)
		accessSend(p, {
			kind = "access",
			role = "delegate",
			label = if g.role == "TESTER" then "TESTER (full power)" else "DELEGATE",
			grantRole = g.role,
			tester = g.role == "TESTER",
			actions = AdminLogic.AllowedActions(g),
			secondsLeft = if g.expiresAt then math.max(0, g.expiresAt - clock()) else nil,
			grantedBy = g.grantedByName,
		})
	end
end

revoke = function(userId: number, why: string)
	local g = delegates[userId]
	if not g then
		return
	end
	delegates[userId] = nil
	lastDelegateAt[userId] = nil
	print(string.format("[Admin] delegate %s (%d) %s role %s ended: %s", g.name, userId, "of", g.role, why))
	local p = Players:GetPlayerByUserId(userId)
	if p then
		p:SetAttribute("SuperRun", nil)
		local char = p.Character
		local ff = if char then char:FindFirstChild("OwnerGod") else nil
		if ff then
			ff:Destroy()
		end
		accessSend(p, { kind = "revoked", reason = why })
		deliver(p, "Your owner powers have ended.")
		AdminService.Mark(p)
	end
	sendOwners()
end

-- Ends grants that have run out (the server also sweeps on a timer).
function AdminService.Sweep()
	for userId, g in pairs(table.clone(delegates)) do
		if AdminLogic.Expired(g, clock()) then
			revoke(userId, "expired")
		end
	end
end

local function log(owner: Player, line: string)
	local g = actor.grant
	if actor.role == "delegate" and g then
		local text = string.format("%s (%s, by %s): %s", owner.Name, g.role, g.grantedByName, line)
		print(
			string.format(
				"[Admin] DELEGATE %s (%d) role %s granted by %s (%d): %s",
				owner.Name,
				owner.UserId,
				g.role,
				g.grantedByName,
				g.grantedBy,
				line
			)
		)
		eachOwner(function(o)
			accessSend(o, { kind = "audit", text = text })
			-- A TESTER's destructive action is shown on the owner's screen too.
			if g.role == "TESTER" and AdminLogic.IsDestructive(actor.command) then
				deliver(o, "TESTER " .. text)
			end
		end)
		return
	end
	print(string.format("[Admin] %s (%d): %s", owner.Name, owner.UserId, line))
end

local handlers: { [string]: (owner: Player, args: { string }, rest: string) -> () } = {}

handlers.give = function(owner, args)
	local who, amount = target(owner, args[1]), AdminLogic.Amount(args[2])
	if not who or not amount then
		if who then
			refuse(owner, "Amount must be a whole number, 1 to " .. Util.formatCash(AdminLogic.MaxAmount) .. ".")
		end
		return
	end
	local credited = EconomyService.AddCash(who, amount, "owner gift", "OwnerGift")
	log(owner, string.format("gave %s %d", who.Name, credited))
	notify(owner, string.format("Gave %s %s.", who.Name, Util.formatCash(credited)))
	if who ~= owner then
		notify(who, string.format("The owner gave you %s.", Util.formatCash(credited)))
	end
end

handlers.take = function(owner, args)
	local who, amount = target(owner, args[1]), AdminLogic.Amount(args[2])
	if not who or not amount then
		if who then
			refuse(owner, "Amount must be a whole number, 1 to " .. Util.formatCash(AdminLogic.MaxAmount) .. ".")
		end
		return
	end
	local have = EconomyService.GetCash(who)
	local took = math.min(have, amount)
	if took > 0 and EconomyService.SpendCash(who, took, "owner took", "OwnerTake") then
		log(owner, string.format("took %d from %s", took, who.Name))
		notify(owner, string.format("Took %s from %s.", Util.formatCash(took), who.Name))
		notify(who, string.format("The owner took %s.", Util.formatCash(took)))
	else
		refuse(owner, who.Name .. " has no cash to take.")
	end
end

handlers.setcash = function(owner, args)
	local who = target(owner, args[1])
	local text = args[2]
	local amount = if text == "0" then 0 else AdminLogic.Amount(text)
	if not who or not amount then
		if who then
			refuse(owner, "Amount must be a whole number from 0.")
		end
		return
	end
	EconomyService.ReplaceCash(who, amount, "owner set")
	log(owner, string.format("set %s to %d", who.Name, amount))
	notify(owner, string.format("%s now has %s.", who.Name, Util.formatCash(amount)))
	if who ~= owner then
		notify(who, string.format("The owner set your cash to %s.", Util.formatCash(amount)))
	end
end

-- An item's own name ("Steel Axe") for the toast, else its id.
local function giftName(kind: string, itemId: string): string
	local def: any = nil
	if kind == "Axe" then
		def = ItemCatalog.GetAxe(itemId)
	elseif kind == "Gear" then
		def = ItemCatalog.GetGear(itemId)
	elseif kind == "Sawmill" then
		def = ItemCatalog.GetSawmill(itemId)
	elseif kind == "Machine" then
		def = ItemCatalog.GetMachine(itemId)
	elseif kind == "Blueprint" then
		for _, bp in ipairs(PlotData.Blueprints) do
			if bp.id == itemId then
				def = bp
				break
			end
		end
	end
	return if def and type(def.displayName) == "string" then def.displayName else itemId
end

handlers.gift = function(owner, args)
	local who = target(owner, args[1])
	local kind, itemId = args[2], args[3]
	if not who then
		return
	end
	if not AdminLogic.IsGiftKind(kind) or type(itemId) ~= "string" then
		refuse(owner, "Usage: /gift <player> <Axe|Gear|Sawmill|Machine|Blueprint> <id>")
		return
	end
	local ok, line = ShopService.ChargeAndGrant(who, {
		uid = "admin-" .. HttpService:GenerateGUID(false),
		kind = kind,
		itemId = itemId,
		free = true,
	})
	log(owner, string.format("gift %s %s to %s: %s", kind, itemId, who.Name, line))
	if ok then
		notify(owner, string.format("Gave %s to %s.", giftName(kind, itemId), who.Name))
	else
		refuse(owner, string.format("Couldn't gift %s (%s).", itemId, line))
	end
end

-- Paid items (the hub's Paid items tab, or /paidgive, /paidrevoke, /paidlist).
-- The effects are MonetizationService's (OwnerGrant, OwnerRevoke): the same
-- ones a purchase has, with no Robux. Here: who may ask (AdminLogic.GrantAllows
-- ran in Run; paidrevoke checks the role again), which player, which item.
local function paidItem(owner: Player, word: string?): PaidItems.Item?
	local item = PaidItems.Find(PaidItems.All(), word)
	if not item then
		refuse(owner, "That is not a paid item. /paidlist <player> shows the ids.")
	end
	return item
end

-- Tells `to`'s hub what `who` owns (a payload the hub draws on the Paid items tab).
local function sendPaidState(to: Player, who: Player)
	local fn = hooks.paidState
	if fn then
		accessSend(to, { kind = "paidstate", target = who.Name, rows = fn(who) })
	end
end

handlers.paidgive = function(owner, args)
	local who = target(owner, args[1])
	if not who then
		return
	end
	local item = paidItem(owner, args[2])
	if not item then
		return
	end
	local hours: number? = nil
	if args[3] ~= nil then
		hours = tonumber(args[3])
		if hours == nil or hours ~= hours or hours % 1 ~= 0 or hours < 1 or hours > AdminLogic.MaxPaidHours then
			refuse(owner, "Hours must be a whole number from 1 to " .. AdminLogic.MaxPaidHours .. ".")
			return
		end
	end
	local fn = hooks.paidGrant
	if not fn then
		refuse(owner, "Paid items are not wired on this server.")
		return
	end
	local ok, text = fn(who, item.id, { userId = owner.UserId, name = owner.Name }, hours)
	log(owner, string.format("paidgive %s to %s (%d): %s", item.id, who.Name, who.UserId, text))
	if ok then
		notify(owner, text)
	else
		refuse(owner, text)
	end
	sendPaidState(owner, who)
end

handlers.paidrevoke = function(owner, args)
	if actor.role ~= "owner" then
		refuse(owner, "Only the owner can do that.")
		return
	end
	local who = target(owner, args[1])
	if not who then
		return
	end
	local item = paidItem(owner, args[2])
	if not item then
		return
	end
	local fn = hooks.paidRevoke
	if not fn then
		refuse(owner, "Paid items are not wired on this server.")
		return
	end
	local ok, text = fn(who, item.id, { userId = owner.UserId, name = owner.Name })
	log(owner, string.format("paidrevoke %s from %s (%d): %s", item.id, who.Name, who.UserId, text))
	if ok then
		notify(owner, text)
	else
		refuse(owner, text)
	end
	sendPaidState(owner, who)
end

handlers.paidlist = function(owner, args)
	local who = target(owner, args[1])
	if not who then
		return
	end
	if not hooks.paidState then
		refuse(owner, "Paid items are not wired on this server.")
		return
	end
	sendPaidState(owner, who)
	notify(owner, "Showing what " .. who.Name .. " owns.")
end

handlers.kick = function(owner, args, rest)
	local who = target(owner, args[1])
	if not who then
		return
	end
	if who == owner then
		refuse(owner, "You can't kick yourself.")
		return
	end
	if isOtherOwner(who) then
		refuse(owner, who.Name .. " is an owner: not kicked.")
		return
	end
	local reason = string.sub(string.match(rest, "^%S+%s*(.*)$") or "", 1, 100)
	log(owner, string.format("kicked %s (%s)", who.Name, reason))
	who:Kick(if reason ~= "" then reason else "Removed by the owner.")
	notify(owner, "Kicked " .. who.Name .. ".")
end

handlers.ban = function(owner, args, rest)
	local who = target(owner, args[1])
	local seconds = AdminLogic.BanSeconds(args[2])
	if not who then
		return
	end
	if who == owner then
		refuse(owner, "You can't ban yourself.")
		return
	end
	if isOtherOwner(who) then
		refuse(owner, who.Name .. " is an owner: not banned.")
		return
	end
	if not seconds then
		refuse(owner, "Usage: /ban <player> <hours|perm> [reason]")
		return
	end
	local reason = string.sub(string.match(rest, "^%S+%s+%S+%s*(.*)$") or "", 1, 100)
	local userId = who.UserId
	local ok, err = pcall(function()
		Players:BanAsync({
			UserIds = { userId },
			Duration = seconds,
			DisplayReason = if reason ~= "" then reason else "Banned by the owner.",
			PrivateReason = "Owner ban by " .. tostring(owner.UserId),
			ExcludeAltAccounts = false,
			ApplyToUniverse = true,
		})
	end)
	log(
		owner,
		string.format("ban %s (%d) %s: %s", who.Name, userId, tostring(args[2]), if ok then "ok" else tostring(err))
	)
	if ok then
		notify(owner, "Banned " .. who.Name .. ".")
	else
		refuse(owner, "The ban failed. See Output.")
	end
end

handlers.unban = function(owner, args)
	local userId = tonumber(args[1])
	if userId == nil or userId ~= userId or userId <= 0 or userId % 1 ~= 0 then
		refuse(owner, "Usage: /unban <userId>")
		return
	end
	local ok, err = pcall(function()
		Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
	end)
	log(owner, string.format("unban %d: %s", userId, if ok then "ok" else tostring(err)))
	if ok then
		notify(owner, "Unbanned " .. tostring(userId) .. ".")
	else
		refuse(owner, "The unban failed. See Output.")
	end
end

local function rootOf(player: Player): BasePart?
	local char = player.Character
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

handlers["goto"] = function(owner, args)
	local who = target(owner, args[1])
	local mine, theirs = rootOf(owner), if who then rootOf(who) else nil
	if who and mine and theirs then
		mine.CFrame = theirs.CFrame * CFrame.new(0, 0, 4)
		log(owner, "goto " .. who.Name)
		notify(owner, "Went to " .. who.Name .. ".")
	elseif who then
		refuse(owner, who.Name .. " or you has no character right now.")
	end
end

handlers.bring = function(owner, args)
	local who = target(owner, args[1])
	local mine, theirs = rootOf(owner), if who then rootOf(who) else nil
	if who and mine and theirs then
		theirs.CFrame = mine.CFrame * CFrame.new(0, 0, -4)
		log(owner, "bring " .. who.Name)
		notify(owner, "Brought " .. who.Name .. " to you.")
	elseif who then
		refuse(owner, who.Name .. " or you has no character right now.")
	end
end

-- Toggles the owner's own super run (BiomeService reads the attribute on
-- the server; nothing a client sends can set it).
handlers.superrun = function(owner)
	local on = owner:GetAttribute("SuperRun") ~= true
	owner:SetAttribute("SuperRun", if on then true else nil)
	log(owner, "superrun " .. if on then "on" else "off")
	notify(owner, if on then "Super run on." else "Super run off.")
end

-- Time control. Server memory only: three workspace attributes (see
-- WorldTime). A restarted server has none, so time is real again. Quiet:
-- only the owner is told (the sky changes for everyone, which is the point).
local function writeClock(realNow: number, gameNow: number, speed: number)
	workspace:SetAttribute(WorldTime.AnchorRealAttribute, realNow)
	workspace:SetAttribute(WorldTime.AnchorGameAttribute, gameNow)
	workspace:SetAttribute(WorldTime.SpeedAttribute, speed)
end

handlers.timespeed = function(owner, args)
	local speed = AdminLogic.Speed(args[1])
	if not speed then
		refuse(owner, "Usage: /timespeed <1|4|20|60>")
		return
	end
	-- Re-anchor at "now" so the sky carries on from where it is, then change pace.
	local real = workspace:GetServerTimeNow()
	writeClock(real, WorldTime.GameNow(), speed)
	log(owner, string.format("timespeed %dx", speed))
	notify(owner, string.format("Time runs at %dx on this server (until it restarts).", speed))
end

handlers.settime = function(owner, _args, rest)
	local hour = AdminLogic.TimeOfDay(rest)
	if hour == nil then
		refuse(owner, "Usage: /settime <6am|noon|6pm|midnight|7:30pm|18:30>")
		return
	end
	local real = workspace:GetServerTimeNow()
	local speed = workspace:GetAttribute(WorldTime.SpeedAttribute)
	writeClock(
		real,
		WorldTime.GameTimeForHour(WorldTime.GameNow(), hour),
		if WorldTime.IsSpeed(speed) then speed else 1
	)
	log(owner, "settime " .. WorldTime.Format(hour))
	notify(owner, "It is now " .. WorldTime.Format(hour) .. ".")
end

handlers.timereset = function(owner)
	workspace:SetAttribute(WorldTime.AnchorRealAttribute, nil)
	workspace:SetAttribute(WorldTime.AnchorGameAttribute, nil)
	workspace:SetAttribute(WorldTime.SpeedAttribute, nil)
	log(owner, "timereset")
	notify(owner, "Time is back to normal.")
end

-- God mode (a ForceField on the owner's own character, toggled).
handlers.god = function(owner)
	local char = owner.Character
	if not char then
		refuse(owner, "You have no character right now.")
		return
	end
	local existing = char:FindFirstChild("OwnerGod")
	if existing then
		existing:Destroy()
		log(owner, "god off")
		notify(owner, "God mode off.")
	else
		local ff = Instance.new("ForceField")
		ff.Name = "OwnerGod"
		ff.Visible = false
		ff.Parent = char
		log(owner, "god on")
		notify(owner, "God mode on: no damage.")
	end
end

handlers.heal = function(owner, args)
	local who = target(owner, args[1])
	if not who then
		return
	end
	local hum = if who.Character then who.Character:FindFirstChildOfClass("Humanoid") else nil
	if not hum then
		refuse(owner, who.Name .. " has no character right now.")
		return
	end
	hum.Health = hum.MaxHealth
	log(owner, "heal " .. who.Name)
	notify(owner, "Healed " .. who.Name .. ".")
end

handlers.tospawn = function(owner)
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local mine = rootOf(owner)
	if not spawn or not mine then
		refuse(owner, "No spawn point found.")
		return
	end
	mine.CFrame = spawn.CFrame * CFrame.new(0, 5, 0)
	log(owner, "tospawn")
	notify(owner, "Back at spawn.")
end

-- Freeze / unfreeze (anchors their root; toggles; never the owner).
handlers.freeze = function(owner, args)
	local who = target(owner, args[1])
	if not who then
		return
	end
	if who == owner then
		refuse(owner, "You can't freeze yourself.")
		return
	end
	local root = rootOf(who)
	if not root then
		refuse(owner, who.Name .. " has no character right now.")
		return
	end
	local on = who:GetAttribute("OwnerFrozen") ~= true
	who:SetAttribute("OwnerFrozen", if on then true else nil)
	root.Anchored = on
	log(owner, string.format("%s %s", if on then "froze" else "unfroze", who.Name))
	notify(owner, string.format("%s %s.", if on then "Froze" else "Unfroze", who.Name))
end

-- Read-only: what a player has, as one line for the result panel.
handlers.stats = function(owner, args)
	local who = target(owner, args[1])
	if not who then
		return
	end
	local profile = ProfileService.GetProfile(who)
	if not profile then
		refuse(owner, who.Name .. " has no loaded save.")
		return
	end
	local plot = profile.plot
	local text = string.format(
		"%s: %s cash | plot %s, tier %d, %d squares, %d placed | tutorial %s | %d axes, %d blueprints",
		who.Name,
		Util.formatCash(EconomyService.GetCash(who)),
		if plot.claimed then "owned" else "none",
		plot.tier,
		#plot.squares,
		#plot.placed,
		if profile.tutorialDone then "done" else "step " .. tostring(profile.tutorialStep),
		#profile.axes,
		#(profile.blueprintBook or {})
	)
	log(owner, "stats " .. who.Name)
	notify(owner, text)
end

handlers.resettutorial = function(owner, args)
	local who = target(owner, args[1])
	if not who then
		return
	end
	local fn = hooks.resetTutorial
	if not fn then
		refuse(owner, "Tutorial reset is not wired on this server.")
		return
	end
	fn(who)
	log(owner, "resettutorial " .. who.Name)
	notify(owner, "Reset the tutorial for " .. who.Name .. ".")
end

-- Every building plan in their blueprint book (BlueprintBook.Learn is the rule).
handlers.unlockbp = function(owner, args)
	local who = target(owner, args[1])
	if not who then
		return
	end
	local profile = ProfileService.GetProfile(who)
	if not profile then
		refuse(owner, who.Name .. " has no loaded save.")
		return
	end
	if type(profile.blueprintBook) ~= "table" then
		profile.blueprintBook = {}
	end
	local added = 0
	for _, bp in ipairs(PlotData.Blueprints) do
		if BlueprintBook.Learn(profile.blueprintBook, bp.id) then
			added += 1
		end
	end
	if hooks.publishBlueprints then
		hooks.publishBlueprints(who)
	end
	log(owner, string.format("unlockbp %s (+%d)", who.Name, added))
	notify(owner, string.format("%s now knows every building (%d new).", who.Name, added))
end

-- A free test building on the owner's own plot, at the spot they face
-- (SampleBuilds). Only the owner: AdminLogic.NeverDelegable keeps every
-- delegate role (TESTER too) out before this runs, and this checks the
-- speaker's role again. `/sample clear` takes every sample piece down.
handlers.sample = function(owner, args)
	if actor.role ~= "owner" then
		refuse(owner, "Only the owner can do that.")
		return
	end
	local place, clear = hooks.placeSample, hooks.clearSamples
	if not place or not clear then
		refuse(owner, "Samples aren't available here.")
		return
	end
	local name = args[1]
	if name == nil then
		notify(owner, "Usage: /sample <modern|shop|barn>, or /sample clear")
		return
	end
	if string.lower(name) == "clear" then
		local n = clear(owner)
		log(owner, string.format("sample clear (%d)", n))
		notify(
			owner,
			if n > 0 then string.format("Took down %d sample pieces.", n) else "No sample pieces on your plot."
		)
		return
	end
	local ok, text = place(owner, name)
	log(owner, string.format("sample %s: %s", name, if ok then "placed" else text))
	if ok then
		notify(owner, text)
	else
		refuse(owner, text)
	end
end

-- Kicks everyone (the owner too): the server is gone once the last leaves.
handlers.shutdown = function(owner)
	log(owner, "shutdown")
	for _, p in ipairs(Players:GetPlayers()) do
		p:Kick("The server is shutting down.")
	end
end

handlers.announce = function(owner, _args, rest)
	local text = string.sub(rest, 1, 120)
	if text == "" then
		refuse(owner, "Usage: /announce <text>")
		return
	end
	log(owner, "announce: " .. text)
	for _, p in ipairs(Players:GetPlayers()) do
		notify(p, "Owner: " .. text)
	end
end

-- Delegation commands: the owner only (Run already refuses delegates, and
-- each handler checks the role again).
local function aimedUserId(owner: Player, word: string?): (number?, Player?)
	if word and string.match(word, "^%d+$") then
		local id = tonumber(word) :: number
		return id, Players:GetPlayerByUserId(id)
	end
	local who = target(owner, word)
	return if who then who.UserId else nil, who
end

handlers.delegate = function(owner, args)
	if actor.role ~= "owner" then
		refuse(owner, "Only the owner can do that.")
		return
	end
	local parsed, why = AdminLogic.ParseDelegate(args)
	if not parsed then
		refuse(owner, why or "Usage: /delegate <player|userId> <role>")
		return
	end
	local userId, who = aimedUserId(owner, parsed.target)
	if not userId or userId <= 0 or userId % 1 ~= 0 then
		return
	end
	if userId == owner.UserId or strictOwner(userId) then
		refuse(owner, "The owner can't be a delegate.")
		return
	end
	if parsed.expiry == "session" and not who then
		refuse(owner, "A session grant needs that player to be in this server.")
		return
	end
	if parsed.role == "TESTER" and not parsed.confirmed then
		refuse(owner, AdminLogic.TesterWarning .. " Press again to confirm.")
		return
	end
	local powers = AdminLogic.PowersOf(parsed.role, parsed.powers)
	if not powers then
		refuse(owner, "That role has no powers.")
		return
	end
	local seconds = AdminLogic.ExpirySeconds(parsed.expiry)
	local name = if who then who.Name else tostring(userId)
	delegates[userId] = {
		role = parsed.role,
		powers = powers,
		grantedBy = owner.UserId,
		grantedByName = owner.Name,
		expiresAt = if seconds then clock() + seconds else nil,
		session = parsed.expiry == "session",
		name = name,
	}
	log(owner, string.format("delegate %s (%d) %s until %s", name, userId, parsed.role, parsed.expiry))
	notify(owner, string.format("%s is now a %s (%s).", name, parsed.role, parsed.expiry))
	if who then
		deliver(who, string.format("The owner made you a %s. Open the DELEGATE button.", parsed.role))
		sendAccess(who)
	end
	sendOwners()
end

handlers.undelegate = function(owner, args)
	if actor.role ~= "owner" then
		refuse(owner, "Only the owner can do that.")
		return
	end
	local userId = aimedUserId(owner, args[1])
	if not userId then
		return
	end
	if delegates[userId] == nil then
		refuse(owner, "That player is not a delegate.")
		return
	end
	local name = delegates[userId].name
	revoke(userId, "revoked by the owner")
	log(owner, string.format("undelegate %s (%d)", name, userId))
	notify(owner, name .. " is no longer a delegate.")
end

handlers.delegates = function(owner)
	if actor.role ~= "owner" then
		refuse(owner, "Only the owner can do that.")
		return
	end
	local parts: { string } = {}
	for _, row in ipairs(delegateRows()) do
		local left = if row.secondsLeft
			then string.format("%d min", math.ceil(row.secondsLeft / 60))
			elseif row.session then "session"
			else "until the server closes"
		table.insert(parts, string.format("%s: %s (%s)", row.name, row.role, left))
	end
	sendOwners()
	notify(owner, if #parts == 0 then "No delegates." else "Delegates: " .. table.concat(parts, ", "))
end

handlers.admin = function(owner)
	for _, line in ipairs(AdminLogic.Help) do
		notify(owner, line)
	end
end

-- Runs one chat line from `userId`. Anyone but the owner: nothing happens
-- beyond a log line. Returns whether a command ran (for tests).
function AdminService.Run(userId: number, text: string): boolean
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		return false
	end
	local command = AdminLogic.Parse(text)
	if not command or handlers[command.name] == nil then
		return false
	end
	local role, grant = AdminService.RoleOf(userId)
	if not role then
		warn(string.format("[Admin] refused /%s from %s (%d): not the owner", command.name, player.Name, userId))
		return false
	end
	if role == "delegate" and grant then
		-- A delegate: slower, only what the grant holds, never aimed at an owner.
		local t = os.clock()
		local last = lastDelegateAt[userId]
		if last and t - last < throttleGap then
			refuse(player, "Slow down a little.")
			return false
		end
		lastDelegateAt[userId] = t
		local matched = AdminLogic.MatchName(command.args[1], names())
		local ctx: AdminLogic.Ctx = { selfTarget = matched == player.Name }
		if command.name == "ban" then
			local seconds = AdminLogic.BanSeconds(command.args[2])
			ctx.banHours = if seconds and seconds > 0 then seconds / 3600 else nil
		end
		local allowed, why = AdminLogic.GrantAllows(grant, command.name, ctx)
		if not allowed then
			warn(
				string.format(
					"[Admin] delegate %s (%d) refused /%s: %s",
					player.Name,
					userId,
					command.name,
					tostring(why)
				)
			)
			refuse(player, why or "You can't do that.")
			return false
		end
		if aimsAtPlayer[command.name] and matched then
			local who = Players:FindFirstChild(matched)
			if who and strictOwner((who :: Player).UserId) then
				refuse(player, "You can't use that on the owner.")
				return false
			end
		end
		if grant.role == "TESTER" and AdminLogic.IsDestructive(command.name) and not confirmedFlag then
			refuse(player, "TESTER: confirm this in the hub first (it asks twice).")
			return false
		end
	end
	if ProfileService.GetProfile(player) == nil then
		return false
	end
	local previous = actor
	actor = { role = role, grant = grant, command = command.name }
	local ok, err = pcall(function(): string?
		handlers[command.name](player, command.args, command.rest)
		return nil
	end)
	actor = previous
	if not ok then
		error(err, 0)
	end
	return true
end

-- The owner menu's request (a table from a client, any type). Only the
-- owner gets anything: the speaker's UserId is the remote's own `player`,
-- checked before the request is even read.
function AdminService.RunRequest(player: Player, request: unknown): boolean
	if AdminService.RoleOf(player.UserId) == nil then
		warn(string.format("[Admin] refused a menu request from %s (%d): not the owner", player.Name, player.UserId))
		return false
	end
	local line = AdminLogic.FromRequest(request)
	if not line then
		reply(player, false, "That request is not allowed.")
		return false
	end
	local c = { player = player, lines = {}, failed = false }
	capture = c
	-- "I pressed twice": only ever adds a prompt for a TESTER, never a permission.
	confirmedFlag = type(request) == "table" and (request :: any).confirmed == true
	local ok, ran = pcall(AdminService.Run, player.UserId, line)
	confirmedFlag = false
	capture = nil
	if not ok then
		warn("[Admin] request failed: " .. tostring(ran))
		reply(player, false, "That failed on the server. See Output.")
		return false
	end
	local text = table.concat(c.lines, " ")
	if text == "" then
		text = if ran then "Done." else "Nothing happened."
	end
	reply(player, ran == true and not c.failed, text)
	return ran == true
end

-- Tells the owner's own client to show the menu button. Only a convenience:
-- the server checks the owner again on every request.
function AdminService.Mark(player: Player)
	if AdminService.RoleOf(player.UserId) == "owner" then
		player:SetAttribute("IsOwner", true)
	end
end

-- A session grant ends when its player leaves.
function AdminService.PlayerLeft(player: Player)
	local g = delegates[player.UserId]
	if g and g.session then
		revoke(player.UserId, "left the server")
	end
end

function AdminService.Init(notifyFn: (Player, string) -> ())
	deliver = notifyFn
	local function joined(player: Player)
		AdminService.Mark(player)
		sendAccess(player)
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in ipairs(Players:GetPlayers()) do
		joined(player)
	end
	Players.PlayerRemoving:Connect(AdminService.PlayerLeft)
	task.spawn(function()
		while true do
			task.wait(15)
			AdminService.Sweep()
		end
	end)
	for name in pairs(handlers) do
		local command = Instance.new("TextChatCommand")
		command.Name = "Admin_" .. name
		command.PrimaryAlias = "/" .. name
		command.Triggered:Connect(function(source: TextSource, message: string)
			AdminService.Run(source.UserId, message)
		end)
		command.Parent = TextChatService
	end
end

return AdminService
