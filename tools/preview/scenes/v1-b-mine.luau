--!nocheck
-- The mine mouth and its ramp (ring map, 10 Oct 2026). The arch is the real
-- NatureArt.CaveMouth (uploaded meshes) placed the way UndergroundBuilder
-- places it: door toward town (+Z), throat down the hill (-Z). The ground
-- and the hill over the bore are TerrainGen's. The bore itself is carved
-- terrain in the game (TerrainBuilder.Carve fills UndergroundData.AirBoxes
-- with air), which this viewer cannot draw, so the inside views stand in
-- thin rock panels round each ramp sample: floor, two walls, a roof, and the
-- game's own lamps. Same numbers, same path.
-- 1 the mouth from town, 2 the door close up, 3 the hill from the east,
-- 4 the hill from above, 5 inside the bore at the door, 6 half way down,
-- 7 the same at night with the lamps on, 8 the foot of the ramp.
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local NatureArt = ctx.art("NatureArt")
		local UndergroundData = ctx.load("ReplicatedStorage/Shared/World/UndergroundData")
		local root = roblox.Instance.new("Model")
		local ramp = UndergroundData.Ramp
		local mouth = UndergroundData.MineMouth

		local model = NatureArt.CaveMouth()
		Kit.placeAt(model, CF.new(mouth.x, ramp.top - 0.4, mouth.z) * CF.Angles(0, math.pi, 0))
		model.Parent = root

		-- The bore, as panels (inside views only; they sit under the hill).
		local rock = C3.fromRGB(96, 90, 82)
		local floorColor = C3.fromRGB(120, 112, 100)
		local samples = UndergroundData.RampSamples
		for i = 1, #samples - 1 do
			local a, b = samples[i], samples[i + 1]
			local mid = V3.new((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
			local dir = V3.new(b.x - a.x, b.y - a.y, b.z - a.z)
			local len = dir.Magnitude
			if len > 0 then
				local cf = CF.lookAt(mid, mid + dir)
				local half = ramp.width / 2
				Kit.part(root, "RampFloor", V3.new(ramp.width, 0.4, len + 0.05), cf * CF.new(0, -0.2, 0), floorColor, Enum.Material.Slate)
				Kit.part(root, "RampWall", V3.new(0.6, ramp.height, len + 0.05), cf * CF.new(-half - 0.3, ramp.height / 2, 0), rock, Enum.Material.Slate)
				Kit.part(root, "RampWall", V3.new(0.6, ramp.height, len + 0.05), cf * CF.new(half + 0.3, ramp.height / 2, 0), rock, Enum.Material.Slate)
				if a.s >= ramp.landing then
					Kit.part(root, "RampRoof", V3.new(ramp.width + 1.2, 0.6, len + 0.05), cf * CF.new(0, ramp.height + 0.3, 0), rock, Enum.Material.Slate)
				end
			end
		end
		-- The upper mine's floor where the ramp lands, so the foot reads.
		local last = samples[#samples]
		Kit.part(root, "ChamberFloor", V3.new(48, 0.4, 48), CF.new(150, -48.2, -220), floorColor, Enum.Material.Slate)
		-- The same lamps UndergroundBuilder hangs.
		for i = 1, ramp.lights do
			local at = samples[math.clamp(math.floor(i / (ramp.lights + 0.5) * #samples) + 1, 1, #samples)]
			local lamp = Kit.part(root, "RampLamp", V3.new(1, 1, 1), CF.new(at.x, at.y + ramp.height - 2, at.z), C3.fromRGB(255, 220, 160), Enum.Material.Neon)
			local light = roblox.Instance.new("PointLight")
			light.Brightness = 0.6
			light.Range = 26
			light.Shadows = false
			light.Color = C3.fromRGB(255, 214, 140)
			light.Parent = lamp
		end
		local _ = last

		local function at(i)
			local s = samples[i]
			return s
		end
		local door = at(1)
		local half = at(math.floor(#samples / 2))
		local foot = at(#samples - 6)
		return {
			root = root,
			terrain = Common.terrain(ctx, 70, -290, 290, -90, 2),
			shadowRadius = 200,
			lighting = { fogNear = 500, fogFar = 1800 },
			fov = 50,
			cameras = {
				{ pos = { 172, 14, -100 }, target = { 150, 9, -148 }, label = "the mouth from town", fov = 48 },
				{ pos = { 150, 5.5, -128 }, target = { 150, 6.5, -148 }, label = "the door", fov = 52 },
				{ pos = { 250, 48, -130 }, target = { 160, 8, -180 }, label = "the hill from the east", fov = 50 },
				{ pos = { 170, 230, -190 }, target = { 170, 0, -189 }, label = "the hill from above", fov = 55 },
				{ pos = { door.x, door.y + 5.5, door.z + 1 }, target = { door.x, door.y + 2, door.z - 40 }, label = "inside, at the door", fov = 70 },
				{ pos = { half.x, half.y + 6, half.z + 6 }, target = { half.x + 10, half.y - 6, half.z - 20 }, label = "half way down", fov = 70 },
				{ pos = { half.x, half.y + 6, half.z + 6 }, target = { half.x + 10, half.y - 6, half.z - 20 }, label = "half way down at night", fov = 70, night = true },
				{ pos = { foot.x + 8, foot.y + 6, foot.z + 4 }, target = { 150, -46, -222 }, label = "the foot of the ramp", fov = 70 },
			},
		}
	end,
}
