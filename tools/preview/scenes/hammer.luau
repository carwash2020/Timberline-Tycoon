--!nocheck
-- The hammer and the rolled plans (Shared/Art/HammerArt, BlueprintArt):
-- the hammer standing side-on, three plans (Buildings blue, Decor green,
-- a machine amber) standing, one dropped, and a figure holding each the way
-- Roblox does (the arm raised, the Handle at RightGrip * Tool.Grip:Inverse()).

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local HammerArt = ctx.art("HammerArt")
		local BlueprintArt = ctx.art("BlueprintArt")
		local CharacterArt = ctx.art("CharacterArt")
		local root = roblox.Instance.new("Model")

		Kit.part(
			root,
			"Ground",
			V3.new(40, 1, 22),
			CF.new(8, -0.5, 0),
			C3.fromRGB(196, 176, 140),
			Enum.Material.WoodPlanks
		)

		-- Standing, turned so the face points -X (seen side-on from -Z).
		local hammer = HammerArt.Build()
		hammer:PivotTo(CF.new(0, 0, 0) * CF.Angles(0, math.pi / 2, 0) * hammer:GetPivot())
		hammer.Parent = root

		local ids = { "Shed", "Bench", "Warehouse" }
		for i, id in ipairs(ids) do
			local plan = BlueprintArt.Build(id)
			plan:PivotTo(CF.new(i * 2.4, 0, 0) * plan:GetPivot())
			plan.Parent = root
			local dropped = BlueprintArt.Dropped(id)
			Kit.placeAt(dropped, CF.new(i * 2.4, 0, -3.5) * CF.Angles(0, 0.4 * i, 0))
			dropped.Parent = root
		end

		local function holder(name, tool, grip, at)
			local fig = CharacterArt.Build({
				name = name,
				skin = C3.fromHex("#E8B994"),
				shirt = C3.fromHex("#B8382E"),
				stripe = C3.fromHex("#3A1A16"),
				pants = C3.fromHex("#3D5A8C"),
				hair = C3.fromHex("#5A3A22"),
				hat = "cap",
				hatColor = C3.fromHex("#4C7A3E"),
				tag = false,
			})
			local arm = fig.RightArm
			local shoulder = arm.CFrame * CF.new(0, 0.55, 0)
			local raise = shoulder * CF.Angles(math.pi / 2, 0, 0) * shoulder:Inverse()
			local moving = { arm }
			for _, d in ipairs(arm:GetDescendants()) do
				if d:IsA("BasePart") then
					table.insert(moving, d)
				end
			end
			for _, p in ipairs(moving) do
				p.CFrame = raise * p.CFrame
			end
			local rightGrip = arm.CFrame * CF.new(0, -1, 0) * CF.Angles(-math.pi / 2, 0, 0)
			tool:PivotTo(rightGrip * grip:Inverse())
			tool.Parent = fig
			Kit.placeAt(fig, at)
			fig.Parent = root
		end
		holder("HammerHolder", HammerArt.Held(), HammerArt.Grip(), CF.new(14, 0, 0))
		holder("HammerRaised", HammerArt.Held(), HammerArt.Grip(1.0), CF.new(18, 0, 0))
		holder("PlanHolder", BlueprintArt.Held("Shed"), BlueprintArt.Grip(), CF.new(22, 0, 0))

		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 40,
			fov = 35,
			cameras = {
				cam(0, 2.4, -7, 0, 1.2, 0, "the hammer, side-on"),
				cam(3.5, 3, -9, 4.8, 1, 0, "three plans standing"),
				cam(5, 6, -9, 4.8, 0.3, -3.5, "plans dropped on the ground"),
				cam(14, 3.4, -8, 14, 2.6, 0, "held: the hammer at rest"),
				cam(18, 3.4, -8, 18, 2.6, 0, "held: raised for the swing"),
				cam(22, 3.4, -8, 22, 2.6, 0, "held: a plan"),
				cam(-3, 4, 6, 0, 1.2, 0, "the claw"),
			},
		}
	end,
}
