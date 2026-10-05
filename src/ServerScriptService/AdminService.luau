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
local Util = require(ReplicatedStorage.Shared.Util)

local AdminService = {}

local notify: (Player, string) -> () = function(_player: Player, _message: string) end

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
	notify = fn
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
		notify(owner, if why == "many" then "More than one player starts with that." else "No player by that name.")
		return nil
	end
	return Players:FindFirstChild(name) :: Player?
end

local function log(owner: Player, line: string)
	print(string.format("[Admin] %s (%d): %s", owner.Name, owner.UserId, line))
end

local handlers: { [string]: (owner: Player, args: { string }, rest: string) -> () } = {}

handlers.give = function(owner, args)
	local who, amount = target(owner, args[1]), AdminLogic.Amount(args[2])
	if not who or not amount then
		if who then
			notify(owner, "Amount must be a whole number, 1 to " .. Util.formatCash(AdminLogic.MaxAmount) .. ".")
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
			notify(owner, "Amount must be a whole number, 1 to " .. Util.formatCash(AdminLogic.MaxAmount) .. ".")
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
		notify(owner, who.Name .. " has no cash to take.")
	end
end

handlers.setcash = function(owner, args)
	local who = target(owner, args[1])
	local text = args[2]
	local amount = if text == "0" then 0 else AdminLogic.Amount(text)
	if not who or not amount then
		if who then
			notify(owner, "Amount must be a whole number from 0.")
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

handlers.gift = function(owner, args)
	local who = target(owner, args[1])
	local kind, itemId = args[2], args[3]
	if not who then
		return
	end
	if not AdminLogic.IsGiftKind(kind) or type(itemId) ~= "string" then
		notify(owner, "Usage: /gift <player> <Axe|Gear|Sawmill|Machine|Blueprint> <id>")
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
		notify(owner, string.format("Gave %s the %s %s.", who.Name, string.lower(kind), itemId))
	else
		notify(owner, string.format("Couldn't gift %s (%s).", itemId, line))
	end
end

handlers.kick = function(owner, args, rest)
	local who = target(owner, args[1])
	if not who then
		return
	end
	if who == owner then
		notify(owner, "You can't kick yourself.")
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
		notify(owner, "You can't ban yourself.")
		return
	end
	if not seconds then
		notify(owner, "Usage: /ban <player> <hours|perm> [reason]")
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
	notify(owner, if ok then "Banned " .. who.Name .. "." else "The ban failed. See Output.")
end

handlers.unban = function(owner, args)
	local userId = tonumber(args[1])
	if userId == nil or userId ~= userId or userId <= 0 or userId % 1 ~= 0 then
		notify(owner, "Usage: /unban <userId>")
		return
	end
	local ok, err = pcall(function()
		Players:UnbanAsync({ UserIds = { userId }, ApplyToUniverse = true })
	end)
	log(owner, string.format("unban %d: %s", userId, if ok then "ok" else tostring(err)))
	notify(owner, if ok then "Unbanned " .. tostring(userId) .. "." else "The unban failed. See Output.")
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
	end
end

handlers.bring = function(owner, args)
	local who = target(owner, args[1])
	local mine, theirs = rootOf(owner), if who then rootOf(who) else nil
	if who and mine and theirs then
		theirs.CFrame = mine.CFrame * CFrame.new(0, 0, -4)
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

handlers.announce = function(owner, _args, rest)
	local text = string.sub(rest, 1, 120)
	if text == "" then
		notify(owner, "Usage: /announce <text>")
		return
	end
	log(owner, "announce: " .. text)
	for _, p in ipairs(Players:GetPlayers()) do
		notify(p, "Owner: " .. text)
	end
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
	if not AdminService.IsOwner(userId) then
		warn(string.format("[Admin] refused /%s from %s (%d): not the owner", command.name, player.Name, userId))
		return false
	end
	if ProfileService.GetProfile(player) == nil then
		return false
	end
	handlers[command.name](player, command.args, command.rest)
	return true
end

-- The owner menu's request (a table from a client, any type). Only the
-- owner gets anything: the speaker's UserId is the remote's own `player`,
-- checked before the request is even read.
function AdminService.RunRequest(player: Player, request: unknown): boolean
	if not AdminService.IsOwner(player.UserId) then
		warn(string.format("[Admin] refused a menu request from %s (%d): not the owner", player.Name, player.UserId))
		return false
	end
	local line = AdminLogic.FromRequest(request)
	if not line then
		return false
	end
	return AdminService.Run(player.UserId, line)
end

-- Tells the owner's own client to show the menu button. Only a convenience:
-- the server checks the owner again on every request.
function AdminService.Mark(player: Player)
	if AdminService.IsOwner(player.UserId) then
		player:SetAttribute("IsOwner", true)
	end
end

function AdminService.Init(notifyFn: (Player, string) -> ())
	notify = notifyFn
	Players.PlayerAdded:Connect(AdminService.Mark)
	for _, player in ipairs(Players:GetPlayers()) do
		AdminService.Mark(player)
	end
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
