--!strict
-- SlabData: Red Mesa sandstone slabs, the building stone for the Sandstone
-- pieces. One slab is a single 4 x 2 x 2 part, carried like a log, worth $0
-- anywhere (never cash), refused by the Ore Chute. Lane R spawns slabs at its
-- quarry with SlabData.Make; Lane F fills pieces with them.

local SlabData = {}

SlabData.Tag = "Slab"
SlabData.Size = Vector3.new(4, 2, 2)
SlabData.Color = Color3.fromHex("#C8643C") -- GAD palette PENDING (brief default)
SlabData.Material = Enum.Material.Sandstone
SlabData.Value = 0 -- never sells for cash (QA AR4, BL3)
SlabData.MaxLoose = 24 -- loose slabs per player
SlabData.UnitsPerSlab = 1 -- one slab fills one slabUnit

-- A slab part, unparented. The caller sets the CFrame and parent and gives
-- it to the grab system like a log.
function SlabData.Make(ownerId: number, uid: string): Part
	local part = Instance.new("Part")
	part.Name = "Slab"
	part.Size = SlabData.Size
	part.Color = SlabData.Color
	part.Material = SlabData.Material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("OwnerId", ownerId)
	part:SetAttribute("Uid", uid)
	part:SetAttribute("Slab", true)
	pcall(function()
		game:GetService("CollectionService"):AddTag(part, SlabData.Tag)
	end)
	return part
end

-- Is this instance a slab? (By attribute, so a spec can check it without
-- CollectionService.)
function SlabData.IsSlab(inst: Instance?): boolean
	return inst ~= nil and inst:IsA("BasePart") and inst:GetAttribute("Slab") == true
end

-- What a slab sells for anywhere: nothing.
function SlabData.SellValue(_inst: Instance?): number
	return SlabData.Value
end

-- May another slab be spawned for this player? `loose` is how many they
-- already have lying about.
function SlabData.CanSpawn(loose: number): boolean
	return type(loose) == "number" and loose == loose and loose < SlabData.MaxLoose
end

-- Slabs a set of units needs.
function SlabData.SlabsFor(units: number): number
	if type(units) ~= "number" or units ~= units or units <= 0 then
		return 0
	end
	return math.ceil(units / SlabData.UnitsPerSlab)
end

return SlabData
