--!strict
-- PermissionService: who may visit and build (rules in PermissionLogic).
-- One connection on SetPermission. The handler budgets the call, then
-- writes one flag on the caller's own plot. Grabbing asks Can(); the
-- grab service calls that itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PermissionLogic = require(ReplicatedStorage.Shared.PermissionLogic)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local RateLimiter = require(script.Parent.RateLimiter)

local PermissionService = {}

local bound = false

-- Loaded on a real call. The module itself must not pull ProfileService:
-- that service asks for Players as it loads, and the remote-budget test
-- fires SetPermission with no arguments.
local function profiles(): any
	return require(script.Parent.ProfileService)
end

local function publish(player: Player)
	local profile = profiles().GetProfile(player)
	if not profile then
		return
	end
	player:SetAttribute("PlotPermissions", PermissionLogic.Encode(profile.permissions))
end

function PermissionService.Publish(player: Player)
	publish(player)
end

function PermissionService.Apply(player: Player, targetRaw: unknown, flag: unknown, on: unknown)
	local target = PermissionLogic.Target(targetRaw)
	if not target or type(flag) ~= "string" or type(on) ~= "boolean" then
		return
	end
	if target == tostring(player.UserId) then
		return
	end
	local profile = profiles().GetProfile(player)
	if not profile then
		return
	end
	if type(profile.permissions) ~= "table" then
		profile.permissions = {}
	end
	if not PermissionLogic.Set(profile.permissions, target, flag, on) then
		return
	end
	publish(player)
end

-- True when `player` may do `flag` on `ownerId`'s plot. The owner always may.
-- A missing owner (left the server) is a no, except for the owner id itself.
function PermissionService.Can(player: Player, ownerId: number, flag: string): boolean
	local userId = if type(player) == "table" or typeof(player) == "Instance" then player.UserId else nil
	if type(userId) ~= "number" or type(ownerId) ~= "number" or type(flag) ~= "string" then
		return false
	end
	if userId == ownerId then
		return true
	end
	local ok, players = pcall(function()
		return game:GetService("Players")
	end)
	if not ok or players == nil or type(players.GetPlayerByUserId) ~= "function" then
		return false
	end
	local owner = players:GetPlayerByUserId(ownerId)
	if not owner then
		return false
	end
	local profile = profiles().GetProfile(owner)
	if not profile then
		return false
	end
	-- Lane F: the one edit-rights rule (PlotService.CanEdit's pure twin).
	return PlotLogic.CanEdit(profile.permissions, userId, ownerId, flag)
end

function PermissionService.Init(remoteEvent: RemoteEvent?)
	if bound or remoteEvent == nil then
		return
	end
	bound = true
	remoteEvent.OnServerEvent:Connect(function(player: Player, target: unknown, flag: unknown, on: unknown)
		if not RateLimiter.Allow(player, "SetPermission") then
			return
		end
		PermissionService.Apply(player, target, flag, on)
	end)
end

return PermissionService
