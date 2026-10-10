--!strict
-- StoreData: everything sold for Robux (GAME_DESIGN §7: convenience and
-- cosmetics, never pay-to-win). Prices are set in Creator Hub, not here:
-- the Store screen shows whatever Roblox says each item costs.
--
-- Paste ids in CreatorIds only. 0 means "not set up yet": that card shows
-- "Coming soon" (or stays hidden) and the server refuses the purchase. A
-- pasted id alone never sells anything: Roblox must also say the item is
-- for sale (Store/StoreSale, StoreSaleService). Never invent an id. Never
-- delete a product entry: a receipt for a missing product is never granted.
--   Passes:    Creator Hub → your experience → Monetization → Passes → ⋯ → Copy Asset ID
--   Products:  Monetization → Developer Products → ⋯ → Copy Asset ID
-- No Robux price is ever written here or anywhere in the game: every price
-- a player sees is read live from Roblox on their own client (StorePrices).

local StageOf = require(script.Parent.StageOf)

local StoreData = {}

export type PassKey = "DoubleCash" | "LuxAxe" | "TowService" | "TimberClassic" | "PaintShop"
export type ProductKey = "Cash1k" | "Cash10k" | "DoubleWood" | "InstantDelivery"
-- What a card shows when Roblox says the item isn't for sale (or the id is
-- 0): "soon" = a "Coming soon" card with no price, "hidden" = no card.
export type OffSale = "soon" | "hidden"

-- The only place a Creator Hub id is written (Connor set these up on
-- 8 Oct 2026; all nine were on sale then).
StoreData.CreatorIds = {
	Passes = {
		DoubleCash = 2005256811, -- PASTE: Monetization → Passes → 2x Cash → ID
		LuxAxe = 2005226878, -- PASTE: Monetization → Passes → Lux Axe → ID
		TowService = 2006186967, -- PASTE: Monetization → Passes → Tow Service → ID
		TimberClassic = 2006912886, -- PASTE: Monetization → Passes → Timber Classic → ID
		PaintShop = 2006456926, -- PASTE: Monetization → Passes → Paint Shop → ID
	},
	Products = {
		Cash1k = 3716312861, -- PASTE: Monetization → Developer Products → Small Cash Pack → ID
		Cash10k = 3716312899, -- PASTE: Monetization → Developer Products → Large Cash Pack → ID
		DoubleWood = 3717310556, -- PASTE: Monetization → Developer Products → 2x Wood (48 hours) → ID
		InstantDelivery = 3717310577, -- PASTE: Monetization → Developer Products → Instant Delivery → ID
	},
}

export type Pass = {
	key: PassKey,
	id: number, -- game pass id from Creator Hub (0 until pasted)
	image: number, -- PASTE a decal asset id; 0 = styled placeholder
	name: string,
	description: string, -- word for word what Creator Hub says
	order: number, -- card order in the store, on the board and on the shelf
	offSale: OffSale,
	-- Optional, for the owner hub's Paid items list (Shared/PaidItems works
	-- both out when they are left off): "pass", "tool" or "cosmetic", and
	-- whether an owner grant may be taken back (false when granting it
	-- changes the save for good, like the Timber Classic truck).
	kind: string?,
	revocable: boolean?,
}

export type Product = {
	key: ProductKey,
	id: number, -- developer product id from Creator Hub (0 until pasted)
	image: number, -- PASTE a decal asset id; 0 = styled placeholder
	name: string,
	description: string, -- word for word what Creator Hub says (static, no live amount)
	order: number,
	offSale: OffSale,
	kind: string?, -- optional: "consumable" or "booster" (PaidItems works it out if left off)
	-- Cash packs: the least they ever add (what the pack added before it
	-- scaled). The real amount is PackCash: packMinutes of the player's
	-- stage income, never under this.
	cash: number?,
	packMinutes: number?,
	boostHours: number?, -- timed boosts: how long
}

StoreData.Passes = {
	{
		key = "DoubleCash",
		id = StoreData.CreatorIds.Passes.DoubleCash,
		image = 0, -- PASTE decal id
		name = "2x Cash",
		description = "Wood you sell pays double. It doesn't change your axes, trucks, or how fast you chop, and everything in the game can still be earned without it.",
		order = 1,
		offSale = "soon",
	},
	{
		key = "LuxAxe",
		id = StoreData.CreatorIds.Passes.LuxAxe,
		image = 0, -- PASTE decal id
		name = "Lux Axe",
		description = "A black axe with a gold head, a diamond edge, and a sparkle. It sits between the Inferno Axe and the Starfall Axe, and the Starfall Axe can still be bought with cash. Wood you cut with it sells for 10% more. It's yours to keep and can't be sold. It can't be tempered.",
		order = 2,
		offSale = "soon",
	},
	{
		key = "TowService",
		id = StoreData.CreatorIds.Passes.TowService,
		image = 91282142796474,
		name = "Tow Service",
		description = "Free recalls for every truck you own. Without this pass, a recall costs 5% of the truck's price, with a $5 minimum.",
		order = 3,
		offSale = "soon",
	},
	{
		key = "TimberClassic",
		id = StoreData.CreatorIds.Passes.TimberClassic,
		image = 79037897236948,
		name = "Timber Classic",
		description = "Unlocks the Timber Classic, an old-school pickup with the same stats as the Pickup. Its dashboard gauge shows what your load is worth, as an estimate at the Wood Dropoff. Your display name is painted on both doors.",
		order = 4,
		offSale = "soon",
		revocable = false, -- an owner grant adds the truck to every slot's save for good
	},
	{
		key = "PaintShop",
		id = StoreData.CreatorIds.Passes.PaintShop,
		image = 71028498113750,
		name = "Paint Shop",
		description = "Paint your trucks in any color from the Paint Shop palette. Paint is cosmetic only and stays on after you rejoin.",
		order = 5,
		offSale = "soon",
		kind = "cosmetic",
	},
} :: { Pass }

-- Keys never change and entries are never deleted (a receipt names the
-- product by id; a missing entry would leave it unprocessed forever).
StoreData.Products = {
	{
		key = "Cash1k",
		id = StoreData.CreatorIds.Products.Cash1k,
		image = 0, -- PASTE decal id
		name = "Small Cash Pack",
		description = "Adds 15 minutes of wood income at your current stage.",
		order = 6,
		offSale = "soon",
		cash = 1000,
		packMinutes = 15,
	},
	{
		key = "Cash10k",
		id = StoreData.CreatorIds.Products.Cash10k,
		image = 0, -- PASTE decal id
		name = "Large Cash Pack",
		description = "Adds 2 hours of wood income at your current stage.",
		order = 7,
		offSale = "soon",
		cash = 10000,
		packMinutes = 120,
	},
	{
		key = "DoubleWood",
		id = StoreData.CreatorIds.Products.DoubleWood,
		image = 0, -- PASTE decal id
		name = "2x Wood (48 hours)",
		description = "For 48 hours, wood from every tree you fell sells for double. Buying it again adds 48 more hours.",
		order = 8,
		offSale = "soon",
		boostHours = 48,
	},
	{
		key = "InstantDelivery",
		id = StoreData.CreatorIds.Products.InstantDelivery,
		image = 0, -- PASTE decal id
		name = "Instant Delivery",
		description = "Sell your truckload from anywhere, once.",
		order = 9,
		offSale = "soon",
	},
} :: { Product }

-- Passes and products whose Creator Hub id is pasted (id > 0).
function StoreData.ListedPasses(): { Pass }
	local out: { Pass } = {}
	for _, pass in ipairs(StoreData.Passes) do
		if StoreData.IsForSale(pass.id) then
			table.insert(out, pass)
		end
	end
	return out
end

function StoreData.ListedProducts(): { Product }
	local out: { Product } = {}
	for _, product in ipairs(StoreData.Products) do
		if StoreData.IsForSale(product.id) then
			table.insert(out, product)
		end
	end
	return out
end

-- True when any pass or product has a real id. (The STORE button follows
-- Roblox's live sale state on top of this; see StoreUI.)
function StoreData.AnyForSale(): boolean
	return #StoreData.ListedPasses() + #StoreData.ListedProducts() > 0
end

function StoreData.Pass(key: string): Pass?
	for _, pass in ipairs(StoreData.Passes) do
		if pass.key == key then
			return pass
		end
	end
	return nil
end

function StoreData.Product(key: string): Product?
	for _, product in ipairs(StoreData.Products) do
		if product.key == key then
			return product
		end
	end
	return nil
end

-- True when `id` is a real Creator Hub id. 0 (and anything else that isn't
-- a positive id) is not for sale: hide the button, don't prompt, don't grant.
function StoreData.IsForSale(id: number): boolean
	return id > 0
end

-- A pass can be bought only once Roblox's product info says IsForSale.
-- `robloxForSale` is that field, or nil while the lookup hasn't come back
-- (or it failed). A pasted id alone is not enough. (The card itself shows
-- "Coming soon" instead: Store/StoreSale.CardState.)
function StoreData.PassCardVisible(id: number, robloxForSale: boolean?): boolean
	return StoreData.IsForSale(id) and robloxForSale == true
end

-- The pass with this Creator Hub id, if it's for sale.
function StoreData.PassById(id: number): Pass?
	if not StoreData.IsForSale(id) then
		return nil
	end
	for _, pass in ipairs(StoreData.Passes) do
		if pass.id == id then
			return pass
		end
	end
	return nil
end

-- The product with this Creator Hub id (for receipts), if it's for sale.
function StoreData.ProductById(id: number): Product?
	if not StoreData.IsForSale(id) then
		return nil
	end
	for _, product in ipairs(StoreData.Products) do
		if product.id == id then
			return product
		end
	end
	return nil
end

-- What a cash pack adds for this player right now: `packMinutes` of their
-- stage's wood income (StageOf), rounded to $10, never under the pack's
-- old fixed amount (`cash`). 0 for anything that isn't a cash pack. The
-- server works it out at receipt time; the card shows the same number.
function StoreData.PackCash(product: Product, profile: unknown): number
	local floor = product.cash
	if floor == nil then
		return 0
	end
	local minutes = product.packMinutes or 0
	local scaled = StageOf.Income(StageOf.Current(profile)) * minutes / 60
	scaled = math.floor(scaled / 10 + 0.5) * 10
	return math.max(floor, scaled)
end

-- PackCash for a stage number (the client knows its stage, not the save).
function StoreData.PackCashAt(product: Product, stage: number): number
	local floor = product.cash
	if floor == nil then
		return 0
	end
	local scaled = StageOf.Income(stage) * (product.packMinutes or 0) / 60
	return math.max(floor, math.floor(scaled / 10 + 0.5) * 10)
end

-- Whether a cash pack still fits in the wallet (never sell cash that can't
-- be credited: a granted receipt can't be undone). `amount` is what it adds
-- (PackCash); without it, the pack's least amount.
function StoreData.PackFits(product: Product, cash: number, cap: number, amount: number?): boolean
	if product.cash == nil then
		return true
	end
	return cash + (amount or product.cash) <= cap
end

-- Passes then products, by `order` (the store, the board and the shelf).
export type Entry = { kind: "Pass" | "Product", key: string, item: Pass | Product }

function StoreData.Ordered(): { Entry }
	local out: { Entry } = {}
	for _, pass in ipairs(StoreData.Passes) do
		table.insert(out, { kind = "Pass", key = pass.key :: string, item = pass })
	end
	for _, product in ipairs(StoreData.Products) do
		table.insert(out, { kind = "Product", key = product.key :: string, item = product })
	end
	table.sort(out, function(a, b)
		return a.item.order < b.item.order
	end)
	return out
end

-- The Creator Hub id for a kind and key, or 0.
function StoreData.IdOf(kind: string, key: string): number
	if kind == "Pass" then
		local pass = StoreData.Pass(key)
		return if pass then pass.id else 0
	elseif kind == "Product" then
		local product = StoreData.Product(key)
		return if product then product.id else 0
	end
	return 0
end

return StoreData
