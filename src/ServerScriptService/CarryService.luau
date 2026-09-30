--!strict
-- CarryService: the logs each player carries in their hands (up to
-- GameConfig.HandCapacity). GameServer picks them up, loads, sells and drops
-- them; the Aether Isles' Cloud Chute and forge take them too. The logs'
-- own records (wood, models) live in TreeService; this only tracks whose
-- hands each one is in, mirrored on the CarriedLogs player attribute.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WoodData = require(ReplicatedStorage.Shared.WoodData)
local TreeService = require(script.Parent.TreeService)

local CarryService = {}

local hands: { [number]: { [string]: boolean } } = {} -- [userId] -> { [logUid] = true }

function CarryService.Start(player: Player)
	hands[player.UserId] = {}
	player:SetAttribute("CarriedLogs", 0)
end

function CarryService.Stop(player: Player)
	hands[player.UserId] = nil
end

-- The player's carried log uids (a set), or nil if they aren't playing.
function CarryService.Hands(player: Player): { [string]: boolean }?
	return hands[player.UserId]
end

function CarryService.Count(player: Player): number
	local n = 0
	for _ in pairs(hands[player.UserId] or {}) do
		n += 1
	end
	return n
end

function CarryService.Publish(player: Player)
	player:SetAttribute("CarriedLogs", CarryService.Count(player))
end

-- Takes up to `max` carried logs whose wood passes `accept` out of the
-- player's hands, destroys their models, and returns their wood ids.
function CarryService.TakeWhere(player: Player, accept: (WoodData.WoodDef) -> boolean, max: number?): { string }
	local set = hands[player.UserId]
	local out: { string } = {}
	if not set then
		return out
	end
	for uid in pairs(set) do
		if max and #out >= max then
			break
		end
		local log = TreeService.GetLog(uid)
		if not log then
			set[uid] = nil -- stale
		elseif accept(log.def) then
			TreeService.TakeLog(uid)
			log.model:Destroy()
			set[uid] = nil
			table.insert(out, log.def.id)
		end
	end
	CarryService.Publish(player)
	return out
end

return CarryService
