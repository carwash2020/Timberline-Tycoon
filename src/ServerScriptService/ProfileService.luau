--!strict
-- ProfileService: the SOLE reader/writer of player save data.
-- A thin wrapper over ProfileStore (loleris, vendored in Vendor/), which does
-- the hard parts: session locking across servers, waiting out (then taking
-- over) another server's lock, autosave, retries, and flushing on shutdown.
-- EconomyService is the only module allowed to change profile.cash.
--
-- DataStore "PlayerProfiles", key "profile_<UserId>" (GAME_DESIGN §14.2).
-- The one exception: the opt-in lifetime-earnings leaderboard is an
-- OrderedDataStore "Leaderboard_TotalEarned" (the Board* functions at the
-- bottom). Nothing else may call DataStoreService; LeaderboardService
-- decides when (budgets, opt-in) and these only do the pcall'd access.
--
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
	-- Reconcile would copy the template's WorldVersion onto a save that
	-- never had one, and a later map would then skip the park. Missing
	-- counts as 1. The field is a number, so the stand-in is 1, not nil.
	-- A new profile already has the field, copied from the template, so
	-- it starts on the current map.
	local hadWorldVersion = session.Data.worldVersion ~= nil
	session:Reconcile()
	if not hadWorldVersion then
		session.Data.worldVersion = 1
	end
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

-- Writes the session now (a slot change). ProfileStore retries. No-op if
-- the session already ended.
function ProfileService.Save(player: Player)
	local session = sessions[player]
	if session ~= nil and session:IsActive() then
		session:Save()
	end
end

-- Final save + release of the session lock. Call when the player leaves.
function ProfileService.ReleaseProfile(player: Player)
	local session = sessions[player]
	sessions[player] = nil
	if session ~= nil then
		session:EndSession()
	end
end

-- The leaderboard (OrderedDataStore, key = userId, value = lifetime cash
-- earned). Every call is pcall'd and says whether it worked; callers
-- (LeaderboardService) own the opt-in rule and the call budgets.
local BOARD_NAME = if RunService:IsStudio() then "Leaderboard_TotalEarned_Studio" else "Leaderboard_TotalEarned"
local boardStore: OrderedDataStore? = nil

local function board(): OrderedDataStore?
	if boardStore == nil then
		-- Looked up here, not at load: nothing but the leaderboard needs it.
		local ok, found = pcall(function()
			return game:GetService("DataStoreService"):GetOrderedDataStore(BOARD_NAME)
		end)
		if ok then
			boardStore = found
		else
			warn("[ProfileService] leaderboard store unavailable: " .. tostring(found))
		end
	end
	return boardStore
end

-- Stores `score` (a whole number) for the user. True if it was saved.
function ProfileService.BoardSet(userId: number, score: number): boolean
	local ordered = board()
	if ordered == nil then
		return false
	end
	local ok, err = pcall(function()
		ordered:SetAsync(tostring(userId), score)
	end)
	if not ok then
		warn("[ProfileService] leaderboard write failed: " .. tostring(err))
	end
	return ok
end

-- Removes the user's entry (they opted out). True if it worked.
function ProfileService.BoardRemove(userId: number): boolean
	local ordered = board()
	if ordered == nil then
		return false
	end
	local ok, err = pcall(function()
		ordered:RemoveAsync(tostring(userId))
	end)
	if not ok then
		warn("[ProfileService] leaderboard remove failed: " .. tostring(err))
	end
	return ok
end

-- The top `count` entries, highest first, as { { userId, score } }, or nil
-- if the read failed.
function ProfileService.BoardTop(count: number): { { userId: number, score: number } }?
	local ordered = board()
	if ordered == nil then
		return nil
	end
	local ok, result = pcall(function()
		local pages = ordered:GetSortedAsync(false, count)
		local out: { { userId: number, score: number } } = {}
		for _, item in ipairs(pages:GetCurrentPage()) do
			local userId = tonumber(item.key)
			local score = item.value
			if userId ~= nil and type(score) == "number" then
				table.insert(out, { userId = userId, score = score })
			end
		end
		return out
	end)
	if not ok then
		warn("[ProfileService] leaderboard read failed: " .. tostring(result))
		return nil
	end
	return result
end

return ProfileService
