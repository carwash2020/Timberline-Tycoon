--!nocheck
-- PlaceCheck (PLAY-02): the boot check that the live place matches
-- default.project.json, run here with stubbed services.
return function(t)
	local Enum = t.roblox.Enum

	-- Roblox errors when a script reads a property it may not (as it does
	-- for some streaming settings): a stub that does the same.
	local function service(props, unreadable)
		return setmetatable({}, {
			__index = function(_, key)
				if unreadable and unreadable[key] then
					error(key .. " is not a valid member of " .. tostring(props.ClassName or "Instance"), 2)
				end
				return props[key]
			end,
		})
	end

	-- A place set up exactly as the project file says.
	local function goodPlace()
		return {
			Workspace = {
				StreamingEnabled = true,
				StreamingTargetRadius = 1024,
				StreamingIntegrityMode = Enum.StreamingIntegrityMode.PauseOutsideLoadedArea,
			},
			Terrain = { Decoration = true },
			Lighting = { LightingStyle = Enum.LightingStyle.Realistic },
			Players = { MaxPlayers = 12 },
		}
	end

	-- Runs PlaceCheck.Run against stubbed services. options: place (props by
	-- service), unreadable ({ [service] = { [property] = true } }), studio,
	-- states (DataStoreState after each task.wait, in order).
	local function run(options)
		options = options or {}
		local place = options.place or goodPlace()
		local unreadable = options.unreadable or {}
		local s = { prints = {}, waits = 0 }
		local terrain = service(place.Terrain, unreadable.Terrain)
		local workspaceProps = table.clone(place.Workspace)
		workspaceProps.Terrain = terrain
		local profileStore = { DataStoreState = options.state or "NotReady" }
		local states = options.states or {}
		local now = 0
		local loader = t.loader({
			mocks = { ProfileStore = profileStore },
			services = {
				Workspace = service(workspaceProps, unreadable.Workspace),
				Lighting = service(place.Lighting, unreadable.Lighting),
				Players = service(place.Players, unreadable.Players),
				RunService = {
					IsStudio = function()
						return options.studio == true
					end,
				},
			},
			globals = {
				print = function(...)
					table.insert(s.prints, table.concat({ ... }, " "))
				end,
				task = {
					wait = function(seconds)
						s.waits += 1
						now += seconds or 0
						if #states > 0 then
							profileStore.DataStoreState = table.remove(states, 1)
						end
					end,
				},
				os = setmetatable({
					clock = function()
						return now
					end,
				}, { __index = os }),
			},
		})
		local PlaceCheck = loader:server("PlaceCheck")
		s.ok = PlaceCheck.Run()
		s.warnings = loader.warnings
		s.PlaceCheck = PlaceCheck
		return s
	end

	-- The module alone, for its pure parts.
	local function module()
		return t.loader({ mocks = { ProfileStore = { DataStoreState = "Access" } } }):server("PlaceCheck")
	end

	local function has(lines, text)
		for _, line in ipairs(lines) do
			if string.find(line, text, 1, true) then
				return true
			end
		end
		return false
	end

	t.test("a place that matches prints [PlaceCheck] OK and warns nothing", function()
		local s = run()
		t.eq(s.warnings, {})
		t.eq(s.prints, { "[PlaceCheck] OK" })
		t.ok(s.ok)
	end)

	t.test("StreamingEnabled off warns once, naming the setting and the fix, and no OK", function()
		local place = goodPlace()
		place.Workspace.StreamingEnabled = false
		local s = run({ place = place })
		t.eq(#s.warnings, 1)
		t.ok(has(s.warnings, "[PlaceCheck] Workspace.StreamingEnabled is false, expected true."), s.warnings[1])
		t.ok(has(s.warnings, "Fix: set Workspace.StreamingEnabled = true in Studio's Properties panel"), s.warnings[1])
		t.ok(has(s.warnings, "rojo build -o build.rbxlx"), "names the publish fix")
		t.ok(not has(s.prints, "[PlaceCheck] OK"), "no OK")
		t.ok(not s.ok)
	end)

	t.test("Max Players over 12 warns with the Game Settings fix; 12 or fewer is fine", function()
		local place = goodPlace()
		place.Players.MaxPlayers = 50
		local s = run({ place = place })
		t.eq(#s.warnings, 1)
		t.ok(has(s.warnings, "[PlaceCheck] Players.MaxPlayers is 50, expected 12 or fewer."), s.warnings[1])
		t.ok(has(s.warnings, "Fix: Game Settings > Places > Max Players = 12."), s.warnings[1])
		t.ok(not has(s.prints, "[PlaceCheck] OK"))

		place.Players.MaxPlayers = 8
		local fewer = run({ place = place })
		t.eq(fewer.warnings, {})
		t.ok(has(fewer.prints, "[PlaceCheck] OK"))
	end)

	t.test("every mismatch warns once, each with its own fix", function()
		local place = goodPlace()
		place.Workspace.StreamingTargetRadius = 512
		place.Workspace.StreamingIntegrityMode = Enum.StreamingIntegrityMode.Default
		place.Lighting.LightingStyle = Enum.LightingStyle.Soft
		place.Terrain.Decoration = false
		local s = run({ place = place })
		t.eq(#s.warnings, 4)
		t.ok(has(s.warnings, "Workspace.StreamingTargetRadius is 512, expected 1024."))
		t.ok(has(s.warnings, "Workspace.StreamingIntegrityMode is Default, expected PauseOutsideLoadedArea."))
		t.ok(has(s.warnings, "Lighting.LightingStyle is Soft, expected Realistic."))
		t.ok(has(s.warnings, "Workspace.Terrain.Decoration is false, expected true."))
		t.ok(has(s.warnings, "set Workspace.Terrain.Decoration = false") == false, "the fix names the wanted value")
		t.ok(has(s.warnings, "set Workspace.Terrain.Decoration = true"))
	end)

	t.test("a property a script can't read says so, never errors, and doesn't block OK", function()
		local s = run({
			unreadable = {
				Workspace = { StreamingTargetRadius = true, StreamingIntegrityMode = true },
				Terrain = { Decoration = true },
			},
		})
		t.eq(s.warnings, {})
		t.eq(#s.prints, 2)
		t.eq(
			s.prints[1],
			"[PlaceCheck] can't check Workspace.StreamingTargetRadius = 1024, "
				.. "Workspace.StreamingIntegrityMode = PauseOutsideLoadedArea, Workspace.Terrain.Decoration = true "
				.. "from a script: look in Studio's Properties panel."
		)
		t.eq(s.prints[2], "[PlaceCheck] OK")
	end)

	t.test("an unreadable property next to a mismatch: the note, the warning, no OK", function()
		local place = goodPlace()
		place.Workspace.StreamingEnabled = false
		local s = run({ place = place, unreadable = { Workspace = { StreamingTargetRadius = true } } })
		t.eq(#s.warnings, 1)
		t.ok(has(s.prints, "can't check Workspace.StreamingTargetRadius = 1024 from a script"))
		t.ok(not has(s.prints, "[PlaceCheck] OK"))
	end)

	t.test("in Studio, DataStore access off warns with the API Services fix", function()
		local s = run({ studio = true, state = "NoAccess" })
		t.eq(#s.warnings, 1)
		t.ok(has(s.warnings, "saves won't persist between tests"), s.warnings[1])
		t.ok(
			has(s.warnings, "Fix: Game Settings > Security > Enable Studio Access to API Services = on"),
			s.warnings[1]
		)
		t.ok(not has(s.prints, "[PlaceCheck] OK"))
		t.ok(not s.ok)
	end)

	t.test("in Studio, it waits for ProfileStore's probe before judging", function()
		local s = run({ studio = true, states = { "NotReady", "Access" } })
		t.eq(s.waits, 2)
		t.eq(s.warnings, {})
		t.eq(s.prints, { "[PlaceCheck] OK" })

		local off = run({ studio = true, states = { "NotReady", "NoAccess" } })
		t.eq(#off.warnings, 1)
		t.ok(has(off.warnings, "Enable Studio Access to API Services"))

		local offline = run({ studio = true, state = "NoInternet" })
		t.eq(#offline.warnings, 1)
		t.ok(has(offline.warnings, "no internet"))
	end)

	t.test("in Studio, a probe that never answers is a note, not a warning", function()
		local s = run({ studio = true, state = "NotReady" })
		t.eq(s.warnings, {})
		t.ok(has(s.prints, "can't tell yet whether Studio has DataStore access"))
		t.ok(has(s.prints, "[PlaceCheck] OK"))
		t.ok(s.waits >= 1 and s.waits <= 61, "gives up after DataStoreWait: " .. s.waits)
	end)

	t.test("live servers don't wait on or judge DataStore access", function()
		local s = run({ studio = false, state = "NoAccess" })
		t.eq(s.waits, 0)
		t.eq(s.warnings, {})
		t.eq(s.prints, { "[PlaceCheck] OK" })
	end)

	t.test("the expected values are default.project.json's", function()
		local fs = require("@lune/fs")
		local serde = require("@lune/serde")
		local tree = serde.decode("json", fs.readFile("default.project.json")).tree
		local fromProject = {
			Workspace = tree.Workspace["$properties"],
			Terrain = tree.Workspace.Terrain["$properties"],
			Lighting = tree.Lighting["$properties"],
		}
		local PlaceCheck = module()
		local checked = 0
		for _, e in ipairs(PlaceCheck.Expected) do
			local props = fromProject[e.service]
			if props then
				local want = if typeof(e.value) == "EnumItem" then e.value.Name else e.value
				t.eq(props[e.property], want, PlaceCheck.Setting(e) .. " vs default.project.json")
				checked += 1
			end
		end
		t.eq(checked, 5, "every project setting PLAY-02 names")
		t.eq(PlaceCheck.Expected[6].property, "MaxPlayers")
		t.eq(PlaceCheck.Expected[6].value, 12)
	end)

	t.test("the expected table is data: one more line is one more check", function()
		local PlaceCheck = module()
		local expected = table.clone(PlaceCheck.Expected)
		table.insert(expected, { service = "Lighting", property = "PrioritizeLightingQuality", value = false })
		local place = goodPlace()
		place.Lighting.PrioritizeLightingQuality = true
		local results = PlaceCheck.Compare(place, expected)
		t.eq(#results, #PlaceCheck.Expected + 1)
		local last = results[#results]
		t.eq(last.setting, "Lighting.PrioritizeLightingQuality")
		t.eq(last.status, "mismatch")
		local report = PlaceCheck.Report(results, nil)
		t.eq(#report.warnings, 1)
		t.ok(has(report.warnings, "Lighting.PrioritizeLightingQuality is true, expected false."))
	end)
end
