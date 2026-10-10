--!strict
-- BaseBoot: binds Lane F's remotes (SaveNow, PaintAllType) without editing
-- GameServer or V1Boot, like EndGameBoot and MiningBoot. GameServer makes
-- the remotes; this waits for them and for the services it hooks to. A
-- missing piece is skipped with a warning.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes", 60)
if remotesFolder == nil then
	warn("[BaseBoot] no Remotes folder")
	return
end

local function remote(name: string): RemoteEvent?
	local r = remotesFolder:WaitForChild(name, 30)
	if r and r:IsA("RemoteEvent") then
		return r
	end
	warn("[BaseBoot] no remote " .. name)
	return nil
end

local function service(name: string): any
	local mod = ServerScriptService:FindFirstChild(name)
	if mod == nil or not mod:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, mod)
	if not ok then
		warn("[BaseBoot] " .. name .. " " .. tostring(result))
		return nil
	end
	return result
end

local function start(name: string, fn: () -> ())
	local ok, err = pcall(function(): any
		fn()
		return nil
	end)
	if not ok then
		warn("[BaseBoot] " .. name .. " " .. tostring(err))
	end
end

-- Save now: the truck's load, then the profile (SaveSlotService.SaveNow).
local slots = service("SaveSlotService")
local plots = service("PlotService")
if slots and type(slots.BindSaveNow) == "function" then
	local truckLoad = service("TruckLoad")
	start("SaveSlotService.BindSaveNow", function()
		slots.BindSaveNow(remote("SaveNow"), {
			truck = function(player: Player)
				if truckLoad and type(truckLoad.Save) == "function" then
					truckLoad.Save(player)
				end
			end,
			busy = function(player: Player): boolean
				return plots ~= nil and type(plots.IsBusy) == "function" and plots.IsBusy(player) == true
			end,
		})
	end)
end

-- Paint all of this type (PlotService.PaintAllType).
if plots and type(plots.BindPaintAll) == "function" then
	start("PlotService.BindPaintAll", function()
		plots.BindPaintAll(remote("PaintAllType"))
	end)
end

-- A blueprint is only left lying on someone else's plot with their say-so.
local blueprints = service("BlueprintService")
if blueprints and plots and type(blueprints.Hooks) == "table" then
	blueprints.Hooks.ownerAt = plots.OwnerAt
	blueprints.Hooks.canEdit = plots.CanEdit
end
