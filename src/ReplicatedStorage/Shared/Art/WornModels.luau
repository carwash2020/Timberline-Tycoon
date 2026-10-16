--!strict
-- WornModels: the worn-gear meshes Connor uploaded on 16 October 2026 (all
-- Approved, thumbnails Completed): the coat and its sleeves, the heat and
-- wader boots, the cloak, the worn hardhat, the belt, the rope ladder's
-- tiles and the V2 blueprint scroll. Same Piece shape as BacklogModels.
--
-- Pure data. Every meshId is a MeshPart id read from the MeshPart inside each
-- uploaded Model (never the Model container id) and has a Rojo template under
-- ReplicatedStorage/MeshTemplates (a spec checks it). Sizes are the Blender
-- sizes, checked against the downloaded Roblox mesh data. There is no
-- TextureID: vertex colours carry the look, so whoever builds from these
-- leaves MeshPart.Color white (it multiplies the vertex colours). The scroll
-- roll is called Handle.001 inside its uploaded Model; it is the Handle piece.
-- Pieces of one asset with a Glow are two MeshParts with an id each.
--
-- GearWear places the worn pieces on the character, MiningArt the ladder,
-- BlueprintArt the scroll; an id of 0 (set only inside a spec) falls back to
-- what the game shows today.

local WornModels = {}

export type Piece = {
	name: string,
	meshId: number,
	size: Vector3,
}

export type Asset = {
	id: string,
	pieces: { Piece },
}

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local ALL: { Asset } = {
	{
		id = "CoatBody",
		pieces = {
			{ name = "Body", meshId = 115269271855313, size = V(2.36, 2.197, 1.617) },
		},
	},
	{
		id = "CoatSleeve",
		pieces = {
			{ name = "Body", meshId = 73589596256678, size = V(1.26, 1.34, 1.26) },
		},
	},
	{
		id = "HeatBoot",
		pieces = {
			{ name = "Body", meshId = 116105552771338, size = V(1.07, 1.18, 1.6) },
			{ name = "Glow", meshId = 124000816344542, size = V(1.05, 0.045, 1.51) },
		},
	},
	{
		id = "WaderBoot",
		pieces = {
			{ name = "Body", meshId = 134517002979770, size = V(1.07, 1.48, 1.605) },
		},
	},
	{
		id = "CloakWorn",
		pieces = {
			{ name = "Body", meshId = 124573428780738, size = V(3.08, 3.96, 1.89) },
			{ name = "Glow", meshId = 75740144633857, size = V(0.228, 0.24, 0.228) },
		},
	},
	{
		id = "HardhatWorn",
		pieces = {
			{ name = "Body", meshId = 98991863528912, size = V(1.832, 0.806, 2.217) },
			{ name = "Glow", meshId = 125383985331389, size = V(0.266, 0.28, 0.07) },
		},
	},
	{
		id = "GearBelt",
		pieces = {
			{ name = "Body", meshId = 114698783853944, size = V(2.12, 0.53, 1.655) },
		},
	},
	{
		id = "RopeLadderSeg",
		pieces = {
			{ name = "Body", meshId = 110300531040960, size = V(1.68, 4, 0.28) },
		},
	},
	{
		id = "RopeLadderTop",
		pieces = {
			{ name = "Body", meshId = 121098136699219, size = V(2.3, 0.74, 1.09) },
		},
	},
	{
		id = "BlueprintScrollV2",
		pieces = {
			{ name = "Handle", meshId = 119840415336807, size = V(0.628, 2.561, 0.628) },
			{ name = "Seal", meshId = 87992443568498, size = V(0.312, 0.641, 0.28) },
		},
	},
}

local BY_ID: { [string]: Asset } = {}
for _, asset in ipairs(ALL) do
	BY_ID[asset.id] = asset
end

WornModels.All = ALL

function WornModels.Get(id: string): Asset?
	return BY_ID[id]
end

-- One piece of an asset, or nil.
function WornModels.Piece(id: string, name: string): Piece?
	local asset = BY_ID[id]
	if asset then
		for _, piece in ipairs(asset.pieces) do
			if piece.name == name then
				return piece
			end
		end
	end
	return nil
end

-- Every mesh id, each once, in order.
function WornModels.MeshIds(): { number }
	local out: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, asset in ipairs(ALL) do
		for _, piece in ipairs(asset.pieces) do
			if piece.meshId ~= 0 and not seen[piece.meshId] then
				seen[piece.meshId] = true
				table.insert(out, piece.meshId)
			end
		end
	end
	return out
end

return WornModels
