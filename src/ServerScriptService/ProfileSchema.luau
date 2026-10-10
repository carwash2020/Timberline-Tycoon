--!strict
-- ProfileSchema: what a save looks like (GAME_DESIGN §14.2), the template
-- new players start from, and the migration that brings older saves up to
-- date. Kept apart from ProfileService so tests can load it without
-- DataStores.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AutomationLogic = require(ReplicatedStorage.Shared.AutomationLogic)
local BlueprintBook = require(ReplicatedStorage.Shared.BlueprintBook)
local BuildCost = require(ReplicatedStorage.Shared.BuildCost)
local DailyData = require(ReplicatedStorage.Shared.DailyData)
local EventData = require(ReplicatedStorage.Shared.EventData)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local KitPaint = require(ReplicatedStorage.Shared.KitPaint)
local PaintShop = require(ReplicatedStorage.Shared.PaintShop)
local PaidItems = require(ReplicatedStorage.Shared.PaidItems)
local EditLogic = require(ReplicatedStorage.Shared.EditLogic)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local SaveSlotLogic = require(ReplicatedStorage.Shared.SaveSlotLogic)
local TemperLogic = require(ReplicatedStorage.Shared.TemperLogic)
local SkyBinLogic = require(ReplicatedStorage.Shared.SkyBinLogic)
local SettingsLogic = require(ReplicatedStorage.Shared.SettingsLogic)
local TutorialData = require(ReplicatedStorage.Shared.TutorialData)
local WireLogic = require(ReplicatedStorage.Shared.WireLogic)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local MiningSchema = require(ReplicatedStorage.Shared.Mining.MiningSchema)
local Util = require(ReplicatedStorage.Shared.Util)

local ProfileSchema = {}

-- One blueprint on your plot: its centre in plot-local studs and 0-3
-- quarter turns (PlotLogic checks every placement).
export type PlacedItem = {
	uid: string,
	blueprintId: string,
	x: number,
	z: number,
	rot: number,
	y: number?, -- base height; missing means the ground
	wood: string?, -- filled wood; missing means the authored look
	paint: string?, -- a KitPaint id (kit pieces only); missing means natural
	fill: { units: number, slabs: number?, ingots: { [string]: number }? }?, -- kit blueprint still taking planks, slabs, ingots; missing means built
	paid: number?, -- fee charged to place a kit piece; missing means the legacy price
	len: number?, -- resized length; missing means the base. woodUnits is not saved
	lenX: number?,
	lenZ: number?,
	-- A placed sawmill's cut, in timber units (V2_PLAN.md §7). Other items
	-- leave it unset.
	data: { x: number, y: number }?,
	-- Lane W also saves `reversed = true` on a belt the owner set to run
	-- backwards and `flip = true` on a mirrored Switch Belt (cleanPlot keeps
	-- only those). Missing means forward and as built, as in every old save.
	-- They are left off this type so it stays equal to PlotLogic.Placed.
}

-- A wire from a switch to a lamp or door, by placed-item uid (WireLogic).
export type WireLink = { from: string, to: string }

-- A box the server kept when you left it in the world. uid is server-made.
-- It is never an axe, a truck, or something already placed on the plot.
export type StoredBox = {
	uid: string,
	itemId: string,
	shop: string,
	-- true: paid, but the item is still in the box (it is granted when the
	-- box is opened). Missing: an older box whose item was granted at the
	-- counter, so opening it only unpacks it.
	pending: boolean?,
}

-- One axe the player owns. Axes are items: duplicates are fine, and each
-- one can be held, switched to, dropped and picked up (AxeService).
export type AxeItem = {
	uid: string,
	id: string, -- ItemCatalog.Axes key
}

-- Today's goals and the streak (DailyService).
export type DailyState = {
	day: number, -- DailyData.Day of the goals below
	goals: { DailyData.Goal },
	streak: number, -- days in a row with every goal done
	bestStreak: number,
	lastCompleteDay: number,
	-- Cash the all-done bonus still owes. Lane E pays it at the Sawmill
	-- Foreman. 0 until then.
	bonusOwed: number,
	-- The daily-return calendar (DailyData.LoginStep; absent in older saves,
	-- read as 0): the calendar day 1..7 last paid, and the UTC day it paid.
	loginDay: number?,
	lastLoginDay: number?,
}

-- One log riding in your truck bed (saved, so a disconnect never loses a
-- haul; VehicleService rebuilds the load when your truck spawns).
-- A left-behind log saved where it lay (VehicleService puts it back).
export type LeftLog = {
	woodId: string,
	value: number,
	figure: string?,
	x: number,
	y: number,
	z: number,
}

export type BedLog = {
	woodId: string,
	value: number,
	figure: string?,
}

-- Wood waiting in the Sky Bin under the v2 loop (V2_PLAN.md §5): its wood
-- id, volume in u³, figure, whether it was a plank, and its boost (2 when
-- it was cut under 2x Wood).
export type SkyWood = {
	w: string,
	v: number,
	f: string?,
	p: boolean?,
	b: number?,
	l: boolean?, -- cut with the Lux Axe: +10% at sale
	m: number?, -- a plank's mill bonus (SellLogic.Bonus); absent means 1.0
	d: number?, -- a finished board's planer bonus; absent means 1.0
	t: number?, -- Prosperous temper; absent means 1
}

-- One loose piece of wood saved off your truck's beds (the v2 loop,
-- TruckLoad; V2_PLAN.md §4d). Compact, since every one goes into the
-- DataStore; LeftLoad has the format, cleans it and caps the list at
-- GameConfig.MaxSavedPieces pieces and MaxSavedSections sections:
--   w wood id, k "log" | "plank", f figure id?, x boost? (2 = 2x Wood),
--   l true when the Lux Axe cut it,
--   bed "BedFloor" | "TrailerBed", at its place on that bed (x, y, z,
--   rx, ry, rz), s its sections (size, place on the root, cut faces).
export type TruckPiece = {
	w: string,
	k: string,
	f: string?,
	x: number?,
	l: boolean?,
	m: number?,
	d: number?,
	t: number?, -- Prosperous temper; absent means 1
	bed: string,
	at: { number },
	s: { { number } },
}

-- The Living Forest (ForestService): figures you've revealed, Elders you helped fell.
export type ForestState = {
	figures: { [string]: number }, -- figured logs you've revealed, by figure id
	elders: number, -- Elder trees you helped fell
}

export type Profile = {
	-- Which core loop the save has been brought into (V2_PLAN.md §14): 0 =
	-- never migrated, 2 = the v2 loop (MigrateV2), 3 = plot squares, 4 =
	-- vehicle pads, 5 = foundations fields (Migrate, once the v2 loop has
	-- run). A save still on schema 0 stays there until MigrateV2.
	schema: number,
	-- Cash owed for the v1 logs bought back when the save came into the v2
	-- loop (and the top-up to StartingCash); GameServer pays it on join.
	v2Credit: number,
	cash: number,
	totalEarned: number,
	rebirths: number,
	axes: { AxeItem },
	bestAxeTier: number, -- highest axe rung ever owned (ItemCatalog.AxeTier); gates the shop
	equippedAxe: string, -- uid of the axe last held; re-equipped on spawn
	ownedTrucks: { string },
	equippedTruck: string,
	-- Set once a slot has been considered for the one-time starter truck.
	-- false (the template) means not yet. Old saves get false from
	-- Reconcile; GrantStarterTrucks then gives a truck only to a slot that
	-- was actually played. A brand-new game is marked true with no truck.
	starterTruckGranted: boolean,
	-- False until Migrate mints one storage box per owned truck. The
	-- template stays false so Reconcile does not mark an old save as already
	-- boxed and skip the mint.
	trucksBoxed: boolean,
	-- False until a save that owned a Rustbucket with no box and no pad has
	-- been given its box (the Rustbucket used to be handed over unboxed, and
	-- those saves were boxed without it). One mint, then true.
	rustbucketBoxed: boolean,
	ownedTrailers: { string },
	equippedTrailer: string, -- hitched trailer id, "" for none
	ownedBoats: { string },
	gear: { string },
	-- Your plot (PlotService). Placed items are plot-local, so the layout
	-- rebuilds on whichever plot slot you get on each server.
	plot: {
		claimed: boolean,
		tier: number, -- PlotData.Tiers index (1 = Campsite)
		placed: { PlacedItem },
		squares: { string }, -- owned squares, "x,z" (empty until land expansion)
		wires: { WireLink }, -- switch to lamp or door links (WireLogic)
		switches: { string }, -- uids of the wall switches that are on; a switch not listed is off
		pads: { any }?, -- vehicle pads (VehicleService); they travel with the base
		loose: { any }, -- loose wood on the plot; each piece may carry `t`
		logic: { any }, -- placed logic links, kept with the plot
	},
	-- Unload base (BaseLogic): account-wide, unix time the next unload is allowed.
	baseCooldownUntil: number,
	-- Boxes kept for you, per slot. Capped at StorageCap.
	storage: { StoredBox },
	-- Who may visit and build, per slot. PermissionService fills this in.
	permissions: { [string]: any },
	-- Account-wide (SaveSlotLogic.ACCOUNT): a slot swap does not move these.
	badgesAwarded: { [string]: boolean },
	badgesSent: { [string]: boolean }, -- AwardBadge returned true. Account-wide, like badgesAwarded.
	questAxe: { step: number }, -- per slot. 0 = not started
	secretsFound: { [string]: boolean },
	areasVisited: { [string]: boolean },
	-- Cosmetics earned (the Halloween Pumpkin Hat is "pumpkinHat"): account-wide.
	cosmetics: { [string]: boolean },
	-- Account-wide, like cosmetics: a tip or a guide stamp is not per slot.
	guideStamps: { [string]: boolean },
	tipsSeen: { [string]: boolean },
	dayCounter: number,
	-- The seasonal event's progress (EventData.State), per slot.
	event: EventData.State,
	compendium: { [string]: boolean },
	materials: { [string]: number }, -- gathered materials by id (Sky Shards, ...)
	forgeLogs: { [string]: number }, -- logs put into the Starfall forge, by wood id
	skyBin: { BedLog }, -- the logs waiting in the Sky Bin at the sawmill (wood, value, figure)
	forgeWood: { [string]: number }, -- v2: u³ of wood put into the Starfall forge, by wood id
	skyWood: { SkyWood }, -- v2: the wood waiting in the Sky Bin
	skyBinOwned: boolean, -- the Sky Bin item (Tool Shed, $400, one per player) is yours: boxed, in stock, or on your plot (SkyBinLogic.Migrate)
	furnitureBlueprints: { [string]: boolean }, -- legacy: store unlocks bought before blueprints were items. Read as part of the book; never written now.
	-- The buildings you own for good, in the order learned (BlueprintBook).
	-- Per slot. Using a physical blueprint adds to it.
	blueprintBook: { string },
	-- Unused rolled plans you carry or have dropped (BlueprintService).
	blueprintItems: { { uid: string, id: string } },
	-- Every player has a Hammer (BUILD_SYSTEM.md). Migrate sets it, the loadout reads it.
	hammer: boolean,
	npcFriendship: { [string]: number },
	stats: {
		treesChopped: number,
		logsSold: number,
		playtimeMin: number,
		volumeSold: number, -- v2: u³ of wood sold
		cuts: number, -- v2: cuts made through trunks and logs
	},
	tutorialDone: boolean,
	tutorialStep: number, -- index into TutorialData.Steps (QuestService)
	tutorialProgress: number, -- count toward the current step
	-- Which v2 step list tutorialStep was saved against (TutorialData.OrderV2).
	-- 0 until ApplyOrder remaps a plot-first save. Not filled by Reconcile
	-- into a value that hides an old save: 0 means "not remapped yet".
	tutorialOrder: number,
	-- A returning player's short run of the v2 tutorial (MigrateV2 sets it
	-- when the v1 tutorial was finished; QuestService clears it when done).
	tutorialRefresher: boolean,
	-- Set by Reset tutorial so a player who already owns a better axe is
	-- not immediately marked "bypassed" the next time they join.
	tutorialReplay: boolean,
	seasonId: string,
	daily: DailyState,
	-- Robux (MonetizationService)
	purchaseIds: { string }, -- recent developer product receipts already granted
	-- Game passes already confirmed (MonetizationService). A backup for
	-- UserOwnsGamePassAsync: once true, a failed ownership check on rejoin
	-- does not take the pass away.
	passes: { [string]: boolean },
	-- Passes the owner granted from the hub (PaidItems, MonetizationService.
	-- OwnerGrant): pass key -> who and when. Kept apart from `passes` so the
	-- join check ORs them in and a revoke only ever takes a grant away, never
	-- a purchase. Account-wide, like `passes`.
	ownerGrants: { [string]: { at: number, by: number, byName: string } },
	-- The last few owner grants and revokes (PaidItems.LogCap), oldest first.
	ownerGrantLog: { PaidItems.LogEntry },
	-- Paint Shop colors, per truck id, on this slot. Cosmetic only.
	truckPaint: { [string]: string },
	-- The Sky Pass (also called the Gondola Pass): a quest reward, not a shop
	-- item. Both names are the same flag.
	gondolaPass: boolean,
	skyPass: boolean,
	skyQuest: { [string]: any },
	-- Axe tempers by axe uid: { prefix, tier }. Prosperous stamps `t` on a fell.
	temper: { [string]: TemperLogic.Record },
	relics: { [string]: boolean },
	forgeOrder: { any },
	saveCooldownUntil: number,
	doubleWoodUntil: number, -- unix time the 2x Wood boost ends (0 = none)
	instantDeliveries: number, -- Instant Delivery uses left
	-- Funnel flags (MilestoneService). Additions only.
	onboarding: { [string]: boolean },
	forest: ForestState,
	truckBed: { BedLog }, -- what's in your truck bed (VehicleService)
	-- Where your truck was when its bed last changed or it last moved (x, y,
	-- z; {} until known): on a rejoin the bed only comes back into the truck
	-- if that was in town, else it waits there on the ground (VehicleService).
	-- Nil after a map-version park: the old spot is not on the new map.
	truckAt: { x: number?, y: number?, z: number? }?,
	leftLoad: { LeftLog }, -- left-behind logs still on the ground when you left (put back on rejoin)
	-- v2: loose wood a load left out of town that you hadn't fetched when
	-- you left (TruckLoad): LeftLoad pieces with bed "Ground" and a world
	-- spot `g`, put back where they lay on rejoin.
	groundLoad: { any },
	-- Wood that was on the ground when the map moved (same shape as
	-- groundLoad). Lane F puts it on the plot and clears this. Migrate only
	-- appends, and only while worldVersion is behind GameConfig.WorldVersion.
	strandedLoad: { any },
	-- The map this slot was saved on. A save that never had the field is
	-- version 1 (ProfileService writes 1 after Reconcile, before Migrate).
	-- Migrate writes GameConfig.WorldVersion exactly, never the higher of
	-- the two.
	worldVersion: number,
	-- Found secrets on this slot (not secretsFound, which is account-wide).
	secrets: { [string]: boolean },
	-- Sawmills bought at the Tool Shed and not placed yet (ids; duplicates
	-- are two mills). Placing one on your plot takes it off this list.
	sawmillStock: { string },
	-- The v2 loop's loose wood on your truck's beds (TruckLoad), saved as it
	-- rides and when you leave; rebuilt on the bed when you rejoin (on the
	-- ground where the truck stood if that wasn't in town). Unused by v1.
	truckLoad: { TruckPiece },
	settings: SettingsLogic.Settings,
	pendingCash: number, -- Robux cash that didn't fit under the wallet cap, paid out as room frees up
	-- Save slots (SaveSlotLogic). The fields above are the slot you're
	-- playing. `slots` holds all three; Robux state (purchaseIds, the 2x
	-- Wood timer, Instant Delivery, pendingCash, accountAxes) is NOT inside
	-- a slot.
	activeSlot: number,
	slotCooldownUntil: number, -- unix time a load or reset is allowed again
	accountAxes: { string }, -- pass axes (Lux Axe), kept across every slot
	-- Pick ladder, bombs, lamp, hat and the ore stash. Account-wide, the same
	-- way PickLevel is one number for the player and not one per slot.
	mining: MiningSchema.Mining,
	slots: { any },
}

-- New players start from this. Fields added here later are filled into
-- existing saves by Reconcile() on load; nothing already saved is dropped.
local TEMPLATE: Profile = {
	schema = 0,
	v2Credit = 0,
	cash = 0,
	totalEarned = 0,
	rebirths = 0,
	axes = {}, -- a Rusty Axe is added on first load (see Migrate)
	bestAxeTier = 1,
	equippedAxe = "",
	ownedTrucks = {},
	equippedTruck = "",
	starterTruckGranted = false,
	trucksBoxed = false,
	rustbucketBoxed = false,
	ownedTrailers = {},
	equippedTrailer = "",
	ownedBoats = {},
	gear = {},
	plot = {
		claimed = false,
		tier = 1,
		placed = {},
		squares = {},
		wires = {},
		switches = {},
		loose = {},
		logic = {},
	},
	baseCooldownUntil = 0,
	storage = {},
	permissions = {},
	badgesAwarded = {},
	badgesSent = {},
	questAxe = { step = 0 },
	secretsFound = {},
	areasVisited = {},
	cosmetics = {},
	event = { id = "", day = 0, progress = {}, done = {}, daysDone = 0, lastDoneDay = 0 },
	compendium = { oak = true },
	materials = {},
	forgeLogs = {},
	skyBin = {},
	forgeWood = {},
	skyWood = {},
	skyBinOwned = false,
	furnitureBlueprints = {},
	blueprintBook = BlueprintBook.Starter(),
	blueprintItems = {},
	hammer = true,
	npcFriendship = { Murph = 0, Millie = 0, Tink = 0 },
	stats = { treesChopped = 0, logsSold = 0, playtimeMin = 0, volumeSold = 0, cuts = 0 },
	tutorialDone = false,
	tutorialStep = 1,
	tutorialProgress = 0,
	tutorialOrder = 0,
	tutorialRefresher = false,
	tutorialReplay = false,
	seasonId = "spring",
	daily = {
		day = 0,
		goals = {},
		streak = 0,
		bestStreak = 0,
		lastCompleteDay = 0,
		loginDay = 0,
		lastLoginDay = 0,
		bonusOwed = 0,
	},
	purchaseIds = {},
	passes = {},
	ownerGrants = {},
	ownerGrantLog = {},
	truckPaint = {},
	gondolaPass = false,
	skyPass = false,
	skyQuest = {},
	temper = {},
	relics = {},
	forgeOrder = {},
	saveCooldownUntil = 0,
	guideStamps = {},
	tipsSeen = {},
	dayCounter = 0,
	doubleWoodUntil = 0,
	instantDeliveries = 0,
	onboarding = {},
	forest = { figures = {}, elders = 0 },
	truckBed = {},
	truckAt = {},
	leftLoad = {},
	truckLoad = {},
	groundLoad = {},
	strandedLoad = {},
	worldVersion = GameConfig.WorldVersion,
	secrets = {},
	sawmillStock = {},
	settings = SettingsLogic.Sanitize(nil),
	pendingCash = 0,
	activeSlot = 1,
	slotCooldownUntil = 0,
	accountAxes = {},
	mining = MiningSchema.Template(),
	slots = {},
}
ProfileSchema.Template = TEMPLATE

-- How many boxes a slot may keep. Past this, Migrate drops the rest.
ProfileSchema.StorageCap = 50
-- A slot's grid is PlotGrid by PlotGrid (GameConfig). Squares past that are dropped.
ProfileSchema.SquareCap = GameConfig.PlotGrid * GameConfig.PlotGrid
-- Foundations version. 2 stays the v2-loop marker (SchemaV2); Migrate bumps
-- a save to 5 only after that marker is set, so a brand-new save still
-- receives the one-time v2 migration.
ProfileSchema.SchemaV2 = 2
ProfileSchema.Schema = 5

local function markFoundationsSchema(data: any)
	local schema = data.schema
	if
		type(schema) == "number"
		and schema == schema
		and schema >= ProfileSchema.SchemaV2
		and schema < ProfileSchema.Schema
	then
		data.schema = ProfileSchema.Schema
	end
end

local function booleanMap(value: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(value) ~= "table" then
		return out
	end
	for key, flag in pairs(value) do
		if type(key) == "string" and type(flag) == "boolean" then
			out[key] = flag
		end
	end
	return out
end

local function copyQuest(value: any): { step: number }
	local step = if type(value) == "table" then value.step else nil
	if type(step) ~= "number" or step ~= step or step < 0 or step == math.huge then
		return { step = 0 }
	end
	return { step = math.floor(step) }
end

local function squareList(value: any): { string }
	local out: { string } = {}
	if type(value) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, entry in ipairs(value) do
		if type(entry) == "string" and not seen[entry] and string.match(entry, "^%-?%d+,%-?%d+$") ~= nil then
			seen[entry] = true
			table.insert(out, entry)
			if #out >= ProfileSchema.SquareCap then
				break
			end
		end
	end
	return out
end

local function takenIds(record: any): { [string]: boolean }
	local taken: { [string]: boolean } = {}
	local function keep(id: any)
		if type(id) == "string" and id ~= "" then
			taken[id] = true
		end
	end
	-- Uids only. A catalog id (axe.id, a truck id, blueprintId) is not an
	-- identity: a boxed Rustbucket is not the truck in the garage.
	if type(record.axes) == "table" then
		for _, axe in ipairs(record.axes) do
			if type(axe) == "table" then
				keep(axe.uid)
			end
		end
	end
	if type(record.ownedTrucks) == "table" then
		for _, truck in ipairs(record.ownedTrucks) do
			if type(truck) == "table" then
				keep(truck.uid)
			end
		end
	end
	local plot = record.plot
	if type(plot) == "table" and type(plot.placed) == "table" then
		for _, item in ipairs(plot.placed) do
			if type(item) == "table" then
				keep(item.uid)
			end
		end
	end
	if type(plot) == "table" and type(plot.pads) == "table" then
		for _, pad in ipairs(plot.pads) do
			if type(pad) == "table" then
				keep(pad.uid)
			end
		end
	end
	return taken
end

local function freshUid(used: { [string]: boolean }): string
	for _ = 1, 8 do
		local uid = Util.guid()
		if not used[uid] then
			return uid
		end
	end
	return Util.guid()
end

-- Trucks that still need a Dealership box: owned, and neither stored nor
-- already placed on a pad (the Rustbucket is a boxed truck like the rest).
function ProfileSchema.WaitingTrucks(record: any): { string }
	local waiting: { string } = {}
	if type(record) ~= "table" or type(record.ownedTrucks) ~= "table" then
		return waiting
	end
	local have: { [string]: boolean } = {}
	if type(record.storage) == "table" then
		for _, box in ipairs(record.storage) do
			if type(box) == "table" and box.shop == "Dealership" and type(box.itemId) == "string" then
				have[box.itemId] = true
			end
		end
	end
	local plot = record.plot
	if type(plot) == "table" and type(plot.pads) == "table" then
		for _, pad in ipairs(plot.pads) do
			if type(pad) == "table" and type(pad.id) == "string" then
				have[pad.id] = true
			end
		end
	end
	for _, id in ipairs(record.ownedTrucks) do
		if type(id) == "string" and ItemCatalog.GetTruck(id) ~= nil and have[id] ~= true then
			table.insert(waiting, id)
		end
	end
	return waiting
end

-- In a mint right now, so a join and a storage retry cannot both insert.
local minting: { [any]: boolean } = {}

-- Mints Dealership boxes for WaitingTrucks. At StorageCap it stops and
-- leaves trucksBoxed false. Uids come from takenIds plus boxes already
-- stored, so a second caller cannot duplicate a box. Never deletes a box.
function ProfileSchema.MintTruckBoxes(record: any): { string }
	if type(record) ~= "table" then
		return {}
	end
	if minting[record] then
		return {}
	end
	minting[record] = true
	if type(record.storage) ~= "table" then
		record.storage = {}
	end
	if record.trucksBoxed ~= true then
		local identity = takenIds(record)
		local used: { [string]: boolean } = {}
		for id in pairs(identity) do
			used[id] = true
		end
		for _, box in ipairs(record.storage) do
			if type(box) == "table" and type(box.uid) == "string" then
				used[box.uid] = true
			end
		end
		while #record.storage < ProfileSchema.StorageCap do
			local nextId = ProfileSchema.WaitingTrucks(record)[1]
			if nextId == nil then
				break
			end
			local uid = freshUid(used)
			used[uid] = true
			table.insert(record.storage, { uid = uid, itemId = nextId, shop = "Dealership" })
		end
		if #ProfileSchema.WaitingTrucks(record) == 0 then
			record.trucksBoxed = true
		else
			record.trucksBoxed = false
		end
	end
	-- A save from before the Rustbucket came in a box: it owns one with no
	-- box and no pad. One box, once (the flag), room permitting; with no
	-- room the flag stays false and a later join finishes the job.
	if record.rustbucketBoxed ~= true then
		local owned = type(record.ownedTrucks) == "table" and table.find(record.ownedTrucks, "Rustbucket") ~= nil
		local waitingRust = table.find(ProfileSchema.WaitingTrucks(record), "Rustbucket") ~= nil
		if owned and waitingRust then
			if #record.storage < ProfileSchema.StorageCap then
				local used: { [string]: boolean } = {}
				for id in pairs(takenIds(record)) do
					used[id] = true
				end
				for _, box in ipairs(record.storage) do
					if type(box) == "table" and type(box.uid) == "string" then
						used[box.uid] = true
					end
				end
				table.insert(record.storage, { uid = freshUid(used), itemId = "Rustbucket", shop = "Dealership" })
				record.rustbucketBoxed = true
			end
		elseif owned then
			record.rustbucketBoxed = true -- boxed or padded already
		end
	end
	local waiting = ProfileSchema.WaitingTrucks(record)
	minting[record] = nil
	return waiting
end

-- One base record (the live plot or a packed-away one): tier, squares, wires,
-- switches and every placed piece, repaired to what the rebuild can take.
-- Idempotent: running it twice changes nothing.
local function cleanPlot(plot: any)
	if plot.claimed ~= true then
		plot.claimed = false
	end
	local tier = plot.tier
	local tierOk = type(tier) == "number"
		and tier == tier
		and tier >= 1
		and tier <= #PlotData.Tiers
		and tier == math.floor(tier)
	if not tierOk then
		plot.tier = 1
	end
	plot.size = nil
	plot.wires = WireLogic.Clean(plot.wires)
	plot.switches = WireLogic.CleanSwitches(plot.switches)
	if type(plot.placed) ~= "table" then
		plot.placed = {}
	end
	local kept = {}
	for _, item in ipairs(plot.placed) do
		local x, z, rot =
			if type(item) == "table" then item.x else nil,
			if type(item) == "table" then item.z else nil,
			if type(item) == "table" then item.rot else nil
		local finite = type(x) == "number"
			and type(z) == "number"
			and type(rot) == "number"
			and x == x
			and z == z
			and rot == rot
			and x ~= math.huge
			and z ~= math.huge
			and rot ~= math.huge
			and x ~= -math.huge
			and z ~= -math.huge
			and rot ~= -math.huge
		if type(item) == "table" and type(item.uid) == "string" and item.uid ~= "" and finite then
			item.rot = math.floor(rot :: number) % 4
			item.open = nil
			if type(item.y) ~= "number" or item.y ~= item.y or item.y < 0 or item.y > PlotData.MaxBuildY then
				item.y = nil
			end
			if item.wood ~= nil and (type(item.wood) ~= "string" or WoodData.Get(item.wood) == nil) then
				item.wood = nil
			end
			-- Lane W: only `true` is saved, and only on a piece that has it.
			local beltId = item.blueprintId
			if item.reversed ~= true or not AutomationLogic.CanReverse(beltId) then
				item.reversed = nil
			end
			if item.flip ~= true or not AutomationLogic.CanFlip(beltId) then
				item.flip = nil
			end
			local bp = if type(item.blueprintId) == "string" then PlotData.Blueprint(item.blueprintId) else nil
			-- Paint is a palette id on a kit piece; anything else (an old save has
			-- none, a hand-edited one may have junk) becomes natural.
			item.paint = if bp and bp.kit == true then KitPaint.Clean(item.paint) else nil
			if not bp or bp.kit ~= true then
				item.fill = nil
				item.paid = nil
				item.len = nil
				item.lenX = nil
				item.lenZ = nil
			else
				local along = EditLogic.CanResize(bp.id)
				if along and bp.id ~= "Floor" and bp.id ~= "Floor4" then
					item.len = EditLogic.CleanLen(bp.footprint.X, item.len)
					item.lenX = nil
					item.lenZ = nil
				elseif bp.id == "Floor" or bp.id == "Floor4" then
					item.len = nil
					item.lenX = EditLogic.CleanLen(bp.footprint.X, item.lenX)
					item.lenZ = EditLogic.CleanLen(bp.footprint.Y, item.lenZ)
				else
					item.len = nil
					item.lenX = nil
					item.lenZ = nil
				end
				if item.fill ~= nil then
					-- Planks, slabs and ingots, each inside what the piece needs. A
					-- piece that has everything it needs is finished: no fill.
					item.fill = BuildCost.CleanFill(bp, item)
				end
				if item.paid ~= nil and (type(item.paid) ~= "number" or item.paid ~= item.paid or item.paid < 0) then
					item.paid = nil
				elseif type(item.paid) == "number" then
					local price = EditLogic.Fee(bp, item)
					if item.paid > price then
						item.paid = price
					end
				end
			end
			table.insert(kept, item)
		end
	end
	plot.placed = kept
end

local function finiteNumber(value: any, fallback: number): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return value
end

-- A piece list (truck, ground, stranded, sky, loose). `t` is kept only when
-- it is a Prosperous grade above 1. The same tables come back, so a second
-- pass does not copy them.
local function snapPieceList(list: any): { any }
	if type(list) ~= "table" then
		return {}
	end
	local out = {}
	for _, entry in ipairs(list) do
		if type(entry) == "table" then
			entry.t = TemperLogic.Stored(entry.t)
			table.insert(out, entry)
		end
	end
	return out
end

-- Missing worldVersion counts as 1. A non-number counts as missing.
local function worldVersionOf(record: any): number
	local v = record.worldVersion
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return 1
	end
	return v
end

-- Park this slot when it was saved on an older map than the one this server
-- is running. Writes GameConfig.WorldVersion exactly, so a server still on
-- an older map stores that older number and the next new-map join parks
-- again. Appending only what is in groundLoad, then clearing it, is what
-- keeps a second pass from duplicating pieces.
local function parkWorld(record: any)
	if type(record.strandedLoad) ~= "table" then
		record.strandedLoad = {}
	end
	if worldVersionOf(record) < GameConfig.WorldVersion then
		record.truckAt = nil
		local ground = if type(record.groundLoad) == "table" then record.groundLoad else {}
		for _, entry in ipairs(ground) do
			table.insert(record.strandedLoad, entry)
		end
		record.groundLoad = {}
	end
	record.worldVersion = GameConfig.WorldVersion
end

-- Lane E pays finished goals at the Sawmill Foreman, not the moment they
-- finish. A goal with no `paid` was already paid when it finished, so
-- `paid` becomes `done` and it is not paid again. A boolean `paid` is left
-- alone: a second Migrate changes nothing, and a goal waiting on the
-- foreman stays unpaid. `bonusOwed` defaults to 0.
local function applyDaily(record: any)
	local daily = record.daily
	if type(daily) ~= "table" then
		record.daily = {
			day = 0,
			goals = {},
			streak = 0,
			bestStreak = 0,
			lastCompleteDay = 0,
			loginDay = 0,
			lastLoginDay = 0,
			bonusOwed = 0,
		}
		return
	end
	local owed = finiteNumber(daily.bonusOwed, 0)
	daily.bonusOwed = if owed < 0 then 0 else owed
	if type(daily.goals) ~= "table" then
		daily.goals = {}
		return
	end
	for _, goal in ipairs(daily.goals) do
		if type(goal) == "table" and type(goal.paid) ~= "boolean" then
			goal.paid = goal.done == true
		end
	end
end

local function applyContract(record: any)
	record.secrets = booleanMap(record.secrets)
	record.temper = TemperLogic.Clean(record.temper)
	record.relics = booleanMap(record.relics)
	record.gondolaPass = record.gondolaPass == true or record.skyPass == true
	record.skyPass = record.gondolaPass
	if type(record.skyQuest) ~= "table" then
		record.skyQuest = {}
	end
	if type(record.forgeOrder) ~= "table" then
		record.forgeOrder = {}
	end
	record.saveCooldownUntil = finiteNumber(record.saveCooldownUntil, 0)
	if type(record.plot) == "table" then
		record.plot.loose = snapPieceList(record.plot.loose)
		if type(record.plot.logic) ~= "table" then
			record.plot.logic = {}
		end
	end
	record.truckLoad = snapPieceList(record.truckLoad)
	record.groundLoad = snapPieceList(record.groundLoad)
	record.skyWood = snapPieceList(record.skyWood)
	record.strandedLoad = snapPieceList(record.strandedLoad)
	parkWorld(record)
	applyDaily(record)
end

-- Per-slot fields. Missing or wrong-typed fields become the template.
-- storage keeps at most StorageCap boxes, each with a server uid, and
-- drops a box only when its uid is already an axe, truck, or placed-item uid.
local function applySlotFields(record: any)
	if type(record.plot) ~= "table" then
		record.plot = { claimed = false, tier = 1, placed = {}, squares = {}, wires = {}, switches = {} }
	end
	record.plot.squares = squareList(record.plot.squares)
	record.plot.wires = WireLogic.Clean(record.plot.wires)
	record.plot.switches = WireLogic.CleanSwitches(record.plot.switches)
	record.bases = nil -- the crated-bases shelf of an earlier build is gone (idempotent)
	record.questAxe = copyQuest(record.questAxe)
	-- The book, carried plans and the hammer. Adds only; safe to repeat.
	BlueprintBook.Migrate(record)
	if type(record.permissions) ~= "table" then
		record.permissions = {}
	end
	local identity = takenIds(record)
	local used: { [string]: boolean } = {}
	for id in pairs(identity) do
		used[id] = true
	end
	local kept: { StoredBox } = {}
	if type(record.storage) == "table" then
		for _, entry in ipairs(record.storage) do
			if #kept >= ProfileSchema.StorageCap then
				break
			end
			if type(entry) == "table" and type(entry.itemId) == "string" and entry.itemId ~= "" then
				local uid = if type(entry.uid) == "string" then entry.uid else ""
				local clashes = uid ~= "" and identity[uid] == true
				if not clashes then
					if uid == "" or used[uid] == true then
						uid = freshUid(used)
					end
					used[uid] = true
					local shop = if type(entry.shop) == "string" then entry.shop else ""
					table.insert(kept, {
						uid = uid,
						itemId = entry.itemId,
						shop = shop,
						pending = if entry.pending == true then true else nil,
					})
				end
			end
		end
	end
	record.storage = kept
	-- One box per owned truck. Trailers are
	-- not minted. A full storage stops the mint and leaves trucksBoxed
	-- false, so a later load can finish. Nothing already stored is removed.
	ProfileSchema.MintTruckBoxes(record)
	applyContract(record)
end

-- Account-wide fields live on the profile, never inside a slot snapshot.
local function applyAccountFields(data: any)
	data.badgesAwarded = booleanMap(data.badgesAwarded)
	data.badgesSent = booleanMap(data.badgesSent)
	data.secretsFound = booleanMap(data.secretsFound)
	data.areasVisited = booleanMap(data.areasVisited)
	data.cosmetics = booleanMap(data.cosmetics)
	data.guideStamps = booleanMap(data.guideStamps)
	data.tipsSeen = booleanMap(data.tipsSeen)
	data.dayCounter = finiteNumber(data.dayCounter, 0)
	data.tollPaidUntil = nil
	-- A copy left inside the active slot is the account's if the profile
	-- itself has none yet. A second migrate finds the account field and
	-- leaves it.
	if data.mining == nil and type(data.slots) == "table" then
		local active = data.slots[data.activeSlot]
		if type(active) == "table" and type(active.mining) == "table" then
			data.mining = active.mining
		end
	end
	data.mining = MiningSchema.Migrate(data.mining)
end

local function stripAccountFields(slot: any)
	slot.badgesAwarded = nil
	slot.badgesSent = nil
	slot.secretsFound = nil
	slot.areasVisited = nil
	slot.cosmetics = nil
	slot.guideStamps = nil
	slot.tipsSeen = nil
	slot.dayCounter = nil
	slot.tollPaidUntil = nil
	slot.mining = nil
end

-- Brings older saves up to date. Call on every load, after ProfileStore's
-- Reconcile() has filled in new fields.
function ProfileSchema.Migrate(data: any)
	-- Saves from before axes were items listed axe ids in `ownedAxes`.
	if #data.axes == 0 then
		local oldEquipped = data.equippedAxe
		for _, id in ipairs(data.ownedAxes or { "RustyAxe" }) do
			local item = { uid = Util.guid(), id = id }
			table.insert(data.axes, item)
			if id == oldEquipped then
				data.equippedAxe = item.uid
			end
		end
	end
	data.ownedAxes = nil
	for _, item in ipairs(data.axes) do
		data.bestAxeTier = math.max(data.bestAxeTier, ItemCatalog.AxeTier(item.id) or 1)
	end
	-- Saves from before plots were built had a `size` (tiers replaced it) and
	-- could only hold an empty layout; anything not in plot-local x/z/rot
	-- form is dropped. NaN or infinite coordinates would break the rebuild
	-- (PivotTo) and leave the player with no plot for the session.
	if type(data.plot) ~= "table" then
		data.plot = { claimed = false, tier = 1, placed = {}, squares = {}, wires = {}, switches = {} }
	end
	cleanPlot(data.plot)
	-- The unload-base cooldown (BaseLogic). A shelf of crated bases from an
	-- earlier, never-released build is dropped; its active base was always
	-- profile.plot, which is kept. Idempotent.
	data.bases = nil
	if type(data.baseCooldownUntil) ~= "number" or data.baseCooldownUntil ~= data.baseCooldownUntil then
		data.baseCooldownUntil = 0
	end
	-- Saves from before the Hidden Grain kept only wood ids in the Sky Bin.
	for i, entry in ipairs(data.skyBin) do
		if type(entry) == "string" then
			local wood = WoodData.Get(entry)
			data.skyBin[i] = { woodId = entry, value = if wood then wood.pricePerLog else 0 }
		end
	end
	-- The Sky Bin became an item: a save with wood in it (or a bin) owns one.
	SkyBinLogic.Migrate(data, Util.guid, ProfileSchema.StorageCap)
	-- Reconcile fills a missing settings table, not keys added inside it.
	data.settings = SettingsLogic.Sanitize(data.settings)
	if type(data.passes) ~= "table" then
		data.passes = {}
	end
	-- Owner grants and their log: cleaned each load, so a bad entry never
	-- reaches the join check (idempotent).
	data.ownerGrants = PaidItems.CleanGrants(data.ownerGrants)
	data.ownerGrantLog = PaidItems.CleanLog(data.ownerGrantLog)
	-- Per slot, with the truck. Anything that isn't a palette color on a
	-- real truck is dropped.
	data.truckPaint = PaintShop.Sanitize(data.truckPaint)
	if data.tutorialReplay ~= true then
		data.tutorialReplay = false
	end
	-- One save becomes slot 1. Live cash, axes, plot and wood stay put.
	-- Settings and passes are account-wide, so they are not copied into a slot.
	-- Foundations fields are filled first so the active slot's snapshot
	-- already has them. Parked slots are filled after, and account-wide
	-- keys are stripped out of every snapshot.
	applySlotFields(data)
	applyAccountFields(data)
	SaveSlotLogic.Migrate(data, TEMPLATE, function()
		return Util.guid()
	end, os.time())
	-- The starter grant above can give a played slot its Rustbucket after the
	-- live mint ran: box it now, and mirror the result onto the active slot's
	-- snapshot so that one box is not minted a second time with another uid.
	ProfileSchema.MintTruckBoxes(data)
	local activeSlot = if type(data.slots) == "table" then data.slots[data.activeSlot] else nil
	if type(activeSlot) == "table" then
		activeSlot.storage = Util.deepCopy(data.storage)
		activeSlot.trucksBoxed = data.trucksBoxed
		activeSlot.rustbucketBoxed = data.rustbucketBoxed
	end
	if type(data.slots) == "table" then
		for _, slot in ipairs(data.slots) do
			if type(slot) == "table" then
				applySlotFields(slot)
				stripAccountFields(slot)
			end
		end
	end
	markFoundationsSchema(data)
	data.tollPaidUntil = nil
end

local function applyTutorialOrders(data: any)
	TutorialData.ApplyOrder(data)
	if type(data.slots) ~= "table" then
		return
	end
	for _, slot in pairs(data.slots) do
		if type(slot) == "table" then
			TutorialData.ApplyOrder(slot)
		end
	end
end

-- The v2 loop (V2_PLAN.md §14) ---------------------------------------------

-- u³ of forge wood each v1 log in the Starfall forge becomes (40 lumenwood
-- logs to 60 u³), never more than the recipe takes.
ProfileSchema.ForgeU3PerLog = 1.5

export type MigrateV2Result = {
	boughtBack: number, -- $ of v1 logs (truck bed, left-behind, Sky Bin) added to v2Credit by this call
	toppedUp: number, -- $ added to v2Credit so cash + credit reaches StartingCash
	migrated: boolean, -- this call brought the save into the v2 loop (schema 2)
}

-- What the saved v1 logs in `list` are worth (their saved per-log values,
-- figures included); malformed entries count for nothing.
local function logsValue(list: any): number
	if type(list) ~= "table" then
		return 0
	end
	local total = 0
	for _, entry in ipairs(list) do
		local v: any = nil
		if type(entry) == "table" then
			v = entry.value
		elseif type(entry) == "string" then
			local wood = WoodData.Get(entry)
			v = if wood then wood.pricePerLog else nil
		end
		if type(v) == "number" and v == v and v > 0 and v < math.huge then
			total += v
		end
	end
	return total
end

local function count(list: any): number
	return if type(list) == "table" then #list else 0
end

-- The most of each wood any forge recipe takes, in v1 logs.
local function forgeLogCaps(): { [string]: number }
	local caps: { [string]: number } = {}
	for _, axe in pairs(ItemCatalog.Axes) do
		local recipe = axe.forge
		if recipe then
			for woodId, n in pairs(recipe.logs) do
				caps[woodId] = math.max(caps[woodId] or 0, n)
			end
		end
	end
	return caps
end

-- Brings a save into the v2 core loop. Call on every join under the v2
-- loop, after Migrate. Never writes cash: what it owes goes in v2Credit,
-- which GameServer pays through EconomyService.
--   * Every call: v1 logs still on hand (truck bed, left-behind logs, Sky
--     Bin) are bought back at their saved values into v2Credit and the
--     lists emptied (an old v1 server may have refilled them).
--   * Once (schema below 2): cash + credit is topped up to StartingCash,
--     the forge's v1 logs become forge wood (forgeLogs is kept, so a
--     rollback to v1 loses nothing), tutorial progress restarts on a step
--     whose unit changed (TutorialData.KeepsProgressV2), a finished
--     tutorial reopens as a refresher of the new steps, daily goals rolled
--     from the v1 pool are rerolled (the streak is kept), and schema = 2.
-- Idempotent: a second call finds nothing to buy back and changes nothing.
local dropPlanting: (data: any) -> ()

function ProfileSchema.MigrateV2(data: any, startingCash: number?): MigrateV2Result
	if type(data.schema) ~= "number" or data.schema ~= data.schema then
		data.schema = 0
	end
	if type(data.v2Credit) ~= "number" or data.v2Credit ~= data.v2Credit or data.v2Credit < 0 then
		data.v2Credit = 0
	end
	if type(data.forgeWood) ~= "table" then
		data.forgeWood = {}
	end
	if type(data.skyWood) ~= "table" then
		data.skyWood = {}
	end
	if type(data.stats) ~= "table" then
		data.stats = {}
	end
	data.stats.volumeSold = tonumber(data.stats.volumeSold) or 0
	data.stats.cuts = tonumber(data.stats.cuts) or 0

	local result: MigrateV2Result = { boughtBack = 0, toppedUp = 0, migrated = false }
	local bedHadLogs = count(data.truckBed) > 0
	if bedHadLogs or count(data.leftLoad) > 0 or count(data.skyBin) > 0 then
		local value = logsValue(data.truckBed) + logsValue(data.leftLoad) + logsValue(data.skyBin)
		result.boughtBack = math.floor(value + 0.5)
		data.v2Credit += result.boughtBack
		data.truckBed = {}
		data.leftLoad = {}
		data.skyBin = {}
		if bedHadLogs then
			data.truckAt = {}
		end
	end
	dropPlanting(data)
	if data.schema >= ProfileSchema.SchemaV2 then
		applyTutorialOrders(data)
		markFoundationsSchema(data)
		return result
	end

	data.truckAt = {}
	local start = startingCash or GameConfig.StartingCash
	local cash = if type(data.cash) == "number" and data.cash == data.cash then data.cash else 0
	local short = math.floor(start - (cash + data.v2Credit))
	if short > 0 then
		data.v2Credit += short
		result.toppedUp = short
	end
	if type(data.forgeLogs) == "table" then
		for woodId, cap in pairs(forgeLogCaps()) do
			local logs = data.forgeLogs[woodId]
			if type(logs) == "number" and logs > 0 then
				local u3 = math.min(cap, logs) * ProfileSchema.ForgeU3PerLog
				data.forgeWood[woodId] = math.max(tonumber(data.forgeWood[woodId]) or 0, u3)
			end
		end
	end
	local step = tonumber(data.tutorialStep) or 1
	if data.tutorialDone then
		-- The loop changed under them: a short refresher of the new steps
		-- (QuestService, TutorialData.RefresherLast).
		data.tutorialDone = false
		data.tutorialStep = 1
		data.tutorialProgress = 0
		data.tutorialRefresher = true
	elseif not TutorialData.KeepsProgressV2(step) then
		data.tutorialProgress = 0
	end
	local daily = data.daily
	if type(daily) == "table" and type(daily.goals) == "table" and DailyData.NeedsReroll(daily.goals, 2) then
		daily.day = 0
	end
	data.schema = ProfileSchema.SchemaV2
	markFoundationsSchema(data)
	result.migrated = true
	applyTutorialOrders(data)
	return result
end

-- Planting counts and royalties go. No refund. Figures and
-- Elders stay. Runs for a save that already took the v2 path and for one
-- taking it now.
dropPlanting = function(data: any)
	local function one(record: any)
		if type(record) ~= "table" then
			return
		end
		record.heartseeds = nil
		local forest = record.forest
		if type(forest) == "table" then
			forest.planted = nil
			forest.harvested = nil
			forest.royalties = nil
		end
	end
	one(data)
	if type(data.slots) == "table" then
		for _, slot in pairs(data.slots) do
			one(slot)
		end
	end
end

-- The toast for cash MigrateV2 left owed, or nil for none: the buy-back
-- of logs on hand, else a starter's top-up.
function ProfileSchema.CreditText(paid: number, boughtBack: number): string?
	if paid <= 0 then
		return nil
	end
	if boughtBack > 0 then
		return string.format("Murph bought back the logs you had on hand: +%s", Util.formatCash(paid))
	end
	return string.format("Murph chipped in %s to get you started.", Util.formatCash(paid))
end

-- How many granted receipts to remember. Roblox retries an unconfirmed
-- receipt for a while; 100 is far more than can be in flight at once.
ProfileSchema.PurchaseIdCacheSize = 100

-- Records a developer product receipt. True if it's new (grant it); false
-- if it was already granted (a retry after a crash or a slow save).
function ProfileSchema.RecordPurchase(data: any, purchaseId: string): boolean
	local ids = data.purchaseIds
	if table.find(ids, purchaseId) then
		return false
	end
	table.insert(ids, purchaseId)
	while #ids > ProfileSchema.PurchaseIdCacheSize do
		table.remove(ids, 1)
	end
	return true
end

return ProfileSchema
