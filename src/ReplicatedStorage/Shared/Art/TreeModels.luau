--!strict
-- Tree meshes (uploaded Models owned by Elucidhealer618, Approved).
-- meshId is the MeshPart id. The Model assetId is not used.
-- Section meshes replace the block but keep the skeleton's size.
-- Crown sizes are the uploaded bounds, in studs, for scale 1.
-- Triangle budgets (not measured here): 150 a section, 1,500 a crown.

local TreeModels = {}

export type CrownPiece = {
	name: string, -- Leaves or Facet, so wind sway still finds them
	meshId: number,
	size: Vector3,
	section: number?, -- Facet_Section_3 rides section 3 when that section exists
}

local sections: { [string]: { number } } = {
	oak = { 106240781110764, 88407278927659, 81476867108470 },
	birch = { 71890137452649, 100432331486427, 138508996721598 },
	lumenwood = { 118218058767651, 78730728517805, 112087968527199 },
	phantomwood = { 138595966323968, 82719064541664, 80876683743330 },
	frostwood = { 84833713688995, 115672468528717, 137835827026580 },
	pine = { 101559062589660, 125117420122950, 118206786010410 },
	maple = { 109577497643149, 85178015121629, 115635347945305 },
	palmwood = { 101525114127541, 94025013138140, 93227720333749 },
	emberwood = { 71905033591284, 84579932172929, 138240165712362 },
}

local crowns: { [string]: { CrownPiece } } = {
	oak = {
		{ name = "Leaves", meshId = 104687332442263, size = Vector3.new(17.031, 11.992, 22.287), section = nil },
		{ name = "Leaves", meshId = 125835772079020, size = Vector3.new(22.105, 10.455, 22.553), section = nil },
		{ name = "Leaves", meshId = 125036188202077, size = Vector3.new(18.728, 8.881, 22.93), section = nil },
	},
	birch = {
		{ name = "Leaves", meshId = 96795427613618, size = Vector3.new(9.226, 18.309, 8.293), section = nil },
		{ name = "Leaves", meshId = 101738227193301, size = Vector3.new(8.522, 17.567, 7.883), section = nil },
		{ name = "Leaves", meshId = 88798385258611, size = Vector3.new(9.265, 15.423, 9.117), section = nil },
	},
	lumenwood = {
		{ name = "Leaves", meshId = 81083955610031, size = Vector3.new(17.874, 17.117, 16.683), section = nil },
		{ name = "Leaves", meshId = 128231736630899, size = Vector3.new(17.955, 15.534, 16.574), section = nil },
		{ name = "Leaves", meshId = 91500735557872, size = Vector3.new(16.926, 13.807, 18.239), section = nil },
		{ name = "Facet", meshId = 89084974588543, size = Vector3.new(9.623, 14.688, 9.885), section = nil },
		{ name = "Facet", meshId = 85979782548399, size = Vector3.new(10.871, 13.104, 9.036), section = nil },
		{ name = "Facet", meshId = 95271263377734, size = Vector3.new(9.467, 11.377, 10.123), section = nil },
		{ name = "Facet", meshId = 134865694365483, size = Vector3.new(0.13, 2.652, 0.531), section = 3 },
	},
	phantomwood = {
		{ name = "Leaves", meshId = 78405414900273, size = Vector3.new(23.164, 15.642, 24.436), section = nil },
		{ name = "Leaves", meshId = 109113608718430, size = Vector3.new(15.144, 14.785, 27.517), section = nil },
		{ name = "Leaves", meshId = 109459775582599, size = Vector3.new(25.654, 11.303, 26.429), section = nil },
		{ name = "Facet", meshId = 98787230378648, size = Vector3.new(5.633, 1.925, 9.614), section = nil },
		{ name = "Facet", meshId = 123349059126526, size = Vector3.new(5.757, 9.088, 24.496), section = nil },
		{ name = "Facet", meshId = 135415690415895, size = Vector3.new(25.781, 2.546, 24.981), section = nil },
	},
	frostwood = {
		{ name = "Leaves", meshId = 76520784565504, size = Vector3.new(14.591, 35.48, 15.212), section = nil },
		{ name = "Leaves", meshId = 121130051862147, size = Vector3.new(14.505, 35.306, 15.217), section = nil },
		{ name = "Leaves", meshId = 79516772478629, size = Vector3.new(15.179, 36.257, 14.767), section = nil },
		{ name = "Facet", meshId = 113357125249890, size = Vector3.new(6.063, 14.83, 6.063), section = nil },
		{ name = "Facet", meshId = 81162824661955, size = Vector3.new(4.84, 14.758, 4.84), section = nil },
		{ name = "Facet", meshId = 79169836502313, size = Vector3.new(6.039, 15.152, 6.039), section = nil },
	},
	pine = {
		{ name = "Leaves", meshId = 72762101555519, size = Vector3.new(18.492, 40.544, 18.492), section = nil },
		{ name = "Leaves", meshId = 95152510866641, size = Vector3.new(16.394, 39.823, 16.394), section = nil },
		{ name = "Leaves", meshId = 93845570251227, size = Vector3.new(16.029, 41.005, 16.029), section = nil },
	},
	maple = {
		{ name = "Leaves", meshId = 107185280727328, size = Vector3.new(31.639, 12.206, 24.146), section = nil },
		{ name = "Leaves", meshId = 102331982236025, size = Vector3.new(34.214, 12.735, 18.971), section = nil },
		{ name = "Leaves", meshId = 70892980568483, size = Vector3.new(34.344, 11.89, 27.349), section = nil },
	},
	palmwood = {
		{ name = "Leaves", meshId = 138062966733596, size = Vector3.new(18.675, 7.166, 18.834), section = nil },
		{ name = "Leaves", meshId = 99575576195148, size = Vector3.new(18.998, 7.063, 19.224), section = nil },
		{ name = "Leaves", meshId = 104869702239200, size = Vector3.new(18.96, 6.833, 19.211), section = nil },
	},
	emberwood = {
		{ name = "Leaves", meshId = 128014872762728, size = Vector3.new(19.251, 9.53, 17.159), section = nil },
		{ name = "Leaves", meshId = 131703911442920, size = Vector3.new(15.914, 8.938, 22.046), section = nil },
		{ name = "Leaves", meshId = 80141114733932, size = Vector3.new(16.995, 8.443, 22.388), section = nil },
		{ name = "Facet", meshId = 78963403567540, size = Vector3.new(15.773, 5.433, 10.8), section = nil },
		{ name = "Facet", meshId = 84894878985661, size = Vector3.new(10.881, 5.217, 18.843), section = nil },
		{ name = "Facet", meshId = 95420384468440, size = Vector3.new(13.155, 5.241, 17.51), section = nil },
		{ name = "Facet", meshId = 122106124846170, size = Vector3.new(0.12, 2.448, 0.491), section = 3 },
	},
}

function TreeModels.SectionMesh(woodId: string, sectionId: number): number
	local list = sections[woodId]
	if not list or #list == 0 then
		return 0
	end
	local i = ((sectionId - 1) % #list) + 1
	return list[i]
end

function TreeModels.Crown(woodId: string): { CrownPiece }
	return crowns[woodId] or {}
end

-- Every section and crown mesh id (MeshManifest's preload), sections first.
function TreeModels.MeshIds(): { number }
	local ids: { number } = {}
	local seen: { [number]: boolean } = {}
	local function add(id: number)
		if id ~= 0 and not seen[id] then
			seen[id] = true
			table.insert(ids, id)
		end
	end
	local woods: { string } = {}
	for wood in pairs(sections) do
		table.insert(woods, wood)
	end
	table.sort(woods)
	for _, wood in ipairs(woods) do
		for _, id in ipairs(sections[wood]) do
			add(id)
		end
	end
	for _, wood in ipairs(woods) do
		for _, piece in ipairs(crowns[wood] or {}) do
			add(piece.meshId)
		end
	end
	return ids
end

function TreeModels.UsesMesh(meshId: number): boolean
	return meshId ~= 0
end

return TreeModels
