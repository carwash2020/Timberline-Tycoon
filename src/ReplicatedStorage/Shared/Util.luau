-- Util: small shared helpers (safe to require from server and client).

local HttpService = game:GetService("HttpService")

local Util = {}

function Util.clamp(n: number, lo: number, hi: number): number
	if n < lo then
		return lo
	end
	if n > hi then
		return hi
	end
	return n
end

function Util.guid(): string
	return HttpService:GenerateGUID(false)
end

-- 1234567 -> "$1,234,567", -4500 -> "-$4,500"
function Util.formatCash(n: number): string
	n = math.floor(n or 0)
	local negative = n < 0
	n = math.abs(n)
	local s = tostring(n)
	local out = ""
	while #s > 3 do
		out = "," .. string.sub(s, -3) .. out
		s = string.sub(s, 1, -4)
	end
	out = s .. out
	return (if negative then "-$" else "$") .. out
end

-- Words that start with a vowel letter but a consonant sound ("a
-- unicorn", "a one-off"), and with a silent h ("an hour"), lower case.
local A_BEFORE = { "uni", "use", "usu", "uti", "ure", "eu", "one", "once" }
local AN_BEFORE = { "hour", "honest", "honor", "honour", "heir" }

local function startsWithAny(word: string, prefixes: { string }): boolean
	for _, prefix in ipairs(prefixes) do
		if string.sub(word, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- `word` with "a" or "an" before it, its own case kept: "an oak", "a
-- birch", "an Elder", "an Insulated Coat", "a unicorn", "an hour". For
-- messages that name a thing ("Lightning struck %s nearby!"); "" stays "".
function Util.article(word: string): string
	local lower = string.lower(word)
	local first = string.sub(lower, 1, 1)
	if first == "" then
		return word
	end
	local an = string.find(first, "[aeiou]") ~= nil
	if an and startsWithAny(lower, A_BEFORE) then
		an = false
	elseif not an and startsWithAny(lower, AN_BEFORE) then
		an = true
	end
	return (if an then "an " else "a ") .. word
end

function Util.deepCopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local copy: { [any]: any } = {}
	for k, v in pairs(t) do
		copy[Util.deepCopy(k)] = Util.deepCopy(v)
	end
	return copy
end

-- Is a world-space point inside an (axis-aligned in local space) part?
function Util.pointInPart(part: BasePart, point: Vector3): boolean
	local rel = part.CFrame:PointToObjectSpace(point)
	local s = part.Size
	return math.abs(rel.X) <= s.X / 2 and math.abs(rel.Y) <= s.Y / 2 and math.abs(rel.Z) <= s.Z / 2
end

return Util
