--!nocheck
-- Chop feel table: for every axe against every wood's thickest section (the
-- trunk's base, wood.v2.shape.trunkThickness, as ECONOMY.md "Hits to cut a
-- mature trunk at its base"), the hits (SectionLogic.HitsToCut) and the
-- seconds of swinging (SectionLogic.CutSeconds with the axe's cooldown for
-- that wood). The pairs a player is meant to meet (ECONOMY.md's buying path,
-- "Then cuts") are flagged when they take fewer than 3 or more than 12 hits,
-- or over 10 seconds. Prints only: it changes no value and fails nothing.
--
-- Run from the repo root:   lune run tools/chop_feel
-- Woods and axes that are not on main yet (Cherry, Willow) join the table
-- when they land; add their pairs to INTENDED then.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

assert(fs.isFile("rokit.toml"), "Run this from the repo root: lune run tools/chop_feel")

local Loader = luau.load(fs.readFile("tools/loader.luau"), { debugName = "tools/loader.luau" })()
local modules = Loader.new()
local WoodData = modules:shared("WoodData")
local ItemCatalog = modules:shared("ItemCatalog")
local SectionLogic = modules:shared("SectionLogic")

local MIN_HITS, MAX_HITS, MAX_SECONDS = 3, 12, 10

-- The intended pairs: ECONOMY.md's buying path, "Then cuts" column (axe, wood).
-- No tier-to-wood table exists in code; the Designer confirms this list.
local INTENDED = {
	{ "RustyAxe", "maple" },
	{ "SteelAxe", "maple" },
	{ "SteelAxe", "bogcypress" },
	{ "SteelAxe", "frostwood" },
	{ "HardenedAxe", "frostwood" },
	{ "SilverAxe", "frostwood" },
	{ "SilverAxe", "emberwood" },
	{ "CobaltAxe", "emberwood" },
	{ "GoldAxe", "emberwood" },
	{ "GoldAxe", "frostwood" },
	{ "ObsidianAxe", "frostwood" },
	{ "InfernoAxe", "frostwood" },
}
local intended = {}
for _, pair in ipairs(INTENDED) do
	intended[pair[1] .. "/" .. pair[2]] = true
end

local flagged = 0
print(string.format("%-14s %-12s %6s %7s  %s", "axe", "wood", "hits", "secs", "note"))
for _, axe in ipairs(ItemCatalog.AxeLadder()) do
	for _, wood in ipairs(WoodData.All()) do
		if wood.v2 then
			local damage, cooldown = ItemCatalog.AxeStats(axe, wood.id)
			local hits = SectionLogic.HitsToCut(wood.v2.hardness, wood.v2.shape.trunkThickness, damage or 0)
			local secs = SectionLogic.CutSeconds(hits, cooldown or 1)
			local note = ""
			if intended[axe.id .. "/" .. wood.id] then
				if hits < MIN_HITS or hits > MAX_HITS or secs > MAX_SECONDS then
					note = "FLAG (intended pair outside 3-12 hits / 10 s)"
					flagged += 1
				else
					note = "intended, ok"
				end
			end
			if note ~= "" then
				print(string.format("%-14s %-12s %6s %7.1f  %s", axe.id, wood.id, tostring(hits), secs, note))
			end
		end
	end
end
print(string.format("%d intended pair(s) flagged", flagged))
