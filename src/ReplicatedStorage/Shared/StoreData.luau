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

export type PassKey = "DoubleCash" | "LuxAxe"
export type ProductKey = "Cash1k" | "Cash10k" | "DoubleWood" | "InstantDelivery"

-- The only place a Creator Hub id is written. Fill these in when the pass
-- or product exists; leave 0 until then.
-- PASTE each id from Creator Hub. 0 = not for sale (button hidden, server
-- refuses). image is a decal asset id for the card; 0 draws a placeholder.
StoreData.CreatorIds = {
	Passes = {
		DoubleCash = 2005256811, -- PASTE: Monetization → Passes → 2x Cash → ID
		LuxAxe = 2005226878, -- PASTE: Monetization → Passes → Lux Axe → ID
	},
	Products = {
		Cash1k = 3716312861, -- PASTE: Monetization → Developer Products → $1,000 → ID
		Cash10k = 3716312899, -- PASTE: Monetization → Developer Products → $10,000 → ID
		DoubleWood = 0, -- PASTE: Monetization → Developer Products → 2x Wood → ID
		InstantDelivery = 0, -- PASTE: Monetization → Developer Products → Instant Delivery → ID
	},
}

export type Pass = {
	key: PassKey,
	id: number, -- game pass id from Creator Hub (0 until pasted)
	image: number, -- PASTE a decal asset id; 0 = styled placeholder
	name: string,
	description: string,
}

export type Product = {
	key: ProductKey,
	id: number, -- developer product id from Creator Hub (0 until pasted)
	image: number, -- PASTE a decal asset id; 0 = styled placeholder
	name: string,
	description: string,
	cash: number?, -- cash packs: how much it adds (checked against the wallet cap first)
	boostHours: number?, -- timed boosts: how long
}

StoreData.Passes = {
	{
		key = "DoubleCash",
		id = StoreData.CreatorIds.Passes.DoubleCash,
		image = 0, -- PASTE decal id
		name = "2x Cash",
		description = "Wood you sell pays double. It doesn't change your axes, trucks, or how fast you chop, and everything in the game can still be earned without it.",
	},
	{
		key = "LuxAxe",
		id = StoreData.CreatorIds.Passes.LuxAxe,
		image = 0, -- PASTE decal id
		name = "Lux Axe",
		description = "A black axe with a gold head, a diamond edge, and a sparkle. It sits between the Inferno Axe and the Starfall Axe, and the Starfall Axe can still be bought with cash. Wood you cut with it sells for 10% more. It's yours to keep and can't be sold.",
	},
} :: { Pass }

StoreData.Products = {
	{
		key = "Cash1k",
		id = StoreData.CreatorIds.Products.Cash1k,
		image = 0, -- PASTE decal id
		name = "$1,000",
		description = "A little cash to get going.",
		cash = 1000,
	},
	{
		key = "Cash10k",
		id = StoreData.CreatorIds.Products.Cash10k,
		image = 0, -- PASTE decal id
		name = "$10,000",
		description = "A big cash pack.",
		cash = 10000,
	},
	{
		key = "DoubleWood",
		id = StoreData.CreatorIds.Products.DoubleWood,
		image = 0, -- PASTE decal id
		name = "2x Wood (48 hours)",
		description = "Wood you cut in the next 48 hours is worth double.",
		boostHours = 48,
	},
	{
		key = "InstantDelivery",
		id = StoreData.CreatorIds.Products.InstantDelivery,
		image = 0, -- PASTE decal id
		name = "Instant Delivery",
		description = "Sell your truckload from anywhere, once.",
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

-- True when any pass or product has a real id. The STORE button stays
-- hidden until then.
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
