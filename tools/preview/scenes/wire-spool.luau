--!nocheck
-- The wire spool (Shared/Art/WireArt, T420): the spool standing, next to the
-- hammer for size, and a figure holding it the way Roblox does (the arm raised,
-- the Handle at RightGrip * Tool.Grip:Inverse()). Flat-colour preview, not Studio.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local HammerArt = ctx.art("HammerArt")
		local WireArt = ctx.art("WireArt")
		local CharacterArt = ctx.art("CharacterArt")
		local root = roblox.Instance.new("Model")

		Kit.part(
			root,
			"Ground",
			V3.new(30, 1, 18),
			CF.new(6, -0.5, 0),
			C3.fromRGB(196, 176, 140),
			Enum.Material.WoodPlanks
		)

		local spool = WireArt.Build()
		spool:PivotTo(CF.new(0, 0.9, 0) * spool:GetPivot())
		spool.Parent = root
		local hammer = HammerArt.Build()
		hammer:PivotTo(CF.new(2.4, 0, 0) * CF.Angles(0, math.pi / 2, 0) * hammer:GetPivot())
		hammer.Parent = root

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
		holder("SpoolHolder", WireArt.Held(), WireArt.Grip(), CF.new(10, 0, 0))

		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 30,
			fov = 35,
			cameras = {
				cam(0.8, 2.4, -4, 0.8, 0.9, 0, "the spool beside the hammer"),
				cam(-1.5, 2.2, -2.6, 0, 0.9, 0, "the spool close up"),
				cam(10, 3.4, -8, 10, 2.6, 0, "held: the spool in hand"),
			},
		}
	end,
}
