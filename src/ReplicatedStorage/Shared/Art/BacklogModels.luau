--!strict
-- BacklogModels: the Blender backlog Connor uploaded on 8 October 2026
-- (creator Elucidhealer618, all Approved): shops, boards, scenes, gear,
-- landmarks, plot furniture, plants, cave props, critters, polish pieces
-- and the two environment remakes. Same Asset/Piece shape as TownModels,
-- which falls through to Get() for an id it has no row for, so
-- TownMeshes.Dress and Adorn find these ids.
--
-- Pure data. Every meshId is a MeshPart id (never the Model asset id) and
-- has a Rojo template under ReplicatedStorage/MeshTemplates (a spec checks
-- it). Sizes are each mesh's initialSize. Collision pieces are invisible
-- shells TownMeshes ignores. Three ids are renamed so they do not clash
-- with a TownModels row: GearLantern (the held lantern), PlantBush and
-- StoreBoardV1 (the remade store board; StoreBoard stays until Connor
-- approves it). SawdustPileV2 and PathRoundV2 are the environment remakes:
-- the TownModels rows keep the old ids (rollback) until the remakes have
-- been seen in Studio.
--
-- Not uploaded, so not here, and the part builds stay: Roots, LavaRock,
-- Pumpkin, PumpkinPatch, PumpkinHat.
--
-- Townsfolk (category "npc") are owned by the NPC lane: TownModels.Get
-- does not fall through to them, so nothing dresses an NPC from here.

local BacklogModels = {}

export type Category =
	"environment"
	| "building"
	| "npc"
	| "shop"
	| "gear"
	| "landmark"
	| "furniture"
	| "plant"
	| "cave"
	| "critter"
	| "polish"

export type Piece = {
	name: string,
	meshId: number,
	size: Vector3,
}

export type Asset = {
	id: string,
	category: Category,
	modelId: number,
	pieces: { Piece },
	tris: number?,
}

local function V(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local ALL: { Asset } = {
	{
		id = "OddsAndEnds",
		category = "shop",
		modelId = 87346054543498,
		tris = 3260,
		pieces = {
			{ name = "Body", meshId = 134209350336685, size = V(20, 8.3, 16) },
			{ name = "Roof", meshId = 79646132220786, size = V(14.496, 4.171, 14.653) },
			{ name = "Glow", meshId = 115837027129147, size = V(10.821, 0.535, 0.421) },
			{ name = "Sign", meshId = 74614278711592, size = V(4.4, 1.5, 0.28) },
			{ name = "Collision", meshId = 134706544241518, size = V(13.2, 8.2, 10.85) },
		},
	},
	{
		id = "Sparkworks",
		category = "shop",
		modelId = 104140369304987,
		tris = 4244,
		pieces = {
			{ name = "Body", meshId = 115092288673826, size = V(20, 13.85, 16) },
			{ name = "Roof", meshId = 89253491911561, size = V(15.3, 4.598, 16.008) },
			{ name = "Glow", meshId = 136237303966536, size = V(15.228, 10.415, 9.655) },
			{ name = "Sign", meshId = 98827174864022, size = V(10, 9.9, 12.06) },
			{ name = "Counter", meshId = 127001968071509, size = V(7.7, 3.34, 2.2) },
			{ name = "Collision", meshId = 100145003690911, size = V(14.5, 9.2, 12.5) },
		},
	},
	{
		id = "LandOffice",
		category = "shop",
		modelId = 95881106855744,
		tris = 3712,
		pieces = {
			{ name = "Body", meshId = 78772496745017, size = V(19.24, 8.5, 15.513) },
			{ name = "Roof", meshId = 103817737726820, size = V(19.3, 5.035, 18.201) },
			{ name = "Glow", meshId = 86262296118558, size = V(18.1, 2.4, 9.348) },
			{ name = "Sign", meshId = 126773804852360, size = V(8.5, 1.8, 0.35) },
			{ name = "Counter", meshId = 113385781102272, size = V(8.2, 3.63, 2.4) },
			{ name = "Collision", meshId = 84553375315370, size = V(18.05, 8.5, 14.025) },
			{ name = "Door", meshId = 139948273690577, size = V(5.55, 6.5, 0.4) },
		},
	},
	{
		id = "GateKiosk",
		category = "shop",
		modelId = 102275825580216,
		tris = 1640,
		pieces = {
			{ name = "Body", meshId = 117388976606872, size = V(8.785, 9.8, 6.812) },
			{ name = "Roof", meshId = 109353867672873, size = V(8.7, 3.03, 8.834) },
			{ name = "Glow", meshId = 122893389339763, size = V(5.8, 2.392, 5.066) },
			{ name = "Sign", meshId = 132573909476965, size = V(5.5, 1.4, 0.28) },
			{ name = "Counter", meshId = 105659719382098, size = V(6, 3.62, 1.05) },
			{ name = "Collision", meshId = 107093865011837, size = V(8, 3.75, 6) },
		},
	},
	{
		id = "ArrivalArch",
		category = "shop",
		modelId = 81918742379248,
		tris = 808,
		pieces = {
			{ name = "Body", meshId = 134117655482234, size = V(13.2, 13.5, 2.8) },
			{ name = "Glow", meshId = 75728483758354, size = V(8.4, 0.24, 0.3) },
			{ name = "Collision", meshId = 87680918505442, size = V(12.6, 12, 2.2) },
			{ name = "Sign", meshId = 70644751185031, size = V(4.6, 1.05, 0.1) },
		},
	},
	{
		id = "PlotMapBoard",
		category = "shop",
		modelId = 79136233765523,
		tris = 296,
		pieces = {
			{ name = "Body", meshId = 81473787840519, size = V(10.3, 8.624, 1.323) },
			{ name = "Sign", meshId = 116107904222470, size = V(9.6, 5.8, 0.35) },
			{ name = "Collision", meshId = 87360284608134, size = V(9.15, 5.4, 0.55) },
			{ name = "Header", meshId = 130515347888458, size = V(8.8, 0.7, 0.06) },
		},
	},
	{
		id = "StoreBoardV1",
		category = "shop",
		modelId = 137330110579210,
		tris = 808,
		pieces = {
			{ name = "Body", meshId = 94156785923751, size = V(6.95, 8.468, 2.493) },
			{ name = "Board", meshId = 116120204594013, size = V(5.4, 7, 0.45) },
			{ name = "Glow", meshId = 125454437458874, size = V(4.76, 0.08, 0.36) },
			{ name = "Collision", meshId = 105039985040939, size = V(6.55, 7.6, 0.55) },
			{ name = "Header", meshId = 73110672314148, size = V(4.5, 0.8, 0.08) },
			{ name = "Soon", meshId = 132135042841212, size = V(4.6, 0.5, 0.06) },
		},
	},
	{
		id = "TownBoard",
		category = "shop",
		modelId = 117991720779337,
		tris = 504,
		pieces = {
			{ name = "Body", meshId = 131256761094132, size = V(14.3, 8.345, 1.436) },
			{ name = "Board", meshId = 140682390428933, size = V(13.2, 7.2, 0.4) },
			{ name = "Collision", meshId = 70813082372828, size = V(13.6, 6.5, 0.6) },
			{ name = "Header", meshId = 119341068391098, size = V(9.5, 0.95, 0.08) },
			{ name = "Footer", meshId = 99274621698903, size = V(7.6, 0.4, 0.06) },
		},
	},
	{
		id = "RobuxBox",
		category = "shop",
		modelId = 109632610317242,
		tris = 1828,
		pieces = {
			{ name = "Body", meshId = 102558370885615, size = V(2.7, 2.67, 2.76) },
			{ name = "Glow", meshId = 86925015241773, size = V(1.75, 1.25, 0.06) },
			{ name = "Badge", meshId = 83833930261493, size = V(0.9, 0.4, 0.06) },
			{ name = "Collision", meshId = 112638347681790, size = V(2.7, 2.5, 2.7) },
		},
	},
	{
		id = "RobuxTable",
		category = "shop",
		modelId = 85459153040965,
		tris = 412,
		pieces = {
			{ name = "Body", meshId = 139196466365847, size = V(10.5, 6.15, 4.21) },
			{ name = "Sign", meshId = 123080036104830, size = V(8.5, 2, 0.3) },
			{ name = "Glow", meshId = 110792829426707, size = V(7.5, 0.12, 0.1) },
			{ name = "Collision", meshId = 78939005994089, size = V(9.55, 2.5, 3.55) },
		},
	},
	{
		id = "SkyMarket",
		category = "shop",
		modelId = 99278034417209,
		tris = 1412,
		pieces = {
			{ name = "Body", meshId = 86651258065675, size = V(10, 8.03, 8) },
			{ name = "Roof", meshId = 118637472083047, size = V(8.6, 1.352, 4.391) },
			{ name = "Glow", meshId = 95198109389147, size = V(3.717, 0.8, 0.517) },
			{ name = "Sign", meshId = 94967453670286, size = V(6, 1.3, 0.25) },
		},
	},
	{
		id = "SkyTurnstile",
		category = "shop",
		modelId = 129559844759108,
		tris = 976,
		pieces = {
			{ name = "Body", meshId = 105909211026204, size = V(4.7, 6.695, 2.4) },
			{ name = "Sign", meshId = 78311847682957, size = V(4.4, 1.8, 0.22) },
			{ name = "Glow", meshId = 89771729025967, size = V(3.733, 0.533, 0.56) },
			{ name = "Collision", meshId = 90022456908524, size = V(4.25, 4, 1.05) },
		},
	},
	{
		id = "SkyForgeCourt",
		category = "shop",
		modelId = 105280552182500,
		tris = 1628,
		pieces = {
			{ name = "Body", meshId = 108675903715340, size = V(30.6, 18.45, 24.15) },
			{ name = "Glow", meshId = 72383940504722, size = V(12.5, 4.11, 5.65) },
			{ name = "Sign", meshId = 91501355731287, size = V(6, 1.4, 0.3) },
			{ name = "Collision", meshId = 96786753223274, size = V(30, 8.8, 24) },
			{ name = "Smokestack", meshId = 99805634998718, size = V(1.8, 0.6, 1.8) },
			{ name = "StarfallForge", meshId = 81308417608874, size = V(3.9, 1.35, 1.5) },
		},
	},
	{
		id = "StarfallForge",
		category = "shop",
		modelId = 96495935199595,
		tris = 932,
		pieces = {
			{ name = "Body", meshId = 107696618004849, size = V(9.25, 12.2, 8.9) },
			{ name = "Glow", meshId = 135521618096100, size = V(8.525, 3.07, 7.122) },
			{ name = "StarfallForge", meshId = 80042056154404, size = V(4.2, 1.825, 1.5) },
			{ name = "Collision", meshId = 94496010872273, size = V(8, 4, 8) },
		},
	},
	{
		id = "CloudChute",
		category = "shop",
		modelId = 84078484732171,
		tris = 640,
		pieces = {
			{ name = "Body", meshId = 116794029888908, size = V(6.506, 4.329, 14.502) },
			{ name = "Glow", meshId = 98040393802218, size = V(1.5, 0.2, 1.5) },
			{ name = "CloudChute", meshId = 113713220925181, size = V(4.6, 3.775, 4.6) },
			{ name = "Collision", meshId = 130604816145155, size = V(4.2, 3, 4.2) },
		},
	},
	{
		id = "SceneFishing",
		category = "shop",
		modelId = 122022737242512,
		tris = 464,
		pieces = {
			{ name = "Body", meshId = 114582567372796, size = V(8, 5.123, 14.216) },
			{ name = "Glow", meshId = 122779730712590, size = V(12, 0.25, 14) },
			{ name = "Stand", meshId = 107441084559523, size = V(0.4, 0.1, 0.4) },
		},
	},
	{
		id = "SceneCampfire",
		category = "shop",
		modelId = 78788016817117,
		tris = 564,
		pieces = {
			{ name = "Body", meshId = 108327183172283, size = V(6.339, 0.858, 3.909) },
			{ name = "Glow", meshId = 103107016650952, size = V(1.046, 1.256, 1.1) },
			{ name = "Embers", meshId = 110751176568445, size = V(0.8, 0.2, 0.8) },
		},
	},
	{
		id = "SceneLookout",
		category = "shop",
		modelId = 83218819122436,
		tris = 524,
		pieces = {
			{ name = "Body", meshId = 135030583556123, size = V(4.4, 9.525, 4.2) },
			{ name = "Glow", meshId = 114031106506134, size = V(0.385, 0.49, 0.385) },
			{ name = "Stand", meshId = 130383364217301, size = V(0.5, 0.1, 0.5) },
			{ name = "Collision", meshId = 140325898404965, size = V(3.2, 5.5, 3.2) },
		},
	},
	{
		id = "SceneBench",
		category = "shop",
		modelId = 78485772758007,
		tris = 476,
		pieces = {
			{ name = "Body", meshId = 129086057183848, size = V(7.675, 7, 1.5) },
			{ name = "Glow", meshId = 139894147621111, size = V(0.856, 0.856, 0.9) },
			{ name = "Stand", meshId = 99253306611423, size = V(0.4, 0.1, 0.4) },
			{ name = "Collision", meshId = 135692878016803, size = V(4.3, 2, 1.8) },
		},
	},
	{
		id = "DailyJobsBoard",
		category = "shop",
		modelId = 80894477954386,
		tris = 864,
		pieces = {
			{ name = "Body", meshId = 76643396358662, size = V(6.4, 7.923, 2.383) },
			{ name = "Board", meshId = 100898841376424, size = V(4.8, 6.4, 0.4) },
			{ name = "Glow", meshId = 110602076736025, size = V(4.151, 1.261, 1.31) },
			{ name = "Collision", meshId = 119710016614388, size = V(5.7, 7.2, 0.5) },
			{ name = "Header", meshId = 79725809382415, size = V(3.9, 0.75, 0.08) },
		},
	},
	{
		id = "Hammer",
		category = "gear",
		modelId = 113149706663857,
		tris = 360,
		pieces = {
			{ name = "Handle", meshId = 128758240506090, size = V(0.34, 3.4, 0.42) },
			{ name = "Head", meshId = 80962635344470, size = V(0.55, 0.625, 1.565) },
		},
	},
	{
		id = "HermitsMaul",
		category = "gear",
		modelId = 75722565225966,
		tris = 704,
		pieces = {
			{ name = "Handle", meshId = 80374396770009, size = V(0.36, 4.015, 0.47) },
			{ name = "Head", meshId = 102757975831227, size = V(1.25, 1.05, 2.285) },
		},
	},
	{
		id = "GearLantern",
		category = "gear",
		modelId = 104161140199363,
		tris = 328,
		pieces = {
			{ name = "Handle", meshId = 79353425288706, size = V(0.85, 1, 0.2) },
			{ name = "Glow", meshId = 117938122720328, size = V(0.78, 1, 0.78) },
			{ name = "Body", meshId = 102381577490896, size = V(1.05, 1.725, 1.05) },
		},
	},
	{
		id = "Flashlight",
		category = "gear",
		modelId = 91812981414831,
		tris = 308,
		pieces = {
			{ name = "Handle", meshId = 131058612496766, size = V(0.618, 1.7, 0.684) },
			{ name = "Glow", meshId = 96000470070085, size = V(0.734, 0.734, 0.12) },
			{ name = "Head", meshId = 108840558722908, size = V(0.869, 0.869, 1.595) },
		},
	},
	{
		id = "InsulatedCoat",
		category = "gear",
		modelId = 118177243223273,
		tris = 620,
		pieces = {
			{ name = "Body", meshId = 99030148403072, size = V(2.95, 3.35, 1.225) },
		},
	},
	{
		id = "HeatBoots",
		category = "gear",
		modelId = 116035819865726,
		tris = 312,
		pieces = {
			{ name = "Body", meshId = 139085752917781, size = V(2.35, 1.83, 1.55) },
			{ name = "Glow", meshId = 107828580898545, size = V(1.9, 0.06, 0.7) },
		},
	},
	{
		id = "FeatherfallCloak",
		category = "gear",
		modelId = 130962788840181,
		tris = 360,
		pieces = {
			{ name = "Body", meshId = 94301951001026, size = V(2.96, 3.302, 1.12) },
			{ name = "Glow", meshId = 72963108243627, size = V(0.247, 0.247, 0.26) },
		},
	},
	{
		id = "BlueprintScroll",
		category = "gear",
		modelId = 95867695893376,
		tris = 332,
		pieces = {
			{ name = "Handle", meshId = 109636296072947, size = V(0.628, 2.4, 0.628) },
			{ name = "Body", meshId = 74357384095782, size = V(0.4, 1.389, 0.693) },
		},
	},
	{
		id = "RustyPick",
		category = "gear",
		modelId = 129227857507214,
		tris = 472,
		pieces = {
			{ name = "Handle", meshId = 105028300980340, size = V(0.36, 3.1, 0.468) },
			{ name = "Head", meshId = 87523010178135, size = V(0.62, 0.765, 2.52) },
		},
	},
	{
		id = "CopperPick",
		category = "gear",
		modelId = 81943049207152,
		tris = 484,
		pieces = {
			{ name = "Handle", meshId = 105684843340556, size = V(0.36, 3.2, 0.468) },
			{ name = "Head", meshId = 133603878799706, size = V(0.62, 0.765, 2.52) },
		},
	},
	{
		id = "IronPick",
		category = "gear",
		modelId = 131711112261525,
		tris = 472,
		pieces = {
			{ name = "Handle", meshId = 121747924685864, size = V(0.36, 3.3, 0.468) },
			{ name = "Head", meshId = 117562419344378, size = V(0.62, 0.765, 2.52) },
		},
	},
	{
		id = "SteelPick",
		category = "gear",
		modelId = 129694910218615,
		tris = 484,
		pieces = {
			{ name = "Handle", meshId = 135270678953453, size = V(0.36, 3.4, 0.468) },
			{ name = "Head", meshId = 136193135895490, size = V(0.62, 0.765, 2.52) },
		},
	},
	{
		id = "ObsidianPick",
		category = "gear",
		modelId = 92469218080617,
		tris = 568,
		pieces = {
			{ name = "Handle", meshId = 88665935127147, size = V(0.36, 3.5, 0.468) },
			{ name = "Head", meshId = 77231848849564, size = V(0.62, 0.765, 2.52) },
			{ name = "Glow", meshId = 110163416002602, size = V(0.19, 0.19, 2.17) },
		},
	},
	{
		id = "LuxPickaxe",
		category = "gear",
		modelId = 105601702247548,
		tris = 708,
		pieces = {
			{ name = "Handle", meshId = 104949822715453, size = V(0.36, 3.5, 0.468) },
			{ name = "Head", meshId = 98084182336127, size = V(0.62, 0.765, 2.52) },
			{ name = "Glow", meshId = 105993586617472, size = V(0.611, 0.19, 2.38) },
		},
	},
	{
		id = "Bomb",
		category = "gear",
		modelId = 104527724916959,
		tris = 668,
		pieces = {
			{ name = "Body", meshId = 109864822627480, size = V(0.927, 2.267, 0.927) },
			{ name = "Glow", meshId = 92319610374793, size = V(0.266, 0.27, 0.28) },
		},
	},
	{
		id = "MinersLamp",
		category = "gear",
		modelId = 133312615758320,
		tris = 404,
		pieces = {
			{ name = "Handle", meshId = 81174118074271, size = V(0.56, 1.098, 0.08) },
			{ name = "Glow", meshId = 76845085416891, size = V(0.304, 0.304, 0.32) },
			{ name = "Body", meshId = 75478470775678, size = V(0.85, 1.728, 0.736) },
		},
	},
	{
		id = "Hardhat",
		category = "gear",
		modelId = 104557996174332,
		tris = 320,
		pieces = {
			{ name = "Body", meshId = 121407216252628, size = V(1.7, 1.617, 2.05) },
			{ name = "Glow", meshId = 127352293750670, size = V(0.3, 0.22, 0.08) },
		},
	},
	{
		id = "RopeLadder",
		category = "gear",
		modelId = 137788544607319,
		tris = 704,
		pieces = {
			{ name = "Body", meshId = 110848980352540, size = V(1.6, 3.919, 0.329) },
		},
	},
	{
		id = "WaderBoots",
		category = "gear",
		modelId = 114779729471662,
		tris = 400,
		pieces = {
			{ name = "Body", meshId = 132321327313387, size = V(2.55, 2.615, 1.75) },
		},
	},
	{
		id = "FerryBoat",
		category = "landmark",
		modelId = 118691414817608,
		tris = 1828,
		pieces = {
			{ name = "Body", meshId = 135358310091964, size = V(14.9, 13.275, 22.85) },
			{ name = "Deck", meshId = 77146455540069, size = V(14, 1.05, 22) },
			{ name = "Glow", meshId = 96785932160215, size = V(2.2, 8.023, 13.25) },
			{ name = "Collision", meshId = 133378287945843, size = V(14, 1, 22) },
			{ name = "Sign", meshId = 93285981053581, size = V(4, 0.75, 0.08) },
		},
	},
	{
		id = "GondolaCabin",
		category = "landmark",
		modelId = 94800364245763,
		tris = 1084,
		pieces = {
			{ name = "Body", meshId = 77940479943185, size = V(5.5, 7.475, 5.5) },
			{ name = "Floor", meshId = 99257592752971, size = V(5, 0.44, 5) },
			{ name = "Glow", meshId = 74891227826759, size = V(0.418, 4.03, 1.768) },
			{ name = "Collision", meshId = 111797988740786, size = V(5, 0.4, 5) },
			{ name = "Sign", meshId = 105705224657483, size = V(1.9, 0.5, 0.06) },
		},
	},
	{
		id = "TollBooth",
		category = "landmark",
		modelId = 81512883922884,
		tris = 1372,
		pieces = {
			{ name = "Body", meshId = 133971115958278, size = V(10.64, 8, 8.72) },
			{ name = "Roof", meshId = 83298423440658, size = V(12.1, 3.51, 12.58) },
			{ name = "Glow", meshId = 97893069221381, size = V(9.5, 2.252, 5.648) },
			{ name = "Counter", meshId = 131229691034458, size = V(6.2, 3.13, 1.2) },
			{ name = "Collision", meshId = 94445933320672, size = V(10, 4, 8) },
			{ name = "Sign", meshId = 110551224889586, size = V(5.5, 1.4, 0.3) },
		},
	},
	{
		id = "TollBridge",
		category = "landmark",
		modelId = 124947458675801,
		tris = 5096,
		pieces = {
			{ name = "Body", meshId = 114109161609787, size = V(27.6, 24.475, 52.4) },
			{ name = "Deck", meshId = 131969385583590, size = V(28, 1.045, 52) },
			{ name = "Glow", meshId = 117911329341245, size = V(23.971, 0.472, 49.571) },
			{ name = "Collision", meshId = 132686325837050, size = V(28, 1, 52) },
			{ name = "BarrierArm", meshId = 122625399336640, size = V(24.85, 1.625, 0.85) },
			{ name = "Sign", meshId = 108668359696033, size = V(1.3, 0.75, 0.06) },
		},
	},
	{
		id = "FerryDock",
		category = "landmark",
		modelId = 71359642429577,
		tris = 1824,
		pieces = {
			{ name = "Body", meshId = 102735153307485, size = V(18.45, 8.257, 10.315) },
			{ name = "Deck", meshId = 99070033171378, size = V(16, 1.045, 10) },
			{ name = "Glow", meshId = 110512450656767, size = V(10.421, 0.535, 0.421) },
			{ name = "Collision", meshId = 120282461669646, size = V(16, 1, 10) },
			{ name = "Sign", meshId = 127282626202893, size = V(4.5, 1.2, 0.25) },
		},
	},
	{
		id = "BaitShack",
		category = "landmark",
		modelId = 132853575430513,
		tris = 1916,
		pieces = {
			{ name = "Body", meshId = 112522495053194, size = V(11.6, 15.3, 13.223) },
			{ name = "Deck", meshId = 105952606894934, size = V(12, 0.945, 10) },
			{ name = "Glow", meshId = 114414665368552, size = V(0.396, 0.504, 0.396) },
			{ name = "Sign", meshId = 70911704509629, size = V(5, 1.4, 0.28) },
			{ name = "Collision", meshId = 132721462488589, size = V(12, 0.9, 10) },
		},
	},
	{
		id = "Boardwalk",
		category = "landmark",
		modelId = 73392169415316,
		tris = 1644,
		pieces = {
			{ name = "Body", meshId = 96308244638167, size = V(7.65, 6.965, 19) },
			{ name = "Deck", meshId = 113178348568781, size = V(8, 0.74, 20) },
			{ name = "Glow", meshId = 72936114739846, size = V(0.346, 0.441, 18.347) },
			{ name = "Collision", meshId = 83011174300994, size = V(8, 0.7, 20) },
		},
	},
	{
		id = "MesaArch",
		category = "landmark",
		modelId = 84098994453968,
		tris = 652,
		pieces = {
			{ name = "Body", meshId = 127503513295771, size = V(19.815, 17.6, 8.134) },
			{ name = "Collision", meshId = 104327515655265, size = V(18, 16, 6) },
		},
	},
	{
		id = "Overlook",
		category = "landmark",
		modelId = 113459063890847,
		tris = 964,
		pieces = {
			{ name = "Body", meshId = 101531004804138, size = V(11.5, 5.275, 9.5) },
			{ name = "Deck", meshId = 118816703309862, size = V(10, 0.845, 8) },
			{ name = "Glow", meshId = 107520790116080, size = V(0.5, 0.2, 0.08) },
			{ name = "Collision", meshId = 76626325648019, size = V(10, 0.8, 8) },
		},
	},
	{
		id = "QuarryFace",
		category = "landmark",
		modelId = 89030351893698,
		tris = 1188,
		pieces = {
			{ name = "Body", meshId = 100471879936497, size = V(30, 14.775, 19.5) },
			{ name = "Collision", meshId = 107163125526338, size = V(30, 14, 20) },
		},
	},
	{
		id = "Skyroot",
		category = "landmark",
		modelId = 107227549552559,
		tris = 2152,
		pieces = {
			{ name = "Trunk", meshId = 108342352135749, size = V(40.754, 106.925, 42.766) },
			{ name = "Roots", meshId = 73494413388533, size = V(61.558, 20.874, 72.527) },
			{ name = "Limbs", meshId = 90992472435134, size = V(43.536, 19.847, 43.399) },
			{ name = "Leaves", meshId = 89500092934472, size = V(72.644, 30.863, 69.915) },
			{ name = "Glow", meshId = 88607294820837, size = V(3.463, 4.763, 3.5) },
			{ name = "Collision", meshId = 116914652995358, size = V(84, 130, 84) },
		},
	},
	{
		id = "Isle",
		category = "landmark",
		modelId = 99016700753351,
		tris = 948,
		pieces = {
			{ name = "Body", meshId = 139470746526812, size = V(53.56, 23.67, 53.558) },
			{ name = "Glow", meshId = 75385407140215, size = V(18.7, 2.4, 16.7) },
			{ name = "Collision", meshId = 130851447598022, size = V(48.4, 29.3, 48.4) },
		},
	},
	{
		id = "Waterfall",
		category = "landmark",
		modelId = 111060278304934,
		tris = 2179,
		pieces = {
			{ name = "Body", meshId = 95639903741116, size = V(41.318, 30.295, 42) },
			{ name = "Glow", meshId = 119728373947198, size = V(10, 20.943, 5.31) },
		},
	},
	{
		id = "CloudBank",
		category = "landmark",
		modelId = 111842190749365,
		tris = 756,
		pieces = {
			{ name = "Body", meshId = 103874934746074, size = V(37.083, 14.484, 18.822) },
		},
	},
	{
		id = "LanternPost",
		category = "landmark",
		modelId = 115997117758639,
		tris = 196,
		pieces = {
			{ name = "Body", meshId = 114314499092342, size = V(2.761, 6.774, 1.8) },
			{ name = "LanternGlow", meshId = 108807919188363, size = V(0.55, 0.7, 0.55) },
		},
	},
	{
		id = "Hermit",
		category = "npc",
		modelId = 117950157265469,
		tris = 1284,
		pieces = {
			{ name = "LeftFoot", meshId = 108899795373711, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftLowerLeg", meshId = 99393445428746, size = V(0.88, 0.8, 0.9) },
			{ name = "LeftUpperLeg", meshId = 73394404028122, size = V(0.94, 0.88, 0.96) },
			{ name = "RightFoot", meshId = 103456868450008, size = V(0.96, 0.4, 1.22) },
			{ name = "RightLowerLeg", meshId = 70563567930935, size = V(0.88, 0.8, 0.9) },
			{ name = "RightUpperLeg", meshId = 106355971282324, size = V(0.94, 0.88, 0.96) },
			{ name = "LowerTorso", meshId = 115152265122543, size = V(1.98, 0.55, 1.05) },
			{ name = "UpperTorso", meshId = 128610487558683, size = V(1.96, 1.54, 1.04) },
			{ name = "LeftUpperArm", meshId = 110709251982656, size = V(0.9, 0.98, 0.92) },
			{ name = "LeftLowerArm", meshId = 87365035463600, size = V(0.84, 0.86, 0.86) },
			{ name = "LeftHand", meshId = 126406813811830, size = V(0.78, 0.42, 0.78) },
			{ name = "RightUpperArm", meshId = 135678465005698, size = V(0.9, 0.98, 0.92) },
			{ name = "RightLowerArm", meshId = 96769907952542, size = V(0.84, 0.86, 0.86) },
			{ name = "RightHand", meshId = 95497067472330, size = V(0.78, 0.42, 0.78) },
			{ name = "Head", meshId = 139117165864827, size = V(1.52, 2.35, 1.82) },
			{ name = "Carry", meshId = 95166951515260, size = V(0.562, 1.318, 0.562) },
			{ name = "Glow", meshId = 77999129021080, size = V(0.412, 0.525, 0.413) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
		},
	},
	{
		id = "OldTolly",
		category = "npc",
		modelId = 78111085461995,
		tris = 1460,
		pieces = {
			{ name = "LeftFoot", meshId = 133995968834980, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftLowerLeg", meshId = 136863174482027, size = V(0.88, 0.8, 0.9) },
			{ name = "LeftUpperLeg", meshId = 119519123256991, size = V(0.94, 0.88, 0.96) },
			{ name = "RightFoot", meshId = 104473520254195, size = V(0.96, 0.4, 1.22) },
			{ name = "RightLowerLeg", meshId = 136548791296416, size = V(0.88, 0.8, 0.9) },
			{ name = "RightUpperLeg", meshId = 125183219391322, size = V(0.94, 0.88, 0.96) },
			{ name = "LowerTorso", meshId = 118466074957946, size = V(1.98, 0.55, 1.05) },
			{ name = "UpperTorso", meshId = 123494831979923, size = V(2.05, 1.565, 1.14) },
			{ name = "LeftUpperArm", meshId = 88039245062397, size = V(0.9, 0.98, 0.92) },
			{ name = "LeftLowerArm", meshId = 109401506247507, size = V(0.84, 0.86, 0.86) },
			{ name = "LeftHand", meshId = 123664690789129, size = V(0.78, 0.42, 0.78) },
			{ name = "RightUpperArm", meshId = 93376008206834, size = V(0.9, 0.98, 0.92) },
			{ name = "RightLowerArm", meshId = 94038624086116, size = V(0.84, 0.86, 0.86) },
			{ name = "RightHand", meshId = 100021606278339, size = V(0.78, 0.42, 0.78) },
			{ name = "Head", meshId = 118330932492159, size = V(1.52, 1.7, 1.75) },
			{ name = "Carry", meshId = 73996108186259, size = V(0.135, 1.287, 1.089) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
		},
	},
	{
		id = "CapnMoss",
		category = "npc",
		modelId = 84930404514317,
		tris = 1524,
		pieces = {
			{ name = "LeftFoot", meshId = 131369134603017, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftLowerLeg", meshId = 136745873348670, size = V(0.88, 0.8, 0.9) },
			{ name = "LeftUpperLeg", meshId = 118397888833590, size = V(0.94, 0.88, 1.02) },
			{ name = "RightFoot", meshId = 86451710141768, size = V(0.96, 0.4, 1.22) },
			{ name = "RightLowerLeg", meshId = 106100433848173, size = V(0.88, 0.8, 0.9) },
			{ name = "RightUpperLeg", meshId = 127325184257732, size = V(0.94, 0.88, 1.02) },
			{ name = "LowerTorso", meshId = 130572611088526, size = V(2.18, 0.55, 1.25) },
			{ name = "UpperTorso", meshId = 130632339470454, size = V(2.18, 1.54, 1.365) },
			{ name = "LeftUpperArm", meshId = 109310136243630, size = V(0.92, 0.98, 0.94) },
			{ name = "LeftLowerArm", meshId = 105240396364735, size = V(0.86, 0.86, 0.88) },
			{ name = "LeftHand", meshId = 97053488051027, size = V(0.78, 0.42, 0.78) },
			{ name = "RightUpperArm", meshId = 116132970703645, size = V(0.92, 0.98, 0.94) },
			{ name = "RightLowerArm", meshId = 135095997060933, size = V(0.86, 0.86, 0.88) },
			{ name = "RightHand", meshId = 75450038812849, size = V(0.78, 0.42, 0.78) },
			{ name = "Head", meshId = 75227647995560, size = V(1.53, 2.52, 1.79) },
			{ name = "Carry", meshId = 79475015654168, size = V(0.562, 1.318, 0.562) },
			{ name = "Glow", meshId = 111275669593597, size = V(0.412, 0.525, 0.413) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
		},
	},
	{
		id = "OldHank",
		category = "npc",
		modelId = 101958118399557,
		tris = 1584,
		pieces = {
			{ name = "LeftFoot", meshId = 119351101193720, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftLowerLeg", meshId = 125090960738705, size = V(0.88, 0.8, 0.9) },
			{ name = "LeftUpperLeg", meshId = 99615933892996, size = V(0.94, 0.88, 0.96) },
			{ name = "RightFoot", meshId = 135014855749918, size = V(0.96, 0.4, 1.22) },
			{ name = "RightLowerLeg", meshId = 108682762615720, size = V(0.88, 0.8, 0.9) },
			{ name = "RightUpperLeg", meshId = 75951220665491, size = V(0.94, 0.88, 0.96) },
			{ name = "LowerTorso", meshId = 96829973485986, size = V(1.94, 0.575, 1.03) },
			{ name = "UpperTorso", meshId = 132022758246041, size = V(1.98, 1.54, 1.14) },
			{ name = "LeftUpperArm", meshId = 110119091605663, size = V(0.92, 0.98, 0.94) },
			{ name = "LeftLowerArm", meshId = 72339417403304, size = V(0.92, 0.88, 0.94) },
			{ name = "LeftHand", meshId = 97266961506672, size = V(0.78, 0.42, 0.78) },
			{ name = "RightUpperArm", meshId = 82992979071507, size = V(0.92, 0.98, 0.94) },
			{ name = "RightLowerArm", meshId = 112484360265753, size = V(0.92, 0.88, 0.94) },
			{ name = "RightHand", meshId = 111198994880257, size = V(0.78, 0.42, 0.78) },
			{ name = "Head", meshId = 83479460212876, size = V(2.1, 2.555, 2.093) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
		},
	},
	{
		id = "Foreman",
		category = "npc",
		modelId = 88871748192723,
		tris = 1588,
		pieces = {
			{ name = "LeftFoot", meshId = 108899795373711, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftLowerLeg", meshId = 116945747529420, size = V(0.88, 0.8, 0.9) },
			{ name = "LeftUpperLeg", meshId = 138351067092204, size = V(0.94, 0.88, 1.02) },
			{ name = "RightFoot", meshId = 103456868450008, size = V(0.96, 0.4, 1.22) },
			{ name = "RightLowerLeg", meshId = 121830555377684, size = V(0.88, 0.8, 0.9) },
			{ name = "RightUpperLeg", meshId = 102282964304879, size = V(0.94, 0.88, 1.02) },
			{ name = "LowerTorso", meshId = 134823406506092, size = V(2.18, 0.55, 1.25) },
			{ name = "UpperTorso", meshId = 75529765177317, size = V(2.25, 1.565, 1.45) },
			{ name = "LeftUpperArm", meshId = 75257765340794, size = V(0.9, 0.98, 0.92) },
			{ name = "LeftLowerArm", meshId = 124235705676246, size = V(0.92, 0.88, 0.94) },
			{ name = "LeftHand", meshId = 136235655596263, size = V(0.78, 0.42, 0.78) },
			{ name = "RightUpperArm", meshId = 131913153253109, size = V(0.9, 0.98, 0.92) },
			{ name = "RightLowerArm", meshId = 107634880266597, size = V(0.92, 0.88, 0.94) },
			{ name = "RightHand", meshId = 139963921669547, size = V(0.78, 0.42, 0.78) },
			{ name = "Head", meshId = 85852295330382, size = V(1.96, 1.955, 1.864) },
			{ name = "Carry", meshId = 136502032652322, size = V(0.135, 1.287, 1.089) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
		},
	},
	{
		id = "Table",
		category = "furniture",
		modelId = 113456956518271,
		tris = 412,
		pieces = {
			{ name = "Body", meshId = 139774804414589, size = V(6.5, 2.77, 3.4) },
			{ name = "Collision", meshId = 86593787303451, size = V(6.5, 2.9, 3.4) },
		},
	},
	{
		id = "Chair",
		category = "furniture",
		modelId = 110133265590338,
		tris = 484,
		pieces = {
			{ name = "Body", meshId = 125875464823291, size = V(1.8, 3.46, 1.8) },
			{ name = "Collision", meshId = 119959987691680, size = V(1.9, 3.4, 1.9) },
		},
	},
	{
		id = "Bookshelf",
		category = "furniture",
		modelId = 84395434320452,
		tris = 1104,
		pieces = {
			{ name = "Body", meshId = 97209780941696, size = V(4.3, 6.76, 1.7) },
			{ name = "Collision", meshId = 103097315376133, size = V(4, 6.5, 1.5) },
		},
	},
	{
		id = "FirePit",
		category = "furniture",
		modelId = 78004273824501,
		tris = 700,
		pieces = {
			{ name = "Body", meshId = 109788425578854, size = V(4.05, 0.925, 3.743) },
			{ name = "Glow", meshId = 98380033067395, size = V(0.966, 0.856, 0.9) },
			{ name = "Collision", meshId = 139848678300469, size = V(4, 1.2, 4) },
		},
	},
	{
		id = "Rug",
		category = "furniture",
		modelId = 83859721822313,
		tris = 148,
		pieces = {
			{ name = "Body", meshId = 135002055793161, size = V(5.5, 0.105, 3.5) },
			{ name = "Collision", meshId = 128381813731256, size = V(5.5, 0.12, 3.5) },
		},
	},
	{
		id = "CopperTrim4",
		category = "furniture",
		modelId = 76010340890213,
		tris = 508,
		pieces = {
			{ name = "Body", meshId = 87662133874242, size = V(4.04, 0.73, 0.465) },
			{ name = "Collision", meshId = 107578389866463, size = V(4, 0.75, 0.42) },
		},
	},
	{
		id = "SandWall4",
		category = "furniture",
		modelId = 132329587017208,
		tris = 1212,
		pieces = {
			{ name = "Body", meshId = 120649476858651, size = V(4.1, 6.637, 0.65) },
			{ name = "Collision", meshId = 120222074894042, size = V(4, 6.2, 0.65) },
		},
	},
	{
		id = "SandFloor4",
		category = "furniture",
		modelId = 83790455645726,
		tris = 748,
		pieces = {
			{ name = "Body", meshId = 81608834142851, size = V(4.05, 0.32, 4.05) },
			{ name = "Collision", meshId = 84004527018302, size = V(4, 0.35, 4) },
		},
	},
	{
		id = "SandArch8",
		category = "furniture",
		modelId = 128991531246506,
		tris = 308,
		pieces = {
			{ name = "Body", meshId = 140489088509915, size = V(8.3, 7.675, 1.4) },
			{ name = "Collision", meshId = 98819012626829, size = V(8.2, 7.5, 1.4) },
		},
	},
	{
		id = "CopperLampPost",
		category = "furniture",
		modelId = 78902712984951,
		tris = 308,
		pieces = {
			{ name = "Body", meshId = 124784990586746, size = V(1.4, 7.075, 2.5) },
			{ name = "Glow", meshId = 132487348702598, size = V(0.5, 0.7, 0.5) },
			{ name = "Collision", meshId = 76773422658178, size = V(1.5, 7.2, 2.5) },
		},
	},
	{
		id = "GoldChest",
		category = "furniture",
		modelId = 103518511557409,
		tris = 496,
		pieces = {
			{ name = "Body", meshId = 88455877414840, size = V(3.35, 2.68, 2.225) },
			{ name = "Glow", meshId = 102865664028561, size = V(0.2, 0.2, 0.06) },
			{ name = "Collision", meshId = 120579624154805, size = V(3.4, 2.6, 2.2) },
		},
	},
	{
		id = "Fern",
		category = "plant",
		modelId = 88011142063407,
		tris = 1292,
		pieces = {
			{ name = "Body", meshId = 74918015519464, size = V(5.03, 2.167, 4.39) },
		},
	},
	{
		id = "Flowers",
		category = "plant",
		modelId = 76597855062929,
		tris = 2780,
		pieces = {
			{ name = "Body", meshId = 114587191348049, size = V(2.6, 1.772, 2.664) },
		},
	},
	{
		id = "Mushroom",
		category = "plant",
		modelId = 86008633645263,
		tris = 300,
		pieces = {
			{ name = "Body", meshId = 90826690575214, size = V(2.85, 1.554, 2.212) },
		},
	},
	{
		id = "Reeds",
		category = "plant",
		modelId = 101812988590883,
		tris = 768,
		pieces = {
			{ name = "Body", meshId = 133209216446504, size = V(2.339, 5.784, 1.894) },
		},
	},
	{
		id = "SnowShrub",
		category = "plant",
		modelId = 84640493079472,
		tris = 2456,
		pieces = {
			{ name = "Body", meshId = 93422740508112, size = V(2.836, 2.241, 3.085) },
		},
	},
	{
		id = "AshShrub",
		category = "plant",
		modelId = 78437608933369,
		tris = 940,
		pieces = {
			{ name = "Body", meshId = 100337996858153, size = V(3.15, 2.379, 2.689) },
		},
	},
	{
		id = "GloamCap",
		category = "plant",
		modelId = 97377139821945,
		tris = 192,
		pieces = {
			{ name = "Body", meshId = 137619479957013, size = V(1.753, 1.5, 0.774) },
			{ name = "Glow", meshId = 104659676938563, size = V(2.55, 1.245, 1.784) },
		},
	},
	{
		id = "IsleCrystal",
		category = "plant",
		modelId = 85908807708848,
		tris = 176,
		pieces = {
			{ name = "Body", meshId = 123860255578817, size = V(1.8, 0.4, 1.6) },
			{ name = "Glow", meshId = 100291417102422, size = V(1.67, 2.442, 1.075) },
		},
	},
	{
		id = "BerryBush",
		category = "plant",
		modelId = 98489146931221,
		tris = 592,
		pieces = {
			{ name = "Body", meshId = 103023167341006, size = V(3.888, 2.827, 2.739) },
		},
	},
	{
		id = "Cattails",
		category = "plant",
		modelId = 114372934748723,
		tris = 476,
		pieces = {
			{ name = "Body", meshId = 108507071051929, size = V(1.833, 6.325, 1.464) },
		},
	},
	{
		id = "LilyPad",
		category = "plant",
		modelId = 75755418189641,
		tris = 328,
		pieces = {
			{ name = "Body", meshId = 113850122202081, size = V(4.735, 0.429, 3.122) },
		},
	},
	{
		id = "GrassTuft",
		category = "plant",
		modelId = 114748601662213,
		tris = 224,
		pieces = {
			{ name = "Body", meshId = 130394084612742, size = V(1.024, 1.508, 1.107) },
		},
	},
	{
		id = "PlantBush",
		category = "plant",
		modelId = 90839848475136,
		tris = 164,
		pieces = {
			{ name = "Body", meshId = 93846701857732, size = V(4.372, 3.168, 3.621) },
		},
	},
	{
		id = "CaveMushroom",
		category = "cave",
		modelId = 135004307264114,
		tris = 300,
		pieces = {
			{ name = "Body", meshId = 103468832922040, size = V(3.25, 1.75, 2.402) },
		},
	},
	{
		id = "GlowFungus",
		category = "cave",
		modelId = 125528517070685,
		tris = 224,
		pieces = {
			{ name = "Body", meshId = 85578615407128, size = V(1.743, 1.2, 1.357) },
			{ name = "Glow", meshId = 71241397054697, size = V(2.436, 0.99, 1.979) },
		},
	},
	{
		id = "CrystalRock",
		category = "cave",
		modelId = 84737376455954,
		tris = 476,
		pieces = {
			{ name = "Body", meshId = 117640608002283, size = V(2.8, 1.2, 2.4) },
			{ name = "Glow", meshId = 75201326674288, size = V(1.575, 2.916, 1.263) },
		},
	},
	{
		id = "DeadBranch",
		category = "cave",
		modelId = 72669352058147,
		tris = 244,
		pieces = {
			{ name = "Body", meshId = 123401667712559, size = V(5.454, 0.802, 1.03) },
		},
	},
	{
		id = "Pinecones",
		category = "cave",
		modelId = 75004140654008,
		tris = 4260,
		pieces = {
			{ name = "Body", meshId = 97551603537708, size = V(3.187, 1.525, 1.403) },
		},
	},
	{
		id = "SnowPile",
		category = "cave",
		modelId = 85472731567593,
		tris = 112,
		pieces = {
			{ name = "Body", meshId = 76985446125396, size = V(4.737, 1.17, 4.468) },
		},
	},
	{
		id = "Pebbles",
		category = "cave",
		modelId = 136577821233988,
		tris = 352,
		pieces = {
			{ name = "Body", meshId = 131084239678885, size = V(1.55, 0.326, 2.123) },
		},
	},
	{
		id = "MushroomRing",
		category = "cave",
		modelId = 104447031904897,
		tris = 560,
		pieces = {
			{ name = "Body", meshId = 138247788482374, size = V(5.259, 1.187, 5.162) },
		},
	},
	{
		id = "LanternPods",
		category = "cave",
		modelId = 79578329915552,
		tris = 908,
		pieces = {
			{ name = "Body", meshId = 87898792301461, size = V(1.611, 1.529, 1.006) },
			{ name = "Glow", meshId = 121371703595548, size = V(1.903, 1.592, 1.615) },
		},
	},
	{
		id = "Deer",
		category = "critter",
		modelId = 117243761111808,
		tris = 688,
		pieces = {
			{ name = "Body", meshId = 79108248618120, size = V(1.476, 3.935, 3.625) },
		},
	},
	{
		id = "Rabbit",
		category = "critter",
		modelId = 91203695149877,
		tris = 460,
		pieces = {
			{ name = "Body", meshId = 87171895585431, size = V(0.9, 1.95, 1.805) },
		},
	},
	{
		id = "Bird",
		category = "critter",
		modelId = 117041476587781,
		tris = 352,
		pieces = {
			{ name = "Body", meshId = 71777505504536, size = V(1.878, 0.85, 1.55) },
		},
	},
	{
		id = "Duck",
		category = "critter",
		modelId = 87641383801076,
		tris = 264,
		pieces = {
			{ name = "Body", meshId = 114985462022222, size = V(0.85, 1.375, 2.025) },
		},
	},
	{
		id = "Fish",
		category = "critter",
		modelId = 117807208696788,
		tris = 240,
		pieces = {
			{ name = "Body", meshId = 104854700959373, size = V(0.55, 1.04, 2.15) },
		},
	},
	{
		id = "Butterfly",
		category = "critter",
		modelId = 72659001675855,
		tris = 576,
		pieces = {
			{ name = "Body", meshId = 137478805470153, size = V(2.8, 1.667, 1.971) },
			{ name = "Glow", meshId = 71857088551381, size = V(0.376, 0.076, 0.08) },
		},
	},
	{
		id = "Gull",
		category = "critter",
		modelId = 110925177490132,
		tris = 352,
		pieces = {
			{ name = "Body", meshId = 79726363710291, size = V(2.682, 1.075, 1.85) },
		},
	},
	{
		id = "SnowFox",
		category = "critter",
		modelId = 122571506405252,
		tris = 460,
		pieces = {
			{ name = "Body", meshId = 111185158508669, size = V(0.85, 1.9, 2.325) },
		},
	},
	{
		id = "SkyMoth",
		category = "critter",
		modelId = 133883545830725,
		tris = 858,
		pieces = {
			{ name = "Body", meshId = 90909032076412, size = V(0.892, 1.375, 3) },
			{ name = "Glow", meshId = 130398160911713, size = V(2.521, 0.532, 0.74) },
		},
	},
	{
		id = "Bat",
		category = "critter",
		modelId = 117511555850718,
		tris = 1126,
		pieces = {
			{ name = "Body", meshId = 74801226284854, size = V(2.1, 4.2, 3.314) },
		},
	},
	{
		id = "Wisp",
		category = "critter",
		modelId = 100251750442856,
		tris = 576,
		pieces = {
			{ name = "Glow", meshId = 140097031213832, size = V(1.331, 1.331, 1.92) },
		},
	},
	{
		id = "EmberSprite",
		category = "critter",
		modelId = 74326907352132,
		tris = 792,
		pieces = {
			{ name = "Glow", meshId = 77354756329353, size = V(1.141, 1.378, 1.206) },
		},
	},
	{
		id = "NameStake",
		category = "polish",
		modelId = 91656129844983,
		tris = 312,
		pieces = {
			{ name = "Body", meshId = 93356447098575, size = V(2.1, 3.05, 0.441) },
			{ name = "Glow", meshId = 120123868095989, size = V(0.247, 0.247, 0.26) },
		},
	},
	{
		id = "Sprout",
		category = "polish",
		modelId = 84941418096556,
		tris = 280,
		pieces = {
			{ name = "Body", meshId = 124388204512672, size = V(1.6, 1.578, 1.6) },
			{ name = "Glow", meshId = 74735967680857, size = V(0.418, 0.418, 0.44) },
		},
	},
	{
		id = "SeedOrb",
		category = "polish",
		modelId = 121541463939061,
		tris = 128,
		pieces = {
			{ name = "Glow", meshId = 120413308807087, size = V(0.856, 0.856, 0.9) },
		},
	},
	{
		id = "SawdustPileV2",
		category = "environment",
		modelId = 75226062773179,
		tris = 1224,
		pieces = {
			{ name = "Body", meshId = 117488161778832, size = V(5.634, 1.611, 5.434) },
		},
	},
	{
		id = "PathRoundV2",
		category = "environment",
		modelId = 109651263295891,
		tris = 472,
		pieces = {
			{ name = "Body", meshId = 116491733478344, size = V(3.4, 0.39, 3.315) },
		},
	},
}

local BY_ID: { [string]: Asset } = {}
for _, asset in ipairs(ALL) do
	BY_ID[asset.id] = asset
end

BacklogModels.All = ALL

function BacklogModels.Get(id: string): Asset?
	return BY_ID[id]
end

function BacklogModels.Ids(category: Category?): { string }
	local out: { string } = {}
	for _, asset in ipairs(ALL) do
		if category == nil or asset.category == category then
			table.insert(out, asset.id)
		end
	end
	return out
end

-- Every non-collision piece id of the given assets, each once, in order
-- (MeshManifest's preload).
function BacklogModels.MeshIds(ids: { string }): { number }
	local out: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, id in ipairs(ids) do
		local asset = BY_ID[id]
		if asset then
			for _, piece in ipairs(asset.pieces) do
				if piece.name ~= "Collision" and piece.meshId ~= 0 and not seen[piece.meshId] then
					seen[piece.meshId] = true
					table.insert(out, piece.meshId)
				end
			end
		end
	end
	return out
end

-- The assets a builder dresses today (a mesh replaces parts; the part
-- build stays when a mesh is missing). Everything else in ALL has a
-- template and a row, and waits for its builder or for a design call
-- (see the PR body); MeshManifest preloads only these.
BacklogModels.Wired = {
	"OddsAndEnds",
	"Sparkworks",
	"LandOffice",
	"GateKiosk",
	"ArrivalArch",
	"RobuxBox",
} :: { string }

return BacklogModels
