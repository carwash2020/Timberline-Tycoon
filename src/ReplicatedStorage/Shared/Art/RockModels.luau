--!strict
-- Rock meshes. meshId is the MeshPart under ReplicatedStorage.MeshTemplates,
-- the same slot pattern as AxeModels. 0 means that piece is not uploaded
-- yet: NatureArt keeps the part build and logs it.
-- Sizes are the mid part-build envelope. Replace them with the Blender
-- bounds when the mesh lands. NatureArt scales them for small and large.
-- Glow is the heartstone emissive piece only. Moss and Snow are the caps.

local RockModels = {}

export type Piece = { meshId: number, size: Vector3 }

export type RockMesh = {
	Host: Piece,
	Moss: Piece,
	Snow: Piece,
	Vein1: Piece,
	Vein2: Piece,
	Glow: Piece,
}

RockModels.Shapes = { "Boulder", "CrackedBoulder", "Spire", "Slab", "PebbleCluster", "Outcrop" }

local function piece(size: Vector3): Piece
	return { meshId = 0, size = size }
end

local function rock(host: Vector3, cap: Vector3, vein: Vector3): RockMesh
	return {
		Host = piece(host),
		Moss = piece(cap),
		Snow = piece(cap),
		Vein1 = piece(vein),
		Vein2 = piece(vein),
		Glow = piece(host),
	}
end

local cap = Vector3.new(1.4, 0.25, 0.9)
local vein = Vector3.new(0.7, 0.14, 0.45)

local rocks: { [string]: RockMesh } = {
	Boulder = rock(Vector3.new(2.6, 2.4, 2.6), cap, vein),
	CrackedBoulder = rock(Vector3.new(2.8, 2.0, 2.4), cap, vein),
	Spire = rock(Vector3.new(1.7, 2.5, 1.5), cap, vein),
	Slab = rock(Vector3.new(3.2, 0.7, 2.1), cap, vein),
	PebbleCluster = rock(Vector3.new(2.2, 1.1, 2.0), cap, vein),
	Outcrop = rock(Vector3.new(2.6, 0.9, 1.7), cap, vein),
}

function RockModels.Get(shape: string): RockMesh?
	return rocks[shape]
end

-- 0 keeps the part-built rock. A shipped id is not 0.
function RockModels.UsesMesh(meshId: number): boolean
	return type(meshId) == "number" and meshId == meshId and meshId ~= 0
end

-- Every id a rock spawns, once each, for MeshManifest. Zeros are skipped.
function RockModels.MeshIds(): { number }
	local seen: { [number]: boolean } = {}
	local ids: { number } = {}
	local function take(item: Piece)
		if item.meshId ~= 0 and not seen[item.meshId] then
			seen[item.meshId] = true
			table.insert(ids, item.meshId)
		end
	end
	for _, spec in pairs(rocks) do
		take(spec.Host)
		take(spec.Moss)
		take(spec.Snow)
		take(spec.Vein1)
		take(spec.Vein2)
		take(spec.Glow)
	end
	table.sort(ids)
	return ids
end

return RockModels
