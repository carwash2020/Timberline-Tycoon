--!strict
-- EditRights: who may edit a plot, in one place (Lane F, QA BL4). The rule
-- is PlotLogic.CanEdit: the owner always, anyone else only with the flag in
-- the owner's permissions. PlotService.CanEdit is this same function; the
-- services PlotService itself requires (LogicService, PermissionService,
-- SawmillService, ChopSawService, VehicleService, BlueprintService, ...)
-- call it from here, so no service needs PlotService back.
--
-- flag: "build" | "destroy" | "interact" | "paint" | "grab". "paint" rides
-- on "build" and "build" implies "destroy" (PermissionLogic).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local ProfileService = require(script.Parent.ProfileService)

local EditRights = {}

-- Whether `actor` may do `flag` on `owner`'s plot. A missing actor or owner
-- (the owner left the server) is a no.
function EditRights.Can(actor: Player?, owner: Player?, flag: string): boolean
	if actor == nil or owner == nil then
		return false
	end
	if actor == owner then
		return true
	end
	local profile = ProfileService.GetProfile(owner)
	if profile == nil then
		return false
	end
	return PlotLogic.CanEdit(profile.permissions, actor.UserId, owner.UserId, flag)
end

return EditRights
