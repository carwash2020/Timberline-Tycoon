--!nocheck
-- WeatherService: publishes the schedule, honours a tester's override, and
-- throws lightning near players in storms, never into town.
return function(t)
	local Vector3 = t.roblox.Vector3
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local BiomeData = t.shared("BiomeData")

	local function setup(options)
		options = options or {}
		local attributes = {}
		local fired = {}
		local strikes = {}
		local positions = options.players or {}
		local players = {}
		for i, pos in ipairs(positions) do
			local root = {
				Position = pos,
				IsA = function(_, class)
					return class == "BasePart"
				end,
			}
			local humanoid = { Health = 100 }
			local char = {
				FindFirstChild = function(_, name)
					return if name == "HumanoidRootPart" then root else nil
				end,
				FindFirstChildOfClass = function(_, class)
					return if class == "Humanoid" then humanoid else nil
				end,
			}
			players[i] = { Character = char }
		end
		local fakeWorkspace = {
			SetAttribute = function(_, k, v)
				attributes[k] = v
			end,
			GetAttribute = function(_, k)
				return attributes[k]
			end,
			GetServerTimeNow = function()
				return 0
			end,
		}
		local loader = t.loader({
			services = {
				Players = {
					GetPlayers = function()
						return players
					end,
				},
			},
			mocks = {
				ForestService = {
					Strike = function(pos)
						table.insert(strikes, pos)
						return options.struckUid
					end,
				},
				SectionTrees = {
					GetTree = function()
						return options.tree
					end,
				},
			},
			globals = {
				workspace = fakeWorkspace,
				task = {
					delay = function(_, fn, ...)
						fn(...)
					end,
					spawn = function() end,
					wait = function() end,
				},
			},
		})
		local WeatherService = loader:server("WeatherService")
		local remote = {
			FireAllClients = function(_, kind, payload)
				table.insert(fired, { kind = kind, payload = payload })
			end,
		}
		WeatherService.Init(remote)
		return WeatherService, attributes, fired, strikes
	end

	t.test("publishes the schedule's weather as workspace attributes", function()
		local WeatherService, attributes = setup()
		local Schedule = t.shared("WeatherSchedule")
		local now = 1790000123
		WeatherService.Step(now)
		local s = Schedule.At(now)
		t.eq(attributes.Weather, s.kind)
		t.ok(math.abs(attributes.WeatherIntensity - s.intensity) <= 0.005)
	end)

	t.test("a tester can force the weather", function()
		local WeatherService, attributes = setup()
		attributes.WeatherOverride = "Storm"
		WeatherService.Step(1790000123)
		t.eq(attributes.Weather, "Storm")
		t.eq(attributes.WeatherIntensity, 1)
		attributes.WeatherOverride = "Hailstorm" -- not a weather: ignored
		WeatherService.Step(1790000124)
		t.ok(attributes.Weather ~= "Hailstorm")
	end)

	t.test("strike points: near the player, on the ground, never in town or the plots", function()
		local WeatherService = setup()
		local spots = {
			Vector3.new(0, 1, -110), -- Starter Forest, right by town
			Vector3.new(0, 1, 60), -- in town
			Vector3.new(-420, 10, 110), -- the Hills
			Vector3.new(0, 30, 1240), -- the Snowfields
		}
		for _, near in ipairs(spots) do
			local found = 0
			for _ = 1, 200 do
				local p = WeatherService.StrikePoint(near)
				if p then
					found += 1
					local flat = Vector3.new(p.X - near.X, 0, p.Z - near.Z).Magnitude
					t.ok(flat <= 250 + 1e-6 and flat >= 40 - 1e-6, "within 40-250 studs: " .. flat)
					t.eq(WorldLayout.FlatWeight(p.X, p.Z), 0)
					t.ok(math.abs(p.Y - TerrainGen.HeightAt(p.X, p.Z)) < 0.01, "on the terrain")
				end
			end
			t.ok(found > 150, "usually finds ground")
		end
	end)

	t.test("on the Aether Isles the bolt lands on an isle", function()
		local WeatherService = setup()
		local area = BiomeData.Get("sky").area
		local near = Vector3.new(area.x, area.y + 50, area.z)
		for _ = 1, 100 do
			local p = WeatherService.StrikePoint(near)
			t.ok(p ~= nil)
			t.ok(p.Y > area.y, "up on an isle")
			t.ok((p - near).Magnitude <= 250)
		end
	end)

	t.test("storms throw bolts: a warning, then the strike, then the bolt", function()
		local WeatherService, attributes, fired, strikes = setup({ players = { Vector3.new(0, 1, -110) } })
		attributes.WeatherOverride = "Storm"
		local now = 1790000000
		for i = 0, 200 do
			WeatherService.Step(now + i)
		end
		t.ok(#strikes >= 3, "a few bolts in 200 s: " .. #strikes)
		t.ok(#strikes <= 12, "but not a barrage: " .. #strikes)
		local warns, bolts = 0, 0
		for _, f in ipairs(fired) do
			if f.kind == "LightningWarn" then
				warns += 1
			elseif f.kind == "Lightning" then
				bolts += 1
				t.eq(typeof(f.payload.position), "Vector3")
				t.eq(WorldLayout.FlatWeight(f.payload.position.X, f.payload.position.Z), 0)
			end
		end
		t.eq(warns, #strikes)
		t.eq(bolts, #strikes)
	end)

	t.test("no bolts when it isn't storming, or nobody is around", function()
		local WeatherService, attributes, _, strikes = setup({ players = { Vector3.new(0, 1, -110) } })
		attributes.WeatherOverride = "Rain"
		for i = 0, 200 do
			WeatherService.Step(1790000000 + i)
		end
		t.eq(#strikes, 0)
		local lonely, lonelyAttributes, _, lonelyStrikes = setup({ players = {} })
		lonelyAttributes.WeatherOverride = "Storm"
		for i = 0, 200 do
			lonely.Step(1790000000 + i)
		end
		t.eq(#lonelyStrikes, 0)
	end)

	t.test("a struck tree pulls the bolt to its crown", function()
		local model = {
			Parent = {},
			GetBoundingBox = function()
				return t.roblox.CFrame.new(5, 20, 5), Vector3.new(10, 30, 10)
			end,
		}
		local WeatherService, attributes, fired = setup({
			players = { Vector3.new(0, 1, -110) },
			struckUid = "tree-1",
			tree = { model = model, base = Vector3.new(7, 0, 9) },
		})
		attributes.WeatherOverride = "Storm"
		for i = 0, 60 do
			WeatherService.Step(1790000000 + i)
		end
		local bolt
		for _, f in ipairs(fired) do
			if f.kind == "Lightning" then
				bolt = f.payload
			end
		end
		t.ok(bolt ~= nil)
		t.eq(bolt.position, Vector3.new(7, 35, 9))
		t.eq(bolt.struck, true)
	end)
end
