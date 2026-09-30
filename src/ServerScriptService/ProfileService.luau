-- ProfileService: the SOLE reader/writer of the PlayerProfiles DataStore.
-- Every other service goes through here for profile data; EconomyService is
-- the only module allowed to change profile.cash.
--
-- Safety rules:
--   * Session lock via UpdateAsync so two servers can't double-spend.
--   * If a load fails, the player gets a session-only profile and nothing
--     is ever saved for them (never overwrite a good save with a blank one).
--   * Autosave every 120s + on PlayerRemoving + on server shutdown.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Shared.Util)

local ProfileService = {}

local STORE_NAME = "PlayerProfiles"
local KEY_PREFIX = "profile_"
local LOCK_TTL = 600 -- seconds; a lock older than this is considered stale
local LOAD_RETRIES = 3
export type Profile = {
	cash: number,
	totalEarned: number,
	rebirths: number,
	ownedAxes: { string },
	equippedAxe: string,
	ownedTrucks: { string },
	equippedTruck: string,
	ownedTrailers: { string },
	ownedBoats: { string },
	gear: { string },
	plot: {
		claimed: boolean,
		size: number,
		placed: { any },
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
}

local store = DataStoreService:GetDataStore(STORE_NAME)
local SERVER_ID = HttpService:GenerateGUID(false)

local profiles: { [number]: Profile } = {}
local sessionOnly: { [number]: boolean } = {}

local function defaultProfile(): Profile
	return {
		cash = 0,
		totalEarned = 0,
		rebirths = 0,
		ownedAxes = { "RustyAxe" },
		equippedAxe = "RustyAxe",
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
	}
end

-- Merge a loaded table over the defaults so new fields always exist.
-- Arrays are replaced wholesale; dictionaries merge key-by-key.
local function mergeInto(defaults: any, loaded: any): any
	if type(defaults) ~= "table" or type(loaded) ~= "table" then
		return loaded
	end
	if #defaults > 0 or #loaded > 0 then
		return Util.deepCopy(loaded) -- it's an array: take it as-is
	end
	local out: { [any]: any } = {}
	for k, v in pairs(defaults) do
		if loaded[k] ~= nil then
			out[k] = mergeInto(v, loaded[k])
		else
			out[k] = Util.deepCopy(v)
		end
	end
	return out
end

-- Loads the profile and acquires the session lock.
-- Returns (profile, nil) on success,
--         (nil, "locked") if another server holds a fresh lock,
--         (profile, "sessionOnly") if the load failed (nothing will be saved).
function ProfileService.LoadProfile(player: Player): (Profile?, string?)
	local userId = player.UserId
	local key = KEY_PREFIX .. userId

	for attempt = 1, LOAD_RETRIES do
		local ok, result = pcall(function()
			return store:UpdateAsync(key, function(old: any)
				old = old or {}
				local lock = old.lock
				local now = os.time()
				if lock and lock.serverId ~= SERVER_ID and (now - (lock.time or 0)) < LOCK_TTL then
					return old -- session active elsewhere; do not steal it
				end
				old.lock = { serverId = SERVER_ID, time = now }
				return old
			end)
		end)
		if ok and result then
			local data: any = result
			if data.lock and data.lock.serverId == SERVER_ID then
				local profile: Profile = mergeInto(defaultProfile(), data.profile or {})
				profiles[userId] = profile
				return profile, nil
			else
				return nil, "locked"
			end
		end
		warn(string.format("[ProfileService] Load attempt %d failed for %s", attempt, player.Name))
		task.wait(2 ^ attempt)
	end

	-- Load failed: play session-only. NEVER write this blank profile.
	local fallback = defaultProfile()
	profiles[userId] = fallback
	sessionOnly[userId] = true
	player:SetAttribute("ProfileSessionOnly", true)
	warn(string.format("[ProfileService] %s is SESSION-ONLY (load failed); saving disabled", player.Name))
	return fallback, "sessionOnly"
end

function ProfileService.GetProfile(player: Player): Profile?
	return profiles[player.UserId]
end

function ProfileService.IsSessionOnly(player: Player): boolean
	return sessionOnly[player.UserId] == true
end

-- Saves the profile. Never overwrites if we lost the session lock or the
-- profile is session-only. releaseLock=true on final save (player leaving).
function ProfileService.SaveProfile(player: Player, releaseLock: boolean?): boolean
	local userId = player.UserId
	if sessionOnly[userId] then
		return false
	end
	local data = profiles[userId]
	if not data then
		return false
	end
	local key = KEY_PREFIX .. userId
	local snapshot = Util.deepCopy(data)
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old: any)
			old = old or {}
			if old.lock and old.lock.serverId ~= SERVER_ID then
				return old -- lost the lock; don't clobber the other session
			end
			old.profile = snapshot
			if releaseLock then
				old.lock = nil
			else
				old.lock = { serverId = SERVER_ID, time = os.time() }
			end
			return old
		end)
	end)
	if not ok then
		warn(string.format("[ProfileService] Save failed for %s: %s", player.Name, tostring(err)))
	end
	return ok
end

function ProfileService.SaveAll(releaseLock: boolean?)
	for _, player in ipairs(Players:GetPlayers()) do
		ProfileService.SaveProfile(player, releaseLock)
	end
end

function ProfileService.ReleaseProfile(player: Player)
	profiles[player.UserId] = nil
	sessionOnly[player.UserId] = nil
end

return ProfileService
