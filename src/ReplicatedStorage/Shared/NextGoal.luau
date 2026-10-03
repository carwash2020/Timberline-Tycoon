--!strict
-- NextGoal: the one objective the tracker shows once Murph's tutorial is
-- over. In order: the next axe on the ladder, else a Field Guide wood that
-- still reads "???", else day 1 of the daily streak (and the streak itself
-- after that day). Always exactly one, so the tracker never goes blank.

local FieldGuide = require(script.Parent.FieldGuide)
local ItemCatalog = require(script.Parent.ItemCatalog)
local ShopLogic = require(script.Parent.ShopLogic)
local WoodData = require(script.Parent.WoodData)

local NextGoal = {}

export type Goal = {
	kind: "axe" | "wood" | "streak",
	text: string,
	beacon: string?, -- a QuestUI beacon name, when pointing helps
}

-- `found` is profile.compendium (wood id -> true). `streak` is
-- profile.daily.streak (0 until the first day is finished).
function NextGoal.Pick(loop: number, bestAxeTier: number, found: { [string]: boolean }, streak: number): Goal
	local ladder = ItemCatalog.AxeLadder()
	local tier = math.max(0, math.floor(bestAxeTier))
	local nextAxe = ladder[tier + 1]
	if nextAxe then
		local price = ShopLogic.Price(nextAxe, loop)
		if price > 0 then
			return {
				kind = "axe",
				text = string.format("Buy the %s (%s)", nextAxe.displayName, FieldGuide.CashText(price)),
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

return NextGoal
