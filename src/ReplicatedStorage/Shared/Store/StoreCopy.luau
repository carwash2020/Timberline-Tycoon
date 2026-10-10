--!strict
-- StoreCopy: every player-facing word of the Robux store in one place, so
-- the Designer edits one file. No Robux number is ever written here: a
-- price is always Roblox's, read live on the player's client. Item names
-- and descriptions stay in StoreData (they match Creator Hub word for word).

local StoreCopy = {}

StoreCopy.Title = "TIMBERLINE STORE"
StoreCopy.Subtitle = "Robux time-savers. Nothing pay-to-win."
StoreCopy.TabPasses = "PASSES"
StoreCopy.TabProducts = "PRODUCTS"
StoreCopy.Close = "X"
StoreCopy.HudButton = "STORE"
StoreCopy.BoardHeader = "TIMBERLINE"
StoreCopy.BoardPrompt = "Browse Store"
StoreCopy.BoardObject = "Store"

-- Card states.
StoreCopy.Owned = "Owned"
StoreCopy.Soon = "Coming soon"
StoreCopy.WalletFull = "Wallet full"
StoreCopy.PriceUnknown = "R$" -- the pill while Roblox's price isn't back yet
StoreCopy.RobuxPrefix = "R$ "

-- Card extras.
StoreCopy.PackNow = "+%s now" -- %s = the PackCash amount ($); short enough for a phone card
StoreCopy.HoursLeft = "%dh left"
StoreCopy.YouHave = "You have %d"
StoreCopy.EmptyPasses = "Passes coming soon."
StoreCopy.EmptyProducts = "Products coming soon."

-- Toasts (server and client).
StoreCopy.NotForSale = "That isn't for sale yet."
StoreCopy.NoAnswer = "Roblox's store didn't answer. Try again in a moment."
StoreCopy.AlreadyHave = "You already have %s."
StoreCopy.AlreadyOwnActive = "You already own %s; it's active now."
StoreCopy.WalletCap = "Your wallet can't hold that much (the cap is %s)."
StoreCopy.ThanksPass = "Thanks! %s is yours."
StoreCopy.ThanksCash = "Thanks! +%s"
StoreCopy.ThanksCashBanked = "Thanks! +%s now; %s more is saved for you and arrives as you spend."
StoreCopy.ThanksBoost = "Thanks! %s is on: wood from every tree you fell sells for double."
StoreCopy.ThanksDelivery = "Thanks! Use Instant Delivery to sell your truckload from anywhere."
StoreCopy.SellHere = "Sell here (%d)"
StoreCopy.RobuxItem = "Robux item" -- a gold box's hover line before its price is known

-- The bulletin board's one short line per item (the mockup's lines).
StoreCopy.BoardLines = {
	DoubleCash = "Wood you sell pays double.",
	LuxAxe = "A bright axe, untemperable.",
	TowService = "Free recalls for every truck.",
	TimberClassic = "An old-school pickup.",
	PaintShop = "Paint your trucks any color.",
	Cash1k = "15 minutes of wood income.",
	Cash10k = "2 hours of wood income.",
	DoubleWood = "48 hours of double wood.",
	InstantDelivery = "Sell your load from anywhere.",
} :: { [string]: string }

-- The glyph on an art disc that has no image yet.
StoreCopy.BoardGlyphs = {
	DoubleCash = "2x",
	LuxAxe = "L",
	Cash1k = "$",
	Cash10k = "$$",
	DoubleWood = "2x",
	InstantDelivery = "ID",
} :: { [string]: string }

-- The price pill text: Roblox's live price, or just "R$" while unknown.
function StoreCopy.Price(price: number?): string
	if type(price) == "number" and price >= 0 and price == price then
		return StoreCopy.RobuxPrefix .. tostring(math.floor(price))
	end
	return StoreCopy.PriceUnknown
end

return StoreCopy
