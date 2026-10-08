--!nocheck
-- One ore rock per daylight frame, vein turned toward the camera, plus
-- the same eight in a cave. Plaques are turned 180 degrees about Y so the
-- text reads from the camera. The cave fill is preview-only.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
		local Kit = ctx.art("Kit")
		local NatureArt = ctx.art("NatureArt")
		local root = roblox.Instance.new("Model")

		local YAW = math.rad(32)
		local ELEV = math.rad(25)
		local FOV = 30

		local function bounds(model)
			local minX, minY, minZ = math.huge, math.huge, math.huge
			local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") then
					local hs = p.Size * 0.5
					local cf = p.CFrame
					for sx = -1, 1, 2 do
						for sy = -1, 1, 2 do
							for sz = -1, 1, 2 do
								local w = cf:PointToWorldSpace(V3.new(hs.X * sx, hs.Y * sy, hs.Z * sz))
								minX = math.min(minX, w.X)
								minY = math.min(minY, w.Y)
								minZ = math.min(minZ, w.Z)
								maxX = math.max(maxX, w.X)
								maxY = math.max(maxY, w.Y)
								maxZ = math.max(maxZ, w.Z)
							end
						end
					end
				end
			end
			return minX, minY, minZ, maxX, maxY, maxZ
		end

		local function plaque(text, x, z)
			local board = Kit.part(
				root,
				"Plaque",
				V3.new(4.0, 0.12, 1.15),
				CF.new(x, 0.07, z) * CF.Angles(0, math.pi + YAW, 0),
				C3.fromRGB(98, 68, 42),
				Enum.Material.Wood
			)
			Kit.signText(board, text, C3.fromRGB(250, 240, 220), { Enum.NormalId.Top })
		end

		local function put(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
		end

		-- Horizontal yaw of the vein normal that faces the camera most.
		local function veinYaw(model)
			local best, score = nil, 0
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") and p.Name == "Vein" then
					local n = p.CFrame.YVector
					local horiz = math.sqrt(n.X * n.X + n.Z * n.Z)
					local area = p.Size.X * p.Size.Z
					local s = horiz * area
					if s > score then
						best, score = n, s
					end
				end
			end
			if not best then
				-- Meshed rock: the first vein sits off the host's centre, turn
				-- that side to the camera.
				local host = model:FindFirstChild("MeshHost")
				local vein = model:FindFirstChild("MeshVein1")
				if host and vein then
					local d = vein.CFrame.Position - host.CFrame.Position
					if math.sqrt(d.X * d.X + d.Z * d.Z) > 0.05 then
						return math.atan2(d.X, d.Z)
					end
				end
				return nil
			end
			return math.atan2(best.X, best.Z)
		end

		-- Extra yaw so that vein's normal points at a camera sitting on `want`.
		local function aimYaw(model, want)
			local current = veinYaw(model)
			if not current then
				return 0
			end
			return want - current
		end

		local function frameOne(cx, lookY, cz, visH, visW)
			local fill = 0.55
			local d = (visH * math.cos(ELEV)) / (fill * 2 * math.tan(math.rad(FOV) / 2))
			local aspect = 1280 / 800
			local function hSpan(dist)
				return 2 * dist * math.tan(math.rad(FOV) / 2) * aspect
			end
			if visW > hSpan(d) * 0.72 then
				d = d * (visW / (hSpan(d) * 0.72))
			end
			local horiz = d * math.cos(ELEV)
			return {
				pos = {
					cx - math.sin(YAW) * horiz,
					lookY + d * math.sin(ELEV),
					cz - math.cos(YAW) * horiz,
				},
				target = { cx, lookY, cz },
				fov = FOV,
			}
		end

		-- OreData shapes (what Lane M passes) and ids, so the colours, materials
		-- and glow come from OreData and the mesh variant from RockModels.KindFor.
		local ores = {
			{ "HOST", nil },
			{ "COAL", { "boulder", C3.fromRGB(12, 12, 14), Enum.Material.Slate, false, "coal" } },
			{ "COPPER", { "split", C3.fromRGB(232, 120, 36), Enum.Material.Metal, false, "copper" } },
			{ "IRON", { "standing", C3.fromRGB(176, 64, 42), Enum.Material.CorrodedMetal, false, "iron" } },
			{ "SILVER", { "slab", C3.fromRGB(232, 236, 242), Enum.Material.Foil, false, "silver" } },
			{ "GOLD", { "pebbles", C3.fromRGB(250, 198, 28), Enum.Material.Metal, false, "gold" } },
			{ "OPAL", { "mossy", C3.fromRGB(214, 206, 230), Enum.Material.SmoothPlastic, true, "opal" } },
			{ "HEARTSTONE", { "split", C3.fromRGB(255, 70, 118), Enum.Material.Neon, true, "heartstone" } },
		}

		local function makeOre(spec, seed)
			if not spec then
				return NatureArt.Build("Boulder", seed, "mid", "host")
			end
			return NatureArt.OreRock(spec[1], "mid", spec[2], spec[3], spec[4], spec[5])
		end

		local cameras = {}
		local camDir = math.atan2(-math.sin(YAW), -math.cos(YAW))
		for i, ore in ipairs(ores) do
			local x = (i - 1) * 36
			local z = 0
			Kit.part(root, "Pad", V3.new(24, 1, 24), CF.new(x, -0.5, z), C3.fromRGB(116, 170, 74), Enum.Material.Grass)
			local model = makeOre(ore[2], 40 + i * 3)
			local spin = aimYaw(model, camDir)
			put(model, CF.new(x, 0, z) * CF.Angles(0, spin, 0))
			local minX, minY, minZ, maxX, maxY, maxZ = bounds(model)
			local cx = (minX + maxX) / 2
			local cz = (minZ + maxZ) / 2
			local bottom = math.max(minY, 0)
			local visH = math.max(maxY - bottom, 0.5)
			local visW = math.max(maxX - minX, maxZ - minZ)
			local reach = visW * 0.5 + 1.0
			plaque(ore[1], cx - math.sin(YAW) * reach, cz - math.cos(YAW) * reach)
			local lookY = bottom + visH * 0.05
			local cam = frameOne(cx, lookY, cz, visH, visW)
			cam.label = string.lower(ore[1])
			table.insert(cameras, cam)
		end

		-- Cave: two rows, open toward -Z. Fill lights are not part of the
		-- rocks; they only lift the walls so the shot can be read.
		local caveZ = 96
		local gap = 8.5
		local function fill(x, y, z, brightness)
			local lamp = Kit.part(root, "CaveFill", V3.new(0.2, 0.2, 0.2), CF.new(x, y, z), C3.fromRGB(16, 18, 22))
			lamp.Transparency = 1
			local light = roblox.Instance.new("PointLight")
			light.Brightness = brightness
			light.Range = 46
			light.Shadows = false
			light.Color = C3.fromRGB(198, 206, 220)
			light.Parent = lamp
		end

		-- Stone is lighter than the game's cave only in this shot, so the
		-- fill can lift the whole frame without a lamp sitting on the floor.
		Kit.part(
			root,
			"CaveFloor",
			V3.new(64, 1, 48),
			CF.new(0, -0.5, caveZ),
			C3.fromRGB(78, 76, 84),
			Enum.Material.Slate
		)
		Kit.part(
			root,
			"CaveWall",
			V3.new(64, 18, 1),
			CF.new(0, 9, caveZ + 20),
			C3.fromRGB(90, 88, 98),
			Enum.Material.Slate
		)
		Kit.part(
			root,
			"CaveWall",
			V3.new(1, 18, 48),
			CF.new(-32, 9, caveZ),
			C3.fromRGB(84, 82, 92),
			Enum.Material.Slate
		)
		Kit.part(root, "CaveWall", V3.new(1, 18, 48), CF.new(32, 9, caveZ), C3.fromRGB(84, 82, 92), Enum.Material.Slate)
		Kit.part(
			root,
			"CaveCeiling",
			V3.new(64, 1, 48),
			CF.new(0, 18, caveZ),
			C3.fromRGB(70, 68, 78),
			Enum.Material.Slate
		)

		local caveCam = {
			pos = { -math.sin(math.rad(34)) * 20, 6.2, caveZ - math.cos(math.rad(34)) * 20 },
			target = { 0, 2.4, caveZ + 1 },
			fov = 50,
			label = "cave",
			night = true,
		}
		local camX, camZ = caveCam.pos[1], caveCam.pos[3]

		local function placeCave(model, col, row)
			local x = -1.5 * gap + col * gap
			local z = caveZ - 4 + row * 9
			local want = math.atan2(camX - x, camZ - z)
			put(model, CF.new(x, 0, z) * CF.Angles(0, aimYaw(model, want), 0))
		end
		-- Front row is the one the entrance camera sees first.
		local caveOrder = { 2, 3, 8, 4, 5, 6, 7, 1 }
		for n, index in ipairs(caveOrder) do
			local spec = ores[index][2]
			local col = (n - 1) % 4
			local row = math.floor((n - 1) / 4)
			placeCave(makeOre(spec, 80 + n), col, row)
		end

		-- Behind the rocks and up at the ceiling. A lamp over the near
		-- floor blows that corner out brighter than the heartstone.
		for _, x in ipairs({ -16, -5, 6, 16 }) do
			fill(x, 15, caveZ + 6, 30)
			fill(x, 15, caveZ + 16, 24)
		end

		table.insert(cameras, caveCam)
		return {
			root = root,
			shadowRadius = 40,
			fov = FOV,
			cameras = cameras,
		}
	end,
}
