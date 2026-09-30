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

local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileStore = require(script.Parent.Vendor.ProfileStore)

local ProfileService = {}

local STORE_NAME = "PlayerProfiles"
local KEY_PREFIX = "profile_"

export type PlacedItem = ProfileSchema.PlacedItem
export type AxeItem = ProfileSchema.AxeItem
export type Profile = ProfileSchema.Profile

-- Fields added to the template later are filled into existing saves by
-- Reconcile() on load; nothing already saved is dropped.
local store = ProfileStore.New(STORE_NAME, ProfileSchema.Template)

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
	ProfileSchema.Migrate(session.Data)

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
