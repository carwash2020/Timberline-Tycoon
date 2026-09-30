--!strict
-- StoreData: everything sold for Robux (GAME_DESIGN §7: convenience and
-- cosmetics, never pay-to-win). Prices are set in Creator Hub, not here:
-- the Store screen shows whatever Roblox says each item costs.
--
-- To put an item on sale: create it in Creator Hub (Monetization → Passes
-- or Developer Products), then paste its id below. An id of 0 means "not
-- set up yet": the item stays hidden and can't be bought.

local StoreData = {}

export type PassKey = "DoubleCash"
export type ProductKey = "Cash1k" | "Cash10k" | "DoubleWood" | "InstantDelivery"

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
		id = 0,
		name = "2x Cash",
		description = "Every log you sell pays double, forever.",
	},
} :: { Pass }

StoreData.Products = {
	{
		key = "Cash1k",
		id = 0,
		name = "$1,000",
		description = "A little cash to get going.",
		cash = 1000,
	},
	{
		key = "Cash10k",
		id = 0,
		name = "$10,000",
		description = "A big cash pack.",
		cash = 10000,
	},
	{
		key = "DoubleWood",
		id = 0,
		name = "2x Wood (48 hours)",
		description = "Every tree you fell drops twice the logs for 48 hours.",
		boostHours = 48,
	},
	{
		key = "InstantDelivery",
		id = 0,
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

-- The product with this Creator Hub id (for receipts), if it's set up.
function StoreData.ProductById(id: number): Product?
	if id == 0 then
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
