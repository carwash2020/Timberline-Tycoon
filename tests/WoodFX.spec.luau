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
end
