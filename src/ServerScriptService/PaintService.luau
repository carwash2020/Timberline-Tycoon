--!strict
-- Paint Shop: the PaintTruck remote. The player names one of their own
-- trucks and a color. PaintShop.Decide clamps it to the palette, refuses
-- someone else's truck, and waits two seconds between accepted changes.
-- The color is saved on the slot and applied the next time that truck is
-- built (immediately, when it isn't being driven).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PaintShop = require(ReplicatedStorage.Shared.PaintShop)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)
local VehicleService = require(script.Parent.VehicleService)

local PaintService = {}

local lastAt: { [Player]: number } = {}
local notify: (Player, string) -> () = function(_player: Player, _message: string) end

function PaintService.Try(player: Player, truckId: unknown, color: unknown, now: number?): (boolean, string)
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return false, "Your save isn't loaded yet."
	end
	local id = if type(truckId) == "string" then truckId else ""
	local clock = if type(now) == "number" then now else os.clock()
	local owns = type(profile.ownedTrucks) == "table" and table.find(profile.ownedTrucks, id) ~= nil
	local pass = type(profile.passes) == "table" and profile.passes.PaintShop == true
	local ok, result = PaintShop.Decide({
		ownsPass = pass,
		ownsTruck = owns,
		callerUserId = player.UserId,
		ownerUserId = player.UserId,
		color = color,
		now = clock,
		lastAt = lastAt[player],
	})
	if not ok then
		return false, result
	end
	if type(profile.truckPaint) ~= "table" then
		profile.truckPaint = {}
	end
	profile.truckPaint[id] = result
	lastAt[player] = clock
	VehicleService.Repaint(player, id)
	return true, result
end

function PaintService.PlayerRemoving(player: Player)
	lastAt[player] = nil
end

function PaintService.Init(remote: RemoteEvent, notifyFn: (Player, string) -> ())
	notify = notifyFn
	remote.OnServerEvent:Connect(function(player: Player, truckId: unknown, color: unknown)
		if not RateLimiter.Allow(player, "PaintTruck") then
			return
		end
		local ok, message = PaintService.Try(player, truckId, color)
		if not ok then
			notify(player, message)
		end
	end)
end

return PaintService
