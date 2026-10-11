--!strict
-- HermitLogic: the Hermit's quest, as rules. Pure, so the server (HermitService)
-- and the specs share it.
--
-- Five carved marks hide in the five ground biomes. The server sets
-- secretsFound["mark_<id>"] from its own prompt after a distance check; the
-- client never sends a key. With all five set the player holds the Carved
-- Totem (secretsFound.CarvedTotem, decor only, never sold). Then the Hermit
-- gives the Hermit's Maul, once per save slot (profile.questAxe.step 2).
--
--   questAxe.step  0 not met   1 met, still looking   2 Maul given

local GameConfig = require(script.Parent.GameConfig)
local WorldLayout = require(script.Parent.World.WorldLayout)

local HermitLogic = {}

export type Mark = { key: string, x: number, z: number, label: string }

HermitLogic.MarkRadius = 10 -- studs the server accepts a mark press from
HermitLogic.TotemKey = "CarvedTotem"
HermitLogic.CaveBoxKey = "secretCaveBox"

-- Positions from docs/WORLD_DESIGN.md §7. The cave box sits inside the room
-- (the design's (-770, -680) is outside the cave's open face).
HermitLogic.Marks = {
	{ key = "mark_starter", x = 24, z = -150, label = "Starter Forest" },
	{ key = "mark_hills", x = -420, z = 260, label = "the Old Ranger Cabin" },
	-- Ring map (MAP_V1.md): the snow peak, the volcano shelf west of the cone
	-- and the cliff by the secret cave moved with their regions.
	{ key = "mark_snow", x = -40, z = 760, label = "the Snowfields" },
	{ key = "mark_volcano", x = 400, z = 460, label = "the Volcano shelf" },
	{
		key = "mark_grove",
		x = WorldLayout.SecretCaveX - 15,
		z = WorldLayout.SecretCaveZ - 15,
		label = "the cave cliff",
	},
} :: { Mark }

HermitLogic.CaveBox = { key = "secretCaveBox", x = WorldLayout.SecretCaveX - 10, z = WorldLayout.SecretCaveZ }

-- Where the Hermit stands: inside the room, off the Lantern, facing the mouth.
HermitLogic.Stand = { x = WorldLayout.SecretCaveX + 10, z = WorldLayout.SecretCaveZ + 3 }
HermitLogic.TalkSlack = 6 -- studs past the prompt's reach the server still allows

function HermitLogic.MarkCount(secrets: { [string]: boolean }?): number
	local n = 0
	if type(secrets) ~= "table" then
		return 0
	end
	for _, mark in ipairs(HermitLogic.Marks) do
		if secrets[mark.key] == true then
			n += 1
		end
	end
	return n
end

function HermitLogic.HasAllMarks(secrets: { [string]: boolean }?): boolean
	return HermitLogic.MarkCount(secrets) >= GameConfig.CarvedMarkCount
end

function HermitLogic.HasTotem(secrets: { [string]: boolean }?): boolean
	return type(secrets) == "table" and secrets[HermitLogic.TotemKey] == true
end

-- The mark whose key is `key`, or nil (a client can't invent one).
function HermitLogic.MarkByKey(key: unknown): Mark?
	for _, mark in ipairs(HermitLogic.Marks) do
		if mark.key == key then
			return mark
		end
	end
	return nil
end

function HermitLogic.Near(px: number, pz: number, x: number, z: number, radius: number): boolean
	local dx, dz = px - x, pz - z
	return dx * dx + dz * dz <= radius * radius
end

export type Stage = "intro" | "seeking" | "ready" | "done"

-- Which line the Hermit speaks. `step` is profile.questAxe.step.
function HermitLogic.StageOf(secrets: { [string]: boolean }?, step: number): Stage
	if step >= 2 then
		return "done"
	end
	if HermitLogic.HasAllMarks(secrets) then
		return "ready"
	end
	if step >= 1 or HermitLogic.MarkCount(secrets) > 0 then
		return "seeking"
	end
	return "intro"
end

-- The quest step after talking at `stage` (never goes backwards).
function HermitLogic.StepAfter(stage: Stage, step: number): number
	if stage == "ready" or stage == "done" then
		return math.max(step, 2)
	end
	return math.max(step, 1)
end

return HermitLogic
