--!nocheck
-- Job 15 (K wire-in): the Blender machine meshes on the plot machines and the
-- logic pieces, one close-up per machine. The meshes come from a preview-only
-- manifest (tools/preview/v1_k_manifest.py), so a machine whose GLB is not in
-- the pack keeps its part build here exactly as the game does when a mesh does
-- not load; it is never drawn with a stand-in box.
--
--   PREVIEW_MESHES=<manifest.json> bash tools/preview/shoot.sh v1-k [view]
--
-- Views (one camera each, 1920x1080 or 667x375 by the size argument):
--   logic   1 to 13   the Sparkworks pieces, each in the pose the game builds it
--   posed   14 to 17  lever on, switch on, hatch open, button pressed
--   stall   18 to 20  the prospector stall with its chute, the craft bench
--   court   21        the Sky Forge Court name board, up close
--   mills   22 on  the part-built TLD-1 sawmills, planers and the chop saw (only when
--                     their GLBs are not in the manifest)
return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local MachineArt = ctx.art("MachineArt")
		local MachineSkin = ctx.art("MachineSkin")
		local MiningArt = ctx.load("ReplicatedStorage/Shared/Mining/MiningArt")
		local BuildingArt = ctx.art("BuildingArt")
		local PlotData = ctx.shared("PlotData")
		local Models = ctx.shared("BlueprintModels")
		local Catalog = ctx.shared("ItemCatalog")
		local PlanerLogic = ctx.shared("PlanerLogic")
		local root = roblox.Instance.new("Model")

		local cameras = {}
		local function cam(label, target, dir, dist, fov)
			local eye = V3.new(target[1], target[2], target[3]) + dir.Unit * dist
			table.insert(cameras, {
				pos = { eye.X, eye.Y, eye.Z },
				target = target,
				label = label,
				fov = fov or 30,
			})
		end

		local function floor(x, z, w, d)
			Kit.part(
				root,
				"Floor",
				V3.new(w, 0.2, d),
				CF.new(x, -0.1, z),
				C3.fromRGB(232, 228, 220),
				Enum.Material.SmoothPlastic
			)
		end

		-- The logic pieces (symbol, inputs and lever lean toward +Z).
		-- id, height, and the camera's distance for a 3/4 view that keeps the whole piece in frame.
		local LOGIC = {
			{ "Button", 1.15, 4.5 },
			{ "Lever", 3.05, 8 },
			{ "PressurePlate", 0.54, 8 },
			{ "SparkSwitch", 3.93, 9 },
			{ "SparkLamp", 5.35, 12 },
			{ "Hatch", 1.72, 9 },
			{ "GateAnd", 0.98, 5 },
			{ "GateOr", 0.98, 5 },
			{ "GateXor", 0.98, 5 },
			{ "GateNot", 0.98, 5 },
			{ "Delay", 1.32, 5 },
			{ "Clock", 0.8, 5 },
			{ "Sustain", 1.32, 5 },
		}
		local x = -48
		local placed = {}
		for _, entry in ipairs(LOGIC) do
			local id = entry[1]
			local model = Models.Build(PlotData.Blueprint(id), false)
			model:PivotTo(CF.new(x, 0, 0))
			model.Parent = root
			placed[id] = { x = x, model = model }
			cam(id, { x, entry[2] / 2, 0 }, V3.new(0.55, 0.5, 1), entry[3])
			x += 7
		end
		floor(-48 + 7 * (#LOGIC - 1) / 2, 0, 7 * #LOGIC + 4, 10)

		-- Poses: the moving mesh swings about its hinge.
		local function posed(id, label, on, h, dist)
			local px = placed[id].x
			local model = Models.Build(PlotData.Blueprint(id), false)
			model:PivotTo(CF.new(px, 0, 30))
			model.Parent = root
			local moving = model:FindFirstChild("Moving")
			if moving and MachineSkin.Hinged(moving) then
				MachineSkin.PoseAbout(model, moving, on)
			elseif moving then
				moving.CFrame = moving.CFrame * CF.new(0, if on then -0.08 else 0, 0)
			end
			cam(label, { px, h, 30 }, V3.new(0.55, 0.5, 1), dist)
		end
		posed("Lever", "Lever on", true, 1.5, 8)
		posed("SparkSwitch", "Wall Switch on", true, 2.0, 9)
		posed("Hatch", "Hatch open", true, 0.9, 9)
		posed("Button", "Button pressed", true, 0.6, 4.5)
		floor(-48 + 7 * 5, 30, 7 * 6 + 4, 10)

		-- The mining pad's stall (with its Ore Chute) and the craft bench.
		local stall = MiningArt.Prospector()
		stall:PivotTo(CF.new(-20, 0, 60))
		stall.Parent = root
		cam("Prospector stall and Ore Chute", { -18, 2.2, 60 }, V3.new(0.35, 0.35, -1), 13, 34)
		local chute = stall:FindFirstChild("OreChute", true)
		cam("Ore Chute", { -15.8, 1.1, 60 }, V3.new(0.7, 0.35, -1), 5.5, 32)
		local bench = MiningArt.CraftBench()
		bench:PivotTo(CF.new(0, 0, 60))
		bench.Parent = root
		cam("Craft Bench", { 0, 1.3, 60 }, V3.new(0.6, 0.45, -1), 5.5, 30)
		floor(-8, 60, 36, 12)

		-- The Sky Forge Court's name board.
		local court = BuildingArt.SkyForgeCourt()
		Kit.placeAt(court, CF.new(60, 0, 100))
		court.Parent = root
		cam("Sky Forge Court sign", { 60, 6.2, 111.05 }, V3.new(0.12, 0.02, -1), 11, 30)

		-- The TLD-1 machines (their GLBs are not in the pack: the part build, labelled as such).
		local mx = 100
		for _, mill in ipairs(Catalog.SawmillList()) do
			local model = MachineArt.Build(mill.id, false)
			model:PivotTo(CF.new(mx + mill.width / 2, 0, 0))
			model.Parent = root
			cam(mill.id .. " (part build)", { mx + mill.width / 2, 3, 0 }, V3.new(1.0, 0.6, -1.4), mill.depth * 1.6, 36)
			mx += mill.width + 6
		end
		for _, machine in ipairs(PlanerLogic.List()) do
			local def = machine.planer
			local model = MachineArt.BuildPlaner(machine.id, false)
			model:PivotTo(CF.new(mx + def.width / 2, 0, 0))
			model.Parent = root
			cam(
				machine.id .. " (part build)",
				{ mx + def.width / 2, 3, 0 },
				V3.new(1.0, 0.6, -1.4),
				def.depth * 1.8,
				36
			)
			mx += def.width + 6
		end

		return {
			root = root,
			shadowRadius = 60,
			fov = 30,
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
				fogNear = 400,
				fogFar = 900,
				exposure = 1.12,
				bloom = 0.05,
			},
			cameras = cameras,
		}
	end,
}
