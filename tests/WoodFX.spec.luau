--!nocheck
-- WoodFX (V2_PLAN.md M1.3): the v2 loop's cutting and felling effects.
-- Its rules (the landing shake within 40 studs for more than 5 mass, the
-- ring's lit dots, the regrow spring, the death sink, the leaf colours),
-- the pools' sizes per quality tier, the figure band, and that under the
-- v1 loop it starts nothing.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

	local function load(loop)
		local connected = 0
		local sig = {
			Connect = function()
				connected += 1
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
					GetAttribute = function(_, name)
						return if name == "CoreLoopActive" then loop else nil
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
		return loader:load("StarterPlayer/StarterPlayerScripts/WoodFX"), function()
			return connected
		end
	end

	local WoodFX = load(2)
	local GameConfig = t.shared("GameConfig")
	local WoodData = t.shared("WoodData")
	local QualityBudgets = t.shared("QualityBudgets")

	t.test("a landing shakes the camera within 40 studs, for more than 5 mass, harder for heavier", function()
		t.ok(WoodFX.Shakes(30, 47), "a pine trunk close by")
		t.ok(not WoodFX.Shakes(41, 47), "too far")
		t.ok(not WoodFX.Shakes(10, 4), "a limb")
		t.ok(WoodFX.ShakeStrength(47) > WoodFX.ShakeStrength(6))
		t.ok(WoodFX.ShakeStrength(10000) <= 0.9, "never more than a big shake")
	end)

	t.test("the cut's ring lights as the cut goes through", function()
		t.eq(WoodFX.RingLit(0), 0)
		t.eq(WoodFX.RingLit(0.5), 8)
		t.eq(WoodFX.RingLit(1), 16)
		t.eq(WoodFX.RingLit(3), 16)
	end)

	t.test("the regrow spring starts smaller, overshoots a touch and ends at 1; the sink takes DeadSinkSec", function()
		t.eq(WoodFX.SpringScale(0), WoodFX.SpringFrom)
		local most = 0
		for k = 0, 20 do
			most = math.max(most, WoodFX.SpringScale(k / 20))
		end
		t.ok(most > 1 and most < 1.06, "a little overshoot")
		t.eq(WoodFX.SpringScale(1), 1)
		t.eq(WoodFX.SinkAt(0), 0)
		t.eq(WoodFX.SinkAt(GameConfig.DeadSinkSec / 2), 0.5)
		t.eq(WoodFX.SinkAt(GameConfig.DeadSinkSec * 3), 1)
	end)

	t.test("a chip's long side starts at least 0.3 studs", function()
		t.eq(WoodFX.ChipMin, 0.3)
		local src = require("@lune/fs").readFile("src/StarterPlayer/StarterPlayerScripts/WoodFX.luau")
		t.ok(string.find(src, "WoodFX.ChipMin + math.random()", 1, true))
	end)

	t.test("leaves flutter in the wood's v2 colours; the pools follow the quality tier", function()
		local oak = WoodData.Get("oak")
		local colors = WoodFX.LeafColors(oak)
		t.eq(#colors, #oak.v2.shape.leafColors)
		t.ok(colors[1] == roblox.Color3.fromHex(oak.v2.shape.leafColors[1]))
		t.eq(QualityBudgets.High.ChipCount, 48)
		t.eq(QualityBudgets.Low.LeafPool, 32)
		t.eq(QualityBudgets.Low.LeafShadows, false, "low: no leaf shadows")
	end)

	t.test("a figured piece's band: a square collar on its section, welded, never collides", function()
		local ForestArt = t.shared("Art/ForestArt")
		local section = Instance.new("Part")
		section.Size = Vector3.new(2, 9, 2)
		section.CFrame = CFrame.new(0, 1, 0)
		local band = ForestArt.SectionBand(section, "birdseye")
		t.ok(band.Parent == section)
		t.ok(band.Size.X > 2 and band.Size.Z > 2, "round the section")
		t.ok(not band.CanCollide and not band.CanQuery and band.Massless)
		t.eq(band:GetAttribute("Figure"), "birdseye")
		local weld = band:FindFirstChildOfClass("WeldConstraint")
		t.ok(weld and weld.Part0 == section)
		local again = ForestArt.SectionBand(section, "stormgrain")
		t.eq(#section:GetChildren(), 1, "a new figure replaces the band")
		t.eq(again.Material, roblox.Enum.Material.Neon, "Stormgrain glows")
	end)

	t.test("under the v1 loop it starts nothing", function()
		local fx, connected = load(1)
		fx.Start()
		t.eq(connected(), 0)
	end)

	t.test("Lanternwood glows only at night, and 12 trees on high make at most 8 lights", function()
		t.eq(WoodFX.GlowRange, 14)
		t.eq(WoodFX.GlowBrightness, 0.8)
		t.eq(QualityBudgets.GlowLights, { low = 0, medium = 4, high = 8 })
		t.eq(QualityBudgets.GlowLightCap("low"), 0)
		t.eq(QualityBudgets.GlowLightCap("medium"), 4)
		t.eq(QualityBudgets.GlowLightCap("high"), 8)
		t.eq(WoodFX.NightGlowOn(19), true)
		t.eq(WoodFX.NightGlowOn(0), true)
		t.eq(WoodFX.NightGlowOn(4.9), true)
		t.eq(WoodFX.NightGlowOn(5), false)
		t.eq(WoodFX.NightGlowOn(12), false)
		t.eq(WoodFX.NightGlowOn(18.9), false)
		local hosts = {}
		for i = 1, 12 do
			table.insert(hosts, { id = "tree" .. i, kind = "tree", distance = i })
		end
		table.insert(hosts, { id = "plank", kind = "plank", distance = 0.1 })
		local lit = WoodFX.LitIds(hosts, "high")
		t.eq(#lit, 8)
		t.eq(lit[1], "tree1")
		t.eq(lit[8], "tree8")
		for _, id in ipairs(lit) do
			t.ok(id ~= "plank", "a plank never gets a light")
		end
		t.eq(WoodFX.LitIds(hosts, "medium"), { "tree1", "tree2", "tree3", "tree4" })
		t.eq(WoodFX.LitIds(hosts, "low"), {})
	end)

	local function lantern(parent, name, at, color)
		local model = Instance.new("Model")
		model.Name = name
		model.Parent = parent
		model:SetAttribute("NightHost", "tree")
		local part = Instance.new("Part")
		part.Name = "Leaves"
		part.Material = roblox.Enum.Material.Wood
		part.Color = color
		part.CFrame = CFrame.new(at)
		part:SetAttribute("NightGlow", true)
		part.Parent = model
		model.PrimaryPart = part
		return model, part
	end

	t.test("a lantern repaint happens only on a day/night flip", function()
		WoodFX.ResetLanterns()
		local folder = Instance.new("Folder")
		local day = roblox.Color3.fromRGB(110, 138, 74)
		local model, part = lantern(folder, "Tree_lanternwood", Vector3.new(0, 0, 10), day)
		local eye = Vector3.new(0, 0, 0)
		t.eq(WoodFX.TrackLantern(model, false), 1, "a new model is painted once")
		t.eq(part.Material, roblox.Enum.Material.Wood)
		t.eq(part.Color, day)
		t.eq(WoodFX.StepLanterns(false, 0, "high", eye), 0)
		t.eq(WoodFX.StepLanterns(false, 0.25, "high", eye), 0, "still day")
		t.eq(WoodFX.TrackLantern(model, false), 0, "tracking the same model again does not repaint")
		t.eq(WoodFX.StepLanterns(true, 1, "high", eye), 1, "dusk")
		t.eq(part.Material, roblox.Enum.Material.Neon)
		t.eq(part.Color, roblox.Color3.fromHex(WoodData.LanternGlow))
		t.eq(WoodFX.StepLanterns(true, 1.25, "high", eye), 0, "still night")
		t.eq(WoodFX.StepLanterns(true, 30, "high", eye), 0, "a later night tick does not repaint")
		local added = Instance.new("Part")
		added.Name = "LeavesLate"
		added:SetAttribute("NightGlow", true)
		added.Material = roblox.Enum.Material.Wood
		added.Color = day
		added.Parent = model
		t.eq(WoodFX.StepLanterns(false, 31, "high", eye), 1, "dawn repaints the cached part only")
		t.eq(part.Material, roblox.Enum.Material.Wood)
		t.eq(part.Color, day)
		t.eq(added.Material, roblox.Enum.Material.Wood, "a part added after the tag was cached stays as it was")
		local other, otherPart = lantern(folder, "Tree_lanternwood", Vector3.new(0, 0, 20), day)
		t.eq(WoodFX.TrackLantern(other, false), 1, "a new model paints without a flip")
		t.eq(otherPart.Material, roblox.Enum.Material.Wood)
		t.eq(WoodFX.StepLanterns(false, 31.2, "high", eye), 0, "the first model is not painted again")
	end)

	t.test("two Lanternwood models with the same name are tracked separately", function()
		WoodFX.ResetLanterns()
		local folder = Instance.new("Folder")
		local eye = Vector3.new(0, 0, 0)
		local models = {}
		local colors = {}
		for i = 1, 9 do
			local color = roblox.Color3.fromRGB(i * 20, 40, 10)
			local model, part = lantern(folder, "Tree_lanternwood", Vector3.new(0, 0, i * 10), color)
			colors[i] = color
			models[i] = { model = model, part = part }
			WoodFX.TrackLantern(model, false)
		end
		t.eq(models[1].model.Name, models[9].model.Name)
		t.eq(models[1].model.Parent, models[9].model.Parent)
		t.eq(models[1].model:GetFullName(), models[9].model:GetFullName())
		t.eq(WoodFX.StepLanterns(true, 0, "high", eye), 9, "dusk paints each model, not one shared name")
		for i = 1, 9 do
			t.eq(models[i].part.Material, roblox.Enum.Material.Neon)
		end
		t.eq(WoodFX.StepLanterns(false, 1, "high", eye), 9)
		for i = 1, 9 do
			t.eq(models[i].part.Color, colors[i], "day colour " .. i .. " is its own")
			t.eq(models[i].part.Material, roblox.Enum.Material.Wood)
		end
		WoodFX.ResetLanterns()
		for i = 1, 9 do
			WoodFX.TrackLantern(models[i].model, true)
		end
		t.eq(WoodFX.StepLanterns(true, 0, "high", eye), 0)
		local lights = 0
		for i = 1, 9 do
			local light = models[i].model.PrimaryPart:FindFirstChild(WoodFX.GlowLightName)
			if light then
				lights += 1
			end
			t.eq(light ~= nil, i <= 8, "tree " .. i)
		end
		t.eq(lights, 8, "the cap is per model, so the ninth same-named tree stays dark")
	end)
end
