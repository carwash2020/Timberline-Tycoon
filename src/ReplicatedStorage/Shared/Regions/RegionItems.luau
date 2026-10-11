--!strict
-- RegionItems: the one rare find in each new region (Lane R). Pure. Each
-- sits at the region's UniqueItemSpawn anchor (WorldPlan.UniqueItemSpawns)
-- behind a ProximityPrompt. The rules here hold whatever the item turns out
-- to be: free (no Robux, no paid random item), found only in its region, one
-- pick per anchor per respawn, never twice in the same frame, and recorded as
-- one per-slot stamp in the existing save map `guideStamps` under the
-- "Region:" prefix (no new ProfileSchema field).
--
-- The Designer's items are not picked yet. Both ship as data with
-- `enabled = false` and the line "Something rare lives here", so the spawn,
-- prompt and save paths are built and tested; flipping `enabled` turns a find
-- on. (The Designer's Bayou item, the Wader Boots, is bought at the Bait
-- Shack, and Red Mesa's material is the quarry's sandstone slab: neither is
-- found at the anchor.)

local BayouData = require(script.Parent.BayouData)
local MesaData = require(script.Parent.MesaData)

local RegionItems = {}

RegionItems.Prefix = "Region:"
RegionItems.Reach = 12 -- studs from the anchor

export type Item = {
	id: string, -- save id
	region: string, -- BiomeData id
	anchorId: string, -- WorldPlan.UniqueItemSpawns id
	name: string,
	enabled: boolean,
	respawnSec: number, -- an anchor is empty this long after a pick (stamped players still see it dim)
	needsStage: number,
	signLine: string,
	spot: { x: number, z: number },
}

local items: { Item } = {
	{
		id = "BayouFind",
		region = "bayou",
		anchorId = "bayou",
		name = "Bayou Find",
		enabled = false,
		respawnSec = 600,
		needsStage = BayouData.NeedsStage,
		signLine = BayouData.RareLine,
		spot = BayouData.UniqueSpot,
	},
	{
		id = "MesaFind",
		region = "mesa",
		anchorId = "redmesa",
		name = "Mesa Find",
		enabled = false,
		respawnSec = 600,
		needsStage = MesaData.NeedsStage,
		signLine = MesaData.RareLine,
		spot = MesaData.UniqueSpot,
	},
}

local byId: { [string]: Item } = {}
local byAnchor: { [string]: Item } = {}
for _, item in ipairs(items) do
	byId[item.id] = item
	byAnchor[item.anchorId] = item
end

function RegionItems.All(): { Item }
	return items
end

function RegionItems.Get(id: string): Item?
	return byId[id]
end

function RegionItems.ForAnchor(anchorId: string): Item?
	return byAnchor[anchorId]
end

-- The guideStamps key for an item: one per slot.
function RegionItems.StampKey(itemId: string): string
	return RegionItems.Prefix .. "Found:" .. itemId
end

-- The key for having entered a region (the first-visit banner), per slot.
function RegionItems.SeenKey(regionId: string): string
	return RegionItems.Prefix .. "Seen:" .. regionId
end

function RegionItems.Has(stamps: unknown, itemId: string): boolean
	return type(stamps) == "table" and (stamps :: any)[RegionItems.StampKey(itemId)] == true
end

-- Anchor state: when each anchor is next live (clock seconds) and the claim
-- made this frame. The caller keeps one per server.
export type Anchors = {
	readyAt: { [string]: number },
	claimed: { [string]: number }, -- anchor id -> the frame token that took it
}

function RegionItems.NewAnchors(): Anchors
	return { readyAt = {}, claimed = {} }
end

function RegionItems.Live(anchors: Anchors, anchorId: string, now: number): boolean
	local at = anchors.readyAt[anchorId]
	return at == nil or now >= at
end

export type Facts = {
	region: string, -- the biome id the player stands in ("" for open country)
	distance: number, -- studs from the player to the anchor
	stage: number,
	hasIt: boolean, -- the slot already holds the stamp
	frame: number, -- a token that changes every frame (os.clock() will do)
}

export type Verdict = { ok: boolean, reason: string? }

-- May this player pick up this item now? A true answer also marks the anchor
-- taken, so a second call in the same frame (or before the respawn) says no.
function RegionItems.Pick(anchors: Anchors, item: Item, now: number, facts: Facts): Verdict
	if not item.enabled then
		return { ok = false, reason = item.signLine .. "." }
	end
	if facts.region ~= item.region then
		return { ok = false, reason = "This only turns up in its own region." }
	end
	if type(facts.distance) ~= "number" or facts.distance ~= facts.distance or facts.distance > RegionItems.Reach then
		return { ok = false, reason = "Step closer." }
	end
	if facts.stage < item.needsStage then
		return { ok = false, reason = "You are not ready for this yet." }
	end
	if facts.hasIt then
		return { ok = false, reason = "You already found this one." }
	end
	if anchors.claimed[item.anchorId] == facts.frame then
		return { ok = false, reason = "Someone just took it." }
	end
	if not RegionItems.Live(anchors, item.anchorId, now) then
		return { ok = false, reason = "It is gone for now. It comes back." }
	end
	anchors.claimed[item.anchorId] = facts.frame
	anchors.readyAt[item.anchorId] = now + item.respawnSec
	return { ok = true, reason = nil }
end

-- Writes the stamp. Idempotent: a second grant changes nothing.
function RegionItems.Stamp(stamps: { [string]: boolean }, itemId: string): boolean
	local key = RegionItems.StampKey(itemId)
	if stamps[key] == true then
		return false
	end
	stamps[key] = true
	return true
end

return RegionItems
