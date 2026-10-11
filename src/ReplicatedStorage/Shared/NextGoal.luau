--!strict
-- NextGoal: the one objective the tracker shows once Murph's tutorial is
-- over. In order: the next axe on the ladder, else a Field Guide wood that
-- still reads "???", else day 1 of the daily streak (and the streak itself
-- after that day). Always exactly one, so the tracker never goes blank.

local FieldGuide = require(script.Parent.FieldGuide)
local ItemCatalog = require(script.Parent.ItemCatalog)
local ShopHoursLogic = require(script.Parent.ShopHoursLogic)
local ShopLogic = require(script.Parent.ShopLogic)
local WoodData = require(script.Parent.WoodData)

local NextGoal = {}

-- The goal line under the cash is at most this many characters.
NextGoal.MaxChars = 40

export type Goal = {
	kind: "axe" | "wood" | "streak" | "gear" | "charter" | "relic" | "plot",
	text: string,
	beacon: string?, -- a QuestUI beacon name, when pointing helps
}

-- " - the shed opens at 6 AM" while the shop is shut, else nothing.
function NextGoal.ClosedNote(shopId: string, hour: number?): string
	if hour == nil or ShopHoursLogic.IsOpen(shopId, hour) then
		return ""
	end
	return string.format(" - opens at %s", ShopHoursLogic.FormatHour(ShopHoursLogic.NextOpen(shopId, hour)))
end

-- `found` is profile.compendium (wood id -> true). `streak` is
-- profile.daily.streak (0 until the first day is finished). `hour` (the game
-- clock, optional) lets the axe goal say when the Tool Shed opens while it is
-- shut at night.
function NextGoal.Pick(
	loop: number,
	bestAxeTier: number,
	found: { [string]: boolean },
	streak: number,
	hour: number?
): Goal
	local ladder = ItemCatalog.AxeLadder()
	local tier = math.max(0, math.floor(bestAxeTier))
	local nextAxe = ladder[tier + 1]
	if nextAxe then
		local price = ShopLogic.Price(nextAxe, loop)
		if price > 0 then
			return {
				kind = "axe",
				text = string.format("Buy the %s (%s)", nextAxe.displayName, FieldGuide.CashText(price))
					.. NextGoal.ClosedNote("ToolShed", hour),
				beacon = "toolShed",
			}
		end
		return {
			kind = "axe",
			text = "Forge the " .. nextAxe.displayName,
			beacon = nil,
		}
	end
	for _, wood in ipairs(WoodData.All()) do
		if not found[wood.id] then
			return {
				kind = "wood",
				text = string.format("Fell a ??? wood · %s", FieldGuide.Hint(wood)),
				beacon = nil,
			}
		end
	end
	local days = math.max(0, math.floor(streak))
	if days < 1 then
		return { kind = "streak", text = "Finish day 1 of your daily streak", beacon = nil }
	end
	return {
		kind = "streak",
		text = string.format("Daily streak: day %d", days),
		beacon = nil,
	}
end

---------------------------------------------------------------------------
-- The V1 ladder (S1 to S8): the next unmet milestone, one line.
--   S1 Steel Axe, S2 the Hills, S3 the Coat then the Snow, S4 the Boots then
--   the Volcano, S5 the Lantern then the Gloam at night, S6 the Obsidian Axe
--   then Gus's Charter, S7 the Gondola Pass, the Starfall Axe and the relics,
--   S8 the full plot. Axe rungs sit between, so each biome is reachable with
--   an axe that fells its wood. After S8, the Field Guide and the streak
--   (the old Pick).
---------------------------------------------------------------------------

export type Facts = {
	loop: number,
	bestAxeTier: number,
	gear: { [string]: boolean }, -- owned gear ids
	found: { [string]: boolean }, -- profile.compendium
	streak: number,
	hour: number?,
	night: boolean?,
	charterDone: boolean, -- the Gondola Pass is earned (SkyQuest done)
	relicsDone: boolean, -- every relic claimed
	plotFull: boolean, -- the plot is at its top tier
}

-- The axe rung each gated biome's wood needs (ItemCatalog.AxeTier order).
local SNOW_TIER, VOLCANO_TIER, OBSIDIAN_TIER, STARFALL_TIER = 4, 6, 7, 9

local function biomeFound(found: { [string]: boolean }, biome: string): boolean
	for _, wood in ipairs(WoodData.All()) do
		if wood.biome == biome and found[wood.id] then
			return true
		end
	end
	return false
end

local function fit(goal: Goal): Goal
	if #goal.text > NextGoal.MaxChars then
		-- Drop a trailing " - opens at ..." note before cutting the words.
		local cut = string.find(goal.text, " - ", 1, true)
		if cut then
			goal.text = string.sub(goal.text, 1, cut - 1)
		end
		if #goal.text > NextGoal.MaxChars then
			goal.text = string.sub(goal.text, 1, NextGoal.MaxChars - 3) .. "..."
		end
	end
	return goal
end

local function axeGoal(facts: Facts, tier: number): Goal?
	if facts.bestAxeTier >= tier then
		return nil
	end
	local axe = ItemCatalog.AxeLadder()[facts.bestAxeTier + 1]
	if axe == nil then
		return nil
	end
	return NextGoal.Pick(facts.loop, facts.bestAxeTier, {}, 0, facts.hour)
end

-- `facts` is read from the save by QuestService. Always one goal under 40 characters.
function NextGoal.PickV1(facts: Facts): Goal
	local function gear(id: string): boolean
		return facts.gear[id] == true
	end
	local function done(g: Goal?): Goal?
		return if g then fit(g) else nil
	end
	local steel = done(axeGoal(facts, 2))
	if steel then
		return steel
	end
	if not biomeFound(facts.found, "hills") then
		return { kind = "wood", text = "Fell a tree in the Hills", beacon = nil }
	end
	if not gear("InsulatedCoat") then
		return { kind = "gear", text = "Buy the Insulated Coat", beacon = nil }
	end
	local silver = done(axeGoal(facts, SNOW_TIER))
	if silver then
		return silver
	end
	if not biomeFound(facts.found, "snow") then
		return { kind = "wood", text = "Fell Frostwood in the Snow", beacon = nil }
	end
	if not gear("HeatBoots") then
		return { kind = "gear", text = "Buy the Heat Boots", beacon = nil }
	end
	local gold = done(axeGoal(facts, VOLCANO_TIER))
	if gold then
		return gold
	end
	if not biomeFound(facts.found, "volcano") then
		return { kind = "wood", text = "Fell Emberwood on the Volcano", beacon = nil }
	end
	if not gear("Lantern") then
		return { kind = "gear", text = "Buy a Lantern", beacon = nil }
	end
	if not biomeFound(facts.found, "grove") then
		return {
			kind = "wood",
			text = if facts.night then "Fell Gloamwood in the Hollow" else "Wait for night, then Gloam Hollow",
			beacon = nil,
		}
	end
	local obsidian = done(axeGoal(facts, OBSIDIAN_TIER))
	if obsidian then
		return obsidian
	end
	if not facts.charterDone then
		return { kind = "charter", text = "Finish Gus's Charter", beacon = "gus" }
	end
	if facts.bestAxeTier < STARFALL_TIER then
		return { kind = "axe", text = "Forge the Starfall Axe", beacon = nil }
	end
	if not facts.relicsDone then
		return { kind = "relic", text = "Forge the relics up in the sky", beacon = nil }
	end
	if not facts.plotFull then
		return { kind = "plot", text = "Grow your plot to full size", beacon = "landOffice" }
	end
	return fit(NextGoal.Pick(facts.loop, facts.bestAxeTier, facts.found, facts.streak, facts.hour))
end

return NextGoal
