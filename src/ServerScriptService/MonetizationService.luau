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
--   * BuyRobuxItem (client -> server): the server checks the item is set up
--     (and that a cash pack fits), then shows Roblox's purchase prompt.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
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

local function setPass(player: Player, key: string)
	local set = owned[player] or {}
	owned[player] = set
	set[key] = true
	player:SetAttribute("Pass_" .. key, true)
end

local function publishBoosts(player: Player, profile: Profile)
	player:SetAttribute("DoubleWoodUntil", profile.doubleWoodUntil)
	player:SetAttribute("InstantDeliveries", profile.instantDeliveries)
end

function MonetizationService.HasPass(player: Player, key: StoreData.PassKey): boolean
	local set = owned[player]
	return set ~= nil and set[key] == true
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

local function grantProduct(player: Player, profile: Profile, product: StoreData.Product)
	if product.cash then
		local credited, banked = EconomyService.AddPaidCash(player, product.cash, "robux: " .. product.key, product.key)
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
			notify(player, string.format("Thanks! +%s", Util.formatCash(product.cash)))
		end
	elseif product.boostHours then
		profile.doubleWoodUntil = math.max(clock(), profile.doubleWoodUntil) + product.boostHours * 3600
		notify(player, string.format("Thanks! %s is on: trees drop twice the logs.", product.name))
	elseif product.key == "InstantDelivery" then
		profile.instantDeliveries += 1
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
		if not pass or pass.id == 0 then
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
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	elseif kind == "Product" then
		local product = StoreData.Product(key)
		local profile = ProfileService.GetProfile(player)
		if not product or product.id == 0 or not profile then
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

-- Call once the player's save has loaded.
function MonetizationService.PlayerJoined(player: Player, profile: Profile)
	publishBoosts(player, profile)
	for _, pass in ipairs(StoreData.Passes) do
		if pass.id ~= 0 then
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
			for _, pass in ipairs(StoreData.Passes) do
				if pass.id == passId then
					setPass(player, pass.key)
					notify(player, string.format("Thanks! %s is yours.", pass.name))
				end
			end
		end
	)
end

return MonetizationService
