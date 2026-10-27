--!nocheck
-- T410-fix: square Block wood, the live look. Views:
--   1  standing oak, notch on the hit face
--   2  that notch, close
--   3  two Block logs fallen toward the notch, and one square stump
--   4  birch, standing and felled
--   5  a bunk with a square log and a plank (a storyboard, not the plot mill)
--   6  top-down of the fell; a red block marks an overlap if one exists
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		local TreeGen = ctx.shared("TreeGen")
		local StumpLogic = ctx.shared("StumpLogic")
		local WoodData = ctx.shared("WoodData")
		local SectionMetrics = ctx.shared("SectionMetrics")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 90, nil, V3.new(16, -0.5, 8))

		local function place(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
			return model
		end

		-- One trunk section, length along Y, square side t.
		local function trunk(def, seed, length)
			local skel = TreeGen.Skeleton(def.id, seed, 1)
			local sec = skel.sections[1]
			local fake = {
				woodId = def.id,
				seed = seed,
				scale = 1,
				stage = 1,
				elder = false,
				trunkSegments = 1,
				maxDepth = 0,
				height = sec.thickness,
				width = sec.thickness,
				stretch = 1,
				sections = {
					{
						id = 1,
						children = {},
						depth = 0,
						cf = CF.identity,
						length = length or sec.length,
						thickness = sec.thickness,
						dress = {},
					},
				},
			}
			local log = TreeArt.FromSkeleton(def, fake)
			local p = log.PrimaryPart
			local side = math.min(p.Size.X, p.Size.Z)
			return log, p.Size.Y, side
		end

		-- Lay a Block so its length runs along +X and the bark sits on the ground.
		local function layAlongX(def, seed, originX, length)
			local log, L, side = trunk(def, seed, length)
			local cf = CF.new(originX + L / 2, side / 2, 0) * CF.Angles(0, 0, -math.pi / 2)
			place(log, cf)
			TreeArt.CutFace(def, log.PrimaryPart, true)
			TreeArt.CutFace(def, log.PrimaryPart, false)
			return L, side, log
		end

		local oak = WoodData.Get("oak")
		local birch = WoodData.Get("birch")

		-- Standing oak. The notch is on the +X face; the fall goes that way.
		local standing = place(TreeArt.FromSkeleton(oak, TreeGen.Skeleton("oak", 1, 1)), CF.new(0, 0, 0))
		local trunkPart = standing.PrimaryPart
		TreeArt.Notch(oak, trunkPart, 4.2, V3.new(1, 0, 0), 1, 1)

		-- The felled oak: one square stump, then two Block logs toward +X.
		local skel = TreeGen.Skeleton("oak", 2, 1)
		local foot = skel.sections[1].thickness
		local shape = StumpLogic.Shape({ { length = 20, thickness = foot } }, 3.2)
		local stumpAt = V3.new(14, 0, 0)
		TreeArt.StumpDress(oak, root, CF.new(stumpAt), shape, {})
		local side = foot
		local gap = 0.4
		local firstX = stumpAt.X + side / 2 + gap
		local len1 = layAlongX(oak, 3, firstX, 7)
		layAlongX(oak, 4, firstX + len1 + gap, 6)

		-- Birch, same story, smaller.
		place(TreeArt.FromSkeleton(birch, TreeGen.Skeleton("birch", 1, 1)), CF.new(0, 0, 22))
		local birchLog, birchLen, birchSide = trunk(birch, 2, nil)
		place(birchLog, CF.new(8 + birchLen / 2, birchSide / 2, 22) * CF.Angles(0, 0, -math.pi / 2))
		TreeArt.CutFace(birch, birchLog.PrimaryPart, true)
		TreeArt.CutFace(birch, birchLog.PrimaryPart, false)

		-- A bunk and a plank. Props only: not the plot mill or the planer.
		local deck = Kit.part(
			root,
			"Bunk",
			V3.new(4, 0.4, 12),
			CF.new(-10, 0.6, 22),
			C3.fromHex("6B4A2E"),
			roblox.Enum.Material.Wood
		)
		Kit.part(
			root,
			"Stake",
			V3.new(0.3, 1.4, 0.3),
			deck.CFrame * CF.new(-1.6, 0.9, 5),
			C3.fromHex("5A3E28"),
			roblox.Enum.Material.Wood
		)
		Kit.part(
			root,
			"Stake",
			V3.new(0.3, 1.4, 0.3),
			deck.CFrame * CF.new(1.6, 0.9, 5),
			C3.fromHex("5A3E28"),
			roblox.Enum.Material.Wood
		)
		Kit.part(
			root,
			"Stake",
			V3.new(0.3, 1.4, 0.3),
			deck.CFrame * CF.new(-1.6, 0.9, -5),
			C3.fromHex("5A3E28"),
			roblox.Enum.Material.Wood
		)
		Kit.part(
			root,
			"Stake",
			V3.new(0.3, 1.4, 0.3),
			deck.CFrame * CF.new(1.6, 0.9, -5),
			C3.fromHex("5A3E28"),
			roblox.Enum.Material.Wood
		)
		local bunkLog, bunkLen, bunkSide = trunk(oak, 5, 8)
		place(bunkLog, CF.new(-10, 0.8 + bunkSide / 2, 22 - bunkLen / 2) * CF.Angles(math.pi / 2, 0, 0))
		TreeArt.CutFace(oak, bunkLog.PrimaryPart, true)
		local plank = Kit.part(
			root,
			"Plank",
			V3.new(1.2, 0.2, 6),
			CF.new(-10, 0.9, 14),
			C3.fromHex("E2BE84"),
			roblox.Enum.Material.Wood
		)
		plank.Name = "Plank"

		-- Top-down overlap mark. Sections of the felled logs and the stump.
		local function boxOf(p)
			local cf, size = SectionMetrics.BlockFrame(p)
			local s = size / 2
			local ext = V3.new(
				math.abs(cf.XVector.X) * s.X + math.abs(cf.YVector.X) * s.Y + math.abs(cf.ZVector.X) * s.Z,
				math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z,
				math.abs(cf.XVector.Z) * s.X + math.abs(cf.YVector.Z) * s.Y + math.abs(cf.ZVector.Z) * s.Z
			)
			return cf.Position - ext, cf.Position + ext
		end
		local watched = {}
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("BasePart") and (d.Name == "Section" or d.Name == "StumpMesh") and d.CFrame.Position.Z < 8 then
				table.insert(watched, d)
			end
		end
		for i = 1, #watched do
			local a0, a1 = boxOf(watched[i])
			for j = i + 1, #watched do
				local b0, b1 = boxOf(watched[j])
				local overlap = a0.X < b1.X - 0.05
					and a1.X > b0.X + 0.05
					and a0.Y < b1.Y - 0.05
					and a1.Y > b0.Y + 0.05
					and a0.Z < b1.Z - 0.05
					and a1.Z > b0.Z + 0.05
				if overlap then
					local mid = (
						V3.new(math.max(a0.X, b0.X), math.max(a0.Y, b0.Y), math.max(a0.Z, b0.Z))
						+ V3.new(math.min(a1.X, b1.X), math.min(a1.Y, b1.Y), math.min(a1.Z, b1.Z))
					) / 2
					Kit.part(
						root,
						"Overlap",
						V3.new(1.2, 0.2, 1.2),
						CF.new(mid + V3.new(0, 2, 0)),
						C3.fromRGB(220, 30, 30),
						roblox.Enum.Material.Neon
					)
				end
			end
		end

		local cams = {}
		local function cam(pos, target, text, extra)
			local c = { pos = pos, target = target, label = text }
			if extra then
				for k, v in pairs(extra) do
					c[k] = v
				end
			end
			table.insert(cams, c)
		end
		cam({ 8, 6, -18 }, { 0, 8, 0 }, "1 standing oak, notch on the hit face", { fov = 42 })
		cam({ 3.2, 4.4, -2.2 }, { 1.1, 4.2, 0 }, "2 the notch, close", { fov = 28 })
		cam({ 20, 4, -14 }, { 20, 1.5, 0 }, "3 two Block logs and a square stump", { fov = 40 })
		cam({ 8, 5, 8 }, { 4, 6, 22 }, "4 birch", { fov = 46 })
		cam({ -18, 4, 14 }, { -10, 1.2, 20 }, "5 bunk, square log, plank", { fov = 40 })
		cam({ 22, 40, 0.01 }, { 22, 0, 0 }, "6 top-down of the fell", { fov = 36 })
		return {
			root = root,
			shadowRadius = 90,
			cameras = cams,
		}
	end,
}
