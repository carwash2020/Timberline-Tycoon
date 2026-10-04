--!strict
-- TutorialGrove: the first-sale grove and Murph's buy cart.
-- A few small oaks stand just west of the spawn, and a cart beside them
-- buys small loads at the mill's own price during the sell, plot and truck
-- steps. It stops once the running total would pass MaxVolume, or once the
-- player owns a truck or can afford the Rustbucket, so it is not a second
-- sawmill. The spots stay off the roads, the spawn walk, the street and
-- the lot (tests/TutorialGrove.spec).

local ItemCatalog = require(script.Parent.ItemCatalog)
local ShopLogic = require(script.Parent.ShopLogic)

local TutorialGrove = {}

-- One small oak, not a truck. A v2 offer is pieces plus u³; a v1 offer is
-- logs in hand (a small oak is two).
TutorialGrove.MaxPieces = 12
TutorialGrove.MaxVolume = 80
TutorialGrove.MaxLogs = 4
-- Old saves set this after the first piece. ProfileSchema.UnstickCart
-- turns that flag back into a volume of 0 when the player is still stuck
-- short of a truck. New sales count onboarding.cartVolume instead.
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
}

TutorialGrove.RefuseUsed = "My cart's just to get you to a truck. The sawmill up north buys the rest."
TutorialGrove.RefuseClosed =
	"Murph's cart only buys a new lumberjack's first small loads. The sawmill up north buys the rest."
TutorialGrove.RefuseBig = "That's more than my cart can take. The sawmill buys a full load."

local OPEN_STEPS: { [string]: boolean } = { sell = true, plot = true, truck = true }

-- The Rustbucket's price in `loop` (0 in v1, where it was free).
function TutorialGrove.TruckPrice(loop: number): number
	local truck = ItemCatalog.GetTruck("Rustbucket")
	if not truck then
		return 0
	end
	return ShopLogic.Price(truck, loop)
end

-- u³ already recorded on the cart. Missing or junk counts as none.
function TutorialGrove.SavedVolume(onboarding: { [string]: boolean | number }?): number
	if type(onboarding) ~= "table" then
		return 0
	end
	local n = onboarding.cartVolume
	if type(n) ~= "number" or n ~= n or n < 0 or n == math.huge then
		return 0
	end
	return n
end

-- Adds a sale the cart just accepted. Junk volume adds nothing.
function TutorialGrove.Remember(onboarding: { [string]: boolean | number }, volume: number)
	local add = if type(volume) == "number"
			and volume == volume
			and volume > 0
			and volume < math.huge
		then volume
		else 0
	onboarding.cartVolume = TutorialGrove.SavedVolume(onboarding) + add
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
