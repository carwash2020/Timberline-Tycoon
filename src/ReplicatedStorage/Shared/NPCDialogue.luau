--!strict
-- NPCDialogue: which line a townsfolk says when you talk to them, and how
-- big their name tag is. Pure, so the client (NPCController) and the tests
-- share it. The client reads the clock, the weather, and the player's
-- attributes and passes them in. There are no floating speech bubbles: every
-- line goes through the dialogue box (DialogueFlow, DialogueUI).

local ItemCatalog = require(script.Parent.ItemCatalog)
local NPCData = require(script.Parent.NPCData)
local TutorialData = require(script.Parent.TutorialData)

local NPCDialogue = {}

-- Phone role line, in pixels. Meets the 14 px tag minimum.
NPCDialogue.PhoneTagRole = 14
-- Keeper role line on a TV. The desktop tag stays at 14.
NPCDialogue.TvTagRole = 18
NPCDialogue.MaxLine = 110 -- the longest a general line may be (the box pages anything longer)
NPCDialogue.ReactMax = 90 -- contextual lines and onboarding tips
NPCDialogue.PromptCooldown = 1 -- seconds after a talk ends before the next Talk opens (the box needs a press to go, so it cannot be spammed)
-- When the weather, the hour, or the player's progress has something to
-- say, how often that wins over a general line.
NPCDialogue.ContextChance = 0.62

export type Band = "morning" | "day" | "evening" | "night"

export type Progress = {
	loaded: boolean,
	sold: boolean,
	upgradedAxe: boolean,
	sawmill: boolean,
}

export type Context = {
	band: Band,
	weather: string,
	progress: Progress,
}

export type Pool = {
	kind: string,
	lines: { string },
}

export type Layout = {
	phone: boolean,
	tagDistance: number,
	tagSize: Vector2,
	tagName: number,
	tagRole: number,
}

-- 5-11 morning, 11-17 day, 17-19 evening, else night (GameConfig's night
-- is 19:00-05:00). `hour` is a ClockTime, 0 to 24.
function NPCDialogue.BandOf(hour: number): Band
	local h = hour % 24
	if h >= 5 and h < 11 then
		return "morning"
	elseif h >= 11 and h < 17 then
		return "day"
	elseif h >= 17 and h < 19 then
		return "evening"
	end
	return "night"
end

-- The workspace Weather attribute, or a biome's rename of it. Clear and
-- cloudy don't get their own lines.
function NPCDialogue.WeatherKey(kind: string): string?
	if kind == "Rain" or kind == "Snow" then
		return "rain"
	elseif kind == "Storm" or kind == "Blizzard" or kind == "Ashfall" then
		return "storm"
	elseif kind == "Fog" then
		return "fog"
	end
	return nil
end

local function num(value: unknown, fallback: number): number
	if type(value) == "number" and value == value then
		return value
	end
	return fallback
end

-- What the client can see of the save (Player attributes, plus whether a
-- sawmill model is sitting on their plot). Unknown until ProfileLoaded:
-- no progress lines, so a veteran doesn't get a new-player line in the
-- moment before the save arrives.
function NPCDialogue.ProgressOf(attrs: {
	loaded: unknown,
	tutorialStep: unknown,
	tutorialRefresher: unknown,
	bestAxeTier: unknown,
	sawmillStock: unknown,
	placedSawmill: boolean?,
}): Progress
	if attrs.loaded ~= true then
		return {
			loaded = false,
			sold = false,
			upgradedAxe = false,
			sawmill = false,
		}
	end
	local step = num(attrs.tutorialStep, 1)
	local refresher = attrs.tutorialRefresher == true
	local tier = num(attrs.bestAxeTier, 1)
	-- A sawmill waiting in stock (the chop saw shares the list and is not one).
	local stocked = false
	if type(attrs.sawmillStock) == "string" then
		for id in string.gmatch(attrs.sawmillStock, "[^,]+") do
			if ItemCatalog.GetSawmill(id) then
				stocked = true
				break
			end
		end
	end
	return {
		loaded = true,
		-- The first sale is the sell step. Finishing it advances past RefresherLast.
		sold = step == 0 or step > TutorialData.RefresherLast or refresher,
		upgradedAxe = tier >= 2,
		sawmill = stocked or attrs.placedSawmill == true,
	}
end

local function linesOf(react: NPCData.React?, key: string): { string }?
	if not react then
		return nil
	end
	local lines: { string }? = nil
	if key == "morning" then
		lines = react.morning
	elseif key == "day" then
		lines = react.day
	elseif key == "evening" then
		lines = react.evening
	elseif key == "night" then
		lines = react.night
	elseif key == "rain" then
		lines = react.rain
	elseif key == "storm" then
		lines = react.storm
	elseif key == "fog" then
		lines = react.fog
	elseif key == "rusty" then
		lines = react.rusty
	elseif key == "axe" then
		lines = react.axe
	elseif key == "unsold" then
		lines = react.unsold
	elseif key == "sale" then
		lines = react.sale
	elseif key == "sawmill" then
		lines = react.sawmill
	end
	if lines and #lines > 0 then
		return lines
	end
	return nil
end

-- The pool to draw from. A low `roll` (0..1) prefers progress, then weather,
-- then the hour, and a high roll is a general line.
function NPCDialogue.PoolFor(npc: NPCData.NPC, ctx: Context, roll: number): Pool
	local general: Pool = { kind = "line", lines = npc.lines }
	if not ctx.progress.loaded then
		return general
	end
	if roll >= NPCDialogue.ContextChance then
		return general
	end
	local keys: { string } = {}
	local progress = ctx.progress
	if progress.sawmill then
		table.insert(keys, "sawmill")
	end
	if not progress.sold then
		table.insert(keys, "unsold")
	end
	table.insert(keys, if progress.upgradedAxe then "axe" else "rusty")
	if progress.sold then
		table.insert(keys, "sale")
	end
	for _, key in ipairs(keys) do
		local lines = linesOf(npc.react, key)
		if lines then
			return { kind = key, lines = lines }
		end
	end
	local weatherKey = NPCDialogue.WeatherKey(ctx.weather)
	local weather = if weatherKey then linesOf(npc.react, weatherKey) else nil
	if weather and weatherKey then
		return { kind = weatherKey, lines = weather }
	end
	local timed = linesOf(npc.react, ctx.band)
	if timed then
		return { kind = ctx.band, lines = timed }
	end
	return general
end

-- The next line of a pool, in a shuffled order that doesn't repeat until
-- every line has been said. A bag left over from a different pool (an
-- index that doesn't fit) is reshuffled.
function NPCDialogue.Draw(lines: { string }, bag: { number }, rng: Random): (string?, { number })
	if #lines == 0 then
		return nil, bag
	end
	local fit = #bag > 0
	if fit then
		for _, i in ipairs(bag) do
			if type(i) ~= "number" or i < 1 or i > #lines then
				fit = false
				break
			end
		end
	end
	if not fit then
		bag = {}
		for i = 1, #lines do
			table.insert(bag, rng:NextInteger(1, #bag + 1), i)
		end
	end
	local index = table.remove(bag)
	if not index then
		return nil, bag
	end
	return lines[index], bag
end

-- A phone is a touch screen with no keyboard and a narrow viewport. The
-- same rule the name tags use (a wide tablet keeps the
-- desktop sizes).
function NPCDialogue.IsPhone(touch: boolean, keyboard: boolean, viewportX: number): boolean
	return touch and not keyboard and viewportX < 900
end

-- Phone: a small tag and a short draw distance so three NPCs don't fill the
-- screen. Desktop tags stay the size CharacterArt builds.
function NPCDialogue.LayoutFor(phone: boolean, tenFoot: boolean?): Layout
	if phone then
		return {
			phone = true,
			tagDistance = 40,
			tagSize = Vector2.new(160, 38),
			tagName = 18,
			tagRole = NPCDialogue.PhoneTagRole,
		}
	end
	return {
		phone = false,
		tagDistance = 60,
		tagSize = Vector2.new(220, 50),
		tagName = 24,
		tagRole = if tenFoot then NPCDialogue.TvTagRole else 14,
	}
end

return NPCDialogue
