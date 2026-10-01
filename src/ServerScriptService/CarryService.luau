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

-- A log taken out of someone's hands: its wood, what it sells for and its
-- figure (the Hidden Grain), the same shape as a truck bed entry.
export type HeldLog = { woodId: string, value: number, figure: string? }

-- Takes up to `max` carried logs that `accept(wood, figure)` allows out of
-- the player's hands, destroys their models, and returns what they were.
function CarryService.TakeLogs(
	player: Player,
	accept: (WoodData.WoodDef, string?) -> boolean,
	max: number?
): { HeldLog }
	local set = hands[player.UserId]
	local out: { HeldLog } = {}
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
		else
			local figure = log.tags.figure
			local figureId: string? = if type(figure) == "string" then figure else nil
			if accept(log.def, figureId) then
				TreeService.TakeLog(uid)
				log.model:Destroy()
				set[uid] = nil
				table.insert(out, { woodId = log.def.id, value = log.value, figure = figureId })
			end
		end
	end
	CarryService.Publish(player)
	return out
end

-- Like TakeLogs, returning just the wood ids.
function CarryService.TakeWhere(player: Player, accept: (WoodData.WoodDef) -> boolean, max: number?): { string }
	local ids: { string } = {}
	for _, log in
		ipairs(CarryService.TakeLogs(player, function(wood)
			return accept(wood)
		end, max))
	do
		table.insert(ids, log.woodId)
	end
	return ids
end

return CarryService
