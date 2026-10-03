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
local RunService = game:GetService("RunService")

local LeaveCommit = require(script.Parent.LeaveCommit)
local ProfileSchema = require(script.Parent.ProfileSchema)
local ProfileStore = require(script.Parent.Vendor.ProfileStore)

local ProfileService = {}

-- Studio playtests (with API access on) get their own store, so testing can
-- never overwrite a real player's save.
local STORE_NAME = if RunService:IsStudio() then "PlayerProfiles_Studio" else "PlayerProfiles"
local KEY_PREFIX = "profile_"

export type PlacedItem = ProfileSchema.PlacedItem
export type AxeItem = ProfileSchema.AxeItem
export type Profile = ProfileSchema.Profile

-- Fields added to the template later are filled into existing saves by
-- Reconcile() on load; nothing already saved is dropped.
-- Autosave every 2 minutes (GAME_DESIGN §14.2; ProfileStore's default is 5).
ProfileStore.SetConstant("AUTO_SAVE_PERIOD", 120)
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
	-- Shutdown saves from ProfileStore's BindToClose, which does not wait
	-- for PlayerRemoving. OnLastSave runs at the start of that save (and
	-- of a normal leave), so playtime, the truck load and left-behind wood
	-- are in Data before it is written. LeaveCommit runs once per player.
	LeaveCommit.Bind(session.OnLastSave, player)
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

-- Grants a developer product purchase exactly once (Roblox calls
-- ProcessReceipt again until it hears PurchaseGranted, even across servers
-- and crashes). `grant` changes the profile; it runs only for a receipt
-- this save hasn't seen. Yields until the save holding the receipt id has
-- reached the DataStore, so a crash can never lose a purchase or grant it
-- twice. Returns the decision for ProcessReceipt.
function ProfileService.ProcessPurchaseAsync(
	player: Player,
	purchaseId: string,
	grant: (Profile) -> ()
): Enum.ProductPurchaseDecision
	-- The receipt can arrive before the save has loaded.
	while sessions[player] == nil and player.Parent == Players do
		task.wait()
	end
	local session = sessions[player]
	if session == nil or not session:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if ProfileSchema.RecordPurchase(session.Data, purchaseId) then
		local data = session.Data :: Profile
		local ok, err = pcall(function(): any
			grant(data)
			return nil
		end)
		if not ok then
			-- Forget the receipt so Roblox retries it: never take Robux for
			-- nothing.
			local ids = data.purchaseIds
			local at = table.find(ids, purchaseId)
			if at then
				table.remove(ids, at)
			end
			warn(string.format("[ProfileService] Granting %s failed: %s", purchaseId, tostring(err)))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		session:Save()
	end
	local function saved(data: any): boolean
		return data ~= nil and data.purchaseIds ~= nil and table.find(data.purchaseIds, purchaseId) ~= nil
	end
	if saved(session.LastSavedData) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	while session:IsActive() do
		if saved(session.OnAfterSave:Wait()) then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
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
