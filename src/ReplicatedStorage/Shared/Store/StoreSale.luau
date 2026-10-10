--!strict
-- StoreSale: the sale state of every Robux item, pure so the store panel,
-- the bulletin board, the gold shelf and the server agree.
--   * Roblox decides what is for sale (Creator Hub's switch), read with
--     GetProductInfoAsync. A pasted id alone never sells anything.
--   * The server caches each item's answer (StoreSaleService) and publishes
--     it as a boolean attribute "StoreOnSale_<Kind>_<Key>" on
--     ReplicatedStorage.StoreState; absent means "not known yet".
--   * CardState is the one rule for what a card shows: Owned beats
--     everything; an id of 0 or a "no" from Roblox is Coming soon (or
--     Hidden, per the item's offSale); no answer yet is Coming soon, never
--     Buy; a cash pack that doesn't fit the wallet is Wallet full.

local StoreSale = {}

export type CardState = "Buy" | "Owned" | "Soon" | "WalletFull" | "Hidden"

export type Facts = {
	owned: boolean?, -- a pass the player has (bought or granted)
	robloxForSale: boolean?, -- Roblox's answer; nil while unknown
	cash: number?, -- the player's wallet
	cap: number?, -- the wallet cap
	packCash: number?, -- what this cash pack would add now (nil: not a pack)
}

export type Item = { id: number, offSale: string? }

StoreSale.StateFolder = "StoreState"
StoreSale.RefreshSec = 600 -- the server re-asks Roblox every 10 minutes
StoreSale.Tries = 3

function StoreSale.AttrName(kind: string, key: string): string
	return "StoreOnSale_" .. kind .. "_" .. key
end

-- Roblox's product info as a sale answer. IsForSale when it is there; a
-- missing field with a numeric PriceInRobux counts as on sale (some
-- product lookups leave the field off); anything else is nil (unknown).
function StoreSale.ReadInfo(info: unknown): boolean?
	if type(info) ~= "table" then
		return nil
	end
	local t = info :: any
	if type(t.IsForSale) == "boolean" then
		return t.IsForSale
	end
	if type(t.PriceInRobux) == "number" then
		return true
	end
	return nil
end

-- A price from Roblox's product info, or nil.
function StoreSale.ReadPrice(info: unknown): number?
	if type(info) ~= "table" then
		return nil
	end
	local price = (info :: any).PriceInRobux
	if type(price) == "number" and price == price and price >= 0 then
		return math.floor(price)
	end
	return nil
end

function StoreSale.CardState(item: Item, facts: Facts): CardState
	if facts.owned == true then
		return "Owned"
	end
	local notSold: CardState = if item.offSale == "hidden" then "Hidden" else "Soon"
	if type(item.id) ~= "number" or item.id <= 0 then
		return notSold
	end
	if facts.robloxForSale ~= true then
		return notSold
	end
	if facts.packCash ~= nil and facts.cash ~= nil and facts.cap ~= nil then
		if facts.cash + facts.packCash > facts.cap then
			return "WalletFull"
		end
	end
	return "Buy"
end

-- Whether the server may show Roblox's prompt for an item: a real id and
-- Roblox's own "yes". (Studio test mode is MonetizationService's.)
function StoreSale.MayPrompt(id: number, robloxForSale: boolean?): boolean
	return type(id) == "number" and id > 0 and robloxForSale == true
end

-- Whether a world display (board poster, gold box) shows the item: on sale
-- per Roblox, or not known yet (the server's first answer is a second
-- away; the purchase itself is still gated). A "no" hides it.
function StoreSale.ShowInWorld(id: number, robloxForSale: boolean?): boolean
	return type(id) == "number" and id > 0 and robloxForSale ~= false
end

return StoreSale
