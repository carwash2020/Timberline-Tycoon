--!nocheck
-- Lane W (job 08): the practical automation pieces in a working line.
--   view 1  a sorting line: laser pair, detector, sweeper, switch belt
--   view 2  a Tilted Belt up onto Belt Supports
--   view 3  close-up: the sweeper swung down, the laser beam
--   view 4  close-up: Switch Belt as placed and flipped, Wood Detector
-- Part builds per TLD-1 (mesh slot 0 until job 15 wires the meshes).

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local MachineArt = ctx.art("MachineArt")
		local PlotData = ctx.shared("PlotData")
		local BlueprintModels = ctx.shared("BlueprintModels")
		local root = roblox.Instance.new("Model")

		Kit.part(
			root,
			"Ground",
			V3.new(200, 1, 160),
			CF.new(0, -0.5, 0),
			C3.fromRGB(196, 176, 140),
			Enum.Material.Grass
		)

		local function belt(id, cf, attrs)
			local model = MachineArt.BuildBelt(id, false)
			for k, v in pairs(attrs or {}) do
				model:SetAttribute(k, v)
			end
			if model:GetAttribute("Flip") then
				MachineArt.SetSwitchSide(model, -1)
			end
			model:PivotTo(cf)
			model.Parent = root
			return model
		end
		local function item(id, cf)
			local model = BlueprintModels.Build(PlotData.Blueprint(id), false)
			model:PivotTo(cf)
			model.Parent = root
			return model
		end
		local oak = C3.fromRGB(176, 128, 82)
		local birch = C3.fromRGB(226, 214, 190)
		local function log(cf, color)
			Kit.part(root, "Log", V3.new(1.1, 1.1, 4), cf, color, Enum.Material.Wood)
		end
		-- The arm swung down across the belt, the pose LogicService sets.
		local function sweepDown(model)
			local base = model:FindFirstChild("Root") or model.PrimaryPart
			local pivot = CF.new(0, 1.72, 0)
			for _, name in ipairs({ "Part3", "Part4" }) do
				local p = model:FindFirstChild(name, true)
				if p and base then
					local rest = base.CFrame:ToObjectSpace(p.CFrame)
					p.CFrame = base.CFrame * pivot * CF.Angles(0, 0, -math.pi / 2) * pivot:Inverse() * rest
				end
			end
		end
		local function beam(emitter, receiver)
			local a = emitter:GetPivot() * V3.new(0, 1.92, 0.72)
			local b = receiver:GetPivot() * V3.new(0, 1.92, -0.64)
			local part = Kit.part(
				root,
				"Beam",
				V3.new((b - a).Magnitude, 0.08, 0.08),
				CF.lookAt((a + b) / 2, b) * CF.Angles(0, math.pi / 2, 0),
				C3.fromHex("#6FB7E8"),
				Enum.Material.Neon
			)
			if part then
				part.Shape = Enum.PartType.Cylinder
				part.Transparency = 0.15
			end
		end
		local face = CF.Angles(0, math.pi / 2, 0) -- local +Z to world +X

		-- View 1: a sorting line running +Z.
		belt("ConveyorStraight", CF.new(0, 0, 0))
		belt("ConveyorStraight", CF.new(0, 0, -8))
		belt("WoodDetector", CF.new(0, 0, 6))
		belt("ConveyorStraight", CF.new(0, 0, 12))
		belt("SwitchBelt", CF.new(0, 0, 20))
		belt("ConveyorStraight", CF.new(-10, 0, 20) * CF.Angles(0, math.pi / 2, 0))
		belt("ConveyorStraight", CF.new(10, 0, 20) * CF.Angles(0, -math.pi / 2, 0), { Reversed = true })
		local e1 = item("LaserEmitter", CF.new(-4.5, 0, -6) * face)
		local r1 = item("LaserReceiver", CF.new(4.5, 0, -6) * face)
		beam(e1, r1)
		item("WoodSweeper", CF.new(-4, 0, 13))
		item("SparkSwitch", CF.new(-6, 0, 6))
		log(CF.new(0, 1.3, -2), oak)
		log(CF.new(0, 1.3, 13), birch)
		log(CF.new(-9, 1.3, 20) * face, oak)

		-- View 2: up a Tilted Belt onto Belt Supports.
		belt("ConveyorStraight", CF.new(50, 0, 0))
		belt("TiltedBelt", CF.new(50, 0, 8))
		belt("BeltSupport", CF.new(50, 0, 13))
		belt("BeltSupport", CF.new(50, 0, 19))
		belt("ConveyorStraight", CF.new(50, 2, 16))
		log(CF.new(50, 3.3, 16), birch)

		-- View 3: sweeper down, laser close.
		belt("ConveyorStraight", CF.new(-50, 0, 0))
		local sw = item("WoodSweeper", CF.new(-54, 0, 0))
		sweepDown(sw)
		log(CF.new(-50, 1.3, 2.4), oak)
		local e2 = item("LaserEmitter", CF.new(-54.5, 0, -6) * face)
		local r2 = item("LaserReceiver", CF.new(-45.5, 0, -6) * face)
		beam(e2, r2)

		-- View 4: Switch Belt as placed and flipped, a detector.
		belt("SwitchBelt", CF.new(-20, 0, 50))
		belt("SwitchBelt", CF.new(0, 0, 50), { Flip = true })
		belt("WoodDetector", CF.new(20, 0, 50))

		local function cam(cx, cy, cz, tx, ty, tz, label)
			return { pos = { cx, cy, cz }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 120,
			fov = 40,
			cameras = {
				cam(30, 28, -26, 0, 1, 8, "a sorting line"),
				cam(68, 10, 4, 50, 1.5, 12, "tilted belt onto supports"),
				cam(-40, 8, -14, -50, 1.5, -2, "sweeper down, laser beam"),
				cam(0, 42, 8, 0, 1, 50, "switch belt placed and flipped, detector"),
			},
		}
	end,
}
