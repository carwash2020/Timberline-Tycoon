--!strict
-- BoxLogic: who may grab or open a shop box, and when an unpaid box has
-- left the store. Pure. BoxService applies it.
--
-- An unpaid box outside the store volume for DespawnChecks watches (2 Hz)
-- goes back to its shelf. Paying grants the item; opening only unpacks it.

local GameConfig = require(script.Parent.GameConfig)

local BoxLogic = {}

-- Open to tuning: how long a grab claim lasts, on the server clock.
-- Not a GameConfig key; that file belongs to wave 0.
BoxLogic.BoxClaimSec = 8

BoxLogic.OpenRange = 12 -- studs, buyer to the box
BoxLogic.MaxUnpaidPerPlayer = 3 -- the 4th take is refused
BoxLogic.MaxUnpaidPerServer = 30 -- the 31st take is refused
BoxLogic.PutBackRadius = 3.5 -- studs: an unpaid box let go this close (across) to its shelf spot goes back on it
BoxLogic.PutBackHeight = 3 -- studs: and no higher or lower than this from it
-- The parts of a box (Art/BoxArt): ShellPartCap for the dark body, its windows and
-- its name strip, plus the display copy of the item (ItemModel.ModelBudget by
-- kind). BoxPartCap is the most a whole box may have, so one in the hand stays
-- light on a phone; the specs check every box against it.
BoxLogic.ShellPartCap = 9
BoxLogic.BoxPartCap = 42
BoxLogic.PayTapPx = 44
BoxLogic.DespawnHz = 2

export type GrabFacts = {
	userId: number,
	now: number,
	heldBy: number,
	paid: boolean?,
	buyerId: number?,
	claimUserId: number?,
	claimUntil: number?,
	unpaidByPlayer: number?,
	unpaidOnServer: number?,
	taking: boolean?, -- this grab lifts it off the shelf
}

-- What the carry cap needs to know of a box.
export type Counted = {
	paid: boolean,
	opened: boolean,
	onShelf: boolean,
	heldBy: number, -- the UserId whose hand it is in right now, 0 = nobody's
}

export type GrabReason = "held" | "owned" | "claim" | "cap"

export type OpenFacts = {
	userId: number,
	buyerId: number,
	paid: boolean,
	opened: boolean?,
	distance: number,
	uid: string?,
	promptUid: string?,
}

export type OpenReason = "owner" | "far" | "unpaid" | "opened" | "uid"

function BoxLogic.ClaimUntil(now: number): number
	return now + BoxLogic.BoxClaimSec
end

function BoxLogic.CheckInterval(): number
	return 1 / BoxLogic.DespawnHz
end

-- Whether `facts.userId` may take hold of a shop box.
function BoxLogic.CanGrab(facts: GrabFacts): (boolean, GrabReason?)
	if facts.heldBy ~= 0 and facts.heldBy ~= facts.userId then
		return false, "held"
	end
	if facts.paid then
		if facts.buyerId ~= facts.userId then
			return false, "owned"
		end
		return true, nil
	end
	local claimUser = facts.claimUserId or 0
	local untilAt = facts.claimUntil or 0
	if claimUser ~= 0 and claimUser ~= facts.userId and facts.now < untilAt then
		return false, "claim"
	end
	if facts.taking then
		local byPlayer = facts.unpaidByPlayer or 0
		local onServer = facts.unpaidOnServer or 0
		if byPlayer >= BoxLogic.MaxUnpaidPerPlayer or onServer >= BoxLogic.MaxUnpaidPerServer then
			return false, "cap"
		end
	end
	return true, nil
end

-- The two numbers the carry cap reads: how many unpaid boxes `userId` HOLDS
-- right now, and how many unpaid boxes are off their shelves, whoever has
-- them. A box counts for a player only while it is in their hands: one they
-- let go of, put back, paid for or never lifted (a grab the server refused)
-- is never counted against them, so the cap cannot fire on a first pickup.
function BoxLogic.CountUnpaid(boxes: { Counted }, userId: number): (number, number)
	local mine, all = 0, 0
	for _, box in ipairs(boxes) do
		if not box.paid and not box.opened and not box.onShelf then
			all += 1
			if box.heldBy == userId and userId ~= 0 then
				mine += 1
			end
		end
	end
	return mine, all
end

-- Whether an unpaid box let go at `at` was put back on its shelf spot `home`
-- (close across, and not far above or below), so it sits there again instead
-- of staying a loose box.
function BoxLogic.PutBack(at: Vector3, home: Vector3): boolean
	local across = Vector3.new(at.X - home.X, 0, at.Z - home.Z).Magnitude
	return across <= BoxLogic.PutBackRadius and math.abs(at.Y - home.Y) <= BoxLogic.PutBackHeight
end

function BoxLogic.CapMessage(byPlayer: number, onServer: number): string?
	if byPlayer >= BoxLogic.MaxUnpaidPerPlayer then
		return "You can only carry 3 unpaid boxes."
	end
	if onServer >= BoxLogic.MaxUnpaidPerServer then
		return "The shop is full of loose boxes. Put one back and try again."
	end
	return nil
end

-- The buyer, close enough, paid, and not already unpacked. The prompt's
-- parent uid has to be this box's server uid.
function BoxLogic.CanOpen(facts: OpenFacts): (boolean, OpenReason?)
	if facts.promptUid == nil or facts.uid == nil or facts.promptUid ~= facts.uid then
		return false, "uid"
	end
	if not facts.paid then
		return false, "unpaid"
	end
	if facts.buyerId ~= facts.userId then
		return false, "owner"
	end
	if facts.distance > BoxLogic.OpenRange then
		return false, "far"
	end
	if facts.opened then
		return false, "opened"
	end
	return true, nil
end

function BoxLogic.OpenMessage(reason: OpenReason?): string?
	if reason == "owner" then
		return "That box isn't yours."
	elseif reason == "far" then
		return "Walk closer to open it."
	elseif reason == "unpaid" then
		return "Pay for it at the counter first."
	elseif reason == "uid" then
		return "That isn't the box you reached for."
	end
	return nil
end

-- `floorCf` sits on the shop floor, +Y up, -Z toward the door.
-- The volume is the footprint grown by StoreDespawnPad, from the floor
-- up to StoreDespawnHeight. The boundary counts as inside.
function BoxLogic.InsideVolume(point: Vector3, floorCf: CFrame, footprint: Vector3): boolean
	local p = floorCf:PointToObjectSpace(point)
	local pad = GameConfig.StoreDespawnPad
	local hx = footprint.X / 2 + pad
	local hz = footprint.Z / 2 + pad
	if math.abs(p.X) > hx or math.abs(p.Z) > hz then
		return false
	end
	return p.Y >= 0 and p.Y <= GameConfig.StoreDespawnHeight
end

-- Maps build space (the shop as authored, origin on the ground) into the
-- world. `buildPivot` is the model's pivot position while it still sat
-- at the origin.
function BoxLogic.BuildToWorld(pivotNow: CFrame, buildPivot: Vector3): CFrame
	return pivotNow * CFrame.new(-buildPivot)
end

function BoxLogic.OutsideStreak(inside: boolean, streak: number): number
	if inside then
		return 0
	end
	return streak + 1
end

function BoxLogic.ShouldReturn(streak: number): boolean
	return streak >= GameConfig.DespawnChecks
end

-- The two faces with the most area: the ones whose axis is the shortest.
function BoxLogic.LargestFaces(size: Vector3): { Enum.NormalId }
	if size.X <= size.Y and size.X <= size.Z then
		return { Enum.NormalId.Right, Enum.NormalId.Left }
	elseif size.Y <= size.X and size.Y <= size.Z then
		return { Enum.NormalId.Top, Enum.NormalId.Bottom }
	end
	return { Enum.NormalId.Front, Enum.NormalId.Back }
end

return BoxLogic
