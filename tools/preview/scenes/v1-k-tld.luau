--!nocheck
-- Job 15: the 25 TLD-1 machines drawn with their real GLB meshes (manifest from
-- tools/preview/v1_k_manifest.py), at close range from several angles, each
-- exactly as MachineSkin places them (mesh origin x offset). Then a deck line.
--   PREVIEW_MESHES=<manifest.json> bash tools/preview/shoot.sh v1-k-tld [view]
-- Views: three per machine in MachineMeshes order (alphabetical, TLD-1 only),
-- then 4 of a line scene.
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local MachineMeshes = ctx.art("MachineMeshes")
		local MachineSkin = ctx.art("MachineSkin")
		local MachineArt = ctx.art("MachineArt")
		local root = roblox.Instance.new("Model")
		local cameras = {}

		local function eyeFrom(target, dir, dist)
			local e = target + dir.Unit * dist
			return { e.X, e.Y, e.Z }
		end
		local function cam(label, target, dir, dist, fov)
			table.insert(cameras, {
				pos = eyeFrom(target, dir, dist),
				target = { target.X, target.Y, target.Z },
				label = label,
				fov = fov or 34,
			})
		end
		local function floor(x, z, w, d)
			Kit.part(
				root,
				"Floor",
				V3.new(w, 0.2, d),
				CF.new(x, -0.1, z),
				C3.fromRGB(228, 224, 214),
				Enum.Material.SmoothPlastic
			)
		end

		local ids = {}
		for _, id in ipairs(MachineMeshes.Ids()) do
			if MachineMeshes.Get(id).source == "tld1" then
				table.insert(ids, id)
			end
		end
		local col, rowZ = 0, 0
		for _, id in ipairs(ids) do
			local asset = MachineMeshes.Get(id)
			local body = MachineMeshes.Piece(id, "Body")
			local size = body.size
			local reach = math.max(size.X, size.Z, size.Y)
			local x = col * 70
			local z = rowZ * 90
			local model = roblox.Instance.new("Model")
			model.Name = id
			local base =
				Kit.part(model, "Root", V3.new(1, 0.2, 1), CF.new(0, 0.1, 0), C3.new(1, 1, 1), Enum.Material.Plastic)
			base.Transparency = 1
			model.PrimaryPart = base
			local skin = MachineSkin.Prepare(id, false)
			if skin then
				MachineSkin.Commit(model, skin, CF.identity)
			end
			model:PivotTo(CF.new(x, 0.1, z))
			model.Parent = root
			floor(x, z, math.max(size.X + 12, 14), math.max(size.Z + 12, 14))
			local c = V3.new(x + body.offset.X, body.offset.Y, z + body.offset.Z)
			local pts = asset.points
			if id == "ChopSaw" then
				local head = V3.new(x, 3, z + 24)
				cam(id .. " head", head, V3.new(1.1, 0.5, -1.2), 22)
				cam(id .. " head from the outfeed", head, V3.new(-1.0, 0.45, 1.2), 22)
				cam(id .. " infeed end", V3.new(x, 1, z - 24), V3.new(1.2, 0.7, -1), 18)
				cam(id .. " middle of the deck", V3.new(x, 1, z), V3.new(1.4, 0.6, 0.3), 16)
			elseif size.Z > 14 then
				cam(id .. " front 3/4", c, V3.new(0.9, 0.55, -1.2), reach * 1.2)
				cam(id .. " rear 3/4", c, V3.new(-0.9, 0.5, 1.2), reach * 1.2)
				cam(id .. " side (+X, panel)", c, V3.new(1.4, 0.35, 0), reach * 1.3)
				cam(id .. " deck close-up", V3.new(x, 1, z - size.Z / 2 + 2.5), V3.new(0.5, 0.9, -0.8), 12)
			else
				cam(id .. " front 3/4", c, V3.new(0.9, 0.6, -1.2), reach * 1.9)
				cam(id .. " rear 3/4", c, V3.new(-0.9, 0.55, 1.2), reach * 1.9)
				cam(id .. " side (+X)", c, V3.new(1.4, 0.35, 0), reach * 2.0)
			end
			col += 1
			if col >= 5 then
				col = 0
				rowZ += 1
			end
		end

		-- A deck line with the real builders: funnel, straight, mill, straight, planer,
		-- straight, turn, chop saw stub (all on one -Z to +Z run at x = -300).
		local lx, lz = -300, 0
		local function put(model, len, yaw)
			model:PivotTo(CF.new(lx, 0.1, lz + len / 2) * (yaw or CF.identity))
			model.Parent = root
			lz += len
		end
		put(MachineArt.BuildBelt("ConveyorFunnel", false), 8)
		put(MachineArt.BuildBelt("ConveyorStraight", false), 8)
		put(MachineArt.Build("SawmillSturdy", false), 14)
		put(MachineArt.BuildBelt("ConveyorStraight", false), 8)
		put(MachineArt.BuildPlaner("PlanerBench", false), 10)
		put(MachineArt.BuildBelt("ConveyorStraight", false), 8)
		put(MachineArt.BuildBelt("ConveyorStraight", false), 8)
		floor(lx, 36, 22, 80)
		cam("line, from the funnel", V3.new(lx, 3, 14), V3.new(0.6, 0.5, -1), 34)
		cam("line, mill and planer", V3.new(lx, 3, 36), V3.new(1.1, 0.5, 0.3), 38)
		cam("line, the joints (deck top, rollers across the seam)", V3.new(lx, 1, 8), V3.new(0.9, 0.5, 0.2), 9)
		cam("line, from the outfeed end", V3.new(lx, 3, 40), V3.new(-0.3, 0.45, 1), 44)

		return {
			root = root,
			shadowRadius = 90,
			fov = 34,
			background = "#f3f0e8",
			hud = false,
			lighting = {
				sunDir = { -0.35, 0.9, -0.25 },
				sunColor = "#fff4e4",
				sunIntensity = 1.7,
				skyTop = "#f3f0e8",
				skyBottom = "#f7f4ee",
				ground = "#e4dfd4",
				hemiIntensity = 1.15,
				ambient = 0.72,
				fog = "#f3f0e8",
				fogNear = 600,
				fogFar = 1400,
				exposure = 1.12,
				bloom = 0.05,
			},
			cameras = cameras,
		}
	end,
}
