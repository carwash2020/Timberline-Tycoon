--!strict
-- StumpMeshIds (T420): the 16 frustum meshes a stump is made of, uploaded as
-- Model assets (owner 5682024709, all Approved). Each model holds one
-- MeshPart; SERVER-side StumpMeshes loads it with InsertService:LoadAsset and
-- keeps one template per id. The key is the shape's top / base ratio in
-- hundredths (85 = a mesh whose top is 0.85 of its base).
-- These are Model ids (LoadAsset), never MeshIds. The inner MeshIds are not
-- readable from this repo and are deliberately not recorded here.
local StumpMeshIds = {}

StumpMeshIds.ModelIds = {
	[85] = 76905857107009,
	[86] = 94685097813522,
	[87] = 123343771533745,
	[88] = 93845189667271,
	[89] = 108828015565287,
	[90] = 120739759090309,
	[91] = 111374207405690,
	[92] = 116584617189944,
	[93] = 101140247454976,
	[94] = 136609324362355,
	[95] = 116027645604571,
	[96] = 133974979860062,
	[97] = 99850153915041,
	[98] = 91013030389376,
	[99] = 86509937305118,
	[100] = 86421668618123,
} :: { [number]: number }

-- The key for StumpLogic.Ratios[index] (index 1..16 = 0.85..1.00).
function StumpMeshIds.KeyFor(index: number): number
	return 84 + index
end

-- The model id for StumpLogic.Ratios[index].
function StumpMeshIds.IdFor(index: number): number?
	return StumpMeshIds.ModelIds[StumpMeshIds.KeyFor(index)]
end

return StumpMeshIds
