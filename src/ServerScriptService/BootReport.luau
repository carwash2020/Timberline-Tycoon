--!strict
-- BootReport: GameServer's one-line "the server is up" report (PLAY-01),
-- from the build stats MapBuilder leaves on workspace (MapBuildSeconds,
-- MapTerrainSeconds, MapTrees, MapBuildFailures). Pure: give it anything
-- with GetAttribute. A missing stat shows as "?", never an error.

local BootReport = {}

local function seconds(value: any): string
	return if type(value) == "number" then string.format("%.1fs", value) else "?s"
end

local function count(value: any, one: string, many: string): string
	if type(value) ~= "number" then
		return "? " .. many
	end
	return string.format("%d %s", value, if value == 1 then one else many)
end

-- e.g. "[GameServer] Online: world built in 12.4s (terrain 9.8s), 334 trees, 1 player"
function BootReport.Line(world: any, players: number): string
	local function stat(name: string): any
		local ok, value = pcall(function(): any
			return world:GetAttribute(name)
		end)
		return if ok then value else nil
	end
	local line = string.format(
		"[GameServer] Online: world built in %s (terrain %s), %s, %s",
		seconds(stat("MapBuildSeconds")),
		seconds(stat("MapTerrainSeconds")),
		count(stat("MapTrees"), "tree", "trees"),
		count(players, "player", "players")
	)
	local failures = stat("MapBuildFailures")
	if type(failures) == "number" and failures > 0 then
		line ..= string.format(
			", %s failed (see the [MapBuilder] warnings)",
			count(failures, "build step", "build steps")
		)
	end
	return line
end

return BootReport
