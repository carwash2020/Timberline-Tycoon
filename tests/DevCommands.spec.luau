--!nocheck
-- DevCommands (V2_PLAN.md §4a): Studio's /spawnwood. What it parses, what
-- it builds (v2-style loose wood GrabService can hold), where it lays it,
-- and that it does nothing outside Studio.
return function(t)
	local roblox = t.roblox
	local Vector3, CFrame, Enum = roblox.Vector3, roblox.CFrame, roblox.Enum

	local function load(isStudio, loop)
		local made, connected = {}, 0
		local signal = {
			Connect = function()
				connected += 1
				return { Disconnect = function() end }
			end,
		}
		local loader = t.loader({
			services = {
				Players = {
					PlayerAdded = signal,
					PlayerRemoving = signal,
					GetPlayers = function()
						return {}
					end,
				},
				PhysicsService = {},
				RunService = {
					IsStudio = function()
						return isStudio
					end,
					Heartbeat = signal,
				},
				TextChatService = {},
			},
			globals = {
				workspace = {
					GetAttribute = function(_, name)
						return if name == "CoreLoopActive" then loop or 2 else nil
					end,
				},
				Instance = setmetatable({
					new = function(class)
						table.insert(made, class)
						return roblox.Instance.new(class)
					end,
				}, { __index = roblox.Instance }),
			},
		})
		return loader:server("DevCommands"), loader, made, function()
			return connected
		end
	end

	local DevCommands = load(true)
	local GameConfig = t.shared("GameConfig")
	local GrabLogic = t.shared("GrabLogic")
	local WoodData = t.shared("WoodData")

	t.test("/spawnwood alone: a limb, an oak trunk, a birch log and a whole pine trunk", function()
		local pieces, problem = DevCommands.Parse("/spawnwood")
		t.eq(problem, nil)
		t.eq(#pieces, 4)
		t.eq(pieces[2], { woodId = "oak", thickness = 2.0, length = 9 })
		t.eq(pieces[4], { woodId = "pine", thickness = 2.6, length = 46 })
		-- The two Studio checks: the oak trunk lifts, the pine trunk only drags.
		local function mass(p)
			return GameConfig.WoodDensity * p.thickness * p.thickness * p.length
		end
		t.ok(GrabLogic.CanLift(mass(pieces[1])), "the limb lifts")
		t.ok(GrabLogic.CanLift(mass(pieces[2])), "the oak trunk lifts")
		t.ok(not GrabLogic.CanLift(mass(pieces[4])), "the pine trunk drags")
		t.eq(DevCommands.Parse("  /SpawnWood  "), DevCommands.Parse("/spawnwood"), "case and spaces don't matter")
	end)

	t.test("/spawnwood <wood> [length]: that wood's trunk, any part of its name", function()
		t.eq(DevCommands.Parse("/spawnwood pine"), { { woodId = "pine", thickness = 2.6, length = 46 } })
		t.eq(DevCommands.Parse("/spawnwood Oak 6"), { { woodId = "oak", thickness = 2.0, length = 6 } })
		t.eq(DevCommands.Parse("/spawnwood gloam")[1].woodId, "phantomwood", "the display name works too")
		t.eq(DevCommands.Parse("/spawnwood lumen 999")[1].length, DevCommands.MaxLength)
		t.eq(DevCommands.Parse("/spawnwood birch 0")[1].length, DevCommands.MinLength)
		for _, wood in ipairs(WoodData.All()) do
			local pieces = DevCommands.Parse("/spawnwood " .. wood.id)
			t.ok(pieces and pieces[1].woodId == wood.id, wood.id)
			t.ok(pieces[1].thickness > 0 and pieces[1].length > 0, wood.id)
		end
	end)

	t.test("anything else: a reason, or not this command at all", function()
		local pieces, problem = DevCommands.Parse("/spawnwood teak")
		t.eq(pieces, nil)
		t.eq(problem, "No wood matches 'teak'.")
		t.eq(select(2, DevCommands.Parse("/spawnwood oak long")), "Usage: /spawnwood <wood> <length in studs>")
		t.eq({ DevCommands.Parse("/giveaxe steel") }, {})
		t.eq({ DevCommands.Parse("/spawnwoodoak") }, {})
		t.eq({ DevCommands.Parse("hello") }, {})
	end)

	t.test("a piece is v2-style loose wood: tagged, unanchored, welded, light, its worth on it", function()
		local spec = { woodId = "oak", thickness = 2, length = 9 }
		local model = DevCommands.Build(spec, 42, "abc")
		t.eq(model.Name, "Wood_abc")
		t.ok(model:HasTag("Wood"))
		t.eq(model.ModelStreamingMode, Enum.ModelStreamingMode.Atomic)
		local section = model.PrimaryPart
		t.eq(section.Name, "Section")
		t.eq(section.Size, Vector3.new(2, 9, 2), "its length is its Y")
		t.eq(section.Anchored, false)
		t.eq(section.CanCollide, true)
		t.ok(math.abs(section.CustomPhysicalProperties.Density - GameConfig.WoodDensity) < 1e-6)
		local faces = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == "CutFace" then
				faces += 1
				t.ok(d.Massless and not d.CanCollide and not d.CanQuery and not d.Anchored, "a cut face is only a look")
				t.eq(d.Material, Enum.Material.Wood, "oak's core is wood")
				t.eq(d.Color, roblox.Color3.fromHex(WoodData.Get("oak").v2.core))
				local weld = d:FindFirstChildOfClass("WeldConstraint")
				t.ok(weld and weld.Part0 == section and weld.Part1 == d, "welded to the section")
			end
		end
		t.eq(faces, 2)
		t.eq(model:GetAttribute("Owner"), 42)
		t.eq(model:GetAttribute("WoodId"), "oak")
		t.eq(model:GetAttribute("Kind"), "log")
		t.eq(model:GetAttribute("HeldBy"), 0)
		local volume, value = DevCommands.Worth(spec)
		t.ok(math.abs(volume - 36 / 1.6 ^ 3) < 1e-9, "u³ = studs³ / 1.6³")
		t.ok(math.abs(value - volume * 1.5) < 1e-9, "oak logs are $1.5 per")
		t.eq(model:GetAttribute("Volume"), 8.79)
		t.eq(model:GetAttribute("Value"), 13.18)
		local glow = DevCommands.Build({ woodId = "lumenwood", thickness = 2.6, length = 4 }, 1, "x")
		local face = glow:FindFirstChild("CutFace")
		t.eq(face.Material, Enum.Material.Neon, "lumenwood's core glows")
	end)

	t.test("pieces lie in front of you, across your path, one behind the other", function()
		local pieces = DevCommands.Parse("/spawnwood")
		local origin = CFrame.new(10, 3, 10) * CFrame.Angles(0, math.rad(30), 0)
		local spots = DevCommands.Layout(origin, pieces)
		t.eq(#spots, #pieces)
		local forward = Vector3.new(origin.LookVector.X, 0, origin.LookVector.Z).Unit
		local last = 0
		for i, cf in ipairs(spots) do
			local ahead = (cf.Position - origin.Position):Dot(forward)
			t.ok(ahead >= last + pieces[i].thickness / 2, "piece " .. i .. " clear of the one before")
			last = ahead + pieces[i].thickness / 2
			t.ok(math.abs(cf.UpVector:Dot(forward)) < 1e-6, "its length runs across your path")
			t.ok(math.abs(cf.UpVector.Y) < 1e-6, "lying flat")
		end
	end)

	t.test("outside Studio, or under the v1 loop, it does nothing at all", function()
		local live, _, made, connections = load(false)
		live.Init(function() end)
		t.eq(made, {}, "no chat command made")
		t.eq(connections(), 0, "nothing connected")
		local v1, _, madeV1, connectionsV1 = load(true, 1)
		v1.Init(function() end)
		t.eq(madeV1, {})
		t.eq(connectionsV1(), 0)
	end)
end
