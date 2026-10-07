--!strict
-- MonetizationService: Robux purchases (items and ids in Shared/StoreData).
--   * Game passes are checked when the player joins and granted the moment
--     one is bought in game; mirrored on "Pass_<key>" player attributes.
--     2x Cash doubles what logs sell for (SaleMultiplier).
--   * Developer products: ProcessReceipt grants each receipt exactly once,
--     saved with the player's profile before Roblox is told it's done
--     (ProfileService.ProcessPurchaseAsync), so a crash can't lose or
--     double a purchase.
--       - Cash packs: only offered when the cash fits under the wallet cap.
--       - 2x Wood: trees drop twice the logs for 48 h; buying again extends it.
--       - Instant Delivery: sell your truck bed once, from anywhere.
--   * Owner grants (the hub's Paid items tab, via AdminService): OwnerGrant,
--     OwnerRevoke and OwnerState give or take back any item in
--     Shared/PaidItems (built from StoreData) through the same effects a
--     purchase has (setPass and its listener, the boost and delivery
--     helpers below), but with no Robux prompt, no receipt, no purchase
--     analytics. A pass is saved in profile.ownerGrants (not `passes`), so
--     the join check ORs it in and a revoke never touches a real purchase.
--     Every grant and revoke is also written to profile.ownerGrantLog.
--   * BuyRobuxItem (client -> server): the server checks the item is set up
--     (and that a cash pack fits), then shows Roblox's purchase prompt.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local PaidItems = require(ReplicatedStorage.Shared.PaidItems)
local StoreData = require(ReplicatedStorage.Shared.StoreData)
local Util = require(ReplicatedStorage.Shared.Util)
local EconomyService = require(script.Parent.EconomyService)
local ProfileService = require(script.Parent.ProfileService)
local RateLimiter = require(script.Parent.RateLimiter)

type Profile = ProfileService.Profile

local MonetizationService = {}

local notify: (Player, string) -> () = function(_player: Player, _message: string) end
local clock: () -> number = os.time -- tests replace this
local owned: { [Player]: { [string]: boolean } } = {} -- passes, per player
-- GameServer wires this to grant the Lux Axe without a require cycle.
local onPass: ((Player, string) -> ())? = nil
-- GameServer wires this to take the Lux Axe back after an owner revoke.
local onPassRevoked: ((Player, string) -> ())? = nil

-- `mode` "seed" only copies a saved pass into the live set (join, no hook).
-- "purchase" (the default) is a real grant (a purchase, or Roblox confirming
-- ownership): it writes profile.passes so a later join still has the pass if
-- UserOwnsGamePassAsync fails. "grant" is the owner's: it switches the pass
-- on and runs the same listener but writes nothing to `passes` (OwnerGrant
-- saves it in profile.ownerGrants). Never clears a pass: a false or a failed
-- check leaves the backup in place.
local function setPass(player: Player, key: string, mode: string?)
	local set = owned[player] or {}
	owned[player] = set
	set[key] = true
	player:SetAttribute("Pass_" .. key, true)
	if mode == "seed" then
		return
	end
	if mode ~= "grant" then
		local profile = ProfileService.GetProfile(player)
		if profile then
			if type(profile.passes) ~= "table" then
				profile.passes = {}
			end
			profile.passes[key] = true
		end
	end
	local hook = onPass
	if hook then
		hook(player, key)
	end
end

function MonetizationService.SetPassListener(fn: (Player, string) -> ())
	onPass = fn
end

function MonetizationService.SetPassRevokedListener(fn: (Player, string) -> ())
	onPassRevoked = fn
end

local function publishBoosts(player: Player, profile: Profile)
	player:SetAttribute("DoubleWoodUntil", profile.doubleWoodUntil)
	player:SetAttribute("InstantDeliveries", profile.instantDeliveries)
end

function MonetizationService.HasPass(player: Player, key: StoreData.PassKey): boolean
	local set = owned[player]
	return set ~= nil and set[key] == true
end

-- Tow Service waives a spawn-pad fee. The live set is checked first; the
-- save is the backup when the marketplace set has not been copied yet.
function MonetizationService.WaivesRespawn(player: Player): boolean
	if MonetizationService.HasPass(player, "TowService") then
		return true
	end
	local profile = ProfileService.GetProfile(player)
	local passes = if profile then (profile :: any).passes else nil
	return type(passes) == "table" and passes.TowService == true
end

-- Multiplier on sale income (2x Cash).
function MonetizationService.SaleMultiplier(player: Player): number
	return if MonetizationService.HasPass(player, "DoubleCash") then 2 else 1
end

-- Multiplier on logs per felled tree (2x Wood, while it lasts).
function MonetizationService.LogMultiplier(player: Player): number
	local profile = ProfileService.GetProfile(player)
	return if profile and profile.doubleWoodUntil > clock() then 2 else 1
end

-- Spends one Instant Delivery. False if the player has none.
function MonetizationService.UseInstantDelivery(player: Player): boolean
	local profile = ProfileService.GetProfile(player)
	if not profile or profile.instantDeliveries <= 0 then
		return false
	end
	profile.instantDeliveries -= 1
	publishBoosts(player, profile)
	return true
end

-- The effects of a boost and of an Instant Delivery, for a purchase and for
-- an owner grant alike.
local function startBoost(profile: Profile, hours: number)
	profile.doubleWoodUntil = math.max(clock(), profile.doubleWoodUntil) + hours * 3600
end

local function addInstantDelivery(profile: Profile)
	profile.instantDeliveries += 1
end

local function grantProduct(player: Player, profile: Profile, product: StoreData.Product)
	local effect = PaidItems.EffectOf(product)
	if effect == "cash" then
		local cash = product.cash :: number
		local credited, banked = EconomyService.AddPaidCash(player, cash, "robux: " .. product.key, product.key)
		if banked > 0 then
			notify(
				player,
				string.format(
					"Thanks! +%s now; %s more is saved for you and arrives as you spend.",
					Util.formatCash(credited),
					Util.formatCash(banked)
				)
			)
		else
			notify(player, string.format("Thanks! +%s", Util.formatCash(cash)))
		end
	elseif effect == "boost" then
		startBoost(profile, product.boostHours :: number)
		notify(player, string.format("Thanks! %s is on: trees drop twice the logs.", product.name))
	elseif effect == "counter" then
		addInstantDelivery(profile)
		notify(player, "Thanks! Use Instant Delivery to sell your truckload from anywhere.")
	end
	publishBoosts(player, profile)
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local product = StoreData.ProductById(receipt.ProductId)
	if not product then
		warn("[Monetization] Receipt for a product not in StoreData: " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- Roblox retries when they're back
	end
	return ProfileService.ProcessPurchaseAsync(player, tostring(receipt.PurchaseId), function(profile: Profile)
		grantProduct(player, profile, product)
	end)
end

-- Whether the player owns a game pass, asking Roblox up to 3 times (with
-- 2 s, then 4 s, between tries) if the service errors. False if it keeps
-- failing or the player leaves.
local function ownsPass(player: Player, passId: number): boolean
	for attempt = 1, 3 do
		local ok, has = pcall(function(): any
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if ok then
			return has == true
		end
		warn(string.format("[Monetization] Couldn't check game pass %d (try %d): %s", passId, attempt, tostring(has)))
		if attempt < 3 then
			task.wait(2 ^ attempt)
		end
		if player.Parent ~= Players then
			return false
		end
	end
	return false
end

local function onBuy(player: Player, kind: unknown, key: unknown)
	if type(kind) ~= "string" or type(key) ~= "string" or not RateLimiter.Allow(player, "BuyRobuxItem") then
		return
	end
	if kind == "Pass" then
		local pass = StoreData.Pass(key)
		if not pass or not StoreData.IsForSale(pass.id) then
			return
		end
		if MonetizationService.HasPass(player, pass.key) then
			notify(player, string.format("You already have %s.", pass.name))
			return
		end
		-- The check on join may have failed (Roblox's service hiccupped):
		-- ask again before prompting, so an owner isn't asked to buy it twice.
		if ownsPass(player, pass.id) then
			setPass(player, pass.key)
			notify(player, string.format("You already own %s; it's active now.", pass.name))
			return
		end
		-- Off sale in Creator Hub: no prompt. A failed lookup stays refused.
		local ok, info = pcall(function(): any
			return MarketplaceService:GetProductInfo(pass.id, Enum.InfoType.GamePass)
		end)
		if not ok or type(info) ~= "table" or info.IsForSale ~= true then
			return
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	elseif kind == "Product" then
		local product = StoreData.Product(key)
		local profile = ProfileService.GetProfile(player)
		if not product or not StoreData.IsForSale(product.id) or not profile then
			return
		end
		if not StoreData.PackFits(product, profile.cash, GameConfig.CashCap) then
			notify(
				player,
				string.format("Your wallet can't hold that much (the cap is %s).", Util.formatCash(GameConfig.CashCap))
			)
			return
		end
		MarketplaceService:PromptProductPurchase(player, product.id)
	end
end

---------------------------------------------------------------------------
-- Owner grants: the hub's Paid items tab (AdminService calls these). Same
-- effects as a purchase, no Robux, no receipt, no purchase analytics. The
-- caller has already checked WHO may ask; the rules about the item (unknown
-- id, already owned, wallet room, boost running, not revocable) are here, so
-- they hold whoever calls.
---------------------------------------------------------------------------

export type By = { userId: number, name: string }

local function ownerLog(profile: Profile, by: By, action: string, item: PaidItems.Item, detail: string?)
	local list = PaidItems.CleanLog(profile.ownerGrantLog)
	PaidItems.PushLog(list, {
		at = clock(),
		by = by.userId,
		byName = by.name,
		action = action,
		item = item.id,
		name = item.name,
		detail = detail,
	})
	profile.ownerGrantLog = list
end

local function stateOf(player: Player, profile: Profile, item: PaidItems.Item): PaidItems.State
	return PaidItems.StateOf(item, profile, MonetizationService.HasPass(player, item.key :: any), clock())
end

-- Gives `itemId` (a PaidItems id) to `player`. `hours` is only for a timed
-- booster (nil: the item's own length). Returns (ok, text): the text is a
-- sentence for the owner either way. The player is told by `notify`.
function MonetizationService.OwnerGrant(player: Player, itemId: unknown, by: By, hours: unknown): (boolean, string)
	local profile = ProfileService.GetProfile(player)
	local item = PaidItems.Find(PaidItems.All(), itemId)
	if not item then
		return false, "That is not a paid item."
	end
	if not profile then
		return false, player.Name .. " has no loaded save."
	end
	local log = PaidItems.CleanLog(profile.ownerGrantLog)
	if PaidItems.IsRepeat(log, "give", item.id, clock()) then
		return false, string.format("Just gave %s to %s. Wait a moment before doing it again.", item.name, player.Name)
	end
	local st = stateOf(player, profile, item)
	local ok, why = PaidItems.CanGrant(item, st, { cash = profile.cash, cap = GameConfig.CashCap })
	if not ok then
		return false, why or "Can't give that."
	end
	local length: number? = nil
	local detail: string? = nil
	if item.effect == "boost" then
		length = PaidItems.CleanHours(item, hours)
		if not length then
			return false, string.format("Pick a boost length from 1 to %d hours.", PaidItems.MaxHours)
		end
		detail = string.format("%d h", length)
	end
	local told: string
	if item.effect == "pass" then
		if type(profile.ownerGrants) ~= "table" then
			profile.ownerGrants = {}
		end
		profile.ownerGrants[item.key] = { at = clock(), by = by.userId, byName = by.name }
		setPass(player, item.key, "grant")
		told = string.format("The owner gave you %s.", item.name)
	elseif item.effect == "cash" then
		local credited = EconomyService.AddCash(player, item.cash :: number, "owner grant: " .. item.key, item.key)
		detail = Util.formatCash(credited)
		told = string.format("The owner gave you %s.", Util.formatCash(credited))
	elseif item.effect == "boost" then
		startBoost(profile, length :: number)
		told = string.format(
			"The owner turned on %s for %d hours: trees drop twice the logs.",
			item.name,
			length :: number
		)
	else -- counter
		addInstantDelivery(profile)
		told = "The owner gave you an Instant Delivery."
	end
	publishBoosts(player, profile)
	ownerLog(profile, by, "give", item, detail)
	if player.UserId ~= by.userId then
		notify(player, told)
	end
	local text = string.format("Gave %s to %s.", item.name, player.Name)
	if item.effect == "boost" and length then
		text = string.format("Gave %s for %d hours to %s.", item.name, length, player.Name)
	end
	return true, text
end

-- Takes back an owner grant (a pass), ends a booster, or removes one
-- Instant Delivery. A pass the player bought stays: only the grant goes.
function MonetizationService.OwnerRevoke(player: Player, itemId: unknown, by: By): (boolean, string)
	local profile = ProfileService.GetProfile(player)
	local item = PaidItems.Find(PaidItems.All(), itemId)
	if not item then
		return false, "That is not a paid item."
	end
	if not profile then
		return false, player.Name .. " has no loaded save."
	end
	local log = PaidItems.CleanLog(profile.ownerGrantLog)
	if PaidItems.IsRepeat(log, "revoke", item.id, clock()) then
		return false, string.format("Just revoked %s from %s.", item.name, player.Name)
	end
	local st = stateOf(player, profile, item)
	local ok, why = PaidItems.CanRevoke(item, st)
	if not ok then
		return false, why or "Can't take that back."
	end
	local detail: string? = nil
	if item.effect == "pass" then
		profile.ownerGrants[item.key] = nil
		local stillBought = type(profile.passes) == "table" and profile.passes[item.key] == true
		if stillBought then
			detail = "grant removed, purchase kept"
		else
			local set = owned[player]
			if set then
				set[item.key] = nil
			end
			player:SetAttribute("Pass_" .. item.key, nil)
			local hook = onPassRevoked
			if hook then
				hook(player, item.key)
			end
		end
	elseif item.effect == "boost" then
		profile.doubleWoodUntil = 0
	else -- counter
		profile.instantDeliveries = math.max(0, profile.instantDeliveries - 1)
	end
	publishBoosts(player, profile)
	ownerLog(profile, by, "revoke", item, detail)
	if player.UserId ~= by.userId then
		notify(player, string.format("The owner took %s back.", item.name))
	end
	local text = string.format("Took %s back from %s.", item.name, player.Name)
	if detail then
		text =
			string.format("Removed the grant of %s from %s; they still own it from a purchase.", item.name, player.Name)
	end
	return true, text
end

-- What `player` owns of every paid item, for the hub: id -> row.
export type StateRow = {
	label: string,
	owned: boolean,
	granted: boolean,
	bought: boolean,
	count: number,
	hoursLeft: number,
}

function MonetizationService.OwnerState(player: Player): { [string]: StateRow }
	local rows: { [string]: StateRow } = {}
	local profile = ProfileService.GetProfile(player)
	if not profile then
		return rows
	end
	local now = clock()
	for _, item in ipairs(PaidItems.All()) do
		local st = stateOf(player, profile, item)
		rows[item.id] = {
			label = st.label,
			owned = st.owned,
			granted = st.granted,
			bought = st.bought,
			count = st.count,
			hoursLeft = if st.untilAt > now then math.ceil((st.untilAt - now) / 3600) else 0,
		}
	end
	return rows
end

-- Call once the player's save has loaded.
function MonetizationService.PlayerJoined(player: Player, profile: Profile)
	publishBoosts(player, profile)
	-- The save is the backup: active immediately, before Roblox answers.
	-- An ownership check only turns a pass on. It never takes one away.
	owned[player] = {}
	if type(profile.passes) == "table" then
		for key, on in pairs(profile.passes) do
			if on == true and StoreData.Pass(key) then
				setPass(player, key, "seed")
			end
		end
	end
	-- Owner grants (the hub's Paid items tab) are ORed in the same way: the
	-- ownership check below never decides about them, so a granted pass is
	-- never stripped because Roblox says the account didn't buy it.
	for key in pairs(PaidItems.CleanGrants(profile.ownerGrants)) do
		if StoreData.Pass(key) then
			setPass(player, key, "seed")
		end
	end
	for _, pass in ipairs(StoreData.Passes) do
		if StoreData.IsForSale(pass.id) then
			task.spawn(function()
				if ownsPass(player, pass.id) then
					setPass(player, pass.key)
				end
			end)
		end
	end
end

function MonetizationService.PlayerRemoving(player: Player)
	owned[player] = nil
end

-- `buyRemote` is BuyRobuxItem; `notifyFn` shows a toast. `clockFn` is for tests.
function MonetizationService.Init(buyRemote: RemoteEvent, notifyFn: (Player, string) -> (), clockFn: (() -> number)?)
	notify = notifyFn
	if clockFn then
		clock = clockFn
	end
	buyRemote.OnServerEvent:Connect(onBuy)
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			if not purchased then
				return
			end
			-- id 0 is not a pass: never grant because a prompt finished with 0.
			local pass = StoreData.PassById(passId)
			if pass then
				setPass(player, pass.key)
				notify(player, string.format("Thanks! %s is yours.", pass.name))
			end
		end
	)
end

return MonetizationService
