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

-- Why a load attempt ended without a save (the reason code shown to the
-- player and printed in the Output):
--   start     StartSessionAsync raised (a DataStore or ProfileStore error)
--   lock      no session before the attempt's time budget ran out: the save
--             stayed held by another session or server, or DataStore calls
--             kept failing
--   contended ProfileStore gave up early: another session overrode our
--             request for the lock
--   migrate   Reconcile/Migrate raised on the stored save (it was put back
--             exactly as stored)
--   error     the load code itself raised
--   closing   the server is shutting down
export type FailInfo = { reason: string, detail: string, waited: number, attempts: number }

-- A failed attempt is tried again (nothing was written and no session is
-- left running, so a second try cannot make anything worse). Total tries per
-- reason; the waits are between tries.
ProfileService.LoadAttempts = 3
ProfileService.MigrateAttempts = 2 -- a Migrate error is deterministic; one more look in case it was not
ProfileService.RetryBudgetSec = 60 -- time budget of each try after the first
ProfileService.RetryWaits = { 3, 6 }
local NOTE_AFTER_SEC = 6 -- a load this slow tells the player what it is waiting for

local function trim(text: string): string
	return if #text > 200 then string.sub(text, 1, 200) .. "..." else text
end

-- The loading card's second line (Player attribute "LoadNote"); nil clears it.
local function setNote(player: Player, text: string?)
	pcall(function()
		player:SetAttribute("LoadNote", text)
	end)
end

type Opened = { session: any?, pristine: any?, committed: boolean }

-- One try at starting the player's save session. Yields until the save is
-- loaded: ProfileStore keeps retrying and, if another server still holds the
-- save (the player just hopped servers), asks it to let go and then takes
-- over. Only one copy is ever loaded: a second join gets the save only after
-- the first server's session has ended, and that server then kicks its
-- player. Returns (profile, nil), or (nil, "left") or (nil, "failed", reason,
-- detail). On a failure nothing was kept: the player is marked unsaveable
-- and no session is left running that could write.
local function loadOnce(player: Player, budget: number, opened: Opened): (Profile?, string?, string?, string?)
	local startedAt = os.clock()
	unsaveable[player] = nil
	local finished = false
	local function waited(): number
		return os.clock() - startedAt
	end
	-- After a few seconds with no save, say what the wait is.
	local function tick()
		if finished or player.Parent ~= Players then
			return
		end
		setNote(
			player,
			string.format("Waiting for your save to be released by another session (%d s)...", math.floor(waited()))
		)
		task.delay(1, tick)
	end
	task.delay(NOTE_AFTER_SEC, tick)

	local started, session = pcall(function(): any
		return store:StartSessionAsync(KEY_PREFIX .. player.UserId, {
			Cancel = function()
				return player.Parent ~= Players or os.clock() - startedAt > budget
			end,
		})
	end)
	finished = true
	if not started then
		unsaveable[player] = "start"
		return nil, if player.Parent ~= Players then "left" else "failed", "start", trim(tostring(session))
	end
	if session == nil then
		if player.Parent ~= Players then
			unsaveable[player] = "load"
			return nil, "left"
		end
		local reason = if ProfileStore.IsClosing then "closing" elseif waited() >= budget then "lock" else "contended"
		unsaveable[player] = reason
		local detail = if reason == "lock"
			then string.format("no session after %.0fs (save held elsewhere, or DataStore calls failing)", waited())
			elseif reason == "closing" then "server is shutting down"
			else "ProfileStore returned early (another session overrode the lock request)"
		return nil, "failed", reason, detail
	end

	opened.session = session
	session:AddUserId(player.UserId) -- GDPR: lets Roblox erase this key on request
	-- Reconcile would copy the template's WorldVersion onto a save that
	-- never had one, and a later map would then skip the park. Missing
	-- counts as 1. The field is a number, so the stand-in is 1, not nil.
	-- A new profile already has the field, copied from the template, so
	-- it starts on the current map.
	local pristine = deepCopy(session.Data)
	opened.pristine = pristine
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
		unsaveable[player] = "migrate"
		session.Data = pristine
		opened.committed = true -- ended here
		session:EndSession()
		return nil, if player.Parent ~= Players then "left" else "failed", "migrate", trim(tostring(why))
	end

	-- The player may have left while we were waiting on the DataStore.
	if player.Parent ~= Players then
		opened.committed = true
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
	opened.committed = true
	return session.Data :: Profile, nil
end

-- The whole load: up to LoadAttempts tries with a short wait between, never
-- retrying a player who left. Every try prints a first line and a last line
-- with the time it took, so a failed join can be explained from the Output.
-- Returns (profile, nil), (nil, "left") or (nil, "failed", FailInfo).
local function loadWithRetry(player: Player): (Profile?, string?, FailInfo?)
	local startedAt = os.clock()
	local attempt = 0
	local info: FailInfo = { reason = "error", detail = "", waited = 0, attempts = 0 }
	while true do
		attempt += 1
		local budget = if attempt == 1 then ProfileService.LoadBudgetSec else ProfileService.RetryBudgetSec
		print(
			string.format(
				"[ProfileService] %s: load attempt %d/%d starting (budget %ds, %.1fs since the first try)",
				player.Name,
				attempt,
				ProfileService.LoadAttempts,
				budget,
				os.clock() - startedAt
			)
		)
		local tryStart = os.clock()
		local opened: Opened = { session = nil, pristine = nil, committed = false }
		local ok, profile, err, reason, detail = pcall(loadOnce, player, budget, opened)
		if not ok then
			-- The load code itself raised. If it had opened a session, end it
			-- (with the data as stored) so the next try is not locked out by it.
			detail, reason, err, profile = trim(tostring(profile)), "error", "failed", nil
			unsaveable[player] = "error"
			if opened.session ~= nil and not opened.committed then
				pcall(function()
					if opened.pristine ~= nil then
						opened.session.Data = opened.pristine
					end
					opened.session:EndSession()
				end)
			end
			if player.Parent ~= Players then
				err = "left"
			end
		end
		if profile ~= nil then
			setNote(player, nil)
			print(
				string.format(
					"[ProfileService] %s: save loaded on attempt %d in %.1fs (%.1fs in all)",
					player.Name,
					attempt,
					os.clock() - tryStart,
					os.clock() - startedAt
				)
			)
			return profile, nil, nil
		end
		if err == "left" then
			setNote(player, nil)
			return nil, "left", nil
		end
		local why = tostring(reason)
		info = { reason = why, detail = tostring(detail), waited = os.clock() - startedAt, attempts = attempt }
		warn(
			string.format(
				"[ProfileService] %s: load attempt %d/%d failed after %.1fs: reason=%s (%s)",
				player.Name,
				attempt,
				ProfileService.LoadAttempts,
				os.clock() - tryStart,
				why,
				info.detail
			)
		)
		local limit = if why == "migrate"
			then math.min(ProfileService.MigrateAttempts, ProfileService.LoadAttempts)
			else ProfileService.LoadAttempts
		if attempt >= limit or why == "closing" then
			break
		end
		local pause = ProfileService.RetryWaits[attempt] or ProfileService.RetryWaits[#ProfileService.RetryWaits] or 3
		setNote(player, string.format("Your save did not open yet. Trying again (%d of %d)...", attempt + 1, limit))
		task.wait(pause)
		if player.Parent ~= Players then
			setNote(player, nil)
			return nil, "left", nil
		end
	end
	setNote(player, nil)
	warn(
		string.format(
			"[ProfileService] %s: save load FAILED (reason=%s, waited %.0fs over %d tries): %s",
			player.Name,
			info.reason,
			info.waited,
			info.attempts,
			info.detail
		)
	)
	return nil, "failed", info
end

-- Server audit (11 October 2026): GameServer connects PlayerAdded only after
-- the world and every service are up (a cold server: tens of seconds), so the
-- save load, a DataStore round trip that can take seconds (or ~45 s when the
-- save is still held by another server), only began then. Prefetch starts it
-- the moment the player arrives; LoadProfile (the join flow) picks up the
-- result. Nothing else changes: the same load, run earlier.
type Fetch = { done: boolean, profile: Profile?, err: string?, info: FailInfo? }
local fetches: { [Player]: Fetch } = setmetatable({}, { __mode = "k" }) :: any

function ProfileService.Prefetch(player: Player)
	if fetches[player] ~= nil then
		return
	end
	local fetch: Fetch = { done = false, profile = nil, err = nil, info = nil }
	fetches[player] = fetch
	task.spawn(function()
		local ok, profile, err, info = pcall(loadWithRetry, player)
		if ok then
			fetch.profile, fetch.err, fetch.info = profile :: any, err :: any, info :: any
		else
			warn(string.format("[ProfileService] loading %s's save failed: %s", player.Name, tostring(profile)))
			unsaveable[player] = "error"
			fetch.err = if player.Parent ~= Players then "left" else "failed"
			fetch.info = { reason = "error", detail = trim(tostring(profile)), waited = 0, attempts = 1 }
		end
		fetch.done = true
	end)
end

-- Yields until the player's save is loaded (starting the load if Prefetch
-- did not). Returns (profile, nil), (nil, "left") or (nil, "failed", info);
-- see loadWithRetry.
function ProfileService.LoadProfile(player: Player): (Profile?, string?, FailInfo?)
	local fetch = fetches[player]
	if fetch == nil then
		return loadWithRetry(player) -- no prefetch: load here, as it always did
	end
	while not fetch.done do
		task.wait()
	end
	if fetches[player] == fetch then
		fetches[player] = nil
	end
	return fetch.profile, fetch.err, fetch.info
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
