--!strict
-- ProfileSchema: what a save looks like (GAME_DESIGN §14.2), the template
-- new players start from, and the migration that brings older saves up to
-- date. Kept apart from ProfileService so tests can load it without
-- DataStores.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyData = require(ReplicatedStorage.Shared.DailyData)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
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
export type BedLog = {
	woodId: string,
	value: number,
	figure: string?,
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
	furnitureBlueprints: { [string]: boolean },
	npcFriendship: { [string]: number },
	stats: {
		treesChopped: number,
		logsSold: number,
		playtimeMin: number,
	},
	tutorialDone: boolean,
	tutorialStep: number, -- index into TutorialData.Steps (QuestService)
	tutorialProgress: number, -- count toward the current step
	seasonId: string,
	daily: DailyState,
	-- Robux (MonetizationService)
	purchaseIds: { string }, -- recent developer product receipts already granted
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
	settings: { music: boolean, sfx: boolean },
	pendingCash: number, -- Robux cash that didn't fit under the wallet cap, paid out as room frees up
}

-- New players start from this. Fields added here later are filled into
-- existing saves by Reconcile() on load; nothing already saved is dropped.
local TEMPLATE: Profile = {
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
	furnitureBlueprints = {},
	npcFriendship = { Murph = 0, Millie = 0, Tink = 0 },
	stats = { treesChopped = 0, logsSold = 0, playtimeMin = 0 },
	tutorialDone = false,
	tutorialStep = 1,
	tutorialProgress = 0,
	seasonId = "spring",
	daily = { day = 0, goals = {}, streak = 0, bestStreak = 0, lastCompleteDay = 0 },
	purchaseIds = {},
	doubleWoodUntil = 0,
	instantDeliveries = 0,
	onboarding = {},
	heartseeds = {},
	forest = { planted = 0, harvested = 0, royalties = 0, figures = {}, elders = 0 },
	truckBed = {},
	truckAt = {},
	settings = { music = true, sfx = true },
	pendingCash = 0,
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
	-- form is dropped.
	data.plot.size = nil
	local kept = {}
	for _, item in ipairs(data.plot.placed) do
		if type(item.x) == "number" and type(item.z) == "number" and type(item.rot) == "number" then
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
