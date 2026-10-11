--!strict
-- FillLogic: dropping planks onto an unfilled kit piece (PlotData). Pure.
-- One wood, planks only. The first wood locks the piece. Units are u³.
-- Excess stays a plank; it is never turned into cash.

local BuildCost = require(script.Parent.BuildCost)
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

-- A sandstone slab or an ingot offered to a piece (Lane F). `ore` is the
-- ingot's ore id. Same rules as a plank for who may use it: yours, and not
-- in anyone's hands.
export type Material = {
	uid: string,
	kind: string, -- "slab" | "ingot"
	ore: string?,
	ownerId: number,
	held: boolean,
}

-- Whether this slab or ingot may go into the piece. `need` is what the
-- piece takes in all, `missing` what it still lacks (BuildCost). A part
-- the piece does not take, or has enough of, is refused and stays a part.
function FillLogic.AcceptMaterial(
	need: BuildCost.Need,
	missing: BuildCost.Need,
	offer: Material,
	ownerId: number
): (boolean, string?)
	if offer.kind == "slab" then
		if need.slabs <= 0 then
			return false, "noslab"
		end
		if missing.slabs <= 0 then
			return false, "full"
		end
	elseif offer.kind == "ingot" then
		local ore = offer.ore
		if type(ore) ~= "string" or need.ingots[ore] == nil then
			return false, "noingot"
		end
		if missing.ingots[ore] == nil then
			return false, "full"
		end
	else
		return false, "noslab"
	end
	if offer.held then
		return false, "held"
	end
	if offer.ownerId ~= ownerId or offer.ownerId == 0 then
		return false, "owner"
	end
	return true, nil
end

-- Every reason Accept can return. A missing message is a bug.
FillLogic.Reasons = { "built", "logs", "held", "owner", "empty", "wood", "noslab", "noingot", "full" }

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
	elseif reason == "noslab" then
		return string.format("The %s doesn't take sandstone slabs.", piece)
	elseif reason == "noingot" then
		return string.format("The %s doesn't take that ingot.", piece)
	elseif reason == "full" then
		return string.format("The %s has all of that already.", piece)
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
