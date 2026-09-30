--!strict
-- ProfileService: the SOLE reader/writer of player save data.
-- A thin wrapper over ProfileStore (loleris, vendored in Vendor/), which does
-- the hard parts: session locking across servers, waiting out (then taking
-- over) another server's lock, autosave, retries, and flushing on shutdown.
-- EconomyService is the only module allowed to change profile.cash.
--
-- DataStore "PlayerProfiles", key "profile_<UserId>" (GAME_DESIGN §14.2).
-- In Studio without "Enable Studio Access to API Services", ProfileStore
-- quietly uses an in-memory mock store, so data won't persist between tests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Util = require(ReplicatedStorage.Shared.Util)
local ProfileStore = require(script.Parent.Vendor.ProfileStore)

local ProfileService = {}

local STORE_NAME = "PlayerProfiles"
local KEY_PREFIX = "profile_"

export type PlacedItem = {
	uid: string,
	blueprintId: string,
	cframe: { number }, -- 12 components, validated server-side
	data: { [string]: any }?,
}

-- One axe the player owns. Axes are items: duplicates are fine, and each
-- one can be held, switched to, dropped and picked up (AxeService).
export type AxeItem = {
	uid: string,
	id: string, -- ItemCatalog.Axes key
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
	ownedBoats: { string },
	gear: { string },
	plot: {
		claimed: boolean,
		size: number,
		placed: { PlacedItem },
	},
	compendium: { [string]: boolean },
	furnitureBlueprints: { [string]: boolean },
	npcFriendship: { [string]: number },
	stats: {
		treesChopped: number,
		logsSold: number,
		playtimeMin: number,
	},
	tutorialDone: boolean,
	seasonId: string,
	onboarding: { [string]: boolean }, -- analytics funnel steps already logged (MilestoneService)
}

-- New players start from this. Fields added here later are filled into
-- existing saves by Reconcile() on load; nothing already saved is dropped.
local TEMPLATE: Profile = {
	cash = 0,
	totalEarned = 0,
	rebirths = 0,
	axes = {}, -- a Rusty Axe is added on first load (see migrate)
	bestAxeTier = 1,
	equippedAxe = "",
	ownedTrucks = { "Rustbucket" },
	equippedTruck = "Rustbucket",
	ownedTrailers = {},
	ownedBoats = {},
	gear = {},
	plot = { claimed = false, size = 120, placed = {} },
	compendium = { oak = true },
	furnitureBlueprints = {},
	npcFriendship = { Murph = 0, Millie = 0, Tink = 0 },
	stats = { treesChopped = 0, logsSold = 0, playtimeMin = 0 },
	tutorialDone = false,
	seasonId = "spring",
	onboarding = {},
}

local store = ProfileStore.New(STORE_NAME, TEMPLATE)

-- Brings older saves up to date after Reconcile() has filled in new fields.
local function migrate(data: any)
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
end
local sessions: { [Player]: any } = {}

-- Starts the player's save session. Yields until the save is loaded:
-- ProfileStore keeps retrying and, if another server still holds the save
-- (the player just hopped servers), asks it to let go and then takes over.
-- Returns (profile, nil) on success, or (nil, "left" | "failed").
function ProfileService.LoadProfile(player: Player): (Profile?, string?)
	local session = store:StartSessionAsync(KEY_PREFIX .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if session == nil then
		return nil, if player.Parent ~= Players then "left" else "failed"
	end

	session:AddUserId(player.UserId) -- GDPR: lets Roblox erase this key on request
	session:Reconcile()
	migrate(session.Data)

	-- The player may have left while we were waiting on the DataStore.
	if player.Parent ~= Players then
		session:EndSession()
		return nil, "left"
	end

	session.OnSessionEnd:Connect(function()
		if sessions[player] ~= session then
			return -- we ended it ourselves in ReleaseProfile (player left)
		end
		sessions[player] = nil
		if player.Parent == Players and not ProfileStore.IsClosing then
			-- Another server took the save over; this copy must stop playing.
			player:Kick("Your save was opened on another server. Please rejoin.")
		end
	end)
	sessions[player] = session
	return session.Data :: Profile, nil
end

function ProfileService.GetProfile(player: Player): Profile?
	local session = sessions[player]
	if session == nil then
		return nil
	end
	return session.Data :: Profile
end

-- Final save + release of the session lock. Call when the player leaves.
function ProfileService.ReleaseProfile(player: Player)
	local session = sessions[player]
	sessions[player] = nil
	if session ~= nil then
		session:EndSession()
	end
end

return ProfileService
