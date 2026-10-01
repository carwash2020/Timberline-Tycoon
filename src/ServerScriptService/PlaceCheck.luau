--!strict
-- PlaceCheck: does the live place match default.project.json? (PLAY-02)
-- `rojo serve` doesn't sync place settings, and Max Players and Studio API
-- access are set by hand, so the place being tested (or the one players
-- get) can drift. GameServer runs this once at boot:
--   * one warning per setting that differs, naming the fix;
--   * "can't check X from a script" (a print, never an error) for a
--     setting Roblox doesn't let scripts read;
--   * in Studio, a warning when DataStore API access is off: ProfileStore
--     then saves to an in-memory mock, so nothing persists between tests.
--     (It reads ProfileStore.DataStoreState, ProfileStore's own probe. It
--     never touches a DataStore itself.)
--   * "[PlaceCheck] OK" when everything it can read matches.
-- The expected values are data (PlaceCheck.Expected): a new or changed
-- setting is one line there (tests/PlaceCheck.spec checks them against
-- default.project.json).

local RunService = game:GetService("RunService")

local ProfileStore = require(script.Parent.Vendor.ProfileStore)

local PlaceCheck = {}

export type Expectation = {
	service: string, -- "Workspace", "Terrain" (workspace.Terrain), "Lighting" or "Players"
	property: string,
	value: any, -- the expected value
	atMost: boolean?, -- numbers: anything up to `value` passes
	fix: string?, -- how to fix it; nil: set it in Studio or publish a fresh build.rbxlx
}

export type Result = {
	setting: string, -- e.g. "Workspace.StreamingEnabled"
	status: "ok" | "mismatch" | "unreadable",
	actual: any,
	expectation: Expectation,
}

export type Report = {
	warnings: { string },
	notes: { string },
	ok: boolean,
}

-- default.project.json's values (and Max Players from the launch plan).
PlaceCheck.Expected = {
	{ service = "Workspace", property = "StreamingEnabled", value = true },
	{ service = "Workspace", property = "StreamingTargetRadius", value = 1024 },
	{
		service = "Workspace",
		property = "StreamingIntegrityMode",
		value = Enum.StreamingIntegrityMode.PauseOutsideLoadedArea,
	},
	{ service = "Lighting", property = "LightingStyle", value = Enum.LightingStyle.Realistic },
	{ service = "Terrain", property = "Decoration", value = true },
	{
		service = "Players",
		property = "MaxPlayers",
		value = 12,
		atMost = true,
		fix = "Game Settings > Places > Max Players = 12",
	},
} :: { Expectation }

-- How long to wait in Studio for ProfileStore's API access probe.
PlaceCheck.DataStoreWait = 15

local DATASTORE_FIX = "Game Settings > Security > Enable Studio Access to API Services = on"
	.. " (a place that was never published has no DataStores: File > Publish to Roblox first)"

function PlaceCheck.Setting(e: Expectation): string
	return (if e.service == "Terrain" then "Workspace.Terrain" else e.service) .. "." .. e.property
end

-- A value as the Properties panel shows it: true, 1024, Realistic.
function PlaceCheck.Show(value: any): string
	if typeof(value) == "EnumItem" then
		return (value :: EnumItem).Name
	end
	return tostring(value)
end

function PlaceCheck.Matches(e: Expectation, actual: any): boolean
	if e.atMost then
		return type(actual) == "number" and actual <= e.value
	end
	return actual == e.value
end

-- Reads every expected setting from `instances` (keyed by Expectation.service)
-- and compares it. A read that errors, or a missing instance, is "unreadable".
function PlaceCheck.Compare(instances: { [string]: any }, expected: { Expectation }?): { Result }
	local results: { Result } = {}
	for _, e in ipairs(expected or PlaceCheck.Expected) do
		local ok, actual = pcall(function(): any
			return (instances[e.service] :: any)[e.property]
		end)
		local status: "ok" | "mismatch" | "unreadable" = if not ok or actual == nil
			then "unreadable"
			elseif PlaceCheck.Matches(e, actual) then "ok"
			else "mismatch"
		table.insert(results, {
			setting = PlaceCheck.Setting(e),
			status = status,
			actual = if ok then actual else nil,
			expectation = e,
		})
	end
	return results
end

local function wanted(e: Expectation): string
	return PlaceCheck.Show(e.value) .. (if e.atMost then " or fewer" else "")
end

local function fixFor(result: Result): string
	local e = result.expectation
	if e.fix then
		return e.fix
	end
	return string.format(
		"set %s = %s in Studio's Properties panel (in Edit mode, then File > Publish to Roblox),"
			.. " or publish a fresh build.rbxlx (rojo build -o build.rbxlx, open it, File > Publish to Roblox)",
		result.setting,
		PlaceCheck.Show(e.value)
	)
end

-- The lines to print and warn. dataStoreState is ProfileStore's
-- DataStoreState in Studio, nil outside it (no check).
function PlaceCheck.Report(results: { Result }, dataStoreState: string?): Report
	local warnings: { string } = {}
	local notes: { string } = {}
	local unreadable: { string } = {}
	for _, result in ipairs(results) do
		if result.status == "mismatch" then
			table.insert(
				warnings,
				string.format(
					"[PlaceCheck] %s is %s, expected %s. Fix: %s.",
					result.setting,
					PlaceCheck.Show(result.actual),
					wanted(result.expectation),
					fixFor(result)
				)
			)
		elseif result.status == "unreadable" then
			table.insert(unreadable, result.setting .. " = " .. wanted(result.expectation))
		end
	end
	if #unreadable > 0 then
		table.insert(
			notes,
			string.format(
				"[PlaceCheck] can't check %s from a script: look in Studio's Properties panel.",
				table.concat(unreadable, ", ")
			)
		)
	end
	if dataStoreState == "NoAccess" then
		table.insert(
			warnings,
			"[PlaceCheck] Studio has no DataStore access, so saves won't persist between tests. Fix: "
				.. DATASTORE_FIX
				.. "."
		)
	elseif dataStoreState == "NoInternet" then
		table.insert(
			warnings,
			"[PlaceCheck] Studio can't reach Roblox (no internet), so saves won't persist between tests."
				.. " Fix: check the connection, then Play again."
		)
	elseif dataStoreState ~= nil and dataStoreState ~= "Access" then
		table.insert(
			notes,
			"[PlaceCheck] can't tell yet whether Studio has DataStore access. If saves reset between tests: "
				.. DATASTORE_FIX
				.. "."
		)
	end
	return { warnings = warnings, notes = notes, ok = #warnings == 0 }
end

-- ProfileStore's probe in Studio is a DataStore write; wait for its answer.
local function dataStoreState(): string
	local deadline = os.clock() + PlaceCheck.DataStoreWait
	while ProfileStore.DataStoreState == "NotReady" and os.clock() < deadline do
		task.wait(0.25)
	end
	return ProfileStore.DataStoreState
end

-- Checks the running place and logs the result. Yields in Studio (up to
-- DataStoreWait seconds), so call it in its own thread. Returns whether
-- everything matched.
function PlaceCheck.Run(): boolean
	local workspaceService = game:GetService("Workspace")
	local instances: { [string]: any } = {
		Workspace = workspaceService,
		Lighting = game:GetService("Lighting"),
		Players = game:GetService("Players"),
	}
	pcall(function(): any
		instances.Terrain = workspaceService.Terrain
		return nil
	end)
	local results = PlaceCheck.Compare(instances)
	local report = PlaceCheck.Report(results, if RunService:IsStudio() then dataStoreState() else nil)
	for _, line in ipairs(report.notes) do
		print(line)
	end
	for _, line in ipairs(report.warnings) do
		warn(line)
	end
	if report.ok then
		print("[PlaceCheck] OK")
	end
	return report.ok
end

return PlaceCheck
