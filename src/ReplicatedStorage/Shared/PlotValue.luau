--!strict
-- PlotValue: what the lane sign and the plot card say about a homestead.
-- Display only. The grade is the haul to the sawmill plus how many named
-- places sit nearby. No price.

local WorldLayout = require(script.Parent.World.WorldLayout)
local PlotData = require(script.Parent.PlotData)

local PlotValue = {}

export type Poi = { name: string, studs: number }
export type Value = { pois: { Poi }, perk: string, grade: "A" | "B" | "C" }

local PLACES = {
	{ name = "Sawmill", x = 0, z = 110 },
	{ name = "Pond", x = -40, z = -160 },
	{ name = "Lake", x = -700, z = 180 },
	{ name = "Mine", x = 150, z = -150 },
	{ name = "Dock", x = 860, z = 160 },
	{ name = "Ravine", x = 10, z = -720 },
	{ name = "Peak", x = 0, z = 720 },
	{ name = "Volcano", x = 450, z = 500 },
}

local function haul(home: PlotData.Home): number
	local saw = WorldLayout.Sawmill
	return math.sqrt((home.x - saw.X) ^ 2 + (home.z - saw.Z) ^ 2)
end

function PlotValue.For(home: PlotData.Home): Value
	local list: { Poi } = {}
	for _, place in ipairs(PLACES) do
		if place.name ~= "Sawmill" then
			local studs = math.sqrt((home.x - place.x) ^ 2 + (home.z - place.z) ^ 2)
			table.insert(list, { name = place.name, studs = studs })
		end
	end
	table.sort(list, function(a, b)
		return a.studs < b.studs
	end)
	local nearest = { list[1], list[2] }
	local h = haul(home)
	local grade: "A" | "B" | "C" = if h < 450 then "A" elseif h < 750 then "B" else "C"
	local perk = string.format("%s is %d studs off", nearest[1].name, math.floor(nearest[1].studs + 0.5))
	return { pois = nearest, perk = perk, grade = grade }
end

return PlotValue
