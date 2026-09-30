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

-- 1234567 -> "$1,234,567"
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
	if negative then
		out = "-" .. out
	end
	return "$" .. out
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
	return math.abs(rel.X) <= s.X / 2
		and math.abs(rel.Y) <= s.Y / 2
		and math.abs(rel.Z) <= s.Z / 2
end

return Util
