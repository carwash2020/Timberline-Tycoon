--!strict
-- TutorialGrove: the first-sale grove and Murph's buy cart.
-- A few small oaks stand just west of the spawn, and a cart beside them
-- buys small loads at the mill's own price. On the v2 loop that lasts
-- through the sell, plot, build and truck steps, up to MaxVolume on this save
-- slot (profile.cartVolume). On the v1 loop it buys one load, during the
-- sell step only, and then profile.cartUsed refuses the rest. It also
-- stops once the player owns a truck or can afford the Rustbucket, so it
-- is not a second sawmill. The spots stay off the roads, the spawn walk,
-- the street and the lot (tests/TutorialGrove.spec).

local GameConfig = require(script.Parent.GameConfig)
local ItemCatalog = require(script.Parent.ItemCatalog)
local ShopLogic = require(script.Parent.ShopLogic)

local TutorialGrove = {}

-- One small oak, not a truck. A v2 offer is pieces plus u³; a v1 offer is
-- logs in hand (a small oak is two).
TutorialGrove.MaxPieces = 12
TutorialGrove.MaxVolume = 80
TutorialGrove.MaxLogs = 4
-- Old saves set this on the account after the first piece.
-- ProfileSchema.UnstickCart turns that flag into a per-slot volume of 0
-- when that slot is still stuck short of a truck, and stamps cartUsed so
-- a v1 rollback still refuses a second sale. New v2 sales count
-- profile.cartVolume. New v1 sales set profile.cartUsed.
TutorialGrove.UsedKey = "TutorialCart"

-- The sell volume, the same height as the mill's (y 0 to 12).
TutorialGrove.ZoneSize = Vector3.new(7, 12, 7)

export type Spot = { x: number, z: number }

-- West of the spawn walk (x -6), south of the street (z 62) and of Bram's
-- walk (his south mark is -17, 50), north of the road mouths (z 36), and
-- clear of Murph's camp at (-28, 45).
TutorialGrove.Trees = {
	{ x = -22, z = 44 },
	{ x = -21, z = 40 },
	{ x = -19, z = 46 },
} :: { Spot }

TutorialGrove.Cart = { x = -13, z = 42 } :: Spot

-- Centre of the sell volume (the cart model itself sits on the ground).
function TutorialGrove.CartCFrame(): CFrame
	local c = TutorialGrove.Cart
	return CFrame.new(c.x, 6, c.z)
end

export type Offer = {
	done: boolean,
	stepId: string?,
	pieces: number,
	volume: number?,
	logs: number?,
	cartVolume: number?, -- u³ already bought at this cart
	cash: number?,
	ownsTruck: boolean?,
	truckPrice: number?,
	landPrice: number?, -- the plot still to buy and the placing buffer (LandPrice): the cart stays open until cash covers them as well as the truck
}

TutorialGrove.RefuseUsed = "My cart's just to get you to a truck. The sawmill up north buys the rest."
TutorialGrove.RefuseClosed =
	"Murph's cart only buys a new lumberjack's first small loads. The sawmill up north buys the rest."
TutorialGrove.RefuseBig = "That's more than my cart can take. The sawmill buys a full load."

-- The cart stays open from the sell through the plot, the build lessons
-- (placing a piece costs a few dollars) and the truck, so a new player can
-- always sell enough to buy the plot and then the Rustbucket box.
local OPEN_STEPS: { [string]: boolean } = {
	sell = true,
	plot = true,
	build = true,
	place = true,
	land = true,
	truck = true,
}

-- A few dollars for the build lesson's first piece (the kit costs
-- PlotData.KitCashPerUnit a unit), kept in the purse before the cart closes.
TutorialGrove.PlaceBuffer = 20

-- What the cart keeps open for besides the truck (offer.landPrice): the
-- plot while it is unbought, and a few dollars for the build lesson.
-- Nothing on the v1 loop. `plotBought` is profile.plot.claimed.
function TutorialGrove.LandPrice(loop: number, plotBought: boolean): number
	if loop ~= 2 then
		return 0
	end
	return TutorialGrove.PlaceBuffer + if plotBought then 0 else GameConfig.PlotPrice
end

-- The Rustbucket's price in `loop` (priceCash in v1, v2.price in v2).
function TutorialGrove.TruckPrice(loop: number): number
	local truck = ItemCatalog.GetTruck("Rustbucket")
	if not truck then
		return 0
	end
	return ShopLogic.Price(truck, loop)
end

-- u³ already recorded on this save slot. Missing or junk counts as none.
function TutorialGrove.SavedVolume(record: { cartVolume: number }?): number
	if type(record) ~= "table" then
		return 0
	end
	local n = record.cartVolume
	if type(n) ~= "number" or n ~= n or n < 0 or n == math.huge then
		return 0
	end
	return n
end

-- Adds a sale the cart just accepted, on this save slot. Junk volume adds nothing.
function TutorialGrove.Remember(record: { cartVolume: number }, volume: number)
	local add = if type(volume) == "number"
			and volume == volume
			and volume > 0
			and volume < math.huge
		then volume
		else 0
	record.cartVolume = TutorialGrove.SavedVolume(record) + add
end

export type OnceOffer = {
	done: boolean,
	stepId: string?,
	used: boolean, -- this slot's cartUsed
	pieces: number,
	volume: number?,
	logs: number?,
}

-- The v1 cart: one sale, and only during the sell step. A set `used` flag
-- refuses even after the player has moved on to the truck.
function TutorialGrove.AcceptV1(offer: OnceOffer): (boolean, string?)
	if offer.used then
		return false, TutorialGrove.RefuseUsed
	end
	if offer.done or offer.stepId ~= "sell" then
		return false, TutorialGrove.RefuseClosed
	end
	if offer.pieces > TutorialGrove.MaxPieces then
		return false, TutorialGrove.RefuseBig
	end
	local volume = offer.volume
	if volume and volume > TutorialGrove.MaxVolume then
		return false, TutorialGrove.RefuseBig
	end
	local logs = offer.logs
	if logs and logs > TutorialGrove.MaxLogs then
		return false, TutorialGrove.RefuseBig
	end
	if offer.pieces < 1 then
		return false, TutorialGrove.RefuseClosed
	end
	return true, nil
end

-- Whether the cart buys this offer. `stepId` is the tutorial step they're
-- on (nil once it's over). Open during sell, plot and truck, until the
-- running total would pass MaxVolume, they own a truck, or their cash
-- already covers the Rustbucket.
function TutorialGrove.Accept(offer: Offer): (boolean, string?)
	if offer.done or not OPEN_STEPS[offer.stepId or ""] then
		return false, TutorialGrove.RefuseClosed
	end
	if offer.ownsTruck == true then
		return false, TutorialGrove.RefuseUsed
	end
	local price = offer.truckPrice
	local cash = offer.cash
	if type(price) == "number" and price > 0 and type(offer.landPrice) == "number" and offer.landPrice > 0 then
		price += offer.landPrice
	end
	if type(price) == "number" and price > 0 and type(cash) == "number" and cash == cash and cash >= price then
		return false, TutorialGrove.RefuseUsed
	end
	if offer.pieces > TutorialGrove.MaxPieces then
		return false, TutorialGrove.RefuseBig
	end
	local volume = offer.volume
	if volume then
		local raw = offer.cartVolume
		local soFar = if type(raw) == "number" and raw == raw and raw >= 0 and raw < math.huge then raw else 0
		if soFar + volume > TutorialGrove.MaxVolume then
			return false, TutorialGrove.RefuseBig
		end
	end
	local logs = offer.logs
	if logs and logs > TutorialGrove.MaxLogs then
		return false, TutorialGrove.RefuseBig
	end
	if offer.pieces < 1 then
		return false, TutorialGrove.RefuseClosed
	end
	return true, nil
end

return TutorialGrove
