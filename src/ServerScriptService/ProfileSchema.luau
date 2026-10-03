--!strict
-- ProfileSchema: what a save looks like (GAME_DESIGN §14.2), the template
-- new players start from, and the migration that brings older saves up to
-- date. Kept apart from ProfileService so tests can load it without
-- DataStores.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyData = require(ReplicatedStorage.Shared.DailyData)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local PlotData = require(ReplicatedStorage.Shared.PlotData)
local SaveSlotLogic = require(ReplicatedStorage.Shared.SaveSlotLogic)
local SettingsLogic = require(ReplicatedStorage.Shared.SettingsLogic)
local TutorialData = require(ReplicatedStorage.Shared.TutorialData)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
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
	-- A placed sawmill's cut, in timber units (V2_PLAN.md §7). Other items
	-- leave it unset.
	data: { x: number, y: number }?,
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
	bed: string,
	at: { number },
	s: { { number } },
}

-- The Living Forest (ForestService): your Heartseeds and steward record.
export type ForestState = {
	planted: number, -- Heartseeds you've planted in the wild
	harvested: number, -- your planted trees others have felled
	royalties: number, -- cash earned from those (the planter's share)
	figures: { [string]: number }, -- figured logs you've revealed, by figure id
	elders: number, -- Elder trees you helped fell
}

export type Profile = {
	-- Which core loop the save has been brought into (V2_PLAN.md §14): 0 =
	-- never migrated, 2 = the v2 loop (MigrateV2), 3 = plot squares, 4 =
	-- vehicle pads.
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
	},
	compendium: { [string]: boolean },
	materials: { [string]: number }, -- gathered materials by id (Sky Shards, ...)
	forgeLogs: { [string]: number }, -- logs put into the Starfall forge, by wood id
	skyBin: { BedLog }, -- the logs waiting in the Sky Bin at the sawmill (wood, value, figure)
	forgeWood: { [string]: number }, -- v2: u³ of wood put into the Starfall forge, by wood id
	skyWood: { SkyWood }, -- v2: the wood waiting in the Sky Bin
	furnitureBlueprints: { [string]: boolean },
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
	doubleWoodUntil: number, -- unix time the 2x Wood boost ends (0 = none)
	instantDeliveries: number, -- Instant Delivery uses left
	onboarding: { [string]: boolean }, -- analytics funnel steps already logged (MilestoneService)
	heartseeds: { [string]: number }, -- Heartseeds by wood id (ForestService)
	forest: ForestState,
	truckBed: { BedLog }, -- what's in your truck bed (VehicleService)
	-- Where your truck was when its bed last changed or it last moved (x, y,
	-- z; {} until known): on a rejoin the bed only comes back into the truck
	-- if that was in town, else it waits there on the ground (VehicleService).
	truckAt: { x: number?, y: number?, z: number? },
	leftLoad: { LeftLog }, -- left-behind logs still on the ground when you left (put back on rejoin)
	-- v2: loose wood a load left out of town that you hadn't fetched when
	-- you left (TruckLoad): LeftLoad pieces with bed "Ground" and a world
	-- spot `g`, put back where they lay on rejoin.
	groundLoad: { any },
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
	ownedTrucks = { "Rustbucket" },
	equippedTruck = "Rustbucket",
	ownedTrailers = {},
	equippedTrailer = "",
	ownedBoats = {},
	gear = {},
	plot = { claimed = false, tier = 1, placed = {} },
	compendium = { oak = true },
	materials = {},
	forgeLogs = {},
	skyBin = {},
	forgeWood = {},
	skyWood = {},
	furnitureBlueprints = {},
	npcFriendship = { Murph = 0, Millie = 0, Tink = 0 },
	stats = { treesChopped = 0, logsSold = 0, playtimeMin = 0, volumeSold = 0, cuts = 0 },
	tutorialDone = false,
	tutorialStep = 1,
	tutorialProgress = 0,
	tutorialRefresher = false,
	tutorialReplay = false,
	seasonId = "spring",
	daily = { day = 0, goals = {}, streak = 0, bestStreak = 0, lastCompleteDay = 0 },
	purchaseIds = {},
	passes = {},
	doubleWoodUntil = 0,
	instantDeliveries = 0,
	onboarding = {},
	heartseeds = {},
	forest = { planted = 0, harvested = 0, royalties = 0, figures = {}, elders = 0 },
	truckBed = {},
	truckAt = {},
	leftLoad = {},
	truckLoad = {},
	groundLoad = {},
	sawmillStock = {},
	settings = SettingsLogic.Sanitize(nil),
	pendingCash = 0,
	activeSlot = 1,
	slotCooldownUntil = 0,
	accountAxes = {},
	slots = {},
}
ProfileSchema.Template = TEMPLATE

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
		data.plot = { claimed = false, tier = 1, placed = {} }
	end
	if data.plot.claimed ~= true then
		data.plot.claimed = false
	end
	local tier = data.plot.tier
	local tierOk = type(tier) == "number"
		and tier == tier
		and tier >= 1
		and tier <= #PlotData.Tiers
		and tier == math.floor(tier)
	if not tierOk then
		data.plot.tier = 1
	end
	data.plot.size = nil
	if type(data.plot.placed) ~= "table" then
		data.plot.placed = {}
	end
	local kept = {}
	for _, item in ipairs(data.plot.placed) do
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
			table.insert(kept, item)
		end
	end
	data.plot.placed = kept
	-- Saves from before the Hidden Grain kept only wood ids in the Sky Bin.
	for i, entry in ipairs(data.skyBin) do
		if type(entry) == "string" then
			local wood = WoodData.Get(entry)
			data.skyBin[i] = { woodId = entry, value = if wood then wood.pricePerLog else 0 }
		end
	end
	-- Reconcile fills a missing settings table, not keys added inside it.
	data.settings = SettingsLogic.Sanitize(data.settings)
	if type(data.passes) ~= "table" then
		data.passes = {}
	end
	if data.tutorialReplay ~= true then
		data.tutorialReplay = false
	end
	-- One save becomes slot 1. Live cash, axes, plot and wood stay put.
	-- Settings and passes are account-wide, so they are not copied into a slot.
	SaveSlotLogic.Migrate(data, TEMPLATE, function()
		return Util.guid()
	end, os.time())
end

-- The v2 loop (V2_PLAN.md §14) ---------------------------------------------

ProfileSchema.SchemaV2 = 2
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
	if data.schema >= ProfileSchema.SchemaV2 then
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
	result.migrated = true
	return result
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
