--!strict
-- CarryService: the logs each player carries in their hands (up to
-- GameConfig.HandCapacity). GameServer picks them up, loads, sells and drops
-- them; the Aether Isles' Cloud Chute and forge take them too. The logs'
-- own records (wood, models) live in TreeService; this only tracks whose
-- hands each one is in, mirrored on the CarriedLogs player attribute.
--
-- Each carried log is welded to the torso at CarryLayout.LogOffset(slot),
-- its slot in the CarrySlot attribute on its PrimaryPart (GameServer's
-- pickup takes the lowest free one). Whenever the count changes, Restack
-- moves the logs still in hand down to slots 0, 1, ..., so a log left
-- alone after the other was loaded into a nearly full bed, sent down the
-- Cloud Chute or forged sits at slot 0, where the arms hold it (ACT-01).
-- It listens to CarriedLogs because every path that takes logs sets it
-- (TakeLogs here, GameServer's load, sell and drop).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CarryLayout = require(ReplicatedStorage.Shared.CarryLayout)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local TreeService = require(script.Parent.TreeService)

local CarryService = {}

local hands: { [number]: { [string]: boolean } } = {} -- [userId] -> { [logUid] = true }
local watching: { [number]: RBXScriptConnection } = {} -- [userId] -> its CarriedLogs listener

-- Moves the player's carried logs to the lowest slots, keeping their
-- order: each one that moves is unwelded, placed at its new slot's offset
-- from the torso and welded again (the same steps as the pickup).
function CarryService.Restack(player: Player)
	local set = hands[player.UserId]
	local char = player.Character
	if not set or not char then
		return
	end
	local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local held: { { pp: BasePart, slot: number } } = {}
	for uid in pairs(set) do
		local log = TreeService.GetLog(uid)
		local pp = if log then log.model.PrimaryPart else nil
		local slot = if pp then pp:GetAttribute("CarrySlot") else nil
		if pp and pp.Parent and type(slot) == "number" then
			table.insert(held, { pp = pp, slot = slot })
		end
	end
	table.sort(held, function(a, b)
		return a.slot < b.slot
	end)
	for i, h in ipairs(held) do
		local slot = i - 1
		if h.slot ~= slot then
			local pp = h.pp
			-- Unweld first: moving a welded part would drag the character.
			for _, child in ipairs(pp:GetChildren()) do
				if child:IsA("WeldConstraint") then
					child:Destroy()
				end
			end
			pp:SetAttribute("CarrySlot", slot)
			pp.CFrame = torso.CFrame * CarryLayout.LogOffset(slot)
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso
			weld.Part1 = pp
			weld.Parent = pp
		end
	end
end

function CarryService.Start(player: Player)
	hands[player.UserId] = {}
	player:SetAttribute("CarriedLogs", 0)
	local old = watching[player.UserId]
	if old then
		old:Disconnect()
	end
	watching[player.UserId] = player:GetAttributeChangedSignal("CarriedLogs"):Connect(function()
		CarryService.Restack(player)
	end)
end

function CarryService.Stop(player: Player)
	hands[player.UserId] = nil
	local conn = watching[player.UserId]
	watching[player.UserId] = nil
	if conn then
		conn:Disconnect()
	end
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
