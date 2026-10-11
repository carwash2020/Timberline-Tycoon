--!strict
-- LooseCaps: which loose things go when there are too many (V1 hardening).
--
-- Loose wood has its own caps in WoodService (a piece count a player and a
-- part count a server). This is the same rule for the other loose parts:
-- sandstone slabs, ore chunks and ingots lying on the ground. Past
-- `perPlayer` of one owner's, that owner's oldest go; past `perServer` in all,
-- the oldest of nobody's go first, then the oldest of anyone's.
--
-- An entry marked `protected` never goes (held in a hand, or inside a box,
-- truck or machine); it still counts toward both caps, so the rest make room
-- for it. Saved plot items and records in plot.loose are not in the world, so
-- they are never entries. Pure: BuildMaterials gathers the entries and
-- removes what this returns.

local LooseCaps = {}

export type Entry = {
	uid: string,
	ownerId: number, -- 0 = nobody's
	bornAt: number, -- when it was made; the smaller, the older
	protected: boolean?,
}

local function finiteCap(n: number): boolean
	return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

local function oldestFirst(a: Entry, b: Entry): boolean
	if a.bornAt ~= b.bornAt then
		return a.bornAt < b.bornAt
	end
	return a.uid < b.uid
end

-- The uids to remove, in the order they go. Entries are not changed.
function LooseCaps.PickEvictions(entries: { Entry }, perPlayer: number, perServer: number): { string }
	local out: { string } = {}
	if not finiteCap(perPlayer) or not finiteCap(perServer) then
		return out -- a bad cap removes nothing rather than everything
	end
	local gone: { [string]: boolean } = {}
	local byOwner: { [number]: { Entry } } = {}
	local total = #entries
	for _, e in ipairs(entries) do
		if e.ownerId ~= 0 then
			local list = byOwner[e.ownerId] or {}
			table.insert(list, e)
			byOwner[e.ownerId] = list
		end
	end
	local function evict(e: Entry)
		gone[e.uid] = true
		table.insert(out, e.uid)
		total -= 1
	end
	local owners: { number } = {}
	for ownerId in pairs(byOwner) do
		table.insert(owners, ownerId)
	end
	table.sort(owners)
	for _, ownerId in ipairs(owners) do
		local list = byOwner[ownerId]
		table.sort(list, oldestFirst)
		local count = #list
		for _, e in ipairs(list) do
			if count <= perPlayer then
				break
			end
			if not e.protected then
				evict(e)
				count -= 1
			end
		end
	end
	if total > perServer then
		local sorted = table.clone(entries)
		table.sort(sorted, oldestFirst)
		for _, nobodysOnly in ipairs({ true, false }) do
			for _, e in ipairs(sorted) do
				if total <= perServer then
					break
				end
				if not gone[e.uid] and not e.protected and (e.ownerId == 0 or not nobodysOnly) then
					evict(e)
				end
			end
		end
	end
	return out
end

return LooseCaps
