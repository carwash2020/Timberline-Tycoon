--!strict
-- MachineMeshes: the Blender machines (Lane K, job 15) as data. One entry per
-- machine or logic piece: its uploaded pieces (meshId, size, and the centre
-- of the piece's bounds relative to the MESH ORIGIN) plus the named points
-- the code animates about (arbor, hinges, pivots). Same slot pattern as
-- AxeModels and RockModels; MachineSkin applies it.
--
-- Mesh origin = the footprint's ground centre (y 0), +Z outfeed, -Z infeed,
-- +X the control-panel side. A piece lands at `frame * CFrame.new(offset)`
-- (an uploaded asset carries no pivot: the part's own centre is its bounds
-- centre, PHASE2_NOTES "vehicle models are messed up"), so `offset` is the
-- bounds centre. meshId 0 or a missing MeshTemplates file keeps the part
-- build (MachineSkin logs it once per machine).
--
-- source
--   tld1   the 25 TLD-1 line-kit assets (uploaded 2026-10-08 MT, 4:54 PM),
--          ids from jobs/15-K-addendum-TLD1.md section E. They replace the
--          first job 15 uploads of the same names.
--   job15  the 16 pieces TLD-1 does not cover (job 15 ids).
-- The ids are copied from assets/uploaded-machines-*.json and checked
-- against both id tables in the briefs. `modelAssetId` is only the Open
-- Cloud Model container; it is never a MeshId.
--
-- Where the offsets come from. Every number is a studs value in mesh space.
--   job15 pieces        read from each GLB's node bounds (exact)
--   Body                the stats.json bounds (exact: every Body spans the
--                       whole footprint bounds, ground up)
--   SawBlade            the arbor / blade point in stats.json (exact)
--   CutterHead, Lamp    the cutter / lamp point in stats.json (exact)
--   Arm                 starts at the pivot post, reaches `size.X` (exact)
--   Belt, Rollers,      TLD-1 LINE-STANDARD: pan centre y 0.33, roller axle
--   ArrowDecal          y 0.5 (pitch 1.0, first 0.5 from each port face),
--                       arrows on the rail tops (1.32), all centred on the
--                       deck. Bends and the switch are centred on their own
--                       bounds. No GLB for these was in the pack, so they are
--                       standard-derived and each is pinned in the spec.
--   Gate, FurnaceDoor,  placed from their hinge and the size of their
--   Lever               bounds (door 55 degrees ajar, gate 45 degrees)
-- Studio check 1 in the PR looks at every one of them up close.

local V3 = Vector3.new

local MachineMeshes = {}

export type Piece = { name: string, meshId: number, size: Vector3, offset: Vector3 }
export type Family = "sawmill" | "planer" | "chopsaw" | "belt" | "line" | "ore" | "logic"
export type Asset = {
	family: Family,
	source: "tld1" | "job15",
	modelAssetId: number,
	pieces: { Piece },
	points: { [string]: Vector3 }?,
}

-- Gameplay parts the machine's mesh sits around (TLD-1 stats.json
-- gameplay_parts). Local to the mesh origin.
export type Row = { name: string, size: Vector3, pos: Vector3, group: string? }
export type Layout = { footprint: Vector2, output: Vector3, parts: { Row } }

-- TLD-1 line standard (reference/LINE-STANDARD.md), pinned in specs.
MachineMeshes.Standard = {
	DeckTop = 0.72,
	PlateWidth = 6.0,
	PlateThick = 0.16,
	Channel = 5.0,
	RailThick = 0.4,
	RailTop = 1.32,
	RollerPitch = 1.0,
	RollerFirst = 0.5, -- first roller centre, from each port face
	RollerRadius = 0.22,
	RollerAxleY = 0.5,
	Lift = 2.0,
	GridStep = 2,
}

-- Specs set a machine's meshId to 0 here ("SawmillRickety" for the whole
-- machine, "SawmillRickety.Body" for one piece) to check the part build.
MachineMeshes.ForcedZero = {} :: { [string]: boolean }

local ASSETS: { [string]: Asset } = {
	SawmillRickety = {
		family = "sawmill",
		source = "tld1",
		modelAssetId = 82203253150448,
		pieces = {
			{ name = "Body", meshId = 82316315960701, size = V3(7.9, 7.008, 12), offset = V3(0, 3.504, 0) },
			{ name = "Belt", meshId = 79470088816517, size = V3(5, 0.1, 12), offset = V3(0, 0.33, 0) },
			{ name = "ArrowDecal", meshId = 71616383391365, size = V3(5.875, 0.045, 10.293), offset = V3(0, 1.343, 0) },
			{ name = "Rollers", meshId = 100124805556860, size = V3(5.9, 0.407, 11.407), offset = V3(0, 0.5, 0) },
			{ name = "SawBlade", meshId = 105278917546675, size = V3(3.406, 3.406, 0.374), offset = V3(0, 2.44, 0.35) },
		},
		points = {
			arbor = V3(0, 2.44, 0.35),
		},
	},
	SawmillSturdy = {
		family = "sawmill",
		source = "tld1",
		modelAssetId = 120733386966709,
		pieces = {
			{ name = "Body", meshId = 115352495869068, size = V3(7.9, 7.288, 14), offset = V3(0, 3.644, 0) },
			{ name = "Belt", meshId = 139811009092137, size = V3(5, 0.1, 14), offset = V3(0, 0.33, 0) },
			{
				name = "ArrowDecal",
				meshId = 112648169356270,
				size = V3(5.875, 0.045, 12.293),
				offset = V3(0, 1.343, 0),
			},
			{ name = "Rollers", meshId = 135820135088645, size = V3(5.9, 0.407, 13.407), offset = V3(0, 0.5, 0) },
			{ name = "SawBlade", meshId = 75946719790138, size = V3(3.722, 3.722, 0.374), offset = V3(0, 2.6, 0.35) },
		},
		points = {
			arbor = V3(0, 2.6, 0.35),
		},
	},
	Millmaster100 = {
		family = "sawmill",
		source = "tld1",
		modelAssetId = 76000687397316,
		pieces = {
			{ name = "Body", meshId = 93421084152103, size = V3(9.9, 9.57, 16), offset = V3(0, 4.785, 0) },
			{ name = "Belt", meshId = 122001219822338, size = V3(5, 0.1, 16), offset = V3(0, 0.33, 0) },
			{ name = "ArrowDecal", meshId = 97534746945740, size = V3(5.875, 0.045, 14.293), offset = V3(0, 1.343, 0) },
			{ name = "Rollers", meshId = 93317397092855, size = V3(5.9, 0.407, 15.407), offset = V3(0, 0.5, 0) },
			{ name = "SawBlade", meshId = 73060656632976, size = V3(4.356, 4.356, 0.374), offset = V3(0, 2.92, 0.35) },
		},
		points = {
			arbor = V3(0, 2.92, 0.35),
		},
	},
	Millmaster200 = {
		family = "sawmill",
		source = "tld1",
		modelAssetId = 86626741100071,
		pieces = {
			{ name = "Body", meshId = 106669780577580, size = V3(9.9, 9.68, 18), offset = V3(0, 4.84, 0) },
			{ name = "Belt", meshId = 105997146156742, size = V3(5, 0.1, 18), offset = V3(0, 0.33, 0) },
			{
				name = "ArrowDecal",
				meshId = 110256564557891,
				size = V3(5.875, 0.045, 16.293),
				offset = V3(0, 1.343, 0),
			},
			{ name = "Rollers", meshId = 89434911284365, size = V3(5.9, 0.407, 17.407), offset = V3(0, 0.5, 0) },
			{ name = "SawBlade", meshId = 115802333263725, size = V3(5.306, 5.306, 0.374), offset = V3(0, 3.4, 0.35) },
		},
		points = {
			arbor = V3(0, 3.4, 0.35),
		},
	},
	Millmaster200L = {
		family = "sawmill",
		source = "tld1",
		modelAssetId = 132542206758505,
		pieces = {
			{ name = "Body", meshId = 123176708762563, size = V3(9.9, 8.98, 26), offset = V3(0, 4.49, 0) },
			{ name = "Belt", meshId = 134657591217029, size = V3(5, 0.1, 26), offset = V3(0, 0.33, 0) },
			{
				name = "ArrowDecal",
				meshId = 138487741009210,
				size = V3(5.875, 0.045, 24.293),
				offset = V3(0, 1.343, 0),
			},
			{ name = "Rollers", meshId = 110422189957775, size = V3(5.9, 0.407, 25.407), offset = V3(0, 0.5, 0) },
			{ name = "SawBlade", meshId = 115802333263725, size = V3(5.306, 5.306, 0.374), offset = V3(0, 3.4, 0.35) },
			{ name = "Glow", meshId = 114169088509905, size = V3(7.08, 6.36, 20.51), offset = V3(0, 5.96, 0) },
		},
		points = {
			arbor = V3(0, 3.4, 0.35),
		},
	},
	PlanerHand = {
		family = "planer",
		source = "tld1",
		modelAssetId = 128302073238305,
		pieces = {
			{ name = "Body", meshId = 139485036599751, size = V3(8.21, 6.92, 8), offset = V3(-0.155, 3.46, 0) },
			{ name = "Belt", meshId = 115448717961056, size = V3(5, 0.1, 8), offset = V3(0, 0.33, 0) },
			{ name = "ArrowDecal", meshId = 113894795100118, size = V3(5.875, 0.045, 1.093), offset = V3(0, 1.343, 0) },
			{ name = "Rollers", meshId = 84416832568991, size = V3(5.9, 4.007, 7.407), offset = V3(0, 2.3, 0) },
			{ name = "CutterHead", meshId = 85226167018473, size = V3(4.7, 1.27, 1.27), offset = V3(0, 4.05, 0) },
		},
		points = {
			cutter = V3(0, 4.05, 0),
		},
	},
	PlanerBench = {
		family = "planer",
		source = "tld1",
		modelAssetId = 73706656679263,
		pieces = {
			{ name = "Body", meshId = 99523857231670, size = V3(7.9, 7.88, 10), offset = V3(0, 3.94, 0) },
			{ name = "Belt", meshId = 84630483083532, size = V3(5, 0.1, 10), offset = V3(0, 0.33, 0) },
			{ name = "ArrowDecal", meshId = 106971447046383, size = V3(5.875, 0.045, 9.093), offset = V3(0, 1.343, 0) },
			{ name = "Rollers", meshId = 118736500953369, size = V3(5.9, 4.967, 9.407), offset = V3(0, 2.78, 0) },
			{ name = "CutterHead", meshId = 110350458529864, size = V3(4.7, 1.27, 1.27), offset = V3(0, 5.01, 0) },
		},
		points = {
			cutter = V3(0, 5.01, 0),
		},
	},
	PlanerSteam = {
		family = "planer",
		source = "tld1",
		modelAssetId = 135902969044789,
		pieces = {
			{ name = "Body", meshId = 95941118078808, size = V3(7.9, 10.32, 12), offset = V3(0, 5.16, 0) },
			{ name = "Belt", meshId = 79470088816517, size = V3(5, 0.1, 12), offset = V3(0, 0.33, 0) },
			{ name = "ArrowDecal", meshId = 83223296721881, size = V3(5.875, 0.045, 11.093), offset = V3(0, 1.343, 0) },
			{ name = "Rollers", meshId = 108851068260356, size = V3(5.9, 5.927, 11.407), offset = V3(0, 3.26, 0) },
			{ name = "CutterHead", meshId = 99962089066042, size = V3(4.7, 1.27, 1.27), offset = V3(0, 5.97, 0) },
		},
		points = {
			cutter = V3(0, 5.97, 0),
		},
	},
	PlanerIndustrial = {
		family = "planer",
		source = "tld1",
		modelAssetId = 99269663197315,
		pieces = {
			{ name = "Body", meshId = 140368307046506, size = V3(7.9, 8.84, 16), offset = V3(0, 4.42, 0) },
			{ name = "Belt", meshId = 122001219822338, size = V3(5, 0.1, 16), offset = V3(0, 0.33, 0) },
			{
				name = "ArrowDecal",
				meshId = 117725368152383,
				size = V3(5.875, 0.045, 14.093),
				offset = V3(0, 1.343, 0),
			},
			{ name = "Rollers", meshId = 127677393146989, size = V3(5.9, 5.927, 15.407), offset = V3(0, 3.26, 0) },
			{ name = "CutterHead", meshId = 99962089066042, size = V3(4.7, 1.27, 1.27), offset = V3(0, 5.97, 0) },
			{ name = "Glow", meshId = 131460205123643, size = V3(7.66, 5.48, 10.2), offset = V3(0, 6.16, 0) },
		},
		points = {
			cutter = V3(0, 5.97, 0),
		},
	},
	ChopSaw = {
		family = "chopsaw",
		source = "tld1",
		modelAssetId = 86450593926500,
		pieces = {
			{ name = "Body", meshId = 82676669720780, size = V3(6.686, 8.38, 56), offset = V3(0, 4.19, 0) },
			{ name = "Belt", meshId = 139694883139382, size = V3(5, 0.1, 56), offset = V3(0, 0.33, 0) },
			{
				name = "ArrowDecal",
				meshId = 111005337162220,
				size = V3(5.875, 0.045, 33.093),
				offset = V3(0, 1.343, 0),
			},
			{ name = "Rollers", meshId = 139928656274744, size = V3(5.9, 0.407, 55.407), offset = V3(0, 0.5, 0) },
			{ name = "SawBlade", meshId = 138618194266659, size = V3(3.168, 3.105, 0.272), offset = V3(0, 2, 24) },
		},
		points = {
			blade = V3(0, 2, 24),
		},
	},
	ConveyorShort = {
		family = "belt",
		source = "tld1",
		modelAssetId = 105676684351431,
		pieces = {
			{ name = "Body", meshId = 103732749952811, size = V3(6, 1.32, 4), offset = V3(0, 0.66, 0) },
			{ name = "Belt", meshId = 72953111751969, size = V3(5, 0.1, 4), offset = V3(0, 0.33, 0) },
			{ name = "ArrowDecal", meshId = 90697262252511, size = V3(5.875, 0.045, 1.093), offset = V3(0, 1.343, 0) },
			{ name = "Rollers", meshId = 91466161753932, size = V3(5.9, 0.407, 3.407), offset = V3(0, 0.5, 0) },
		},
	},
	ConveyorStraight = {
		family = "belt",
		source = "tld1",
		modelAssetId = 71808845784840,
		pieces = {
			{ name = "Body", meshId = 121102816278486, size = V3(6, 1.32, 8), offset = V3(0, 0.66, 0) },
			{ name = "Belt", meshId = 115448717961056, size = V3(5, 0.1, 8), offset = V3(0, 0.33, 0) },
			{ name = "ArrowDecal", meshId = 90697262252511, size = V3(5.875, 0.045, 1.093), offset = V3(0, 1.343, 0) },
			{ name = "Rollers", meshId = 123259738546019, size = V3(5.9, 0.407, 7.407), offset = V3(0, 0.5, 0) },
		},
	},
	ConveyorLong = {
		family = "belt",
		source = "tld1",
		modelAssetId = 126304153360911,
		pieces = {
			{ name = "Body", meshId = 73545583088683, size = V3(6, 1.32, 16), offset = V3(0, 0.66, 0) },
			{ name = "Belt", meshId = 122001219822338, size = V3(5, 0.1, 16), offset = V3(0, 0.33, 0) },
			{ name = "ArrowDecal", meshId = 90697262252511, size = V3(5.875, 0.045, 1.093), offset = V3(0, 1.343, 0) },
			{ name = "Rollers", meshId = 93317397092855, size = V3(5.9, 0.407, 15.407), offset = V3(0, 0.5, 0) },
		},
	},
	ConveyorReversible = {
		family = "belt",
		source = "tld1",
		modelAssetId = 99790914584808,
		pieces = {
			{ name = "Body", meshId = 134980836676411, size = V3(6, 1.82, 8), offset = V3(0, 0.91, 0) },
			{ name = "Belt", meshId = 115448717961056, size = V3(5, 0.1, 8), offset = V3(0, 0.33, 0) },
			{ name = "ArrowDecal", meshId = 122822891842924, size = V3(5.875, 0.045, 2.986), offset = V3(0, 1.343, 0) },
			{ name = "Rollers", meshId = 123259738546019, size = V3(5.9, 0.407, 7.407), offset = V3(0, 0.5, 0) },
			{ name = "Lever", meshId = 103684402243704, size = V3(0.22, 1.135, 1.099), offset = V3(2.7, 2.388, -3) },
		},
		points = {
			lever_pivot = V3(2.7, 1.82, -3),
		},
	},
	ConveyorTurn = {
		family = "belt",
		source = "tld1",
		modelAssetId = 97607742935828,
		pieces = {
			{ name = "Body", meshId = 117039337469037, size = V3(7, 1.32, 7), offset = V3(0.5, 0.66, -0.5) },
			{ name = "Belt", meshId = 113546975286857, size = V3(6.5, 0.1, 6.5), offset = V3(0.75, 0.33, -0.75) },
			{
				name = "ArrowDecal",
				meshId = 138942464537519,
				size = V3(4.857, 0.045, 4.609),
				offset = V3(0.6, 1.343, -0.6),
			},
			{
				name = "Rollers",
				meshId = 133528114022350,
				size = V3(6.851, 0.469, 6.851),
				offset = V3(0.575, 0.5, -0.575),
			},
		},
	},
	ConveyorFunnel = {
		family = "belt",
		source = "tld1",
		modelAssetId = 138533752658757,
		pieces = {
			{ name = "Body", meshId = 116590874132562, size = V3(8, 2.009, 8.055), offset = V3(0, 1.004, -0.027) },
			{ name = "Belt", meshId = 92661088659948, size = V3(7, 0.1, 8), offset = V3(0, 0.33, 0) },
			{
				name = "ArrowDecal",
				meshId = 113894795100118,
				size = V3(5.875, 0.045, 1.093),
				offset = V3(0, 1.343, 1.8),
			},
			{ name = "Rollers", meshId = 102496882690265, size = V3(6.9, 0.407, 7.407), offset = V3(0, 0.5, 0) },
		},
	},
	BeltDrop = {
		family = "belt",
		source = "tld1",
		modelAssetId = 90596669614644,
		pieces = {
			{ name = "Body", meshId = 89409509121237, size = V3(6, 2.02, 4.394), offset = V3(0, 0.31, 0.197) },
			{ name = "Belt", meshId = 112639701527136, size = V3(5, 0.1, 2.5), offset = V3(0, 0.33, -0.75) },
			{
				name = "ArrowDecal",
				meshId = 91366713649077,
				size = V3(5.875, 0.045, 1.093),
				offset = V3(0, 1.343, -0.75),
			},
			{ name = "Rollers", meshId = 86020839494315, size = V3(5.9, 0.407, 1.407), offset = V3(0, 0.5, -0.75) },
		},
	},
	SwitchBelt = {
		family = "line",
		source = "tld1",
		modelAssetId = 91698403492350,
		pieces = {
			{ name = "Body", meshId = 134774202798715, size = V3(12, 1.32, 8), offset = V3(0, 0.66, 0) },
			{ name = "Belt", meshId = 89756778448978, size = V3(12, 0.1, 7.5), offset = V3(0, 0.33, -0.2) },
			{
				name = "ArrowDecal",
				meshId = 115037553348084,
				size = V3(8.386, 0.045, 7.637),
				offset = V3(0, 1.343, -0.2),
			},
			{ name = "Rollers", meshId = 136667181767213, size = V3(11.407, 0.407, 7.153), offset = V3(0, 0.5, -0.2) },
			{ name = "Gate", meshId = 113470506420777, size = V3(2.779, 1, 2.368), offset = V3(-1, 1.22, 2.3) },
		},
		points = {
			GateHinge = V3(0, 0.72, 3.35),
		},
	},
	TiltedBelt = {
		family = "line",
		source = "tld1",
		modelAssetId = 86778935130463,
		pieces = {
			{ name = "Body", meshId = 109275806413936, size = V3(6, 3.32, 8), offset = V3(0, 1.66, 0) },
			{ name = "Belt", meshId = 98887369971807, size = V3(5, 2.1, 8), offset = V3(0, 1.33, 0) },
			{ name = "ArrowDecal", meshId = 126887593045235, size = V3(5.875, 0.318, 1.093), offset = V3(0, 2.343, 0) },
			{ name = "Rollers", meshId = 90906606656930, size = V3(5.9, 2.199, 7.407), offset = V3(0, 1.396, 0) },
		},
	},
	BeltSupport = {
		family = "line",
		source = "tld1",
		modelAssetId = 139146603427790,
		pieces = {
			{ name = "Body", meshId = 135923007231029, size = V3(6, 2.125, 1.055), offset = V3(0, 1.062, 0.028) },
		},
	},
	WoodDetector = {
		family = "line",
		source = "tld1",
		modelAssetId = 115322700999486,
		pieces = {
			{ name = "Body", meshId = 115084242039300, size = V3(8, 8.806, 4), offset = V3(0, 4.403, 0) },
			{ name = "Belt", meshId = 72953111751969, size = V3(5, 0.1, 4), offset = V3(0, 0.33, 0) },
			{ name = "Rollers", meshId = 91466161753932, size = V3(5.9, 0.407, 3.407), offset = V3(0, 0.5, 0) },
			{ name = "Lamp", meshId = 81734615468033, size = V3(0.42, 0.3, 0.42), offset = V3(0, 8.18, 0) },
		},
		points = {
			lamp = V3(0, 8.18, 0),
		},
	},
	WoodSweeper = {
		family = "line",
		source = "tld1",
		modelAssetId = 122136909587197,
		pieces = {
			{ name = "Body", meshId = 77144912159181, size = V3(1.6, 1.9, 1.6), offset = V3(0, 0.95, 0) },
			{ name = "Arm", meshId = 85325867332742, size = V3(6.6, 0.86, 0.9), offset = V3(3.3, 1.82, 0) },
		},
		points = {
			pivot = V3(0, 1.82, 0),
		},
	},
	LaserEmitter = {
		family = "line",
		source = "tld1",
		modelAssetId = 108521666150352,
		pieces = {
			{ name = "Body", meshId = 106615415699429, size = V3(1.4, 2.27, 1.43), offset = V3(0, 1.135, 0.015) },
		},
		points = {
			BeamPort = V3(0, 1.92, 0.72),
		},
	},
	LaserReceiver = {
		family = "line",
		source = "tld1",
		modelAssetId = 128157563745951,
		pieces = {
			{ name = "Body", meshId = 135048878861651, size = V3(1.4, 2.37, 1.4), offset = V3(0, 1.185, 0) },
		},
		points = {
			BeamPort = V3(0, 1.92, -0.64),
		},
	},
	SmeltingFurnace = {
		family = "ore",
		source = "tld1",
		modelAssetId = 77290455540922,
		pieces = {
			{ name = "Body", meshId = 124635139968707, size = V3(8.6, 8.8, 10), offset = V3(0, 4.4, 0.002) },
			{ name = "Belt", meshId = 121687094617487, size = V3(5, 0.1, 10), offset = V3(0, 0.33, 0) },
			{ name = "ArrowDecal", meshId = 106971447046383, size = V3(5.875, 0.045, 9.093), offset = V3(0, 1.343, 0) },
			{ name = "Rollers", meshId = 111156364093830, size = V3(5.9, 0.407, 9.707), offset = V3(0, 0.5, 0) },
			{
				name = "FurnaceDoor",
				meshId = 79585722300617,
				size = V3(0.913, 1.15, 1.384),
				offset = V3(-0.391, 2.1, -2.375),
			},
		},
		points = {
			DoorHinge = V3(-0.85, 2.1, -1.72),
			OutputTray = V3(0, 1.3, 3.9),
			SmeltIntake = V3(0, 1.5, -3.65),
		},
	},
	OreChute = {
		family = "ore",
		source = "job15",
		modelAssetId = 74854181441439,
		pieces = {
			{ name = "Body", meshId = 91355579985009, size = V3(2.9, 2.24, 2.3), offset = V3(0, 1.12, 0) },
			{ name = "Flap", meshId = 88488176788503, size = V3(1, 0.588, 0.511), offset = V3(0, 0.618, 0.625) },
		},
	},
	Prospector = {
		family = "ore",
		source = "job15",
		modelAssetId = 107559468305614,
		pieces = {
			{ name = "Body", meshId = 76460785351208, size = V3(6.56, 4.452, 3.844), offset = V3(0.03, 2.226, 0.178) },
		},
	},
	CraftBench = {
		family = "ore",
		source = "job15",
		modelAssetId = 89007502410295,
		pieces = {
			{ name = "Body", meshId = 87960541936824, size = V3(4.2, 2.5, 2), offset = V3(0, 1.25, 0) },
			{ name = "Vise", meshId = 126020693020676, size = V3(0.55, 0.4, 1.03), offset = V3(1.55, 2.05, 0.665) },
		},
	},
	Button = {
		family = "logic",
		source = "job15",
		modelAssetId = 129700741600926,
		pieces = {
			{ name = "Body", meshId = 100690134624125, size = V3(1.62, 0.8, 1.62), offset = V3(0, 0.4, 0) },
			{ name = "Cap", meshId = 96005605350652, size = V3(1.05, 0.41, 1.05), offset = V3(0, 1.045, 0) },
		},
	},
	Lever = {
		family = "logic",
		source = "job15",
		modelAssetId = 106839158017289,
		pieces = {
			{ name = "Body", meshId = 109761930546365, size = V3(1.15, 2.6, 0.48), offset = V3(0, 1.3, 0) },
			{ name = "Handle", meshId = 120019028738936, size = V3(0.28, 0.87, 0.851), offset = V3(0, 2.618, 0.265) },
		},
	},
	PressurePlate = {
		family = "logic",
		source = "job15",
		modelAssetId = 98854737801311,
		pieces = {
			{ name = "Body", meshId = 79598607884838, size = V3(3.7, 0.27, 3.7), offset = V3(0, 0.135, 0) },
			{ name = "Plate", meshId = 132100885502137, size = V3(3.15, 0.24, 3.15), offset = V3(0, 0.42, 0) },
		},
	},
	SparkSwitch = {
		family = "logic",
		source = "job15",
		modelAssetId = 116842413558596,
		pieces = {
			{ name = "Body", meshId = 97549717154510, size = V3(1.2, 3.925, 0.48), offset = V3(0, 1.962, 0) },
			{ name = "Toggle", meshId = 79992582768558, size = V3(0.16, 0.838, 0.504), offset = V3(0, 3.507, 0.479) },
		},
	},
	SparkLamp = {
		family = "logic",
		source = "job15",
		modelAssetId = 128330391426992,
		pieces = {
			{ name = "Body", meshId = 126493171652000, size = V3(1.35, 5.25, 1.35), offset = V3(0, 2.625, 0) },
			{ name = "Lamp", meshId = 134332595127508, size = V3(1.05, 0.7, 1.05), offset = V3(0, 5, 0) },
		},
	},
	Hatch = {
		family = "logic",
		source = "job15",
		modelAssetId = 114603645184039,
		pieces = {
			{ name = "Body", meshId = 128997736032155, size = V3(3.8, 0.2, 3.8), offset = V3(0, 0.1, 0) },
			{ name = "Leaf", meshId = 128713390516912, size = V3(3.2, 1.487, 2.274), offset = V3(0, 0.973, 0.393) },
		},
	},
	GateAnd = {
		family = "logic",
		source = "job15",
		modelAssetId = 130263440254894,
		pieces = {
			{ name = "Body", meshId = 72286730685700, size = V3(1.53, 0.98, 1.73), offset = V3(0, 0.49, -0.02) },
			{ name = "Lamp", meshId = 105665496849508, size = V3(0.22, 0.22, 0.16), offset = V3(0, 0.55, -0.78) },
		},
	},
	GateOr = {
		family = "logic",
		source = "job15",
		modelAssetId = 73620875360752,
		pieces = {
			{ name = "Body", meshId = 137720818161182, size = V3(1.53, 0.98, 1.73), offset = V3(0, 0.49, -0.02) },
			{ name = "Lamp", meshId = 105665496849508, size = V3(0.22, 0.22, 0.16), offset = V3(0, 0.55, -0.78) },
		},
	},
	GateXor = {
		family = "logic",
		source = "job15",
		modelAssetId = 90061927018794,
		pieces = {
			{ name = "Body", meshId = 115955909858686, size = V3(1.53, 0.98, 1.73), offset = V3(0, 0.49, -0.02) },
			{ name = "Lamp", meshId = 105665496849508, size = V3(0.22, 0.22, 0.16), offset = V3(0, 0.55, -0.78) },
		},
	},
	GateNot = {
		family = "logic",
		source = "job15",
		modelAssetId = 139264137432427,
		pieces = {
			{ name = "Body", meshId = 113453812028789, size = V3(1.53, 0.98, 1.73), offset = V3(0, 0.49, -0.015) },
			{ name = "Lamp", meshId = 105665496849508, size = V3(0.22, 0.22, 0.16), offset = V3(0, 0.55, -0.78) },
		},
	},
	Delay = {
		family = "logic",
		source = "job15",
		modelAssetId = 120033100873169,
		pieces = {
			{ name = "Body", meshId = 139422150822446, size = V3(1.6, 1.1, 1.4), offset = V3(0, 0.55, 0.015) },
			{ name = "Lamp", meshId = 84002178124720, size = V3(0.22, 0.18, 0.22), offset = V3(0.52, 1.22, 0.35) },
		},
	},
	Clock = {
		family = "logic",
		source = "job15",
		modelAssetId = 108734873645068,
		pieces = {
			{ name = "Body", meshId = 82339447914092, size = V3(1.4, 0.8, 1.52), offset = V3(0, 0.4, 0.072) },
			{ name = "Lamp", meshId = 120603346606193, size = V3(0.2, 0.2, 0.14), offset = V3(0, 0.55, -0.78) },
		},
	},
	Sustain = {
		family = "logic",
		source = "job15",
		modelAssetId = 76457772975746,
		pieces = {
			{ name = "Body", meshId = 96783433225204, size = V3(1.6, 1.1, 1.4), offset = V3(0, 0.55, 0.015) },
			{ name = "Lamp", meshId = 84002178124720, size = V3(0.22, 0.18, 0.22), offset = V3(0.52, 1.22, 0.35) },
		},
	},
}

local LAYOUT: { [string]: Layout } = {
	ChopSaw = {
		footprint = Vector2.new(6, 56),
		output = V3(0, 0, 28),
		parts = {
			{ name = "Root", size = V3(6, 0.2, 56), pos = V3(0, 0.1, 0) },
			{ name = "Conveyor", size = V3(5, 0.32, 56), pos = V3(0, 0.56, 0), group = "MillBelt" },
			{ name = "Infeed", size = V3(5, 0.32, 52), pos = V3(0, 0.56, -2) },
			{ name = "GuardRail", size = V3(0.4, 1.16, 56), pos = V3(-2.7, 0.74, 0) },
			{ name = "GuardRail", size = V3(0.4, 1.16, 56), pos = V3(2.7, 0.74, 0) },
			{ name = "BladeGuard", size = V3(3, 4, 3), pos = V3(0, 2, 24) },
			{ name = "Intake", size = V3(5, 2.4, 52), pos = V3(0, 1.92, -2) },
			{ name = "Panel", size = V3(0.24, 2.6, 3.2), pos = V3(3.16, 2.9, 24.5) },
			{ name = "Base", size = V3(6, 4, 4), pos = V3(0, 2, 26) },
		},
	},
	Millmaster100 = {
		footprint = Vector2.new(10, 16),
		output = V3(0, 1.6, 6.6),
		parts = {
			{ name = "Root", size = V3(10, 0.2, 16), pos = V3(0, 0.1, 0) },
			{ name = "Conveyor", size = V3(5, 0.32, 16), pos = V3(0, 0.56, 0), group = "MillBelt" },
			{ name = "GuardRail", size = V3(0.4, 1.16, 16), pos = V3(-2.7, 0.74, 0) },
			{ name = "GuardRail", size = V3(0.4, 1.16, 16), pos = V3(2.7, 0.74, 0) },
			{ name = "Wall", size = V3(0.65, 5.12, 10), pos = V3(-4.1, 2.96, 0) },
			{ name = "Wall", size = V3(0.65, 5.12, 10), pos = V3(4.1, 2.96, 0) },
			{ name = "Roof", size = V3(8.8, 0.36, 10), pos = V3(0, 5.62, 0), group = "Mill" },
			{ name = "FeedGuard", size = V3(8.6, 5.12, 0.45), pos = V3(0, 2.96, -5), group = "Mill" },
			{ name = "FeedGuard", size = V3(8.6, 5.12, 0.45), pos = V3(0, 2.96, 5), group = "Mill" },
			{ name = "BladeGuard", size = V3(5.2, 5, 1.3), pos = V3(0, 2.92, 0.35), group = "Mill" },
			{ name = "Intake", size = V3(6, 5, 3), pos = V3(0, 2.6, -6.5) },
			{ name = "Panel", size = V3(5.6, 2.8, 0.25), pos = V3(4.615, 2.9, 0) },
			{ name = "Blockage", size = V3(3.6, 1.15, 0.2), pos = V3(0, 8.72, 0) },
		},
	},
	Millmaster200 = {
		footprint = Vector2.new(10, 18),
		output = V3(0, 1.6, 7.6),
		parts = {
			{ name = "Root", size = V3(10, 0.2, 18), pos = V3(0, 0.1, 0) },
			{ name = "Conveyor", size = V3(5, 0.32, 18), pos = V3(0, 0.56, 0), group = "MillBelt" },
			{ name = "GuardRail", size = V3(0.4, 1.16, 18), pos = V3(-2.7, 0.74, 0) },
			{ name = "GuardRail", size = V3(0.4, 1.16, 18), pos = V3(2.7, 0.74, 0) },
			{ name = "Wall", size = V3(0.65, 6.08, 12), pos = V3(-4.1, 3.44, 0) },
			{ name = "Wall", size = V3(0.65, 6.08, 12), pos = V3(4.1, 3.44, 0) },
			{ name = "Roof", size = V3(8.8, 0.36, 12), pos = V3(0, 6.58, 0), group = "Mill" },
			{ name = "FeedGuard", size = V3(8.6, 6.08, 0.45), pos = V3(0, 3.44, -6), group = "Mill" },
			{ name = "FeedGuard", size = V3(8.6, 6.08, 0.45), pos = V3(0, 3.44, 6), group = "Mill" },
			{ name = "BladeGuard", size = V3(6.16, 5.96, 1.3), pos = V3(0, 3.4, 0.35), group = "Mill" },
			{ name = "Intake", size = V3(6, 5, 3), pos = V3(0, 2.6, -7.5) },
			{ name = "Panel", size = V3(5.6, 2.8, 0.25), pos = V3(4.615, 2.9, 0) },
			{ name = "Blockage", size = V3(3.6, 1.15, 0.2), pos = V3(0, 9.68, 0) },
		},
	},
	Millmaster200L = {
		footprint = Vector2.new(10, 26),
		output = V3(0, 1.6, 11.6),
		parts = {
			{ name = "Root", size = V3(10, 0.2, 26), pos = V3(0, 0.1, 0) },
			{ name = "Conveyor", size = V3(5, 0.32, 26), pos = V3(0, 0.56, 0), group = "MillBelt" },
			{ name = "GuardRail", size = V3(0.4, 1.16, 26), pos = V3(-2.7, 0.74, 0) },
			{ name = "GuardRail", size = V3(0.4, 1.16, 26), pos = V3(2.7, 0.74, 0) },
			{ name = "Wall", size = V3(0.65, 6.08, 20), pos = V3(-4.1, 3.44, 0) },
			{ name = "Wall", size = V3(0.65, 6.08, 20), pos = V3(4.1, 3.44, 0) },
			{ name = "Roof", size = V3(8.8, 0.36, 20), pos = V3(0, 6.58, 0), group = "Mill" },
			{ name = "FeedGuard", size = V3(8.6, 6.08, 0.45), pos = V3(0, 3.44, -10), group = "Mill" },
			{ name = "FeedGuard", size = V3(8.6, 6.08, 0.45), pos = V3(0, 3.44, 10), group = "Mill" },
			{ name = "BladeGuard", size = V3(6.16, 5.96, 1.3), pos = V3(0, 3.4, 0.35), group = "Mill" },
			{ name = "Intake", size = V3(6, 5, 3), pos = V3(0, 2.6, -11.5) },
			{ name = "Panel", size = V3(5.6, 2.8, 0.25), pos = V3(4.615, 2.9, 0) },
			{ name = "Blockage", size = V3(3.6, 1.15, 0.2), pos = V3(0, 9.68, 0) },
		},
	},
	PlanerBench = {
		footprint = Vector2.new(8, 10),
		output = V3(0, 1.6, 4),
		parts = {
			{ name = "Root", size = V3(8, 0.2, 10), pos = V3(0, 0.1, 0) },
			{ name = "Conveyor", size = V3(5, 0.32, 10), pos = V3(0, 0.56, 0), group = "MillBelt" },
			{ name = "GuardRail", size = V3(0.4, 1.16, 10), pos = V3(-2.7, 0.74, 0) },
			{ name = "GuardRail", size = V3(0.4, 1.16, 10), pos = V3(2.7, 0.74, 0) },
			{ name = "Wall", size = V3(0.6, 5.66, 6), pos = V3(-3.15, 3.23, 0) },
			{ name = "Wall", size = V3(0.6, 5.66, 6), pos = V3(3.15, 3.23, 0) },
			{ name = "Roof", size = V3(6.9, 0.4, 6), pos = V3(0, 6.96, 0) },
			{ name = "FeedGuard", size = V3(6.9, 6.06, 0.4), pos = V3(0, 3.43, -3) },
			{ name = "FeedGuard", size = V3(6.9, 6.06, 0.4), pos = V3(0, 3.43, 3) },
			{ name = "BladeGuard", size = V3(6, 5.31, 1.2), pos = V3(0, 3.055, 0) },
			{ name = "Intake", size = V3(5, 4, 3), pos = V3(0, 2.2, -3.5) },
			{ name = "Panel", size = V3(5.6, 2.8, 0.25), pos = V3(4, 2.9, 0) },
		},
	},
	PlanerHand = {
		footprint = Vector2.new(8, 8),
		output = V3(0, 1.6, 3),
		parts = {
			{ name = "Root", size = V3(8, 0.2, 8), pos = V3(0, 0.1, 0) },
			{ name = "Conveyor", size = V3(5, 0.32, 8), pos = V3(0, 0.56, 0), group = "MillBelt" },
			{ name = "GuardRail", size = V3(0.4, 1.16, 8), pos = V3(-2.7, 0.74, 0) },
			{ name = "GuardRail", size = V3(0.4, 1.16, 8), pos = V3(2.7, 0.74, 0) },
			{ name = "Wall", size = V3(0.6, 4.7, 6), pos = V3(-3.15, 2.75, 0) },
			{ name = "Wall", size = V3(0.6, 4.7, 6), pos = V3(3.15, 2.75, 0) },
			{ name = "Roof", size = V3(6.9, 0.4, 6), pos = V3(0, 6, 0) },
			{ name = "FeedGuard", size = V3(6.9, 5.1, 0.4), pos = V3(0, 2.95, -3) },
			{ name = "FeedGuard", size = V3(6.9, 5.1, 0.4), pos = V3(0, 2.95, 3) },
			{ name = "BladeGuard", size = V3(6, 4.35, 1.2), pos = V3(0, 2.575, 0) },
			{ name = "Intake", size = V3(5, 4, 3), pos = V3(0, 2.2, -2.5) },
			{ name = "Panel", size = V3(5.6, 2.8, 0.25), pos = V3(4, 2.9, 0) },
		},
	},
	PlanerIndustrial = {
		footprint = Vector2.new(8, 16),
		output = V3(0, 1.6, 7),
		parts = {
			{ name = "Root", size = V3(8, 0.2, 16), pos = V3(0, 0.1, 0) },
			{ name = "Conveyor", size = V3(5, 0.32, 16), pos = V3(0, 0.56, 0), group = "MillBelt" },
			{ name = "GuardRail", size = V3(0.4, 1.16, 16), pos = V3(-2.7, 0.74, 0) },
			{ name = "GuardRail", size = V3(0.4, 1.16, 16), pos = V3(2.7, 0.74, 0) },
			{ name = "Wall", size = V3(0.6, 6.62, 10), pos = V3(-3.15, 3.71, 0) },
			{ name = "Wall", size = V3(0.6, 6.62, 10), pos = V3(3.15, 3.71, 0) },
			{ name = "Roof", size = V3(6.9, 0.4, 10), pos = V3(0, 7.92, 0) },
			{ name = "FeedGuard", size = V3(6.9, 7.02, 0.4), pos = V3(0, 3.91, -5) },
			{ name = "FeedGuard", size = V3(6.9, 7.02, 0.4), pos = V3(0, 3.91, 5) },
			{ name = "BladeGuard", size = V3(6, 6.27, 1.2), pos = V3(0, 3.535, 0) },
			{ name = "Intake", size = V3(5, 4, 3), pos = V3(0, 2.2, -6.5) },
			{ name = "Panel", size = V3(5.6, 2.8, 0.25), pos = V3(4, 2.9, 0) },
		},
	},
	PlanerSteam = {
		footprint = Vector2.new(8, 12),
		output = V3(0, 1.6, 5),
		parts = {
			{ name = "Root", size = V3(8, 0.2, 12), pos = V3(0, 0.1, 0) },
			{ name = "Conveyor", size = V3(5, 0.32, 12), pos = V3(0, 0.56, 0), group = "MillBelt" },
			{ name = "GuardRail", size = V3(0.4, 1.16, 12), pos = V3(-2.7, 0.74, 0) },
			{ name = "GuardRail", size = V3(0.4, 1.16, 12), pos = V3(2.7, 0.74, 0) },
			{ name = "Wall", size = V3(0.6, 6.62, 8), pos = V3(-3.15, 3.71, 0) },
			{ name = "Wall", size = V3(0.6, 6.62, 8), pos = V3(3.15, 3.71, 0) },
			{ name = "Roof", size = V3(6.9, 0.4, 8), pos = V3(0, 7.92, 0) },
			{ name = "FeedGuard", size = V3(6.9, 7.02, 0.4), pos = V3(0, 3.91, -4) },
			{ name = "FeedGuard", size = V3(6.9, 7.02, 0.4), pos = V3(0, 3.91, 4) },
			{ name = "BladeGuard", size = V3(6, 6.27, 1.2), pos = V3(0, 3.535, 0) },
			{ name = "Intake", size = V3(5, 4, 3), pos = V3(0, 2.2, -4.5) },
			{ name = "Panel", size = V3(5.6, 2.8, 0.25), pos = V3(4, 2.9, 0) },
		},
	},
	SawmillRickety = {
		footprint = Vector2.new(8, 12),
		output = V3(0, 1.6, 4.6),
		parts = {
			{ name = "Root", size = V3(8, 0.2, 12), pos = V3(0, 0.1, 0) },
			{ name = "Conveyor", size = V3(5, 0.32, 12), pos = V3(0, 0.56, 0), group = "MillBelt" },
			{ name = "GuardRail", size = V3(0.4, 1.16, 12), pos = V3(-2.7, 0.74, 0) },
			{ name = "GuardRail", size = V3(0.4, 1.16, 12), pos = V3(2.7, 0.74, 0) },
			{ name = "Wall", size = V3(0.65, 4.2, 6), pos = V3(-3.1, 2.5, 0) },
			{ name = "Wall", size = V3(0.65, 4.2, 6), pos = V3(3.1, 2.5, 0) },
			{ name = "Roof", size = V3(6.8, 0.36, 6), pos = V3(0, 4.7, 0), group = "Mill" },
			{ name = "FeedGuard", size = V3(6.6, 4.2, 0.45), pos = V3(0, 2.5, -3), group = "Mill" },
			{ name = "FeedGuard", size = V3(6.6, 4.2, 0.45), pos = V3(0, 2.5, 3), group = "Mill" },
			{ name = "BladeGuard", size = V3(4.24, 4.04, 1.3), pos = V3(0, 2.44, 0.35), group = "Mill" },
			{ name = "Intake", size = V3(6, 5, 3), pos = V3(0, 2.6, -4.5) },
			{ name = "Panel", size = V3(5.6, 2.8, 0.25), pos = V3(3.615, 2.9, 0) },
			{ name = "Blockage", size = V3(3.6, 1.15, 0.2), pos = V3(0, 7.708, 0) },
		},
	},
	SawmillSturdy = {
		footprint = Vector2.new(8, 14),
		output = V3(0, 1.6, 5.6),
		parts = {
			{ name = "Root", size = V3(8, 0.2, 14), pos = V3(0, 0.1, 0) },
			{ name = "Conveyor", size = V3(5, 0.32, 14), pos = V3(0, 0.56, 0), group = "MillBelt" },
			{ name = "GuardRail", size = V3(0.4, 1.16, 14), pos = V3(-2.7, 0.74, 0) },
			{ name = "GuardRail", size = V3(0.4, 1.16, 14), pos = V3(2.7, 0.74, 0) },
			{ name = "Wall", size = V3(0.65, 4.48, 8), pos = V3(-3.1, 2.64, 0) },
			{ name = "Wall", size = V3(0.65, 4.48, 8), pos = V3(3.1, 2.64, 0) },
			{ name = "Roof", size = V3(6.8, 0.36, 8), pos = V3(0, 4.98, 0), group = "Mill" },
			{ name = "FeedGuard", size = V3(6.6, 4.48, 0.45), pos = V3(0, 2.64, -4), group = "Mill" },
			{ name = "FeedGuard", size = V3(6.6, 4.48, 0.45), pos = V3(0, 2.64, 4), group = "Mill" },
			{ name = "BladeGuard", size = V3(4.56, 4.36, 1.3), pos = V3(0, 2.6, 0.35), group = "Mill" },
			{ name = "Intake", size = V3(6, 5, 3), pos = V3(0, 2.6, -5.5) },
			{ name = "Panel", size = V3(5.6, 2.8, 0.25), pos = V3(3.615, 2.9, 0) },
			{ name = "Blockage", size = V3(3.6, 1.15, 0.2), pos = V3(0, 7.988, 0) },
		},
	},
}

-- The moving piece of a logic piece, and the hinge it swings about (mesh
-- space), as the Blender model is built: `on` and `off` are radians about
-- `axis` FROM the modelled pose. The lever is modelled tipped on, the switch
-- bat on, the hatch leaf open about 32 degrees (so "closed" lies flat), the
-- sweeper's arm parked. Directions follow each piece's modelled tilt; Studio
-- check 4 in the PR looks at all of them.
export type Pose = { piece: string, axis: "X" | "Y" | "Z", hinge: Vector3, on: number, off: number }

local POSES: { [string]: Pose } = {
	Lever = { piece = "Handle", axis = "X", hinge = V3(0, 2.15, 0.2), on = 0, off = math.rad(-70) },
	SparkSwitch = { piece = "Toggle", axis = "X", hinge = V3(0, 3.15, 0.18), on = 0, off = math.rad(-50) },
	Hatch = { piece = "Leaf", axis = "X", hinge = V3(0, 0.22, 1.45), on = math.rad(40), off = math.rad(-32) },
	WoodSweeper = { piece = "Arm", axis = "Y", hinge = V3(0, 1.82, 0), on = math.rad(-90), off = 0 },
}

function MachineMeshes.Pose(id: string): Pose?
	return POSES[id]
end

function MachineMeshes.Get(id: string): Asset?
	return ASSETS[id]
end

-- Every asset id, sorted (specs and the manifest walk this).
function MachineMeshes.Ids(): { string }
	local out: { string } = {}
	for id in pairs(ASSETS) do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

-- The meshId a piece asks MeshKit for. A forced zero (a spec) wins.
function MachineMeshes.MeshId(id: string, pieceName: string): number
	if MachineMeshes.ForcedZero[id] or MachineMeshes.ForcedZero[id .. "." .. pieceName] then
		return 0
	end
	local asset = ASSETS[id]
	if not asset then
		return 0
	end
	for _, piece in ipairs(asset.pieces) do
		if piece.name == pieceName then
			return piece.meshId
		end
	end
	return 0
end

function MachineMeshes.Piece(id: string, pieceName: string): Piece?
	local asset = ASSETS[id]
	if not asset then
		return nil
	end
	for _, piece in ipairs(asset.pieces) do
		if piece.name == pieceName then
			return piece
		end
	end
	return nil
end

-- A named point of the machine (Arbor, a hinge, a pivot), mesh space.
function MachineMeshes.Point(id: string, name: string): Vector3?
	local asset = ASSETS[id]
	if asset and asset.points then
		return asset.points[name]
	end
	return nil
end

function MachineMeshes.Layout(id: string): Layout?
	return LAYOUT[id]
end

-- Every distinct nonzero meshId, in asset order then piece order (the
-- manifest's "machines" group; each id once).
function MachineMeshes.MeshIds(): { number }
	local out: { number } = {}
	local seen: { [number]: boolean } = {}
	for _, id in ipairs(MachineMeshes.Ids()) do
		for _, piece in ipairs((ASSETS[id] :: Asset).pieces) do
			if piece.meshId ~= 0 and not seen[piece.meshId] then
				seen[piece.meshId] = true
				table.insert(out, piece.meshId)
			end
		end
	end
	return out
end

-- True when `meshId` is one of the machine pieces (preview tools).
function MachineMeshes.UsesMesh(meshId: number): boolean
	for _, id in ipairs(MachineMeshes.Ids()) do
		for _, piece in ipairs((ASSETS[id] :: Asset).pieces) do
			if piece.meshId == meshId then
				return true
			end
		end
	end
	return false
end

return MachineMeshes
