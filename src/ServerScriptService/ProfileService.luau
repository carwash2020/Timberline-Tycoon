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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Backoff = require(ReplicatedStorage.Shared.Backoff)
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

-- A load that did not finish cleanly is marked here, by the Player instance,
-- and nothing may write for it: a failed load or a save that broke while it
-- was being prepared must never reach the DataStore, or an empty or
-- half-migrated copy could replace the real save. The mark is per Player
-- instance, so a rejoin (a new instance) starts clean.
local unsaveable: { [Player]: string } = setmetatable({}, { __mode = "k" }) :: any

-- Longest a join waits for the save. ProfileStore alone retries for as long
-- as the player stays (and it spends up to ~45 s asking another server to
-- let go before it takes the save over), so this is a ceiling that leaves
-- room for that, then tells the player to rejoin instead of leaving them on
-- the loading card for good.
ProfileService.LoadBudgetSec = 150

-- A manual save (a slot change, a purchase, Save now) that did not land is
-- tried again on this schedule; the 2-minute autosave is the backstop.
ProfileService.SaveRetry = { base = 2, cap = 15, maxTries = 4, budget = 40 } :: Backoff.Options
local SAVE_CONFIRM_SEC = 12 -- how long one try may take before it counts as failed

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in pairs(value) do
		copy[key] = deepCopy(inner)
	end
	return copy
end

-- Why a player's save may not be written (nil when it may).
function ProfileService.Unsaveable(player: Player): string?
	return unsaveable[player]
end

-- Starts the player's save session. Yields until the save is loaded:
-- ProfileStore keeps retrying and, if another server still holds the save
-- (the player just hopped servers), asks it to let go and then takes over.
-- Only one copy is ever loaded: a second join gets the save only after the
-- first server's session has ended, and that server then kicks its player.
-- Returns (profile, nil) on success, or (nil, "left" | "failed"). On
-- "failed" nothing was kept: the player is marked unsaveable and no session
-- is left running that could write.
local function loadNow(player: Player): (Profile?, string?)
	local startedAt = os.clock()
	local started, session = pcall(function(): any
		return store:StartSessionAsync(KEY_PREFIX .. player.UserId, {
			Cancel = function()
				return player.Parent ~= Players or os.clock() - startedAt > ProfileService.LoadBudgetSec
			end,
		})
	end)
	if not started then
		warn(string.format("[ProfileService] starting %s's save failed: %s", player.Name, tostring(session)))
		unsaveable[player] = "start"
		return nil, if player.Parent ~= Players then "left" else "failed"
	end
	if session == nil then
		unsaveable[player] = "load"
		return nil, if player.Parent ~= Players then "left" else "failed"
	end

	session:AddUserId(player.UserId) -- GDPR: lets Roblox erase this key on request
	-- Reconcile would copy the template's WorldVersion onto a save that
	-- never had one, and a later map would then skip the park. Missing
	-- counts as 1. The field is a number, so the stand-in is 1, not nil.
	-- A new profile already has the field, copied from the template, so
	-- it starts on the current map.
	local pristine = deepCopy(session.Data)
	local prepared, why = pcall(function()
		local hadWorldVersion = session.Data.worldVersion ~= nil
		session:Reconcile()
		if not hadWorldVersion then
			session.Data.worldVersion = 1
		end
		ProfileSchema.Migrate(session.Data)
	end)
	if not prepared then
		-- A half-migrated table must not be written back over the real
		-- save. Put back what the DataStore gave us, end the session
		-- (which writes exactly that) and refuse to play on it.
		warn(string.format("[ProfileService] %s's save could not be prepared: %s", player.Name, tostring(why)))
		unsaveable[player] = "migrate"
		session.Data = pristine
		session:EndSession()
		return nil, if player.Parent ~= Players then "left" else "failed"
	end

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
			unsaveable[player] = "taken"
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

-- Server audit (11 October 2026): GameServer connects PlayerAdded only after
-- the world and every service are up (a cold server: tens of seconds), so the
-- save load, a DataStore round trip that can take seconds (or ~45 s when the
-- save is still held by another server), only began then. Prefetch starts it
-- the moment the player arrives; LoadProfile (the join flow) picks up the
-- result. Nothing else changes: the same load, run earlier.
type Fetch = { done: boolean, profile: Profile?, err: string? }
local fetches: { [Player]: Fetch } = setmetatable({}, { __mode = "k" }) :: any

function ProfileService.Prefetch(player: Player)
	if fetches[player] ~= nil then
		return
	end
	local fetch: Fetch = { done = false, profile = nil, err = nil }
	fetches[player] = fetch
	task.spawn(function()
		local ok, profile, err = pcall(loadNow, player)
		if ok then
			fetch.profile, fetch.err = profile :: any, err :: any
		else
			warn(string.format("[ProfileService] loading %s's save failed: %s", player.Name, tostring(profile)))
			unsaveable[player] = "start"
			fetch.err = if player.Parent ~= Players then "left" else "failed"
		end
		fetch.done = true
	end)
end

-- Yields until the player's save is loaded (starting the load if Prefetch
-- did not). Returns (profile, nil) or (nil, "left" | "failed"); see loadNow.
function ProfileService.LoadProfile(player: Player): (Profile?, string?)
	local fetch = fetches[player]
	if fetch == nil then
		return loadNow(player) -- no prefetch: load here, as it always did
	end
	while not fetch.done do
		task.wait()
	end
	if fetches[player] == fetch then
		fetches[player] = nil
	end
	return fetch.profile, fetch.err
end

-- A player who leaves before the join flow has picked their save up (the
-- server was still starting; its own PlayerRemoving is not connected yet)
-- must not leave the session open: it holds the save's lock for as long as
-- this server lives. Releases it once the load is done.
function ProfileService.PrefetchLeft(player: Player)
	local fetch = fetches[player]
	if fetch == nil then
		return
	end
	task.spawn(function()
		while not fetch.done do
			task.wait()
		end
		if fetches[player] == fetch then
			fetches[player] = nil
		end
		ProfileService.ReleaseProfile(player)
	end)
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
	while sessions[player] == nil and player.Parent == Players and unsaveable[player] == nil do
		task.wait()
	end
	local session = sessions[player]
	if session == nil or unsaveable[player] ~= nil or not session:IsActive() then
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

-- Writes the session now (a slot change). If the write does not land (the
-- DataStore is throttled or down) it is tried again with a growing wait
-- (Shared/Backoff). No-op if the session already ended or the load failed.
function ProfileService.Save(player: Player)
	local session = sessions[player]
	if session == nil or unsaveable[player] ~= nil or not session:IsActive() then
		return
	end
	task.spawn(function()
		Backoff.Retry(
			function(): boolean
				if not session:IsActive() then
					return true -- the final save has it
				end
				local before = session.LastSavedData
				session:Save()
				local waited = 0
				while session:IsActive() and session.LastSavedData == before and waited < SAVE_CONFIRM_SEC do
					task.wait(0.25)
					waited += 0.25
				end
				return not session:IsActive() or session.LastSavedData ~= before
			end,
			function(seconds: number)
				task.wait(seconds)
			end,
			ProfileService.SaveRetry,
			function(): boolean
				return sessions[player] ~= session or ProfileStore.IsClosing
			end
		)
	end)
end

-- Final save + release of the session lock. Call when the player leaves.
function ProfileService.ReleaseProfile(player: Player)
	local session = sessions[player]
	sessions[player] = nil
	if session ~= nil and unsaveable[player] == nil then
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
