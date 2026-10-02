--!strict
-- GameConfig: gameplay tuning shared by server and client, so the two sides
-- can never disagree about a range or a cooldown. Wood and item balance
-- still lives in WoodData / ItemCatalog.

local GameConfig = {
	-- Economy
	CashCap = 2_000_000, -- most cash a wallet holds; hardcore players can grind, not run away
	-- Chopping
	SwingCooldown = 0.8, -- seconds between chops (GAME_DESIGN §14.8)
	SwingTolerance = 0.15, -- server accepts a swing this early, to absorb network jitter
	ChopRange = 12, -- studs, horizontal, character to the bark (trunk radius added per tree, §14.4)
	AutoTargetRange = 6, -- nothing under the pointer? chop the nearest tree this close to its bark

	-- Logs
	PickupPromptRange = 10, -- studs (§14.9)
	RangeTolerance = 3, -- extra studs the server allows over any prompt range
	HandCapacity = 2,
	PickupGraceSec = 45, -- the feller's exclusive pickup window: time to walk two logs to the truck and back (PLAY-15)
	LogDespawnSec = 300, -- logs left lying in the world disappear after this
	LeftLoadGraceSec = 600, -- a truck load left behind (Truck to lot, rejoin) stays yours this long
	LeftLoadDespawnSec = 1200, -- and lies there this long, so there's time to drive back for it
	-- Left-behind logs saved when you leave (profile.leftLoad) and put back
	-- when you rejoin: the biggest load there is (Logging Rig 48 + Heavy
	-- Hauler 24), so nobody loses a full truck (PLAY-14).
	MaxLeftLogs = 72,

	-- Axes (items: see AxeService)
	AxePickupByOthers = false, -- true lets anyone pick up a dropped axe (a gift); off until trading exists
	MaxDroppedAxes = 10, -- per player, lying in the world at once
	MaxOwnedAxes = 20, -- the shop stops selling past this (keeps hotbars and saves small)

	-- World (biome areas and rules are in BiomeData)
	DayCycleMinutes = 20, -- one full day and night, real minutes; the same on every server
	NightStartsAt = 19, -- in-game hour (ClockTime) the night starts
	NightEndsAt = 5, -- ... and ends; the Gloam Hollow only exists in between
	LavaDamagePerSecond = 5, -- on the Volcano without Heat Boots (100 health = 20 s)

	-- HUD
	-- Roblox's own player list opens top right on computers, right over the
	-- cash. Off until our own leaderboard (GAME_DESIGN §8 phase 7).
	ShowRobloxPlayerList = false,
	-- World prompts ("Browse axes", "Pick up", ...) in the game's own wood
	-- look (UI spec 05, PromptUI). false = Roblox's default prompts.
	CustomPrompts = true,

	-- Shops (Tool Shed, Dealership)
	ShopPromptRange = 10, -- studs from the counter to open the shop
	ShopRange = 20, -- the shop screen closes past this; the server allows + RangeTolerance

	-- Truck + sawmill
	LoadPromptRange = 8, -- studs from the tailgate (the server allows + RangeTolerance)
	SellTruckRange = 35, -- the truck bed only sells if the truck is this close to the sell zone

	-- Driving (each truck's top speed and turn rate are in ItemCatalog)
	VehiclePhysics = true, -- false = Phase 1 arcade driving (glides through trees and walls)
	VehicleAccel = 14, -- studs/s², throttle held
	VehicleBrake = 40, -- studs/s², throttle against the direction of travel
	VehicleCoast = 8, -- studs/s², no throttle
	ReverseFactor = 0.5, -- reverse top speed, as a share of forward
	TruckRecallCooldown = 10, -- seconds between "Truck to lot" presses

	-- Sound asset ids (e.g. "rbxassetid://123"). Pick them from the Creator
	-- Store; empty = silent.
	ChopSoundId = "",
	FellSoundId = "",

	-- The v2 core loop (V2_PLAN.md §2f): section trees cut anywhere, wood
	-- dragged by hand and carried loose on beds, value by volume. 1 = the
	-- v1 loop (live until the flip), 2 = v2. In Studio the workspace
	-- attribute CoreLoop overrides it (Shared/CoreLoop); live servers never.
	CoreLoop = 1,
	WoodUnit = 1.6, -- studs in one timber unit "u"; prices are $/u³, hardness per u² of cut
	StartingCash = 20, -- v2: a new player's cash
	-- cutting
	CutK = 1, -- required damage = hardness * (width/u) * (depth/u) * CutK
	CutWindow = 0.6, -- studs: a hit this near an existing cut adds to it
	CutEdge = 0.3, -- studs: cuts keep this far from a section's ends
	MaxCutsPerSection = 2,
	MinPieceVolume = 0.05, -- u³: smaller offcuts vanish
	FallNoCollideSec = 2.5, -- a falling piece passes through players this long
	FellImpulse = 8, -- studs/s pushed away from the cut face
	LeafDropSec = 1.5, -- a felled piece's leaves fall off after this
	-- wood physics
	WoodDensity = 0.15,
	WoodFriction = 0.8,
	WoodElasticity = 0.05,
	BedFriction = 1.0,
	BedAutoWeld = false, -- fallback if loads jitter on a moving bed
	-- grab and drag
	GrabRange = 12, -- studs from the character to start holding a piece
	HoldMin = 3,
	HoldMax = 14, -- studs: how far in front of the camera a held piece floats
	ReleaseDistance = 20, -- a held piece further than this lets go
	DragForcePerMass = 400,
	DragForceCap = 4000,
	DragResponsiveness = 30,
	DragMaxSpeed = 40,
	ReleaseKeepOwnerSec = 2, -- the dropper keeps network ownership briefly
	-- wood lifetime and caps
	WoodUnownedAfterSec = 600, -- off a plot, untouched: loses its owner
	WoodDespawnAfterSec = 300, -- ...then vanishes this much later
	MaxWoodPiecesPerPlayer = 150,
	MaxWoodPartsServer = 2500,
	WoodMaxSpeed = 80, -- a player-owned piece faster than this is put back
	WoodJudgeEvery = 0.5,
	SellPollSec = 0.25,
	MaxSavedPieces = 40,
	MaxSavedSections = 300,
	-- growth
	GrowTickSec = 5,
	GrowStages = 4,
	TreesPerGrowTick = 12,
	PreDeadAt = 0.9, -- of a tree's lifespan: its leaves go
	DeadSinkSec = 4,
	-- later phases (M2-M6)
	PlankYield = 1,
	PlankStep = 0.2, -- u
	PlankMinX = 0.6, -- u
	PlankMinY = 0.4, -- u
	FirstPlotPrice = 100,
	ExpansionPriceStep = 3000, -- expansion k costs ExpansionPriceStep * k
	PlotSquare = 40, -- studs
	PlotGrid = 5,
	BlueprintPricePerUnit = 10,
	VehicleRespawnFeeRate = 0.02,
	TollFee = 100,
	TollSeconds = 180,
	FerryFare = 400,
	FerryIntervalSec = 360,
	BlastingChargePrice = 220,
	BoulderRespawnSec = 1200,
	WaterDamage = 15,
	WaterTickSec = 1.5,
	ConveyorSpeed = 4,
	LogicEvalsPerTick = 200,
	LogicTickSec = 0.1,
	MaxConveyorsPerPlot = 150,
	MaxLogicPerPlot = 200,
}

return GameConfig
