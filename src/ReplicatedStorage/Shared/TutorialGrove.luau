--!strict
-- TutorialGrove: the first-sale grove and Murph's buy cart.
-- A few small oaks stand just west of the spawn, and a cart beside them
-- buys one small load at the mill's own price while the tutorial's sell
-- step is the current one. After that single sale the cart refuses, so it
-- is not a second sawmill: the haul up to the real pad is the next lesson.
-- The spots stay off the roads, the spawn walk, the street and the lot
-- (tests/TutorialGrove.spec).

local TutorialGrove = {}

-- One small oak, not a truck. A v2 offer is pieces plus u³; a v1 offer is
-- logs in hand (a small oak is two).
TutorialGrove.MaxPieces = 12
TutorialGrove.MaxVolume = 80
TutorialGrove.MaxLogs = 4
TutorialGrove.UsedKey = "TutorialCart" -- profile.onboarding, set after the one sale

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
	used: boolean,
	pieces: number,
	volume: number?,
	logs: number?,
}

TutorialGrove.RefuseUsed = "Murph already bought your first load. The sawmill up north buys the rest."
TutorialGrove.RefuseClosed =
	"Murph's cart only buys a new lumberjack's first small load. The sawmill up north buys the rest."
TutorialGrove.RefuseBig = "That's more than my cart can take. The sawmill buys a full load."

-- Whether the cart buys this offer. `stepId` is the tutorial step they're
-- on (nil once it's over). One sale, and only during the sell step.
function TutorialGrove.Accept(offer: Offer): (boolean, string?)
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

return TutorialGrove
