--!strict
-- ModelSlots: one model slot per item whose real model is still being made in
-- Blender (Flashlight, Lantern, Wood Sign, Shed Blueprint). Each item has ONE
-- slot and ONE mesh id; the same id is used by every place the item shows up:
--
--   display  the box's window copy and the sample on the General Store's back
--            ledge (BoxArt.Dress, BuildingArt)
--   held     the thing in the player's hand (BlueprintArt.Held for a plan;
--            ItemModel.Held for the gear)
--   placed   the item standing in the world (BlueprintModels.Build for the
--            Wood Sign and the Shed on a plot; ItemModel.Placed for the gear)
--
-- meshId 0 means "not made yet": every path keeps its existing part-built
-- look and nothing changes. Put the real MeshPart id in the slot's `meshId`
-- and all three paths swap it in with no other code change (the swap goes
-- through MeshKit.Create inside MeshKit.Attempt, so it never blocks: the
-- part-built look stays until the mesh has loaded, then is replaced).
--
-- What the model must be (also in STATUS.md, "MODEL_SLOTS"):
--   * `size` is the studs the mesh is stretched to (the GLB's own proportions
--     times `fit`), so a model with other proportions will look squashed.
--   * The pivot is the middle of the bounding box, +Y up, the front of the
--     thing facing -Z (toward the door of a shop, toward the player).
--   * The Flashlight lies along X (lens toward +X, handle toward -X); a Wood Sign
--     stands (post down, board facing -Z); the Lantern and the Shed Blueprint
--     stand on their base.
-- Pure data and one dressing helper; no other module is required here, so
-- the art modules that use it never form a cycle.

local MeshKit = require(script.Parent.MeshKit)

local ModelSlots = {}

export type Slot = {
	name: string, -- the slot's name ("Flashlight", "Lantern", "WoodSign", "ShedBlueprint")
	kind: string, -- StoreStock kind of the item
	itemId: string, -- ItemCatalog / PlotData id
	meshId: number, -- 0 = not made yet; the part-built look stays
	glb: string, -- Connor's model file in the repo (the preview loads it; there is no Roblox id yet)
	glbSize: Vector3, -- that file's bounding box
	fit: number, -- uniform scale from the GLB to game studs
	size: Vector3, -- glbSize * fit: the studs the mesh is stretched to
	placedAs: string, -- "plot" (a piece on a plot), "ground" (set down in the world), "dropped" (the plan lying on the ground)
	pivot: string, -- plain words for the modeller
}

local V3 = Vector3.new

-- THE FOUR SLOTS. Paste a MeshPart id into `meshId` and nothing else. The models are Connor's GLBs
-- (assets/glb/store-items/<Name>.glb, no Roblox mesh id yet, so meshId stays 0). `glbSize` is the GLB's
-- own bounding box (x, y, z; a spec reads the file to check it), `fit` the one uniform scale that
-- brings it to game size, and `size` = glbSize * fit is what the mesh is stretched to (so it is never
-- distorted). The Flashlight lies along X; the Shed Blueprint's model is the plan itself, so on a plot
-- the Shed ghost stays the part-built shed you fill with planks, and the model is the item you carry
-- and the one lying in the world when dropped (`placedAs`).
ModelSlots.Slots = {
	{
		name = "Flashlight",
		kind = "Gear",
		itemId = "Flashlight",
		meshId = 0,
		glb = "assets/glb/store-items/Flashlight.glb",
		glbSize = V3(0.851, 0.214, 0.214),
		fit = 2.7,
		size = V3(2.298, 0.578, 0.578),
		placedAs = "ground",
		pivot = "middle of the box; lying along X: lens at +X, handle at -X",
	},
	{
		name = "Lantern",
		kind = "Gear",
		itemId = "Lantern",
		meshId = 0,
		glb = "assets/glb/store-items/Lantern.glb",
		glbSize = V3(0.509, 1.306, 0.509),
		fit = 1.19,
		size = V3(0.606, 1.554, 0.606),
		placedAs = "ground",
		pivot = "middle of the box; standing on its base, carry handle on top",
	},
	{
		name = "WoodSign",
		kind = "Blueprint",
		itemId = "WoodSign",
		meshId = 0,
		glb = "assets/glb/store-items/WoodSign.glb",
		glbSize = V3(2.2, 3.75, 0.395),
		fit = 1.04,
		size = V3(2.288, 3.9, 0.411),
		placedAs = "plot",
		pivot = "middle of the box; post down, the board facing -Z",
	},
	{
		name = "ShedBlueprint",
		kind = "Blueprint",
		itemId = "Shed",
		meshId = 0,
		glb = "assets/glb/store-items/ShedBlueprint.glb",
		glbSize = V3(1.4, 3.045, 1.807),
		fit = 1.5,
		size = V3(2.1, 4.568, 2.711),
		placedAs = "dropped",
		pivot = "middle of the box; standing on its base, front toward -Z",
	},
} :: { Slot }

local BY_ITEM: { [string]: Slot } = {}
local BY_NAME: { [string]: Slot } = {}
for _, slot in ipairs(ModelSlots.Slots) do
	BY_ITEM[slot.kind .. ":" .. slot.itemId] = slot
	BY_NAME[slot.name] = slot
end

-- The slot of an item, or nil for an item with no slot.
function ModelSlots.For(kind: string, itemId: string): Slot?
	return BY_ITEM[kind .. ":" .. itemId]
end

function ModelSlots.Named(name: string): Slot?
	return BY_NAME[name]
end

-- Whether a real model has been set in the slot.
function ModelSlots.IsSet(slot: Slot): boolean
	return slot.meshId ~= 0
end

export type Role = "display" | "held" | "placed"

export type DressOptions = {
	scale: number?, -- the mesh is the slot's size times this (a display copy is smaller than the item)
	anchored: boolean?, -- default true; a held item is welded instead
	weldTo: BasePart?, -- weld the mesh to this part (the held roll's handle)
	remove: { BasePart }?, -- the part-built look, destroyed once the mesh is up
	hide: { BasePart }?, -- parts kept (a Tool's Handle) but made invisible once the mesh is up
	inBuildFrame: boolean?, -- the centre is in the coordinates the model was built in (the shop is moved after): MeshKit.Attempt's swap puts the model back for the step
	onDressed: ((MeshPart) -> ())?, -- the caller's own touch (a ghost's fade, a collider) once the mesh is up
}

-- Puts the slot's mesh, centred on `centre`, under `parent`, and takes the
-- part-built look away once it is there. Never yields and never blocks: with
-- meshId 0, or while the mesh is still loading, it returns false and the
-- part-built look stays (MeshKit.Attempt runs it again when the mesh has
-- arrived). Returns whether the mesh is up now.
function ModelSlots.Dress(parent: Instance, slot: Slot, centre: CFrame, role: Role, options: DressOptions?): boolean
	if not ModelSlots.IsSet(slot) then
		return false
	end
	local opts: DressOptions = options or {}
	local scale = opts.scale or 1
	return MeshKit.Attempt(parent, function()
		local part = MeshKit.Create(slot.meshId, slot.name, slot.size * scale)
		if not part then
			return false
		end
		MeshKit.Visual(part, slot.meshId)
		part:SetAttribute("ModelSlot", slot.name)
		part:SetAttribute("SlotRole", role)
		part.CFrame = centre
		part.Anchored = opts.anchored ~= false and opts.weldTo == nil
		part.Parent = parent
		if opts.weldTo then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "SlotWeld"
			weld.Part0 = opts.weldTo
			weld.Part1 = part
			weld.Parent = part
		end
		for _, old in ipairs(opts.remove or {}) do
			old:Destroy()
		end
		for _, keep in ipairs(opts.hide or {}) do
			keep.Transparency = 1
		end
		if opts.onDressed then
			opts.onDressed(part)
		end
		return true
	end, opts.inBuildFrame)
end

return ModelSlots
