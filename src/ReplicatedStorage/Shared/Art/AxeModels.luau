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

-- Look data for the part-built axe (AxeArt). Uploaded meshes stay optional:
-- a mesh id of 0, or a mesh that fails to load, keeps this silhouette.
-- `length` is the handle in studs. The Lux Axe's design length is 4.0, but
-- the gameplay Handle stays 3.5 (tests/MeshArt.spec pins that haft).
export type AxeLook = {
	length: number,
	handleColor: string,
	handleMaterial: string,
	gripColor: string,
	gripMaterial: string,
	shape: string,
	head: Vector3, -- thick, tall, deep (X, Y, Z); the edge faces -Z
	headColor: string,
	headMaterial: string,
	trim: string,
}

local looks: { [string]: AxeLook } = {
	RustyAxe = {
		length = 3.2,
		handleColor = "#6B4A2F", -- Timber, tape wrap
		handleMaterial = "Wood",
		gripColor = "#C8BBA4",
		gripMaterial = "Fabric",
		shape = "chipped",
		head = Vector3.new(0.25, 0.9, 1.0),
		headColor = "#7D6A5A",
		headMaterial = "CorrodedMetal",
		trim = "tape",
	},
	SteelAxe = {
		length = 3.4,
		handleColor = "#8A6A45",
		handleMaterial = "Wood",
		gripColor = "#3A322C",
		gripMaterial = "Leather",
		shape = "wedge",
		head = Vector3.new(0.25, 1.0, 1.15),
		headColor = "#A7ADB4",
		headMaterial = "Metal",
		trim = "collar",
	},
	HardenedAxe = {
		length = 3.5,
		handleColor = "#5A4632",
		handleMaterial = "Wood",
		gripColor = "#4A3428",
		gripMaterial = "Leather",
		shape = "spike",
		head = Vector3.new(0.28, 1.1, 1.3),
		headColor = "#5E6670",
		headMaterial = "DiamondPlate",
		trim = "collars2",
	},
	SilverAxe = {
		length = 3.6,
		handleColor = "#D8D2C4",
		handleMaterial = "Wood",
		gripColor = "#5C534C",
		gripMaterial = "Leather",
		shape = "bearded",
		head = Vector3.new(0.25, 1.3, 1.3),
		headColor = "#DCE1E6",
		headMaterial = "Foil",
		trim = "brassPin",
	},
	CobaltAxe = {
		length = 3.7,
		handleColor = "#2B2B2E", -- IronBlack
		handleMaterial = "Metal",
		gripColor = "#1A1A1C",
		gripMaterial = "Metal",
		shape = "doubleBevel",
		head = Vector3.new(0.22, 1.25, 1.4),
		headColor = "#3A6FD8",
		headMaterial = "Metal",
		trim = "whiteEdge",
	},
	GoldAxe = {
		length = 3.7,
		handleColor = "#6B4A2F",
		handleMaterial = "Wood",
		gripColor = "#4A3018",
		gripMaterial = "Leather",
		shape = "crescent",
		head = Vector3.new(0.25, 1.5, 1.45),
		headColor = "#E1B530",
		headMaterial = "Foil",
		trim = "bands3",
	},
	ObsidianAxe = {
		length = 3.9,
		handleColor = "#3A3548",
		handleMaterial = "Glass",
		gripColor = "#2A2436",
		gripMaterial = "Leather",
		shape = "facets",
		head = Vector3.new(0.3, 1.6, 1.6),
		headColor = "#1D1A24",
		headMaterial = "Glass",
		trim = "violetEdge",
	},
	InfernoAxe = {
		length = 4.0,
		handleColor = "#3A2A24",
		handleMaterial = "Basalt",
		gripColor = "#2A1C18",
		gripMaterial = "Basalt",
		shape = "flame",
		head = Vector3.new(0.3, 1.6, 1.7),
		headColor = "#FF6A1A",
		headMaterial = "Neon",
		trim = "none",
	},
	StarfallAxe = {
		length = 4.2,
		handleColor = "#F2E6C8",
		handleMaterial = "Wood",
		gripColor = "#D4C4A4",
		gripMaterial = "Leather",
		shape = "star",
		head = Vector3.new(0.28, 1.8, 1.8),
		headColor = "#BFD8FF",
		headMaterial = "Neon",
		trim = "none",
	},
	-- Design length 4.0. Gameplay Handle is 3.5 (see GameplayLength).
	LuxAxe = {
		length = 4.0,
		handleColor = "#F2D36B",
		handleMaterial = "Metal",
		gripColor = "#C9A24A", -- Brass
		gripMaterial = "Metal",
		shape = "fan",
		head = Vector3.new(0.25, 1.6, 1.6),
		headColor = "#F2D36B",
		headMaterial = "Metal",
		trim = "none",
	},
	HermitsMaul = {
		length = 3.6,
		handleColor = "#5A4632",
		handleMaterial = "Wood",
		gripColor = "#6B5340",
		gripMaterial = "Fabric",
		shape = "maul",
		head = Vector3.new(0.8, 0.8, 1.2),
		headColor = "#6F7B5C",
		headMaterial = "Slate",
		trim = "rope",
	},
}

function AxeModels.Look(axeId: string): AxeLook?
	return looks[axeId]
end

-- The Handle part's length. Lux stays 3.5 so the pinned swing haft and the
-- Lux attachment offsets do not move. Every other axe uses its design length.
function AxeModels.GameplayLength(axeId: string): number
	local look = looks[axeId]
	if not look then
		return 3.2
	end
	if axeId == "LuxAxe" then
		return 3.5
	end
	return look.length
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
