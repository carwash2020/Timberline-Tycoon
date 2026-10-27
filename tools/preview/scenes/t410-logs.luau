--!nocheck
-- T410: oak and birch, standing and felled, so Art can compare block trunks
-- with round bark logs. Views:
--   1  oak, day, standing trunk and a felled log (bark and cut face)
--   2  birch, the same
--   3  close-up of the oak log's end (bark ring and core)
--   4  oak silhouette, low and to the side
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Kit = ctx.art("Kit")
		local TreeArt = ctx.art("TreeArt")
		-- Part-built on purpose: this shot is the block-versus-cylinder fallback.
		-- Uploaded section meshes replace it in game when they load.
		local MeshKit = ctx.art("MeshKit")
		MeshKit.Override = function()
			return nil
		end
		local TreeGen = ctx.shared("TreeGen")
		local WoodData = ctx.shared("WoodData")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 80, nil, V3.new(20, -0.5, 10))

		local function place(model, cf)
			Kit.placeAt(model, cf)
			model.Parent = root
			return model
		end

		-- Lays a single-section log so its length runs along world Z and its
		-- bark sits on the ground. A block's length is Y; a cylinder's is X
		-- and already stands up, so both tip with the same parent turn.
		local function lay(def, seed)
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
						length = sec.length,
						thickness = sec.thickness,
						dress = {},
					},
				},
			}
			local log = TreeArt.FromSkeleton(def, fake)
			local p = log.PrimaryPart
			local length, lift
			-- Lune's Part has no Shape until one is assigned. An unset shape is a block.
			local okShape, shape = pcall(function()
				return p.Shape
			end)
			local cylinder = okShape and shape == roblox.Enum.PartType.Cylinder
			if cylinder then
				length = p.Size.X
				lift = math.min(p.Size.Y, p.Size.Z) / 2
			else
				length = p.Size.Y
				lift = math.min(p.Size.X, p.Size.Z) / 2
			end
			return log, length, lift
		end

		local function fell(def, seed, centre)
			local log, length, lift = lay(def, seed)
			Kit.placeAt(log, CF.new(centre.X, lift, centre.Z - length / 2) * CF.Angles(math.pi / 2, 0, 0))
			log.Parent = root
			TreeArt.CutFace(def, log.PrimaryPart, true)
			TreeArt.CutFace(def, log.PrimaryPart, false)
			return length
		end

		local oak = WoodData.Get("oak")
		local birch = WoodData.Get("birch")
		place(TreeArt.FromSkeleton(oak, TreeGen.Skeleton("oak", 1, 1)), CF.new(0, 0, 0))
		local oakLen = fell(oak, 2, V3.new(7, 0, 6))
		place(TreeArt.FromSkeleton(birch, TreeGen.Skeleton("birch", 1, 1)), CF.new(36, 0, 0))
		fell(birch, 2, V3.new(43, 0, 6))

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
		cam({ 10, 5, -16 }, { 4, 7, 2 }, "1 oak trunk and felled log", { fov = 48 })
		cam({ 46, 5, -16 }, { 40, 8, 2 }, "2 birch trunk and felled log", { fov = 48 })
		-- The log's +Z end, close enough to read bark and the core disc.
		cam({ 7, 1.6, 6 + oakLen / 2 + 5 }, { 7, 1.1, 6 }, "3 oak log end, bark and core", { fov = 32 })
		cam({ -28, 3, -8 }, { 0, 14, 0 }, "4 oak silhouette", { fov = 40 })
		return {
			root = root,
			shadowRadius = 80,
			cameras = cams,
		}
	end,
}
