--!strict
-- AnalyticsEvents: what the game tells Roblox's AnalyticsService, as pure
-- rules (names, argument checks) so the server wrapper (GameAnalytics) and
-- the specs agree. No player names, user ids or free text ever go out:
-- an event carries a fixed name, a number and at most one short item key.
--
--   * First-session funnel (MilestoneService logs these through
--     LogOnboardingFunnelStepEvent, each once per player ever, remembered in
--     profile.onboarding): FirstSession below, in order. MilestoneService.Funnel
--     must contain every one of them (specced); new steps go at the END only.
--   * Store events (custom): StoreOpened, PurchasePrompted, PurchaseCompleted.
--   * Economy events: EconomyService (every AddCash / SpendCash / Refund),
--     with the source or sink name as the item sku.

local AnalyticsEvents = {}

-- The first session, in order. These are names in MilestoneService.Funnel.
AnalyticsEvents.FirstSession = {
	"Joined",
	"First chop",
	"First sale",
	"Claimed a plot",
	"First machine placed",
} :: { string }

-- Custom event names. Fixed strings only.
AnalyticsEvents.Custom = {
	StoreOpened = "StoreOpened",
	PurchasePrompted = "PurchasePrompted",
	PurchaseCompleted = "PurchaseCompleted",
} :: { [string]: string }

-- The custom field the item key rides in (Enum.AnalyticsCustomFieldKeys.CustomField01).
AnalyticsEvents.ItemField = "CustomField01"

local MAX_SKU = 40

-- A sku or item key that is safe to send: letters, digits and . _ : - only,
-- at most 40 characters. Anything else (spaces, other symbols) is dropped, so
-- a name or a sentence can't ride along. Empty or non-string gives "unknown".
function AnalyticsEvents.Sku(raw: unknown): string
	if type(raw) ~= "string" then
		return "unknown"
	end
	local clean = string.gsub(raw, "[^%w%.:_%-]", "")
	clean = string.sub(clean, 1, MAX_SKU)
	if clean == "" then
		return "unknown"
	end
	return clean
end

-- A custom event as (name, value, fields), or nil when `name` is not one of
-- ours. `item` is the store item key (a pass or a product), if there is one.
function AnalyticsEvents.CustomEvent(name: unknown, item: unknown): (string?, number, { [string]: string }?)
	if type(name) ~= "string" or AnalyticsEvents.Custom[name] ~= name then
		return nil, 0, nil
	end
	local fields: { [string]: string }? = nil
	if type(item) == "string" then
		fields = { [AnalyticsEvents.ItemField] = AnalyticsEvents.Sku(item) }
	end
	return name, 1, fields
end

-- A finite, whole, positive amount, or nil.
local function wholeAmount(n: unknown): number?
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	local whole = math.floor(n)
	if whole < 1 then
		return nil
	end
	return whole
end

export type EconomyArgs = { amount: number, balance: number, sku: string }

-- The checked arguments of one cash event, or nil when the amount is not a
-- positive whole number. The balance is clamped to zero or more.
function AnalyticsEvents.Economy(amount: unknown, balance: unknown, sku: unknown): EconomyArgs?
	local a = wholeAmount(amount)
	if a == nil then
		return nil
	end
	local b = 0
	if type(balance) == "number" and balance == balance and balance ~= math.huge and balance > 0 then
		b = math.floor(balance)
	end
	return { amount = a, balance = b, sku = AnalyticsEvents.Sku(sku) }
end

return AnalyticsEvents
