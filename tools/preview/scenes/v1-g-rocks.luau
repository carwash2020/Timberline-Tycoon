--!nocheck
-- One nature rock per frame. Camera is a 3/4 view, 25 degrees up, far
-- enough that the rock is about 55% of the frame height. The plaque lies
-- on the grass in front of it, turned 180 degrees about Y so the top-face
-- text reads from this side of the rock.
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

		local grounds = {
			meadow = { C3.fromRGB(116, 170, 74), Enum.Material.Grass },
			snow = { C3.fromRGB(214, 222, 230), Enum.Material.Sand },
			shore = { C3.fromRGB(196, 176, 130), Enum.Material.Sand },
			volcano = { C3.fromRGB(128, 116, 106), Enum.Material.Slate },
			gloam = { C3.fromRGB(58, 52, 72), Enum.Material.Slate },
			cave = { C3.fromRGB(118, 114, 124), Enum.Material.Slate },
		}

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

		-- Text on the top face reads upside down from the -Z side until the
		-- board is turned 180 degrees. Add the camera's yaw so "up" on the
		-- plaque points away from this 3/4 view.
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

		-- Distance where a vertical span `visH` covers `fill` of the frame.
		local function frameOne(cx, lookY, cz, visH, visW)
			local fill = 0.42
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

		local rocks = {
			{ "Boulder", "meadow", "MOSS", "boulder" },
			{ "CrackedBoulder", "snow", "SNOW", "crackedboulder" },
			{ "Spire", "shore", "SAND", "spire" },
			{ "Slab", "volcano", "BASALT", "slab" },
			{ "PebbleCluster", "gloam", "GLOAM", "pebblecluster" },
			{ "Outcrop", "cave", "CAVE", "outcrop" },
		}

		local cameras = {}
		for i, row in ipairs(rocks) do
			local x = (i - 1) * 40
			local z = 0
			local ground = grounds[row[2]]
			Kit.part(root, "Pad", V3.new(28, 1, 28), CF.new(x, -0.5, z), ground[1], ground[2])
			local model = NatureArt.Build(row[1], i * 19, "large", row[2])
			put(model, CF.new(x, 0, z))
			local minX, minY, minZ, maxX, maxY, maxZ = bounds(model)
			local cx = (minX + maxX) / 2
			local cz = (minZ + maxZ) / 2
			local bottom = math.max(minY, 0)
			local visH = math.max(maxY - bottom, 0.5)
			local visW = math.max(maxX - minX, maxZ - minZ)
			local reach = math.max(visW, maxZ - minZ, maxX - minX) * 0.42 + 0.95
			plaque(row[3], cx - math.sin(YAW) * reach, cz - math.cos(YAW) * reach)
			local lookY = bottom + visH * 0.0
			local cam = frameOne(cx, lookY, cz, visH, visW)
			cam.label = row[4]
			do
				local n = 0
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") then
						n += 1
					end
				end
				cam.own = n
			end
			table.insert(cameras, cam)
		end

		return {
			root = root,
			shadowRadius = 40,
			fov = FOV,
			cameras = cameras,
		}
	end,
}
