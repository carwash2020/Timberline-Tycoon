--!strict
-- MineSites: the one adapter for cave positions. Live tagged anchors and
-- rubble win. Otherwise UndergroundData, when that module is in the
-- place. Otherwise the constants from MAP_V1 (the mine mouth, the furnace
-- pad, the five rubble ids).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MineSites = {}

export type Anchor = { tier: number, x: number, y: number, z: number }
export type Rubble = {
	id: string,
	tier: number,
	x: number,
	y: number,
	z: number,
	ex: number, -- unit exit toward the mine mouth, X
	ez: number, -- unit exit toward the mine mouth, Z
}
export type Pad = { x: number, y: number, z: number, sx: number, sz: number }
export type Sites = {
	source: string,
	furnace: Pad,
	mouth: { x: number, z: number },
	anchors: { Anchor },
	rubble: { Rubble },
	ledges: { Anchor },
}

MineSites.RubbleIds = { "mine-mid", "mine-deep", "hidden-hills", "hidden-peak", "hidden-lava" }

local function pad(x: number, y: number, z: number, sx: number, sz: number): Pad
	return { x = x, y = y, z = z, sx = sx, sz = sz }
end

-- Horizontal unit from a wall toward the mouth. Straight +Z when the two
-- spots are the same, so a crawl never follows LookVector down -Z.
function MineSites.Exit(x: number, z: number, mouth: { x: number, z: number }): (number, number)
	local dx = mouth.x - x
	local dz = mouth.z - z
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-4 then
		return 0, 1
	end
	return dx / len, dz / len
end

local function wall(id: string, tier: number, x: number, y: number, z: number, mouth: { x: number, z: number }): Rubble
	local ex, ez = MineSites.Exit(x, z, mouth)
	return { id = id, tier = tier, x = x, y = y, z = z, ex = ex, ez = ez }
end

local function fallbackBody(): Sites
	-- FurnaceSite (48, -110), 30 x 24, beside the south link. The mouth
	-- (150, -150) opens tier 1 only. Anchors sit in the chambers, off the
	-- roads, the sell pad, the truck tunnel and the grotto.
	return {
		source = "fallback",
		furnace = pad(48, 0, -110, 30, 24),
		mouth = { x = 150, z = -150 },
		-- rubble is filled just below, once `mouth` exists
		anchors = {
			{ tier = 1, x = 168, y = -12, z = -168 },
			{ tier = 1, x = 176, y = -12, z = -184 },
			{ tier = 1, x = 160, y = -14, z = -196 },
			{ tier = 1, x = 184, y = -14, z = -176 },
			{ tier = 1, x = 172, y = -16, z = -208 },
			{ tier = 1, x = 188, y = -12, z = -192 },
			{ tier = 1, x = 164, y = -18, z = -180 },
			{ tier = 1, x = 180, y = -16, z = -204 },
			{ tier = 2, x = 196, y = -32, z = -220 },
			{ tier = 2, x = 208, y = -34, z = -232 },
			{ tier = 2, x = 188, y = -36, z = -240 },
			{ tier = 2, x = 204, y = -30, z = -212 },
			{ tier = 2, x = 216, y = -38, z = -228 },
			{ tier = 3, x = 200, y = -64, z = -260 },
			{ tier = 3, x = 188, y = -66, z = -272 },
			{ tier = 3, x = 212, y = -62, z = -268 },
			{ tier = 3, x = 196, y = -70, z = -284 },
		},
		rubble = {},
		ledges = {
			{ tier = 2, x = 210, y = -30, z = -236 },
			{ tier = 3, x = 204, y = -60, z = -276 },
		},
	}
end

-- Fallback builds the mouth first, then the walls, so each exit points at it.
function MineSites.Fallback(): Sites
	local sites = fallbackBody()
	local mouth = sites.mouth
	sites.rubble = {
		wall("mine-mid", 2, 192, -28, -214, mouth),
		wall("mine-deep", 3, 198, -58, -252, mouth),
		wall("hidden-hills", 2, -460, 8, 160, mouth),
		wall("hidden-peak", 3, -80, 24, 620, mouth),
		wall("hidden-lava", 3, 280, -8, 420, mouth),
	}
	return sites
end

local function num(v: any, fallback: number): number
	if type(v) == "number" and v == v then
		return v
	end
	return fallback
end

-- Accepts the shape UndergroundData is documented to expose.
function MineSites.FromUnderground(data: any): Sites?
	if type(data) ~= "table" or type(data.FurnaceSite) ~= "table" then
		return nil
	end
	local furnace = data.FurnaceSite
	local sites = MineSites.Fallback()
	sites.source = "underground"
	sites.furnace =
		pad(num(furnace.x, 48), num(furnace.y, 0), num(furnace.z, -110), num(furnace.sx, 30), num(furnace.sz, 24))
	if type(data.Mouth) == "table" then
		sites.mouth = { x = num(data.Mouth.x, 150), z = num(data.Mouth.z, -150) }
		if type(data.Rubble) ~= "table" then
			for _, row in ipairs(sites.rubble) do
				row.ex, row.ez = MineSites.Exit(row.x, row.z, sites.mouth)
			end
		end
	end
	if type(data.MineAnchors) == "table" then
		local anchors: { Anchor } = {}
		for _, row in ipairs(data.MineAnchors) do
			if type(row) == "table" then
				table.insert(anchors, {
					tier = math.clamp(math.floor(num(row.tier, 1)), 1, 3),
					x = num(row.x, 0),
					y = num(row.y, 0),
					z = num(row.z, 0),
				})
			end
		end
		if #anchors > 0 then
			sites.anchors = anchors
		end
	end
	if type(data.Rubble) == "table" then
		local rubble: { Rubble } = {}
		for _, row in ipairs(data.Rubble) do
			if type(row) == "table" and type(row.id) == "string" then
				local x, y, z = num(row.x, 0), num(row.y, 0), num(row.z, 0)
				local ex, ez = MineSites.Exit(x, z, sites.mouth)
				table.insert(rubble, {
					id = row.id,
					tier = math.clamp(math.floor(num(row.tier, 1)), 1, 3),
					x = x,
					y = y,
					z = z,
					ex = ex,
					ez = ez,
				})
			end
		end
		if #rubble > 0 then
			sites.rubble = rubble
		end
	end
	return sites
end

function MineSites.FindModule(): any?
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local world = shared and shared:FindFirstChild("World")
	local mod = world and world:FindFirstChild("UndergroundData")
	if mod == nil then
		return nil
	end
	local isScript, yes = pcall(function()
		return (mod :: any):IsA("ModuleScript")
	end)
	if not isScript or yes ~= true then
		-- Outside Roblox (the Lune loader) a module is a table with __module.
		if not (type(mod) == "table" and (mod :: any).__module ~= nil) then
			return nil
		end
	end
	local ok, result = pcall(require, mod)
	if ok and type(result) == "table" then
		return result
	end
	return nil
end

function MineSites.Current(override: any?): Sites
	if override ~= nil then
		local parsed = MineSites.FromUnderground(override)
		if parsed then
			return parsed
		end
	end
	local live = MineSites.FindModule()
	if live ~= nil then
		local parsed = MineSites.FromUnderground(live)
		if parsed then
			return parsed
		end
	end
	return MineSites.Fallback()
end

export type LiveAnchor = { tier: number, x: number, y: number, z: number }
export type LiveRubble = { id: string, tier: number, x: number, y: number, z: number }

-- Tagged workspace parts replace the table when the world actually has them.
function MineSites.MergeLive(sites: Sites, anchors: { LiveAnchor }, rubble: { LiveRubble }): Sites
	local copy: Sites = {
		source = sites.source,
		furnace = sites.furnace,
		mouth = sites.mouth,
		anchors = sites.anchors,
		rubble = sites.rubble,
		ledges = sites.ledges,
	}
	if #anchors > 0 then
		copy.source = "live"
		copy.anchors = anchors
	end
	if #rubble > 0 then
		copy.source = if #anchors > 0 then "live" else sites.source .. "+rubble"
		local placed: { Rubble } = {}
		for _, row in ipairs(rubble) do
			local ex, ez = MineSites.Exit(row.x, row.z, copy.mouth)
			table.insert(placed, {
				id = row.id,
				tier = row.tier,
				x = row.x,
				y = row.y,
				z = row.z,
				ex = ex,
				ez = ez,
			})
		end
		copy.rubble = placed
	end
	return copy
end

return MineSites
