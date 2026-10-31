--!strict
-- PerfPolicy (T415): the performance rules as data, so specs can pin them. Pure; no engine calls.
--
--   * PreloadCap        the most ids the client's first-view ContentProvider:PreloadAsync may take
--   * Persistent        the models that stream as Persistent, by name. Everything interactive is Atomic and
--                       pure decor is Default (Streaming.spec scans the source for every other site).
--   * NoShadowSize      a part whose largest side is under this casts no shadow
--   * PreciseAllowlist  files that may use RenderFidelity.Precise (none: hero hand items would go here)
--   * ScatterAssets     town assets that are far scatter: their meshes render at Performance
--   * Duplicates        two live MeshIds for one source mesh

local PerfPolicy = {}

PerfPolicy.PreloadCap = 96

PerfPolicy.Persistent = {
	FerryBoat = true,
	LiftBridge = true,
	GateLodge = true,
	MainlandDock = true,
	IslandDock = true,
	-- spawn landmarks: the two boards at the spawn and the tutorial's two guides
	TownBoard = true,
	StoreBoard = true,
	Murph = true,
	OldHank = true,
} :: { [string]: boolean }

PerfPolicy.NoShadowSize = 1.5

PerfPolicy.PreciseAllowlist = {} :: { string }

PerfPolicy.ScatterAssets = {
	"RockGrey",
	"RockBrown",
	"RockMossy",
	"Bush",
	"Stump",
	"FallenLog",
	"GlowMushrooms",
	"SawdustPile",
	"PathRound",
} :: { string }

local scatter: { [string]: boolean } = {}
for _, id in ipairs(PerfPolicy.ScatterAssets) do
	scatter[id] = true
end

function PerfPolicy.IsScatter(assetId: string?): boolean
	return assetId ~= nil and scatter[assetId] == true
end

-- True when `part` is too small for its shadow to read.
function PerfPolicy.ShadowOff(part: BasePart): boolean
	local s = part.Size
	return math.max(s.X, s.Y, s.Z) < PerfPolicy.NoShadowSize
end

-- Turns CastShadow off on every small part under `root`. Returns how many it changed.
function PerfPolicy.TrimShadows(root: Instance): number
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d.CastShadow and PerfPolicy.ShadowOff(d) then
			d.CastShadow = false
			n += 1
		end
	end
	return n
end

export type Manifest = { [string]: { file: string, node: string } }

-- One line per source mesh (glb file + node) that has more than one of `ids` (the live MeshIds) in `manifest`
-- (assets/meshes/manifest.json: MeshId to source).
function PerfPolicy.Duplicates(ids: { number }, manifest: Manifest): { string }
	local bySource: { [string]: { [number]: boolean } } = {}
	local order: { string } = {}
	for _, id in ipairs(ids) do
		local row = manifest[tostring(id)]
		if row then
			local key = row.file .. " / " .. row.node
			if not bySource[key] then
				bySource[key] = {}
				table.insert(order, key)
			end
			bySource[key][id] = true
		end
	end
	table.sort(order)
	local lines: { string } = {}
	for _, key in ipairs(order) do
		local found: { string } = {}
		for id in pairs(bySource[key]) do
			table.insert(found, tostring(id))
		end
		if #found > 1 then
			table.sort(found)
			table.insert(lines, string.format("[PerfAssets] %s has %d live MeshIds: %s", key, #found, table.concat(found, ", ")))
		end
	end
	return lines
end

return PerfPolicy
