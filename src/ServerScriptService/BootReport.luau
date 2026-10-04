--!strict
-- BootReport: GameServer's one-line "the server is up" report (PLAY-01),
-- from the build stats MapBuilder leaves on workspace (MapBuildSeconds,
-- MapTerrainSeconds, MapTrees, MapBuildFailures). Pure: give it anything
-- with GetAttribute. A missing stat shows as "?", never an error.
--
-- The same three timings also go out as AnalyticsService custom events
-- (Events / Log), so Creator Hub shows real server load times. The print
-- stays. LogCustomEvent needs a player, so Log sends them once, on the
-- first player it's given, and returns false when there isn't one yet.

local BootReport = {}

export type Event = { name: string, value: number }

-- Attribute on the world -> custom event name in Creator Hub.
local EVENT_NAMES = {
	{ attribute = "MapBuildSeconds", name = "ServerWorldBuildSeconds" },
	{ attribute = "MapTerrainSeconds", name = "ServerTerrainBuildSeconds" },
	{ attribute = "MapBuildFailures", name = "ServerWorldBuildFailures" },
}

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

local function stat(world: any, name: string): any
	local ok, value = pcall(function(): any
		return world:GetAttribute(name)
	end)
	return if ok then value else nil
end

-- The custom events for this boot. A stat that isn't a number is left out
-- (the printed line shows "?" instead). Zero failures are included, so a
-- clean boot shows up as 0.
function BootReport.Events(world: any): { Event }
	local out: { Event } = {}
	for _, item in ipairs(EVENT_NAMES) do
		local value = stat(world, item.attribute)
		if type(value) == "number" then
			table.insert(out, { name = item.name, value = value })
		end
	end
	return out
end

-- Sends Events for `players[1]`. False when there's nobody to attach them
-- to (the caller tries again when someone joins). Analytics never throws
-- out of here.
function BootReport.Log(world: any, players: { any }, analytics: any): boolean
	local player = players[1]
	if player == nil then
		return false
	end
	for _, event in ipairs(BootReport.Events(world)) do
		pcall(function(): any
			analytics:LogCustomEvent(player, event.name, event.value)
			return nil
		end)
	end
	return true
end

export type StubStart = {
	name: string,
	init: () -> (),
}

-- One line when a reserved service throws during boot. GameServer prints
-- these and keeps starting the rest.
function BootReport.StubWarning(name: string, err: any): string
	return string.format("[BootReport] %s failed to start: %s", name, tostring(err))
end

-- Runs each stub's init inside its own pcall. A throw is warned and the
-- later stubs still start. Returns the warning lines, in order.
function BootReport.StartStubs(stubs: { StubStart }): { string }
	local warnings: { string } = {}
	for _, stub in ipairs(stubs) do
		local ok, err = pcall(function(): any
			stub.init()
			return nil
		end)
		if not ok then
			local line = BootReport.StubWarning(stub.name, err)
			table.insert(warnings, line)
			warn(line)
		end
	end
	return warnings
end

return BootReport
