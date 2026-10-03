--!strict
-- FillLogic: dropping planks onto an unfilled kit piece (PlotData). Pure.
-- One wood, planks only. The first wood locks the piece. Units are u³.
-- Excess stays a plank; it is never turned into cash.

local GameConfig = require(script.Parent.GameConfig)

local FillLogic = {}

FillLogic.Reach = 16 -- studs from the piece to the plank

export type Offer = {
	uid: string,
	kind: string,
	woodId: string,
	volume: number,
	ownerId: number,
	held: boolean,
	size: Vector3,
}

function FillLogic.InRange(distance: number): boolean
	return distance == distance and distance >= 0 and distance <= FillLogic.Reach
end

-- Whether this plank may go into the piece. The piece must still be a
-- blueprint (fill set, short of its wood units).
function FillLogic.Accept(
	wood: string?,
	filled: number,
	need: number,
	offer: Offer,
	ownerId: number
): (boolean, string?)
	if filled >= need then
		return false, "built"
	end
	if offer.kind ~= "plank" then
		return false, "logs"
	end
	if offer.held then
		return false, "held"
	end
	if offer.ownerId ~= ownerId or offer.ownerId == 0 then
		return false, "owner"
	end
	if offer.volume ~= offer.volume or offer.volume <= 0 then
		return false, "empty"
	end
	if wood ~= nil and wood ~= offer.woodId then
		return false, "wood"
	end
	return true, nil
end

-- Every reason Accept can return. A missing message is a bug.
FillLogic.Reasons = { "built", "logs", "held", "owner", "empty", "wood" }

-- Player text for a refusal. `pieceName` and `woodName` are display names.
function FillLogic.Message(reason: string?, pieceName: string?, woodName: string?): string?
	local piece = if type(pieceName) == "string" and pieceName ~= "" then pieceName else "piece"
	local wood = if type(woodName) == "string" and woodName ~= "" then woodName else "another wood"
	if reason == "wood" then
		return string.format("This %s is being built with %s.", piece, wood)
	elseif reason == "logs" then
		return "Saw logs into planks first."
	elseif reason == "held" then
		return "Drop the plank before it can go into the build."
	elseif reason == "owner" then
		return "That wood isn't yours."
	elseif reason == "empty" then
		return "That plank is too small to use."
	elseif reason == "built" then
		return string.format("This %s is already built.", piece)
	end
	return nil
end

-- How much of `volume` fills the piece, and what is left on a new plank.
function FillLogic.Take(filled: number, need: number, volume: number): (number, number)
	local room = math.max(0, need - filled)
	local take = math.min(room, volume)
	if take < 0 then
		take = 0
	end
	return take, volume - take
end

-- A leftover plank with the same cross-section and a shorter length (Y).
function FillLogic.LeftoverSize(size: Vector3, leftover: number, original: number): Vector3
	local frac = if original > 0 then leftover / original else 0
	local length = math.max(size.Y * frac, GameConfig.WoodUnit * 0.05)
	return Vector3.new(size.X, length, size.Z)
end

return FillLogic
