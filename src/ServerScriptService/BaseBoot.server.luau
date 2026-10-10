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

-- Stage unlocks: every few seconds each player's book is brought up to the
-- plans their stage owes it (BlueprintService.SyncStage). Cheap: one profile
-- read per player, and it writes only when a plan is new.
if blueprints and type(blueprints.SyncStage) == "function" then
	local Players = game:GetService("Players")
	task.spawn(function()
		while true do
			task.wait(5)
			for _, player in ipairs(Players:GetPlayers()) do
				start("BlueprintService.SyncStage", function()
					blueprints.SyncStage(player)
				end)
			end
		end
	end)
end

-- Crafted furniture: the bench grants a placeable piece through PlotService.
local crafting = service("CraftingService")
if crafting and plots and type(crafting.Hooks) == "table" then
	crafting.Hooks.canGrant = plots.CanGrant
	crafting.Hooks.grant = plots.GrantPiece
end

-- Fallen pieces (Lane F): owned wood, slabs, ingots and trucks that fall out of
-- the world come back at their owner's plot (FallenLogic). Wood is caught by
-- WoodService's own tick through this hook; trucks and loose stone are looked
-- at every two seconds here.
local Players = game:GetService("Players")
local FallenLogic = require(ReplicatedStorage.Shared.FallenLogic)
local wood = service("WoodService")
if wood and plots and type(wood.Hooks) == "table" then
	wood.Hooks.recover = function(piece: any): CFrame?
		local owner = Players:GetPlayerByUserId(piece.ownerId)
		if owner == nil then
			return nil
		end
		return plots.RecoverSpot(owner)
	end
end

local vehicles = service("VehicleService")
local materials = service("BuildMaterials")
local function tell(player: Player, text: string)
	local notifyRemote = remotesFolder:FindFirstChild("Notify")
	if notifyRemote and notifyRemote:IsA("RemoteEvent") then
		notifyRemote:FireClient(player, text)
	end
end
if plots and (vehicles or materials) then
	task.spawn(function()
		while true do
			task.wait(2)
			for _, player in ipairs(Players:GetPlayers()) do
				start("rescue fallen", function()
					if vehicles and type(vehicles.RescueFallen) == "function" and vehicles.RescueFallen(player) then
						tell(player, FallenLogic.Texts.truck)
					end
					if materials and type(materials.Of) == "function" then
						local moved = false
						for _, m in ipairs(materials.Of(player.UserId)) do
							if FallenLogic.Fell(m.position.Y) then
								local spot = plots.RecoverSpot(player)
								if spot and materials.MoveTo(m.uid, spot) then
									moved = true
								end
							end
						end
						if moved then
							tell(player, FallenLogic.Texts.stone)
						end
					end
				end)
			end
		end
	end)
end
