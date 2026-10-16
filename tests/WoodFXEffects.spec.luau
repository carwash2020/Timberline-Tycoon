--!nocheck
-- WoodFX sparks on ember and gloam buildings (WOODFX-T316): StepEffects with an
-- injected tier and eye, the cap per tier, nearest first, nothing past 150
-- studs, one emitter per building with Rate <= 3 and Lifetime <= 2, cleanup when
-- a building goes, and paint winning on the client at dawn.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
	local Enum, Color3 = roblox.Enum, roblox.Color3

	local sig = {
		Connect = function()
			return { Disconnect = function() end }
		end,
	}
	local loader = t.loader({
		services = {
			Debris = { AddItem = function() end },
			Players = { LocalPlayer = { UserId = 1 } },
			RunService = { Heartbeat = sig },
			TweenService = {},
			CollectionService = {
				GetTagged = function()
					return {}
				end,
				GetInstanceAddedSignal = function()
					return sig
				end,
				GetInstanceRemovedSignal = function()
					return sig
				end,
			},
		},
		mocks = {
			CameraShake = { Shake = function() end },
			SoundData = { PlayAt = function() end, Play = function() end },
			Quality = {
				Budget = function()
					return t.shared("QualityBudgets").High
				end,
			},
			Net = {
				Remote = function()
					return { OnClientEvent = sig }
				end,
			},
		},
		globals = {
			workspace = {
				GetAttribute = function()
					return nil
				end,
			},
			RaycastParams = {
				new = function()
					return {}
				end,
			},
			task = {
				wait = function()
					return 0.25
				end,
			},
		},
	})
	local WoodFX = loader:load("StarterPlayer/StarterPlayerScripts/WoodFX")
	local QualityBudgets = t.shared("QualityBudgets")
	local WoodData = t.shared("WoodData")
	local Palette = t.load("ReplicatedStorage/Shared/Art/Palette")

	-- A building of `woodId` with one glowing Door part.
	local function building(parent, woodId, at, tag)
		local model = Instance.new("Model")
		model.Name = "Cabin_" .. woodId
		model:SetAttribute("WoodId", woodId)
		model:SetAttribute("NightHost", "plank")
		model.Parent = parent
		local root = Instance.new("Part")
		root.Name = "Root"
		root.CFrame = CFrame.new(at)
		root.Parent = model
		model.PrimaryPart = root
		local door = Instance.new("Part")
		door.Name = "Door"
		door.Material = Enum.Material.Wood
		door.Color = Color3.fromRGB(200, 100, 20)
		door.CFrame = CFrame.new(at)
		door:SetAttribute("Role", "Door")
		door:SetAttribute("NightGlow", true)
		door.Parent = model
		return model, door
	end

	local function emitters(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("ParticleEmitter") then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("EffectHostIds: nearest first, ties by id, only within range, never over the tier's cap", function()
		local hosts = {}
		for i = 1, 12 do
			table.insert(hosts, { id = string.format("%02d", i), distance = i * 10 })
		end
		local high = WoodFX.EffectHostIds(hosts, "high", 150)
		t.eq(#high, 8)
		t.eq(high[1], "01")
		t.eq(high[8], "08")
		t.eq(#WoodFX.EffectHostIds(hosts, "medium", 150), 4)
		t.eq(WoodFX.EffectHostIds(hosts, "low", 150), {})
		t.eq(#WoodFX.EffectHostIds(hosts, "high", 55), 5, "a host past the range gets none")
		local tie = WoodFX.EffectHostIds({ { id = "b", distance = 5 }, { id = "a", distance = 5 } }, "medium")
		t.eq(tie, { "a", "b" })
		t.eq(#WoodFX.EffectHostIds({ { id = "far", distance = 151 } }, "high"), 0, "FxRange is 150 by default")
	end)

	t.test("12 ember buildings give 8 emitters on high, 4 on medium, 0 on low", function()
		for tier, want in pairs({ high = 8, medium = 4, low = 0 }) do
			WoodFX.ResetLanterns()
			local folder = Instance.new("Folder")
			for i = 1, 12 do
				local model = building(folder, "emberwood", Vector3.new(i * 5, 0, 0))
				WoodFX.TrackLantern(model, false)
			end
			t.eq(WoodFX.StepEffects(false, 0, tier, Vector3.new(0, 0, 0)), want, tier)
			local live = 0
			for _, model in ipairs(folder:GetChildren()) do
				local found = emitters(model)
				t.ok(#found <= 1, "one emitter per building")
				live += #found
			end
			t.eq(live, want, tier .. " live emitters")
		end
	end)

	t.test("nearest first; moving the eye swaps the hosts within a second; a host past 150 studs gets none", function()
		WoodFX.ResetLanterns()
		local folder = Instance.new("Folder")
		local models = {}
		for i = 1, 10 do
			models[i] = building(folder, "phantomwood", Vector3.new(i * 20, 0, 0))
			WoodFX.TrackLantern(models[i], false)
		end
		-- Eye at x = 0: buildings 1..7 are within 150; the nearest 4 get sparks on medium.
		t.eq(WoodFX.StepEffects(false, 0, "medium", Vector3.new(0, 0, 0)), 4)
		for i = 1, 4 do
			t.eq(#emitters(models[i]), 1, "building " .. i)
		end
		t.eq(#emitters(models[5]), 0)
		t.eq(#emitters(models[10]), 0, "past 150 studs")
		-- Move the eye to x = 200: the nearest are now 10, 9, 8, 7.
		t.eq(
			WoodFX.StepEffects(false, 0.5, "medium", Vector3.new(200, 0, 0)),
			4,
			"inside the interval: unchanged count"
		)
		t.eq(#emitters(models[1]), 1, "not re-sorted within the interval")
		t.eq(WoodFX.StepEffects(false, 1.2, "medium", Vector3.new(200, 0, 0)), 4)
		for i = 7, 10 do
			t.eq(#emitters(models[i]), 1, "building " .. i .. " now")
		end
		t.eq(#emitters(models[1]), 0, "the old hosts let go")
	end)

	t.test(
		"every emitter is small: Rate <= 3, Lifetime <= 2, the glow colour, the dust texture, on the PrimaryPart",
		function()
			WoodFX.ResetLanterns()
			local folder = Instance.new("Folder")
			local ember = building(folder, "emberwood", Vector3.new(5, 0, 0))
			local gloam = building(folder, "phantomwood", Vector3.new(10, 0, 0))
			WoodFX.TrackLantern(ember, false)
			WoodFX.TrackLantern(gloam, false)
			t.eq(WoodFX.StepEffects(false, 0, "high", Vector3.new(0, 0, 0)), 2)
			for _, model in ipairs({ ember, gloam }) do
				local found = emitters(model)
				t.eq(#found, 1)
				local e = found[1]
				t.eq(e.Name, "WoodEffectFx")
				t.eq(e:GetAttribute("ClientFx"), true)
				t.ok(e.Rate <= 3, "Rate")
				t.ok(e.Lifetime.Max <= 2, "Lifetime")
				t.eq(e.Texture, "rbxasset://textures/particles/smoke_main.dds")
				t.eq(e.Parent, model.PrimaryPart)
				t.ok(e.LightEmission <= 0.5, "LightEmission small")
			end
			t.eq(emitters(ember)[1].Color.Keypoints[1].Value, Palette.Get("EmberGlow"))
			t.eq(emitters(gloam)[1].Color.Keypoints[1].Value, Palette.Get("GloamGlow"))
		end
	)

	t.test("frost, lumen and lantern never get an emitter, day or night", function()
		WoodFX.ResetLanterns()
		local folder = Instance.new("Folder")
		for i, id in ipairs({ "frostwood", "lumenwood", "lanternwood" }) do
			local model = building(folder, id, Vector3.new(i * 5, 0, 0))
			WoodFX.TrackLantern(model, false)
		end
		t.eq(WoodFX.StepEffects(false, 0, "high", Vector3.new(0, 0, 0)), 0)
		t.eq(WoodFX.StepEffects(true, 2, "high", Vector3.new(0, 0, 0)), 0)
		for _, model in ipairs(folder:GetChildren()) do
			t.eq(#emitters(model), 0)
		end
	end)

	t.test("a destroyed, untagged or painted building leaves no emitter", function()
		WoodFX.ResetLanterns()
		local folder = Instance.new("Folder")
		local a, doorA = building(folder, "emberwood", Vector3.new(5, 0, 0))
		local b = building(folder, "emberwood", Vector3.new(10, 0, 0))
		local c = building(folder, "emberwood", Vector3.new(15, 0, 0))
		for _, m in ipairs({ a, b, c }) do
			WoodFX.TrackLantern(m, false)
		end
		t.eq(WoodFX.StepEffects(false, 0, "high", Vector3.new(0, 0, 0)), 3)
		-- Painted: the paint clears NightGlow; the sparks go at the next step.
		doorA:SetAttribute("NightGlow", nil)
		doorA:SetAttribute("Painted", true)
		-- Picked up: the model leaves the world.
		b.Parent = nil
		-- Untagged: the tag listener forgets it.
		WoodFX.ForgetLantern(c)
		t.eq(#emitters(c), 0, "forgetting a model removes its emitter")
		t.eq(WoodFX.StepEffects(false, 5, "high", Vector3.new(0, 0, 0)), 0)
		t.eq(#emitters(a), 0, "a painted building has no sparks")
		t.eq(#emitters(b), 0)
	end)

	t.test("paint wins on the client: a painted part is dropped and never repainted with the old day colour", function()
		WoodFX.ResetLanterns()
		local folder = Instance.new("Folder")
		local model, door = building(folder, "emberwood", Vector3.new(0, 0, 10))
		local day = door.Color
		local eye = Vector3.new(0, 0, 0)
		WoodFX.TrackLantern(model, false)
		-- Paint arrives (server: ApplyPaint recolours, clears NightGlow, sets Painted).
		local painted = Color3.fromRGB(168, 65, 47)
		door.Color = painted
		door.Material = Enum.Material.SmoothPlastic
		door:SetAttribute("NightGlow", nil)
		door:SetAttribute("Painted", true)
		WoodFX.StepLanterns(true, 1, "high", eye)
		t.eq(door.Color, painted, "night does not glow a painted part")
		t.ok(door.Material ~= Enum.Material.Neon, "and never Neon")
		WoodFX.StepLanterns(false, 2, "high", eye)
		t.eq(door.Color, painted, "dawn does not write the old day colour back")
		t.ok(door.Color ~= day)
		t.eq(door.Material, Enum.Material.SmoothPlastic)
	end)

	t.test("night glow follows the model's wood: ember orange, gloam violet, lantern its own", function()
		WoodFX.ResetLanterns()
		local folder = Instance.new("Folder")
		local eye = Vector3.new(0, 0, 0)
		local want = {
			emberwood = Palette.Get("EmberGlow"),
			phantomwood = Palette.Get("GloamGlow"),
			lanternwood = Color3.fromHex(WoodData.LanternGlow),
		}
		local doors = {}
		local i = 0
		for id in pairs(want) do
			i += 1
			local model, door = building(folder, id, Vector3.new(i * 5, 0, 0))
			doors[id] = door
			WoodFX.TrackLantern(model, false)
		end
		WoodFX.StepLanterns(true, 1, "high", eye)
		for id, door in pairs(doors) do
			t.eq(door.Color, want[id], id)
			t.eq(door.Material, Enum.Material.Neon)
		end
		t.eq(QualityBudgets.EffectHostCap("high"), 8)
	end)
end
