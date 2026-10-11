--!strict
-- LooseService: the loose things on a plot go into the save when the base
-- comes off the pad, and come back when it goes onto one (Shared/LooseSave
-- has the rules). Lane F, Connor's decision 9.
--
--   Scan      what an unload would keep: nothing is touched.
--   Collect   snapshots every unheld log, plank, board, slab and ingot that is
--             the owner's (or nobody's) on their plot into plot.loose,
--             relative to the pad's pivot, and takes each one out of the
--             world in the same step, with no yield between the snapshot and
--             the destroy. A refusal (over the cap, a piece the save cannot
--             hold) touches nothing.
--   Restore   puts them back relative to the new pad, once, and keeps any
--             record it could not rebuild so no wood is ever lost.
--   Stranded  strandedLoad (the map remake parked it) comes back at the plot
--             the same way, within the loose cap, then is cleared.
--
-- Someone else's wood stays where it is. Held pieces stay in their hands.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local LooseSave = require(ReplicatedStorage.Shared.LooseSave)
local OreData = require(ReplicatedStorage.Shared.Mining.OreData)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local PlotLogic = require(ReplicatedStorage.Shared.PlotLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local BuildMaterials = require(script.Parent.BuildMaterials)
local LeftLoad = require(script.Parent.LeftLoad)
local TruckLoad = require(script.Parent.TruckLoad)
local WoodService = require(script.Parent.WoodService)

local LooseService = {}

export type Slot = { cframe: CFrame }

type Profile = { plot: any }

-- The plot's own ground, in the pad's axes (no build margin): a slab at the
-- ramp's foot is not on the plot.
local function onPlot(slot: Slot, extent: number, position: Vector3): boolean
	local half = extent / 2 + PlotData.PlatformRamp
	local p = slot.cframe:PointToObjectSpace(position)
	return math.abs(p.X) <= half and math.abs(p.Z) <= half
end

local function extentOf(profile: Profile): number
	local plot = profile.plot
	local tier = PlotData.Tier(plot.tier) or PlotData.Tiers[1]
	local squares = if type(plot.squares) == "table" then plot.squares else {}
	return PlotLogic.Extent(tier.size, squares)
end

local function heldModel(model: Model): boolean
	local by = model:GetAttribute("HeldBy")
	return type(by) == "number" and by ~= 0
end

type Take = {
	record: { [string]: any },
	remove: () -> (),
}

type Plan = {
	takes: { Take },
	found: LooseSave.Found,
}

-- Everything an unload or a leave would keep, with the way to take each one
-- out of the world. `withIngots` is false on a plain leave (Lane M saves the
-- ingots itself); an unload takes them too, or they would be orphaned on a
-- freed pad.
local function plan(player: Player, slot: Slot, profile: Profile, withIngots: boolean): Plan
	local takes: { Take } = {}
	local found: LooseSave.Found = { pieces = 0, sections = 0, unsaveable = 0 }
	local extent = extentOf(profile)
	local all = WoodService.All()
	for _, piece in pairs(all) do
		local root = piece.root
		local mine = piece.ownerId == player.UserId or piece.ownerId == 0
		if
			mine
			and not piece.dead
			and not piece.selling
			and (piece.kind == "log" or piece.kind == "plank")
			and root
			and root.Parent
			and not heldModel(piece.model)
			and onPlot(slot, extent, root.Position)
		then
			local record = TruckLoad.SnapshotAt(piece.model, slot.cframe, LooseSave.Bed)
			if record == nil then
				found.unsaveable += 1
			else
				found.pieces += 1
				found.sections += #record.s
				table.insert(takes, {
					record = record :: any,
					remove = function()
						WoodService.Remove(piece, "unload")
					end,
				})
			end
		end
	end
	for _, m in ipairs(BuildMaterials.Of(player.UserId)) do
		if not m.held and onPlot(slot, extent, m.position) and (m.kind == "slab" or withIngots) then
			local rx, ry, rz = 0, 0, 0
			local at = slot.cframe:ToObjectSpace(CFrame.new(m.position))
			local p = at.Position
			local place = LooseSave.EncodePlace(p.X, p.Y, p.Z, rx, ry, rz)
			local record = if m.kind == "slab"
				then LooseSave.SlabRecord(place)
				else LooseSave.IngotRecord(m.ore :: string, place)
			found.pieces += 1
			local uid = m.uid
			table.insert(takes, {
				record = record,
				remove = function()
					BuildMaterials.Take(uid)
				end,
			})
		end
	end
	return { takes = takes, found = found }
end

-- What an unload would keep (nothing is touched): BaseLogic reads this.
-- Records already waiting in the save count toward the cap too.
function LooseService.Scan(player: Player, slot: Slot, profile: Profile): LooseSave.Found
	local p = plan(player, slot, profile, true)
	local waiting = LooseSave.Count(profile.plot.loose)
	p.found.pieces += waiting.pieces
	p.found.sections += waiting.sections
	return p.found
end

-- Writes the loose things into plot.loose and takes them out of the world.
-- Returns whether it did, and the line to show when it did not. Nothing is
-- destroyed unless the whole list fits.
function LooseService.Collect(player: Player, slot: Slot, profile: Profile, withIngots: boolean): (boolean, string?)
	local p = plan(player, slot, profile, withIngots)
	local waiting = if type(profile.plot.loose) == "table" then profile.plot.loose else {}
	local carried = LooseSave.Count(waiting)
	local total: LooseSave.Found = {
		pieces = p.found.pieces + carried.pieces,
		sections = p.found.sections + carried.sections,
		unsaveable = p.found.unsaveable,
	}
	local ok, why = LooseSave.Check(total)
	if not ok then
		return false, why
	end
	local list: { any } = table.clone(waiting)
	for _, take in ipairs(p.takes) do
		table.insert(list, take.record)
	end
	-- One step, no yield: the list is written and every part is taken out.
	profile.plot.loose = list
	for _, take in ipairs(p.takes) do
		take.remove()
	end
	return true, nil
end

local function isOre(id: string): boolean
	return OreData.Known(id)
end

local function worldCFrame(slot: Slot, at: unknown): CFrame?
	local local6 = LeftLoad.DecodeCFrame(at)
	if local6 == nil then
		return nil
	end
	return slot.cframe * local6
end

-- Rebuilds what plot.loose holds on `slot`, once. A record that could not be
-- rebuilt (no room for a slab, a piece the world cannot build right now) stays
-- in the list for the next load; junk is dropped. Returns how many came back
-- and how many are still waiting.
function LooseService.Restore(player: Player, slot: Slot, profile: Profile): (number, number)
	local saved = profile.plot.loose
	if type(saved) ~= "table" or #saved == 0 then
		return 0, 0
	end
	local now, later = LooseSave.Split(saved)
	local kept: { any } = later
	local back = 0
	for _, rec in ipairs(now) do
		local done = false
		if LooseSave.IsWood(rec) then
			local piece = LeftLoad.CleanPiece(rec, function(id: string): boolean
				return WoodData.Get(id) ~= nil
			end, { [LooseSave.Bed] = true })
			if piece then
				local cf = worldCFrame(slot, piece.at)
				if cf then
					local model = TruckLoad.Build(piece, player, cf, GameConfig.LeftLoadGraceSec)
					done = model ~= nil
				else
					done = true -- junk place: dropped, nothing to rebuild
				end
			else
				done = true -- junk record: dropped
			end
		else
			local other = LooseSave.CleanOther(rec, isOre)
			if other == nil then
				done = true
			else
				local cf = worldCFrame(slot, other.at)
				if cf == nil then
					done = true
				elseif other.kind == "slab" then
					done = BuildMaterials.ReturnSlab(player.UserId, cf)
				else
					done = BuildMaterials.ReturnIngot(player, other.ore :: string, cf)
				end
			end
		end
		if done then
			back += 1
		else
			table.insert(kept, rec)
		end
	end
	profile.plot.loose = kept
	return back, #kept
end

-- The map remake parked wood that was lying on the ground (strandedLoad). It
-- comes back at the player's plot as loose wood, within the loose cap, and
-- the list is cleared. Pieces over the cap are not dropped: they stay parked
-- and the count is returned. Never touches worldVersion.
function LooseService.RestoreStranded(player: Player, slot: Slot, profile: any): (number, number)
	local saved = profile.strandedLoad
	if type(saved) ~= "table" or #saved == 0 then
		return 0, 0
	end
	local isWood = function(id: string): boolean
		return WoodData.Get(id) ~= nil
	end
	local plotLoose = if type(profile.plot) == "table" then profile.plot.loose else nil
	local room = math.max(0, LooseSave.MaxPieces - LooseSave.Count(plotLoose).pieces)
	local back = 0
	local left: { any } = {}
	for _, raw in ipairs(saved) do
		local piece = LeftLoad.CleanPiece(raw, isWood, LeftLoad.GroundBeds)
		if piece == nil then
			continue -- junk: nothing to rebuild, and nothing to keep
		end
		if back >= room then
			table.insert(left, raw) -- over the loose cap: stays parked, never dropped
			continue
		end
		-- Laid out in rows on the plot, off its middle.
		local turn = LeftLoad.DecodeCFrame(piece.at) or CFrame.new()
		local col, row = back % 6, back // 6
		local cf = slot.cframe * CFrame.new(-10 + col * 4, 3 + row * 2, -10) * turn
		local model = TruckLoad.Build(piece, player, cf, GameConfig.LeftLoadGraceSec)
		if model then
			back += 1
		else
			table.insert(left, raw)
		end
	end
	profile.strandedLoad = left
	return back, #left
end

return LooseService
