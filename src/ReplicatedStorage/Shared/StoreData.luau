--!strict
-- StoreData: everything sold for Robux (GAME_DESIGN §7: convenience and
-- cosmetics, never pay-to-win). Prices are set in Creator Hub, not here:
-- the Store screen shows whatever Roblox says each item costs.
--
-- Paste ids in CreatorIds only. 0 means "not for sale yet": that button
-- stays hidden and the server refuses the purchase. Never invent an id.
--   Passes:    Creator Hub → your experience → Monetization → Passes → ID
--   Products:  Monetization → Developer Products → ID

local StoreData = {}

export type PassKey = "DoubleCash"
export type ProductKey = "Cash1k" | "Cash10k" | "DoubleWood" | "InstantDelivery"

-- The only place a Creator Hub id is written. Fill these in when the pass
-- or product exists; leave 0 until then.
StoreData.CreatorIds = {
	Passes = {
		DoubleCash = 0, -- 2x Cash, forever
	},
	Products = {
		Cash1k = 0, -- $1,000 cash pack
		Cash10k = 0, -- $10,000 cash pack
		DoubleWood = 0, -- 2x Wood for 48 hours
		InstantDelivery = 0, -- sell the truck bed from anywhere, once
	},
}

export type Pass = {
	key: PassKey,
	id: number, -- game pass id from Creator Hub
	name: string,
	description: string,
}

export type Product = {
	key: ProductKey,
	id: number, -- developer product id from Creator Hub
	name: string,
	description: string,
	cash: number?, -- cash packs: how much it adds (checked against the wallet cap first)
	boostHours: number?, -- timed boosts: how long
}

StoreData.Passes = {
	{
		key = "DoubleCash",
		id = StoreData.CreatorIds.Passes.DoubleCash,
		name = "2x Cash",
		description = "All the wood you sell pays double, forever.",
	},
} :: { Pass }

StoreData.Products = {
	{
		key = "Cash1k",
		id = StoreData.CreatorIds.Products.Cash1k,
		name = "$1,000",
		description = "A little cash to get going.",
		cash = 1000,
	},
	{
		key = "Cash10k",
		id = StoreData.CreatorIds.Products.Cash10k,
		name = "$10,000",
		description = "A big cash pack.",
		cash = 10000,
	},
	{
		key = "DoubleWood",
		id = StoreData.CreatorIds.Products.DoubleWood,
		name = "2x Wood (48 hours)",
		description = "Wood you cut in the next 48 hours is worth double.",
		boostHours = 48,
	},
	{
		key = "InstantDelivery",
		id = StoreData.CreatorIds.Products.InstantDelivery,
		name = "Instant Delivery",
		description = "Sell your truckload from anywhere, once.",
	},
} :: { Product }

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

-- Whether a cash pack still fits in the wallet (never sell cash that can't
-- be credited: a granted receipt can't be undone).
function StoreData.PackFits(product: Product, cash: number, cap: number): boolean
	return product.cash == nil or cash + product.cash <= cap
end

return StoreData
