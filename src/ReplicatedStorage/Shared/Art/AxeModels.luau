--!strict
-- Axe meshes (uploaded Models owned by Elucidhealer618, Approved).
-- meshId is the MeshPart id, not the Model assetId on each line of the
-- upload list. A meshId of 0 means keep the part-built axe (AxeArt).
-- The Trail piece is an invisible guide: it is never spawned. TrailTop,
-- TrailBottom and LuxBurst are created in code from the Blender points
-- below (the FBX _Att names are not used).

local AxeModels = {}

export type Piece = { meshId: number, size: Vector3 }

export type AxeMesh = {
	Handle: Piece,
	Head: Piece,
	Glow: Piece?,
	Trail: Piece?,
}

-- The blade's front face (-Z) sits on this plane for every axe. It is the
-- Lux trail's Z, the only authored edge we have. Studio: if a head looks
-- too far forward or back, this is the number to move.
AxeModels.BladeFrontZ = -1.41

-- Blender positions on the visual handle, measured from its foot (y = 0),
-- blade toward -Z. AxeArt subtracts half the gameplay handle's length to
-- put them in the Handle part's space.
AxeModels.LuxPoints = {
	TrailTop = Vector3.new(0, 4.095, -1.41),
	TrailBottom = Vector3.new(0, 2.951, -1.41),
	LuxBurst = Vector3.new(0, 3.52, -1.33),
}

local axes: { [string]: AxeMesh } = {
	RustyAxe = {
		Handle = { meshId = 125228989315064, size = Vector3.new(0.295, 3.6, 0.396) },
		Head = { meshId = 132884007738463, size = Vector3.new(0.445, 0.938, 1.738) },
	},
	SteelAxe = {
		Handle = { meshId = 80550306632305, size = Vector3.new(0.295, 3.75, 0.396) },
		Head = { meshId = 139649051325358, size = Vector3.new(0.445, 1.092, 1.919) },
	},
	HardenedAxe = {
		Handle = { meshId = 82273669284316, size = Vector3.new(0.295, 3.874, 0.396) },
		Head = { meshId = 73648959184321, size = Vector3.new(0.509, 2.111, 2.279) },
	},
	SilverAxe = {
		Handle = { meshId = 80860699331818, size = Vector3.new(0.312, 3.832, 0.405) },
		Head = { meshId = 75426342751786, size = Vector3.new(0.445, 1.426, 1.972) },
	},
	CobaltAxe = {
		Handle = { meshId = 126941607721593, size = Vector3.new(0.295, 3.882, 0.396) },
		Head = { meshId = 96144513964536, size = Vector3.new(0.445, 1.264, 2.438) },
	},
	GoldAxe = {
		Handle = { meshId = 124343533685558, size = Vector3.new(0.328, 3.945, 0.413) },
		Head = { meshId = 95238469359825, size = Vector3.new(0.551, 1.081, 2.586) },
	},
	ObsidianAxe = {
		Handle = { meshId = 130646054040528, size = Vector3.new(0.295, 3.9, 0.383) },
		Head = { meshId = 115239214273651, size = Vector3.new(0.547, 1.718, 2.491) },
	},
	InfernoAxe = {
		Handle = { meshId = 121962083793739, size = Vector3.new(0.295, 3.953, 0.396) },
		Head = { meshId = 92529563640180, size = Vector3.new(0.445, 1.23, 1.993) },
		Glow = { meshId = 106039931444640, size = Vector3.new(0.233, 2.824, 1.626) },
	},
	StarfallAxe = {
		Handle = { meshId = 92965386864498, size = Vector3.new(0.295, 4.042, 0.396) },
		Head = { meshId = 121084898724236, size = Vector3.new(0.466, 2.26, 2.046) },
		Glow = { meshId = 87927667111212, size = Vector3.new(0.127, 2.437, 0.858) },
	},
	LuxAxe = {
		Handle = { meshId = 99836533054151, size = Vector3.new(0.328, 4.053, 0.413) },
		Head = { meshId = 102328618104359, size = Vector3.new(0.477, 1.251, 2.035) },
		Glow = { meshId = 128937745363899, size = Vector3.new(0.424, 1.251, 2.088) },
		-- Invisible guide only. Not spawned.
		Trail = { meshId = 122126725797799, size = Vector3.new(0.021, 1.145, 0.021) },
	},
}

function AxeModels.Get(axeId: string): AxeMesh?
	return axes[axeId]
end

-- Every mesh id an axe spawns (the invisible Trail guide is never loaded),
-- for MeshManifest's preload.
function AxeModels.MeshIds(): { number }
	local ids: { number } = {}
	for _, axe in pairs(axes) do
		for _, key in ipairs({ "Handle", "Head", "Glow" }) do
			local piece = (axe :: any)[key] :: Piece?
			if piece and piece.meshId ~= 0 then
				table.insert(ids, piece.meshId)
			end
		end
	end
	table.sort(ids)
	return ids
end

-- 0 keeps the current part-built axe. Shipped ids are not 0.
function AxeModels.UsesMesh(meshId: number): boolean
	return type(meshId) == "number" and meshId ~= 0
end

-- Foot-space (Blender, y = 0 at the handle's foot) to the Handle part,
-- whose centre is half its length up.
function AxeModels.AttachmentOffset(foot: Vector3, handleLength: number): CFrame
	return CFrame.new(foot - Vector3.new(0, handleLength / 2, 0))
end

-- TrailTop, TrailBottom and LuxBurst on the gameplay Handle. Safe to call
-- again. The visual handle length is not used: the tool's Handle size is.
function AxeModels.AddLuxAttachments(handle: BasePart)
	local len = handle.Size.Y
	for name, foot in pairs(AxeModels.LuxPoints) do
		if handle:FindFirstChild(name) == nil then
			local attachment = Instance.new("Attachment")
			attachment.Name = name
			attachment.CFrame = AxeModels.AttachmentOffset(foot, len)
			attachment.Parent = handle
		end
	end
end

return AxeModels
