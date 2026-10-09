--!nocheck
-- NatureData. ScatterZones and UndergroundData are stubbed here. Nothing
-- under src/ stands in for Lane B's modules.
return function(t)
	local NatureData = t.load("ReplicatedStorage/Shared/NatureData")
	local QualityBudgets = t.load("ReplicatedStorage/Shared/QualityBudgets")
	local Vector2 = t.roblox.Vector2
	local Vector3 = t.roblox.Vector3
	local CFrame = t.roblox.CFrame

	local function zone(id, kind, x, z, radius, extra)
		local row = {
			id = id,
			kind = kind,
			center = Vector2.new(x, z),
			radius = radius,
			density = 0.8,
		}
		for k, v in pairs(extra or {}) do
			row[k] = v
		end
		return row
	end

	t.test("scatter rows win over the plan and the underground rooms", function()
		local scatter = { zone("s", "meadow", 0, 0, 40) }
		local plan = { zone("p", "forest", 100, 0, 40) }
		local rooms = { zone("r", "cave", 0, 0, 20, { shelter = "cave" }) }
		local got = NatureData.Assemble(scatter, plan, rooms)
		t.eq(#got, 1)
		t.eq(got[1].id, "s")
		local fallback = NatureData.Assemble({}, plan, rooms)
		t.eq(#fallback, 2)
	end)

	t.test("a cell is deterministic and skips blocked ground", function()
		local zones = { zone("meadow", "meadow", 32, 32, 80) }
		local function blocked(x, z)
			return x < 20
		end
		local a = NatureData.CellSpots(0, 0, zones, blocked, {}, 500)
		local b = NatureData.CellSpots(0, 0, zones, blocked, {}, 500)
		t.eq(#a, #b)
		for i, spot in ipairs(a) do
			t.eq(spot.x, b[i].x)
			t.eq(spot.kind, b[i].kind)
			t.ok(spot.x >= 20, "blocked ground is skipped")
		end
	end)

	t.test("one cave stays within 120 parts and 6 lights", function()
		local cave = zone("cinder", "cave", 32, 32, 200, { shelter = "cave", floor = -20, below = -8 })
		local parts = {}
		local total, lights = 0, 0
		for i = 0, 40 do
			local spots = NatureData.CellSpots(i, 0, { cave }, function()
				return false
			end, parts, 0)
			for _, spot in ipairs(spots) do
				total += spot.parts
				parts[spot.caveId] = (parts[spot.caveId] or 0) + spot.parts
				if spot.light then
					lights += 1
				end
			end
		end
		t.ok(total <= NatureData.CavePartCap, "cave parts " .. total)
		t.ok(lights <= NatureData.CaveLightCap, "cave lights " .. lights)
		t.ok(QualityBudgets.CaveLightCap("high") <= 6)
		t.ok(QualityBudgets.CaveLightCap("low") <= 6)
		t.ok(QualityBudgets.RainLive("high") < 560, "high rain stays under the decor budget")
		t.ok(QualityBudgets.RainLive("low") < QualityBudgets.RainLive("high"))
	end)

	t.test("rain stops in a cave, a tunnel, a grotto, and under a ceiling", function()
		local zones = {
			zone("c", "cave", 0, 0, 30, { shelter = "cave", below = 10 }),
			zone("t", "cave", 80, 0, 20, { shelter = "tunnel", below = 4 }),
			zone("g", "cave", 140, 0, 16, { shelter = "grotto", below = -2 }),
		}
		t.eq(NatureData.Sheltered(zones, 0, 0, 0, false), true)
		t.eq(NatureData.Sheltered(zones, 0, 40, 0, false), false)
		t.eq(NatureData.Sheltered(zones, 80, 0, 0, false), true)
		t.eq(NatureData.Sheltered(zones, 140, -6, 0, false), true)
		t.eq(NatureData.Sheltered(zones, 400, 0, 0, true), true)
		t.eq(NatureData.Sheltered(zones, 400, 0, 0, false), false)
	end)

	t.test("a WorldPlan-shaped stub becomes zones without hardcoded spots", function()
		local plan = {
			GroveDiscs = function()
				return { { cx = 10, cz = 20, radius = 30 } }
			end,
			PointsOfInterest = function()
				return {
					{ id = "Cinder", kind = "Cave", cframe = CFrame.new(5, 12, 7) },
				}
			end,
			Underground = function()
				return {
					{
						id = "tunnel",
						center = Vector3.new(1, -30, 2),
						radius = 18,
						shelter = "tunnel",
						below = -20,
						floor = -32,
					},
				}
			end,
		}
		local zones = NatureData.FromWorldPlan(plan)
		local kinds = {}
		for _, z in ipairs(zones) do
			kinds[z.kind] = (kinds[z.kind] or 0) + 1
			t.ok(z.center ~= nil)
		end
		t.eq(kinds.forest, 1)
		t.ok(kinds.cave >= 2, "the cave and the underground room")
	end)
end
