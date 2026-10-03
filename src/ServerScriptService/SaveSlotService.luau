--!strict
-- SaveSlotService: load or reset a save slot (rules in Shared/SaveSlotLogic).
-- One DataStore session holds all three slots, so two servers can't have
-- the same save open. A load or a reset:
--   1. refuses, and touches nothing, while the cooldown is running;
--   2. commits wood and the truck into the profile and takes them out of
--      the world (the same path as leaving);
--   3. swaps the slot data (Robux state stays);
--   4. rebuilds the plot, the truck and the axe loadout from the slot;
--   5. saves immediately, and stamps the cooldown so a rejoin can't skip it.
-- Reset asks for a confirm first (Arm), so one stray tap can't wipe a slot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local SaveSlotLogic = require(ReplicatedStorage.Shared.SaveSlotLogic)
local Util = require(ReplicatedStorage.Shared.Util)
local EconomyService = require(script.Parent.EconomyService)
local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

local SaveSlotService = {}

local ARM_SECONDS = 20

type Hooks = {
	commit: (Player) -> (),
	rebuild: (Player) -> (),
}

local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local hooks: Hooks = {
	commit = function(_player: Player) end,
	rebuild = function(_player: Player) end,
}
local stateRemote: RemoteEvent? = nil
local armedUntil: { [Player]: number } = {}

local function publish(player: Player)
	local profile = ProfileService.GetProfile(player)
	local remote = stateRemote
	if not profile or not remote then
		return
	end
	player:SetAttribute("ActiveSlot", profile.activeSlot)
	player:SetAttribute("SlotCooldownUntil", profile.slotCooldownUntil)
	remote:FireClient(player, SaveSlotLogic.Summary(profile))
end

local function perform(player: Player, action: string, index: number): boolean
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return false
	end
	local ok, why = SaveSlotLogic.Perform(profile, action, index, os.time(), ProfileSchema.Template, Util.guid, {
		commit = function(_data: any)
			hooks.commit(player)
		end,
		setCash = function(amount: number)
			EconomyService.ReplaceCash(player, amount, "save slot " .. action)
		end,
		rebuild = function(_data: any)
			hooks.rebuild(player)
		end,
	})
	if not ok then
		if why and why ~= "bad" then
			notify(player, why)
		end
		return false
	end
	ProfileService.Save(player)
	publish(player)
	if action == "reset" then
		notify(player, string.format("Save %d is a fresh start.", profile.activeSlot))
	else
		notify(player, string.format("Loaded save %d.", profile.activeSlot))
	end
	return true
end

local function onAction(player: Player, action: unknown, index: unknown, confirm: unknown)
	if not RateLimiter.Allow(player, "SlotAction") then
		return
	end
	if action == "arm" then
		armedUntil[player] = os.clock() + ARM_SECONDS
		return
	end
	if confirm ~= true or (action ~= "load" and action ~= "reset") then
		return
	end
	if action == "reset" and os.clock() > (armedUntil[player] or 0) then
		notify(player, "Tap Redo, then confirm. That save's cash, wood and plot will be wiped.")
		return
	end
	armedUntil[player] = nil
	local slot = if action == "load" then index else 0
	if action == "load" and type(slot) ~= "number" then
		return
	end
	perform(player, action :: string, if type(slot) == "number" then slot else 0)
end

function SaveSlotService.PlayerJoined(player: Player)
	publish(player)
end

function SaveSlotService.PlayerRemoving(player: Player)
	armedUntil[player] = nil
end

function SaveSlotService.Init(action: RemoteEvent, state: RemoteEvent, notifyFn: (Player, string) -> (), world: Hooks)
	notify = notifyFn
	hooks = world
	stateRemote = state
	action.OnServerEvent:Connect(onAction)
	-- Touch the constant so a tune of the cooldown is the one the logic uses.
	if GameConfig.SlotCooldownSec < 30 then
		warn("[SaveSlot] SlotCooldownSec is under 30s; a load could be used to move wood")
	end
end

return SaveSlotService
