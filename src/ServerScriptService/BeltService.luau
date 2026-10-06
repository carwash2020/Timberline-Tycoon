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
		local speed = AutomationLogic.BeltSpeed(online, loose)
		MachineArt.AimBelt(belt, speed)
		belt:SetAttribute("Running", speed > 0)
		if speed > 0 then
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
