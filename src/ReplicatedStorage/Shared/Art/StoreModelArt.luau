--!strict
-- StoreModelArt: the engine side of StoreModelSlots. Builds a slot's MeshParts
-- (MeshKit.Create, which never yields) standing on a frame, and swaps them in
-- for the part-built look once the mesh is there (MeshKit.Attempt), so a slot
-- whose mesh id is unset, still loading, or failed leaves the part-built item
-- exactly as it was and never errors.
--
-- One model per item: ItemModel/BoxArt (the shop box and the carried box),
-- BlueprintModels (a placed plan or its ghost) and MachineArt (the placed Sky
-- Bin) all call Build with the same slot; only the frame and the `fit` differ.

local MeshKit = require(script.Parent.MeshKit)
local StoreModelSlots = require(script.Parent.Parent.StoreModelSlots)

local StoreModelArt = {}

export type BuildOpts = {
	parent: any?, -- an Instance (any: a table field's type is invariant, callers pass a Model)
	limit: Vector3?, -- an extra box the model must fit (the display's part-built extent)
	scale: number?, -- multiplies the fitted size (the display's box scale)
	anchored: boolean?,
	weldTo: any?, -- a BasePart: welds every piece to this part
	attribute: string?, -- set true on every piece (BlueprintModels marks its visuals)
}

-- True while a part-built item is being built only to measure or to copy
-- (ItemModel's display copy): a placed model must not start a mesh swap
-- of its own then, BoxArt does the swap on the box.
StoreModelArt.Suspended = false

-- The slot's pieces standing on `frame` (the middle of their feet), or nil when
-- any piece has no mesh id or its mesh is not ready (nothing is left half made).
function StoreModelArt.Build(slot: StoreModelSlots.Slot, frame: CFrame, opts: BuildOpts?): { MeshPart }?
	if not StoreModelSlots.HasMesh(slot) then
		return nil
	end
	local o: BuildOpts = opts or {}
	local layout = StoreModelSlots.Layout(slot, o.limit)
	local extra = o.scale or 1
	local turn = CFrame.Angles(0, layout.yaw, 0)
	local made: { MeshPart } = {}
	for index, piece in ipairs(slot.pieces) do
		local place = layout.pieces[index]
		local id = StoreModelSlots.MeshIdOf(slot, piece)
		local part = MeshKit.Create(id, piece.name, place.size * extra)
		if part == nil then
			for _, old in ipairs(made) do
				old:Destroy()
			end
			return nil
		end
		MeshKit.Visual(part, id)
		MeshKit.Fidelity(part, Enum.RenderFidelity.Automatic)
		if piece.textureId ~= 0 then
			pcall(function()
				part.TextureID = "rbxassetid://" .. tostring(piece.textureId)
			end)
		end
		part:SetAttribute("StoreModel", slot.id)
		if o.attribute then
			part:SetAttribute(o.attribute, true)
		end
		table.insert(made, part)
	end
	for index, part in ipairs(made) do
		local place = layout.pieces[index]
		if part:GetAttribute("MeshPivot") == "authored" then
			-- The mesh keeps the model's own origin (its PivotOffset): put that origin
			-- where the GLB's origin goes in the frame.
			part:PivotTo(frame * CFrame.new(place.origin * extra) * turn)
		else
			part.CFrame = frame * CFrame.new(place.offset * extra) * turn
		end
		part.Anchored = o.anchored == true
		if o.parent then
			part.Parent = o.parent
		end
		local host = o.weldTo
		if host then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "Weld"
			weld.Part0 = host
			weld.Part1 = part
			weld.Parent = part
		end
	end
	return made
end

-- Runs `build` now and, while a mesh is still on its way, again when it lands.
-- When it makes parts, `replaced` (the part-built look) is destroyed. Returns
-- the parts, or nil (the part-built look stays). `alive` is what the swap
-- belongs to: when it is gone the swap is dropped.
function StoreModelArt.Dress(alive: Instance, build: () -> { MeshPart }?, replaced: { any }?): { MeshPart }?
	return MeshKit.Attempt(alive, function(): { MeshPart }?
		local made = build()
		if made ~= nil and replaced ~= nil then
			for _, old in ipairs(replaced) do
				if old.Parent ~= nil then
					old:Destroy()
				end
			end
		end
		return made
	end)
end

-- A placed item (BlueprintModels, MachineArt): the slot's mesh welded to `host`
-- (the model's Root slab, 0.2 thick on the ground), the part-built boxes left
-- as the collider and made invisible, like ItemMeshes.Attach. With `hide`,
-- only those parts are hidden instead (the Sky Bin keeps its flume and cloud).
-- False, and nothing changed, when the item has no slot, the slot has no mesh
-- id, or the mesh is not ready (the swap tries again when it is).
function StoreModelArt.DressPlaced(
	model: Model,
	host: BasePart,
	itemId: string,
	ghost: boolean,
	hide: { BasePart }?
): boolean
	if StoreModelArt.Suspended then
		return false
	end
	local slot = StoreModelSlots.ForItem(itemId, nil)
	-- A "items" slot (the lamp post) is placed by ItemMeshes already, from the same ids.
	if slot == nil or slot.source == "items" or not StoreModelSlots.HasMesh(slot) then
		return false
	end
	local result = MeshKit.Attempt(model, function(): boolean
		local frame = host.CFrame * CFrame.new(0, -host.Size.Y / 2, 0)
		local made = StoreModelArt.Build(slot, frame, { parent = model, weldTo = host, attribute = "ItemVisual" })
		if made == nil then
			return false
		end
		for _, part in ipairs(made) do
			part:SetAttribute("Role", "Prop")
			part.Transparency = if ghost then 0.45 else 0
		end
		if hide then
			for _, part in ipairs(hide) do
				part.Transparency = 1
			end
		else
			for _, child in ipairs(model:GetChildren()) do
				if child:IsA("BasePart") and child ~= host and child:GetAttribute("ItemVisual") ~= true then
					child.Transparency = 1
				end
			end
		end
		return true
	end)
	return result == true
end

return StoreModelArt
