--!strict
-- BeltService: runs the conveyor belts you placed (AutomationLogic, V2_PLAN.md
-- §10). A belt is an anchored trough whose Conveyor part has an
-- AssemblyLinearVelocity of dir * GameConfig.ConveyorSpeed: loose logs and
-- planks resting on it are carried (the MillBelt collision group lets wood
-- ride and lets players walk through). Every GameConfig.SellPollSec this sets
-- each belt's speed from the rules, because the velocity is in world space
-- (a placed or turned belt needs it re-aimed) and a belt is only a belt while
-- it runs:
--   * the owner must be online (GAME_DESIGN §9: no offline production);
--   * the owner must have fewer than AutomationLogic.MaxLooseOutputs planks
--     and boards lying about (the Warehouse stand-in): a full plot stops the
--     line until some is sold or loaded.
-- The machines' own throughput caps live in SawmillService and PlanerService.
-- Lane W: LogicService sets PowerIn / WireReverse / WireSide from the wires,
-- and the owner's Reverse and Flip prompts set Reversed / Flip.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutomationLogic = require(ReplicatedStorage.Shared.AutomationLogic)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local MachineArt = require(ReplicatedStorage.Shared.Art.MachineArt)
local WoodService = require(script.Parent.WoodService)

local BeltService = {}

type Context = {
	belts: () -> { Model },
	online: (number) -> boolean,
	outputs: (number) -> number,
}

local ctx: Context? = nil
local running = false

local function defaultBelts(): { Model }
	local out: { Model } = {}
	for _, inst in ipairs(CollectionService:GetTagged(AutomationLogic.Tag)) do
		if inst:IsA("Model") and inst.Parent then
			table.insert(out, inst)
		end
	end
	return out
end

-- One pass: every belt gets the speed its owner's state allows. Returns how
-- many belts are running (for specs).
function BeltService.Tick(): number
	local c = ctx
	if not c then
		return 0
	end
	local counted: { [number]: number } = {}
	local going = 0
	for _, belt in ipairs(c.belts()) do
		local owner = belt:GetAttribute("OwnerId")
		local ownerId = if type(owner) == "number" then owner else 0
		local online = ownerId ~= 0 and c.online(ownerId)
		local loose = counted[ownerId]
		if loose == nil then
			loose = if online then c.outputs(ownerId) else 0
			counted[ownerId] = loose
		end
		local base = AutomationLogic.BeltSpeed(online, loose)
		-- Lane W: PowerIn false (a wire turned it off) stops it; Reversed (the
		-- owner's prompt) and WireReverse (a wired reverse input) each flip it.
		-- A belt nobody wired has neither attribute, so it runs as before.
		local powered = belt:GetAttribute("PowerIn") ~= false
		local reversed = (belt:GetAttribute("Reversed") == true) ~= (belt:GetAttribute("WireReverse") == true)
		if belt:GetAttribute("BeltShape") == "switch" then
			local wireSide = belt:GetAttribute("WireSide") == true
			local flip = belt:GetAttribute("Flip") == true
			belt:SetAttribute("Side", AutomationLogic.SwitchSide(flip, wireSide, wireSide))
		end
		local speed = AutomationLogic.SignedSpeed(base, powered, reversed)
		MachineArt.AimBelt(belt, speed)
		belt:SetAttribute("Running", speed ~= 0)
		if speed ~= 0 then
			going += 1
		end
	end
	return going
end

function BeltService.Init()
	ctx = {
		belts = defaultBelts,
		online = function(userId: number): boolean
			return game:GetService("Players"):GetPlayerByUserId(userId) ~= nil
		end,
		outputs = WoodService.CountOutputs,
	}
	if running then
		return
	end
	running = true
	task.spawn(function()
		while running do
			task.wait(GameConfig.SellPollSec)
			local ok, err = pcall(function(): any
				BeltService.Tick()
				return nil
			end)
			if not ok then
				warn("[BeltService] tick failed: " .. tostring(err))
			end
		end
	end)
end

function BeltService._reset()
	ctx = nil
	running = false
end

-- Specs: a context and no polling loop.
function BeltService._use(partial: {
	belts: (() -> { Model })?,
	online: ((number) -> boolean)?,
	outputs: ((number) -> number)?,
})
	ctx = {
		belts = partial.belts or defaultBelts,
		online = partial.online or function(_userId: number): boolean
			return true
		end,
		outputs = partial.outputs or function(_userId: number): number
			return 0
		end,
	}
end

return BeltService
