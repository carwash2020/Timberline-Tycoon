--!strict
-- HandInWood: the loose wood a player has laid by a hand-in spot (Gus's
-- station, the Sky Forge anvil), and taking it. The rules are pure in
-- Shared/HandInLogic; this reads the live pieces (WoodService) and removes
-- the ones used. Taken wood is used up and pays nothing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HandInLogic = require(ReplicatedStorage.Shared.HandInLogic)
local CraftLogic = require(ReplicatedStorage.Shared.Mining.CraftLogic)
local WoodService = require(script.Parent.WoodService)

local HandInWood = {}

local function truckWelded(model: Model): boolean
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Weld") or d:IsA("WeldConstraint") then
			local other = if d.Part0 and d.Part0:IsDescendantOf(model) then d.Part1 else d.Part0
			if other and CraftLogic.IsTruckWeld(other.Name) then
				return true
			end
		end
	end
	return false
end

-- Every piece within reach of `at`, as HandInLogic candidates, and the
-- pieces by uid.
function HandInWood.Near(at: Vector3): ({ HandInLogic.Candidate }, { [string]: WoodService.Piece })
	local list: { HandInLogic.Candidate } = {}
	local byUid: { [string]: WoodService.Piece } = {}
	for uid, p in pairs(WoodService.All()) do
		if not p.dead and not p.selling and p.model.Parent ~= nil then
			local distance = (p.root.Position - at).Magnitude
			if distance <= HandInLogic.Reach then
				local heldBy = p.model:GetAttribute("HeldBy")
				local volume = p.model:GetAttribute("Volume")
				table.insert(list, {
					uid = uid,
					woodId = p.woodId,
					kind = p.kind :: string,
					volume = if type(volume) == "number" then volume else 0,
					figure = p.figure,
					owner = p.ownerId,
					welded = truckWelded(p.model),
					held = type(heldBy) == "number" and heldBy ~= 0 and heldBy ~= p.ownerId,
					distance = distance,
				})
				byUid[uid] = p
			end
		end
	end
	return list, byUid
end

-- Removes the pieces named in `uids` (used up by a hand-in). Returns the
-- u³ removed.
function HandInWood.Take(byUid: { [string]: WoodService.Piece }, uids: { string }, reason: string): number
	local total = 0
	for _, uid in ipairs(uids) do
		local p = byUid[uid]
		if p and not p.dead then
			local volume = p.model:GetAttribute("Volume")
			total += if type(volume) == "number" then volume else 0
			WoodService.Remove(p, reason)
		end
	end
	return total
end

return HandInWood
