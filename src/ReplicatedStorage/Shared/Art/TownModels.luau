--!strict
-- TownModels: uploaded town meshes (environment, buildings, NPCs).
-- Sizes are each mesh's initialSize. Collision rows are ignored by
-- TownMeshes. The upload has no triangle counts, so tris is nil.

local TownModels = {}

export type Category = "environment" | "building" | "npc"

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
		id = "RockGrey",
		category = "environment",
		modelId = 85725901574422,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 124895017446055, size = V(5.634, 3.236, 3.727) },
		},
	},
	{
		id = "RockBrown",
		category = "environment",
		modelId = 90216428627951,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 114906176954403, size = V(5.966, 3.861, 4.791) },
		},
	},
	{
		id = "RockMossy",
		category = "environment",
		modelId = 93890031949806,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 96007499157338, size = V(3.961, 2.811, 3.499) },
		},
	},
	{
		id = "Bush",
		category = "environment",
		modelId = 106474795699950,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 132647270125437, size = V(3.959, 2.941, 3.32) },
		},
	},
	{
		id = "Stump",
		category = "environment",
		modelId = 123699440638928,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 139195335876549, size = V(3.226, 1.757, 3.226) },
		},
	},
	{
		id = "FallenLog",
		category = "environment",
		modelId = 78197269535311,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 138884656779084, size = V(6.899, 2.022, 1.992) },
		},
	},
	{
		id = "GlowMushrooms",
		category = "environment",
		modelId = 87739922614736,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 88481479388142, size = V(2.247, 1.343, 1.594) },
			{ name = "Glow", meshId = 85622271046056, size = V(2.139, 1.24, 1.47) },
		},
	},
	{
		id = "SawdustPile",
		category = "environment",
		modelId = 76461215877777,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 87654189754458, size = V(5.147, 1.44, 5.046) },
		},
	},
	{
		id = "PathRound",
		category = "environment",
		modelId = 72907519330768,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 123109371096027, size = V(3.091, 0.27, 3.091) },
		},
	},
	{
		id = "LampPost",
		category = "environment",
		modelId = 119153668014536,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 83918398499306, size = V(1.9, 10.625, 3.662) },
			{ name = "Collision", meshId = 131056384322053, size = V(0.8, 10.6, 0.8) },
			{ name = "LampGlow", meshId = 87504427783528, size = V(0.605, 0.77, 0.605) },
		},
	},
	{
		id = "Fence",
		category = "environment",
		modelId = 102776095396948,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 99228152972776, size = V(8.583, 3.499, 0.741) },
			{ name = "Collision", meshId = 122079815376996, size = V(8.5, 3.4, 0.7) },
		},
	},
	{
		id = "Signpost",
		category = "environment",
		modelId = 133947316728270,
		tris = nil,
		pieces = {
			{ name = "Board", meshId = 87523682880006, size = V(9, 4.4, 0.3) },
			{ name = "Body", meshId = 135928373740350, size = V(12.501, 10.1, 2.1) },
			{ name = "Collision", meshId = 71426736590879, size = V(10.6, 9.8, 0.8) },
			{ name = "Glow", meshId = 78972491879481, size = V(5.36, 0.08, 0.36) },
		},
	},
	{
		id = "SellPad",
		category = "environment",
		modelId = 122800814190149,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 89045210450121, size = V(26.1, 0.26, 20.1) },
			{ name = "SellPad", meshId = 103133226390723, size = V(24, 0.2, 17.94) },
		},
	},
	{
		id = "ParkingBay",
		category = "environment",
		modelId = 123213737659362,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 91923957383838, size = V(11, 0.04, 18) },
			{ name = "LanternGlow", meshId = 108200236177822, size = V(2.6, 0.06, 0.7) },
		},
	},
	{
		id = "LogPile",
		category = "environment",
		modelId = 81060386028455,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 111473608570682, size = V(5.15, 3.612, 5.922) },
		},
	},
	{
		id = "Crate",
		category = "environment",
		modelId = 134137103204003,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 102282482919035, size = V(2.409, 3.47, 2.452) },
		},
	},
	{
		id = "Barrel",
		category = "environment",
		modelId = 127894467938021,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 84929156961939, size = V(1.681, 2.22, 1.7) },
		},
	},
	{
		id = "Bench",
		category = "environment",
		modelId = 117264199155900,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 118925999764012, size = V(5, 3.412, 1.773) },
			{ name = "Collision", meshId = 78601687849004, size = V(5, 3.35, 1.75) },
		},
	},
	{
		id = "Well",
		category = "environment",
		modelId = 130819133439741,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 134482743397348, size = V(5.25, 5.4, 4.8) },
			{ name = "Collision", meshId = 111622442505696, size = V(5, 5.4, 4.527) },
			{ name = "Roof", meshId = 110217796170520, size = V(5.9, 2.571, 4.735) },
			{ name = "WellWater", meshId = 121403425366835, size = V(3.141, 0.1, 3.141) },
		},
	},
	{
		id = "Cart",
		category = "environment",
		modelId = 135866962601383,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 115632734637819, size = V(4.5, 3.584, 8.045) },
			{ name = "Collision", meshId = 97919227077911, size = V(4.3, 3.2, 5.2) },
		},
	},
	{
		id = "WaterTower",
		category = "environment",
		modelId = 90134156037115,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 126744027047585, size = V(6.871, 17.204, 6.239) },
			{ name = "Collision", meshId = 85784017066458, size = V(5.6, 16.7, 5.6) },
			{ name = "Roof", meshId = 78683464149744, size = V(6, 2.3, 5.706) },
		},
	},
	{
		id = "Mailbox",
		category = "environment",
		modelId = 78970416424419,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 139464974716589, size = V(1.175, 4.625, 1.77) },
			{ name = "Collision", meshId = 80269525184898, size = V(1.1, 1.1, 1.75) },
		},
	},
	{
		id = "Haybale",
		category = "environment",
		modelId = 132042499337199,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 120579076567292, size = V(2.723, 2.85, 2.774) },
		},
	},
	{
		id = "Wheelbarrow",
		category = "environment",
		modelId = 91080688852419,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 104437473223082, size = V(2.09, 2.205, 5.087) },
		},
	},
	{
		id = "ToolRack",
		category = "environment",
		modelId = 85577077494103,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 81114717507868, size = V(5.1, 4.6, 1.3) },
			{ name = "Collision", meshId = 122927328430335, size = V(4.8, 4.6, 0.5) },
		},
	},
	{
		id = "Lantern",
		category = "environment",
		modelId = 91456222951322,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 77430231533861, size = V(1, 5.105, 1.8) },
			{ name = "Glow", meshId = 137197018763785, size = V(0.44, 0.56, 0.44) },
		},
	},
	{
		id = "Planter",
		category = "environment",
		modelId = 72298139031805,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 88791806526106, size = V(2.75, 2.324, 2.75) },
		},
	},
	{
		id = "FlowerBox",
		category = "environment",
		modelId = 134201967070902,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 88157571885674, size = V(3.037, 1.001, 0.6) },
		},
	},
	{
		id = "MillBell",
		category = "environment",
		modelId = 138463622410573,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 101631149063987, size = V(1, 5.39, 1.525) },
			{ name = "Collision", meshId = 96607075043621, size = V(0.6, 5.2, 0.6) },
		},
	},
	{
		id = "RopeBridge",
		category = "environment",
		modelId = 131586620588560,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 137475826693991, size = V(7.3, 4.45, 16.8) },
			{ name = "Collision", meshId = 82151058963952, size = V(7, 2.1, 16) },
			{ name = "Deck", meshId = 89682155893512, size = V(6.482, 0.75, 16.039) },
		},
	},
	{
		id = "Footbridge",
		category = "environment",
		modelId = 87900760608810,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 108374815739635, size = V(5.3, 4.939, 14.4) },
			{ name = "Collision", meshId = 88262540650736, size = V(5.2, 2.158, 16.457) },
			{ name = "Deck", meshId = 73832096671738, size = V(4.6, 1.706, 14.092) },
		},
	},
	{
		id = "Campfire",
		category = "environment",
		modelId = 134705958760492,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 75065765379379, size = V(4.177, 1.506, 4.161) },
			{ name = "Embers", meshId = 105398150865760, size = V(1.586, 0.284, 1.36) },
			{ name = "Flame", meshId = 84294902067749, size = V(1.546, 1.756, 1.732) },
		},
	},
	{
		id = "MurphsCamp",
		category = "environment",
		modelId = 98277499129961,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 131136044406175, size = V(13.533, 5.25, 14.768) },
			{ name = "Collision", meshId = 120967515606051, size = V(13, 4.2, 10.6) },
			{ name = "Embers", meshId = 105398150865760, size = V(1.586, 0.284, 1.36) },
			{ name = "Flame", meshId = 84294902067749, size = V(1.546, 1.756, 1.732) },
			{ name = "Glow", meshId = 140048197540221, size = V(0.44, 0.56, 0.44) },
			{ name = "Sign", meshId = 124588773103657, size = V(2.231, 0.8, 1.592) },
			{ name = "Tent", meshId = 136804358591165, size = V(6.217, 4.699, 7.181) },
		},
	},
	{
		id = "StoreBoard",
		category = "environment",
		modelId = 135690050501294,
		tris = nil,
		pieces = {
			{ name = "Board", meshId = 126860307040734, size = V(4.6, 4.6, 0.4) },
			{ name = "Body", meshId = 107509873567959, size = V(5.7, 5.562, 1.421) },
			{ name = "Collision", meshId = 111307059016521, size = V(5, 5.2, 0.6) },
		},
	},
	{
		id = "TownTree",
		category = "environment",
		modelId = 133070566543211,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 92471087482503, size = V(6.311, 11.137, 6.44) },
			{ name = "Collision", meshId = 88569217185155, size = V(1.386, 10.5, 1.386) },
			{ name = "Crown", meshId = 94933689637736, size = V(11.915, 9.754, 11.461) },
		},
	},
	{
		id = "RuinedCabin",
		category = "environment",
		modelId = 98556803847224,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 139692668119426, size = V(13.1, 7.65, 14.693) },
			{ name = "Collision", meshId = 91247694595859, size = V(13.1, 7.5, 12.3) },
		},
	},
	{
		id = "Windmill",
		category = "environment",
		modelId = 105827292925595,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 124592511391743, size = V(8, 16.425, 8.3) },
			{ name = "Collision", meshId = 83334681998584, size = V(8, 14, 7.608) },
			{ name = "Sails", meshId = 84592207708255, size = V(17.046, 17.046, 4) },
		},
	},
	{
		id = "LookoutTower",
		category = "environment",
		modelId = 137547685227922,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 140486008025625, size = V(7.1, 18.531, 7.275) },
			{ name = "Collision", meshId = 115405926778726, size = V(6.601, 15.661, 7.049) },
		},
	},
	{
		id = "Lighthouse",
		category = "environment",
		modelId = 111079372511098,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 90232166847277, size = V(16.92, 56.05, 12.418) },
			{ name = "Collision", meshId = 128328086500877, size = V(16.028, 47.5, 11.759) },
			{ name = "LampGlow", meshId = 92385742285426, size = V(2.092, 2.092, 2.2) },
			{ name = "LampRoom", meshId = 97460440164368, size = V(4.25, 3.6, 4.25) },
			{ name = "WindowGlass", meshId = 85367554456096, size = V(3.76, 23.7, 7.47) },
		},
	},
	{
		id = "Dock",
		category = "environment",
		modelId = 80549673556790,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 139213895433736, size = V(5.6, 10.6, 20.35) },
			{ name = "Collision", meshId = 134730710875106, size = V(5.55, 10.6, 20) },
			{ name = "Deck", meshId = 102697546003435, size = V(5.271, 0.3, 19.937) },
			{ name = "LanternGlow", meshId = 79575927974739, size = V(0.55, 0.7, 0.55) },
		},
	},
	{
		id = "Rowboat",
		category = "environment",
		modelId = 88641268553017,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 125093131488068, size = V(2.96, 1.32, 7.153) },
		},
	},
	{
		id = "Sawmill",
		category = "building",
		modelId = 122113550398654,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 86215100835246, size = V(63.785, 42.3, 42.938) },
			{ name = "Collision", meshId = 112566568598574, size = V(61.65, 42, 40.95) },
			{ name = "Door", meshId = 103111550635504, size = V(4.125, 9, 0.6) },
			{ name = "Glow", meshId = 130480099384678, size = V(47.321, 37.748, 32.209) },
			{ name = "Roof", meshId = 106500111589450, size = V(63.367, 20.52, 40.5) },
			{ name = "SawBlade", meshId = 104702159359138, size = V(14.725, 14.725, 0.9) },
			{ name = "Sign", meshId = 76545053823377, size = V(39.6, 6.9, 0.75) },
			{ name = "Smokestack", meshId = 129773781524937, size = V(4.8, 3.3, 4.8) },
		},
	},
	{
		id = "ToolShed",
		category = "building",
		modelId = 103216324496102,
		tris = nil,
		pieces = {
			{ name = "BarnDoorL", meshId = 104574414484630, size = V(6.6, 11.775, 0.787) },
			{ name = "BarnDoorR", meshId = 128974784954519, size = V(6.6, 11.775, 0.787) },
			{ name = "Body", meshId = 111225616877210, size = V(31.68, 32.107, 27.769) },
			{ name = "Collision", meshId = 86986832102076, size = V(31.1, 22.107, 27.6) },
			{ name = "Counter", meshId = 100192126544226, size = V(9.6, 4.55, 2.6) },
			{ name = "Glow", meshId = 107147198667062, size = V(27.9, 25.448, 24.12) },
			{ name = "Roof", meshId = 122254759522234, size = V(31.213, 10.695, 24) },
			{ name = "Sign", meshId = 138480592524964, size = V(25.5, 5.7, 0.75) },
		},
	},
	{
		id = "Dealership",
		category = "building",
		modelId = 72283597849277,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 82514834771582, size = V(32.43, 30.665, 25.159) },
			{ name = "Collision", meshId = 77525517309414, size = V(29.898, 21.75, 25.8) },
			{ name = "Counter", meshId = 139469055377248, size = V(7.6, 4.55, 2.4) },
			{ name = "Glow", meshId = 128731335060332, size = V(27.075, 24.923, 15.57) },
			{ name = "OfficeDoor", meshId = 73211772830716, size = V(3.225, 9, 0.6) },
			{ name = "OfficeSign", meshId = 97474817544364, size = V(7.8, 1.125, 0.3) },
			{ name = "RollDoor", meshId = 132814082294569, size = V(14.4, 1.65, 1.569) },
			{ name = "Roof", meshId = 126436581421231, size = V(31.333, 9.35, 22.35) },
			{ name = "Sign", meshId = 100283783007723, size = V(24.3, 5.4, 0.75) },
		},
	},
	{
		id = "GeneralStore",
		category = "building",
		modelId = 87424363129550,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 126615154910404, size = V(51.06, 30.525, 40.524) },
			{ name = "Chimney", meshId = 126429254955747, size = V(2.4, 0.75, 2.4) },
			{ name = "Collision", meshId = 116430701440570, size = V(51.6, 30, 41.106) },
			{ name = "Counter", meshId = 106358396545112, size = V(8.6, 4.55, 2.4) },
			{ name = "Glow", meshId = 76572574544186, size = V(49.35, 17.798, 37.091) },
			{ name = "PriceTags", meshId = 124570295416522, size = V(37.35, 3.45, 0.24) },
			{ name = "Roof", meshId = 97929711741619, size = V(51.75, 13.001, 47) },
			{ name = "Sign", meshId = 74063491046370, size = V(27, 4.2, 0.75) },
		},
	},
	{
		id = "GondolaStation",
		category = "building",
		modelId = 91952415804874,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 76209421282595, size = V(12.8, 16.55, 12.128) },
			{ name = "Bullwheel", meshId = 77508109255073, size = V(7.487, 1.2, 7.487) },
			{ name = "Collision", meshId = 137106255286313, size = V(14.756, 14.115, 11.7) },
			{ name = "Glow", meshId = 128179108608673, size = V(11.646, 0.567, 0.446) },
			{ name = "Platform", meshId = 132790652457449, size = V(10, 1, 10) },
			{ name = "Roof", meshId = 135045241070662, size = V(15.272, 5.165, 11) },
			{ name = "Sign", meshId = 97206762661640, size = V(6.4, 1.5, 0.3) },
		},
	},
	{
		id = "SkyBin",
		category = "building",
		modelId = 119616511605580,
		tris = nil,
		pieces = {
			{ name = "Body", meshId = 100903937466780, size = V(4.825, 10.085, 7.374) },
			{ name = "FlumeWater", meshId = 80895288519775, size = V(1.3, 3.575, 2.894) },
			{ name = "Glow", meshId = 100635326256018, size = V(0.33, 0.42, 0.33) },
			{ name = "SkyBin", meshId = 106816754909256, size = V(4.336, 3.66, 4.348) },
		},
	},
	{
		id = "Murph",
		category = "npc",
		modelId = 116498139907119,
		tris = nil,
		pieces = {
			{ name = "Carry", meshId = 129282759397083, size = V(0.601, 0.6, 0.462) },
			{ name = "Head", meshId = 119641824946975, size = V(1.52, 3.02, 1.42) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
			{ name = "LeftFoot", meshId = 115567970319340, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftHand", meshId = 96198574363660, size = V(0.78, 0.42, 0.78) },
			{ name = "LeftLowerArm", meshId = 130708537761087, size = V(0.86, 0.86, 0.88) },
			{ name = "LeftLowerLeg", meshId = 101607517869693, size = V(0.95, 0.8, 0.97) },
			{ name = "LeftUpperArm", meshId = 105284930523566, size = V(0.92, 0.98, 0.94) },
			{ name = "LeftUpperLeg", meshId = 139387790017966, size = V(0.94, 0.88, 1.02) },
			{ name = "LowerTorso", meshId = 121726594323101, size = V(2.18, 0.55, 1.25) },
			{ name = "RightFoot", meshId = 136434036384438, size = V(0.96, 0.4, 1.22) },
			{ name = "RightHand", meshId = 103621913097291, size = V(0.78, 0.42, 0.78) },
			{ name = "RightLowerArm", meshId = 78264803126606, size = V(0.86, 0.86, 0.88) },
			{ name = "RightLowerLeg", meshId = 93169923368878, size = V(0.95, 0.8, 0.97) },
			{ name = "RightUpperArm", meshId = 102593030407778, size = V(0.92, 0.98, 0.94) },
			{ name = "RightUpperLeg", meshId = 122013450324601, size = V(0.94, 0.88, 1.02) },
			{ name = "UpperTorso", meshId = 102865278963145, size = V(2.18, 1.54, 1.44) },
		},
	},
	{
		id = "Millie",
		category = "npc",
		modelId = 99114742559192,
		tris = nil,
		pieces = {
			{ name = "Carry", meshId = 73996108186259, size = V(0.135, 1.287, 1.089) },
			{ name = "Head", meshId = 102313140359146, size = V(1.52, 1.798, 1.66) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
			{ name = "LeftFoot", meshId = 104416240141512, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftHand", meshId = 77666165822042, size = V(0.78, 0.42, 0.78) },
			{ name = "LeftLowerArm", meshId = 119957434678210, size = V(0.92, 0.88, 0.94) },
			{ name = "LeftLowerLeg", meshId = 116687476427666, size = V(0.95, 0.8, 0.97) },
			{ name = "LeftUpperArm", meshId = 118563219993952, size = V(0.92, 0.98, 0.94) },
			{ name = "LeftUpperLeg", meshId = 101508101794001, size = V(0.94, 0.88, 0.96) },
			{ name = "LowerTorso", meshId = 133080680995508, size = V(1.94, 0.575, 1.03) },
			{ name = "RightFoot", meshId = 73427235174280, size = V(0.96, 0.4, 1.22) },
			{ name = "RightHand", meshId = 113829338505467, size = V(0.78, 0.42, 0.78) },
			{ name = "RightLowerArm", meshId = 126182097546615, size = V(0.92, 0.88, 0.94) },
			{ name = "RightLowerLeg", meshId = 73679620163478, size = V(0.95, 0.8, 0.97) },
			{ name = "RightUpperArm", meshId = 79925629935072, size = V(0.92, 0.98, 0.94) },
			{ name = "RightUpperLeg", meshId = 129326766967750, size = V(0.94, 0.88, 0.96) },
			{ name = "UpperTorso", meshId = 119961448211765, size = V(1.98, 1.54, 1.14) },
		},
	},
	{
		id = "Tink",
		category = "npc",
		modelId = 122987026100545,
		tris = nil,
		pieces = {
			{ name = "Carry", meshId = 102672823416739, size = V(1, 0.37, 0.37) },
			{ name = "Head", meshId = 85114800128167, size = V(1.78, 1.791, 1.858) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
			{ name = "LeftFoot", meshId = 72378122111931, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftHand", meshId = 85954106592221, size = V(0.78, 0.42, 0.78) },
			{ name = "LeftLowerArm", meshId = 125421785530563, size = V(0.92, 0.88, 0.94) },
			{ name = "LeftLowerLeg", meshId = 122929934130988, size = V(0.88, 0.8, 0.9) },
			{ name = "LeftUpperArm", meshId = 128822943813662, size = V(0.9, 0.98, 0.92) },
			{ name = "LeftUpperLeg", meshId = 77491757108641, size = V(0.94, 0.88, 0.96) },
			{ name = "LowerTorso", meshId = 105839768179795, size = V(1.98, 1.375, 1.1) },
			{ name = "RightFoot", meshId = 87065553139625, size = V(0.96, 0.4, 1.22) },
			{ name = "RightHand", meshId = 114422124406733, size = V(0.78, 0.42, 0.78) },
			{ name = "RightLowerArm", meshId = 130628169716671, size = V(0.92, 0.88, 0.94) },
			{ name = "RightLowerLeg", meshId = 108290746826201, size = V(0.88, 0.8, 0.9) },
			{ name = "RightUpperArm", meshId = 89887064461596, size = V(0.9, 0.98, 0.92) },
			{ name = "RightUpperLeg", meshId = 78585942862069, size = V(0.94, 0.88, 0.96) },
			{ name = "UpperTorso", meshId = 103975676965652, size = V(1.96, 1.54, 1.095) },
		},
	},
	{
		id = "Dale",
		category = "npc",
		modelId = 121779024595337,
		tris = nil,
		pieces = {
			{ name = "Carry", meshId = 88085019167252, size = V(0.16, 1.7, 0.6) },
			{ name = "Head", meshId = 96013384851518, size = V(1.52, 1.715, 1.915) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
			{ name = "LeftFoot", meshId = 104766179787748, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftHand", meshId = 83071415666688, size = V(0.78, 0.42, 0.78) },
			{ name = "LeftLowerArm", meshId = 85134454559323, size = V(0.92, 0.88, 0.94) },
			{ name = "LeftLowerLeg", meshId = 108310065203684, size = V(0.88, 0.83, 0.93) },
			{ name = "LeftUpperArm", meshId = 136768692724386, size = V(0.9, 0.98, 0.92) },
			{ name = "LeftUpperLeg", meshId = 109602148572490, size = V(0.94, 0.88, 0.96) },
			{ name = "LowerTorso", meshId = 103556777932740, size = V(1.94, 0.575, 1.03) },
			{ name = "RightFoot", meshId = 117109970254679, size = V(0.96, 0.4, 1.22) },
			{ name = "RightHand", meshId = 139564345155945, size = V(0.78, 0.42, 0.78) },
			{ name = "RightLowerArm", meshId = 123969354159436, size = V(0.92, 0.88, 0.94) },
			{ name = "RightLowerLeg", meshId = 97721950217923, size = V(0.88, 0.83, 0.93) },
			{ name = "RightUpperArm", meshId = 73102814846989, size = V(0.9, 0.98, 0.92) },
			{ name = "RightUpperLeg", meshId = 82134973035228, size = V(0.94, 0.88, 0.96) },
			{ name = "UpperTorso", meshId = 115367571641134, size = V(1.96, 1.54, 1.14) },
		},
	},
	{
		id = "Hazel",
		category = "npc",
		modelId = 74883633826857,
		tris = nil,
		pieces = {
			{ name = "Carry", meshId = 95166951515260, size = V(0.562, 1.318, 0.562) },
			{ name = "Glow", meshId = 77999129021080, size = V(0.412, 0.525, 0.413) },
			{ name = "Head", meshId = 121133497628718, size = V(1.52, 1.798, 1.66) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
			{ name = "LeftFoot", meshId = 88895260081796, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftHand", meshId = 97681876019747, size = V(0.78, 0.42, 0.78) },
			{ name = "LeftLowerArm", meshId = 136200588858564, size = V(0.84, 0.86, 0.86) },
			{ name = "LeftLowerLeg", meshId = 129236426052873, size = V(0.88, 0.8, 0.9) },
			{ name = "LeftUpperArm", meshId = 82916793253147, size = V(0.9, 0.98, 0.92) },
			{ name = "LeftUpperLeg", meshId = 103840124258122, size = V(0.94, 0.88, 0.96) },
			{ name = "LowerTorso", meshId = 115887287930870, size = V(1.98, 0.55, 1.05) },
			{ name = "RightFoot", meshId = 131814545854935, size = V(0.96, 0.4, 1.22) },
			{ name = "RightHand", meshId = 116160073850108, size = V(0.78, 0.42, 0.78) },
			{ name = "RightLowerArm", meshId = 102449064454701, size = V(0.84, 0.86, 0.86) },
			{ name = "RightLowerLeg", meshId = 112366473449777, size = V(0.88, 0.8, 0.9) },
			{ name = "RightUpperArm", meshId = 133263885973371, size = V(0.9, 0.98, 0.92) },
			{ name = "RightUpperLeg", meshId = 83517310351339, size = V(0.94, 0.88, 0.96) },
			{ name = "UpperTorso", meshId = 129983915802950, size = V(1.96, 1.68, 1.145) },
		},
	},
	{
		id = "Gus",
		category = "npc",
		modelId = 86167893945213,
		tris = nil,
		pieces = {
			{ name = "Head", meshId = 137243554156858, size = V(1.53, 1.825, 1.79) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
			{ name = "LeftFoot", meshId = 137461808658419, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftHand", meshId = 97251985544625, size = V(0.78, 0.42, 0.78) },
			{ name = "LeftLowerArm", meshId = 116977876197897, size = V(0.84, 0.86, 0.86) },
			{ name = "LeftLowerLeg", meshId = 124094016599150, size = V(0.88, 0.8, 0.9) },
			{ name = "LeftUpperArm", meshId = 126675592445622, size = V(0.9, 0.98, 0.92) },
			{ name = "LeftUpperLeg", meshId = 124499237471996, size = V(0.94, 0.88, 0.96) },
			{ name = "LowerTorso", meshId = 97694939333482, size = V(1.98, 0.55, 1.05) },
			{ name = "RightFoot", meshId = 105009286686361, size = V(0.96, 0.4, 1.22) },
			{ name = "RightHand", meshId = 103978168374792, size = V(0.78, 0.42, 0.78) },
			{ name = "RightLowerArm", meshId = 108371403171450, size = V(0.84, 0.86, 0.86) },
			{ name = "RightLowerLeg", meshId = 131862798681592, size = V(0.88, 0.8, 0.9) },
			{ name = "RightUpperArm", meshId = 126741158290606, size = V(0.9, 0.98, 0.92) },
			{ name = "RightUpperLeg", meshId = 83283479724897, size = V(0.94, 0.88, 0.96) },
			{ name = "UpperTorso", meshId = 104857227459379, size = V(2.05, 1.705, 1.2) },
		},
	},
	{
		id = "Rosa",
		category = "npc",
		modelId = 76753398201249,
		tris = nil,
		pieces = {
			{ name = "Carry", meshId = 135893698322865, size = V(1.12, 1.29, 0.9) },
			{ name = "Head", meshId = 108009426716841, size = V(1.52, 1.568, 1.663) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
			{ name = "LeftFoot", meshId = 119349865481682, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftHand", meshId = 83674626488519, size = V(0.78, 0.42, 0.78) },
			{ name = "LeftLowerArm", meshId = 79984537639444, size = V(0.92, 0.88, 0.94) },
			{ name = "LeftLowerLeg", meshId = 100066231658827, size = V(0.95, 0.8, 0.97) },
			{ name = "LeftUpperArm", meshId = 71618342241004, size = V(0.92, 0.98, 0.94) },
			{ name = "LeftUpperLeg", meshId = 79778138876188, size = V(0.94, 0.88, 0.96) },
			{ name = "LowerTorso", meshId = 135958628937217, size = V(1.98, 0.55, 1.05) },
			{ name = "RightFoot", meshId = 132533867776257, size = V(0.96, 0.4, 1.22) },
			{ name = "RightHand", meshId = 97636778870157, size = V(0.78, 0.42, 0.78) },
			{ name = "RightLowerArm", meshId = 110928270659032, size = V(0.92, 0.88, 0.94) },
			{ name = "RightLowerLeg", meshId = 123241877210621, size = V(0.95, 0.8, 0.97) },
			{ name = "RightUpperArm", meshId = 93478161314715, size = V(0.92, 0.98, 0.94) },
			{ name = "RightUpperLeg", meshId = 84109447694675, size = V(0.94, 0.88, 0.96) },
			{ name = "UpperTorso", meshId = 137332886057378, size = V(1.98, 1.54, 1.055) },
		},
	},
	{
		id = "Pip",
		category = "npc",
		modelId = 119462072845615,
		tris = nil,
		pieces = {
			{ name = "Carry", meshId = 111101942473680, size = V(0.59, 1.127, 0.548) },
			{ name = "Head", meshId = 124190518401724, size = V(1.529, 1.525, 1.454) },
			{ name = "HumanoidRootPart", meshId = 98910544598150, size = V(1.56, 1.56, 0.78) },
			{ name = "LeftFoot", meshId = 87049330143094, size = V(0.749, 0.312, 0.952) },
			{ name = "LeftHand", meshId = 97652593772480, size = V(0.608, 0.328, 0.608) },
			{ name = "LeftLowerArm", meshId = 87322205534816, size = V(0.655, 0.671, 0.671) },
			{ name = "LeftLowerLeg", meshId = 97410892935245, size = V(0.686, 0.624, 0.702) },
			{ name = "LeftUpperArm", meshId = 132987667702902, size = V(0.702, 0.764, 0.718) },
			{ name = "LeftUpperLeg", meshId = 132628679495380, size = V(0.733, 0.686, 0.749) },
			{ name = "LowerTorso", meshId = 131332680191580, size = V(1.513, 0.448, 0.803) },
			{ name = "RightFoot", meshId = 86487216536816, size = V(0.749, 0.312, 0.952) },
			{ name = "RightHand", meshId = 96169983593532, size = V(0.608, 0.328, 0.608) },
			{ name = "RightLowerArm", meshId = 124897971224275, size = V(0.655, 0.671, 0.671) },
			{ name = "RightLowerLeg", meshId = 73687041929457, size = V(0.686, 0.624, 0.702) },
			{ name = "RightUpperArm", meshId = 131540414701446, size = V(0.702, 0.764, 0.718) },
			{ name = "RightUpperLeg", meshId = 121165382213492, size = V(0.733, 0.686, 0.749) },
			{ name = "UpperTorso", meshId = 87493254949869, size = V(1.529, 1.201, 0.889) },
		},
	},
	{
		id = "OldBram",
		category = "npc",
		modelId = 79097238419970,
		tris = nil,
		pieces = {
			{ name = "Carry", meshId = 106182055345622, size = V(0.455, 2.387, 0.156) },
			{ name = "Head", meshId = 108637384034532, size = V(1.52, 1.365, 1.39) },
			{ name = "HumanoidRootPart", meshId = 137889643879858, size = V(2, 2, 1) },
			{ name = "LeftFoot", meshId = 119351101193720, size = V(0.96, 0.4, 1.22) },
			{ name = "LeftHand", meshId = 140592453452011, size = V(0.78, 0.42, 0.78) },
			{ name = "LeftLowerArm", meshId = 126907896592866, size = V(0.86, 0.86, 0.88) },
			{ name = "LeftLowerLeg", meshId = 77490113182466, size = V(0.88, 0.8, 0.9) },
			{ name = "LeftUpperArm", meshId = 104141006365223, size = V(0.92, 0.98, 0.94) },
			{ name = "LeftUpperLeg", meshId = 101660484556741, size = V(0.94, 0.88, 0.96) },
			{ name = "LowerTorso", meshId = 82339079226406, size = V(1.98, 0.55, 1.05) },
			{ name = "RightFoot", meshId = 135014855749918, size = V(0.96, 0.4, 1.22) },
			{ name = "RightHand", meshId = 86190154234212, size = V(0.78, 0.42, 0.78) },
			{ name = "RightLowerArm", meshId = 135756150151986, size = V(0.86, 0.86, 0.88) },
			{ name = "RightLowerLeg", meshId = 82740805087300, size = V(0.88, 0.8, 0.9) },
			{ name = "RightUpperArm", meshId = 131366081636560, size = V(0.92, 0.98, 0.94) },
			{ name = "RightUpperLeg", meshId = 90389890437469, size = V(0.94, 0.88, 0.96) },
			{ name = "UpperTorso", meshId = 102934582150383, size = V(1.98, 1.54, 1.09) },
		},
	},
}

local BY_ID: { [string]: Asset } = {}
for _, asset in ipairs(ALL) do
	BY_ID[asset.id] = asset
end

TownModels.All = ALL
-- Authored lengths the placement rules scale from.
TownModels.FenceLength = 8.583
TownModels.DockLength = 20
TownModels.RopeSpan = 16
TownModels.FootSpan = 14.4
TownModels.NpcHeight = 5.67
TownModels.StoreBoardDrop = 2.3
TownModels.WindmillHub = Vector3.new(0, 12.4, -3.9)
-- Visible-triangle caps (ticket I). Unknown tris do not spend the cap.
TownModels.BuildingTriCap = 10000
TownModels.NpcTriCap = 2000
TownModels.PropTriCap = 2000
TownModels.SellViewTriCap = 60000

function TownModels.Get(id: string): Asset?
	return BY_ID[id]
end

function TownModels.Ids(category: Category): { string }
	local out = {}
	for _, asset in ipairs(ALL) do
		if asset.category == category then
			table.insert(out, asset.id)
		end
	end
	return out
end

function TownModels.Visual(asset: Asset): { Piece }
	local out = {}
	for _, piece in ipairs(asset.pieces) do
		if piece.name ~= "Collision" then
			table.insert(out, piece)
		end
	end
	return out
end

function TownModels.Piece(asset: Asset, name: string): Piece?
	for _, piece in ipairs(asset.pieces) do
		if piece.name == name then
			return piece
		end
	end
	return nil
end

-- Hearth & Home is the general store. The other shop kinds match.
function TownModels.ShopAsset(kind: string): string
	if kind == "ToolShed" or kind == "Dealership" or kind == "Sawmill" then
		return kind
	end
	return "GeneralStore"
end

function TownModels.MultiMesh(asset: Asset): boolean
	return #asset.pieces > 1
end

return TownModels
