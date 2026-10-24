--!nocheck
-- The wire spool (Shared/Art/WireArt, T420): the spool standing, next to the
-- hammer for size, and a figure holding it the way Roblox does (the arm raised,
-- the Handle at RightGrip * Tool.Grip:Inverse()). Flat-colour preview, not Studio.
--
-- STAND-IN: the real spool is five uploaded MeshParts (WireArt.Config, loaded by the
-- server with InsertService), and this tool can load neither the model nor those
-- meshes. So each of the five pieces is drawn here as a cylinder (the flanges, hub
-- and band) or an ellipsoid (the coil) of the piece's REAL listed size, colour,
-- material and position from WireArt.Config, so the proportions, the colours and
-- the 1.0 x 1.5 x 1.5 box can be judged; it is NOT the real mesh and shows none of
-- its detail. The game builds no such parts (WireArt.Build only clones the meshes).
-- Lit by the viewer's sun and sky, not by Roblox. Views:
--   1 the spool beside the hammer   2 the spool close up (assembled)   3 spool and hammer held   4 held in hand

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

		-- The stand-in pieces, from the real config (PREVIEW ONLY, see the header).
		local function standIn(model)
			for _, piece in ipairs(WireArt.Config.Pieces) do
				local at = CF.new(piece.x, 0, 0)
				local part
				if piece.name == "Coil" then
					part = Kit.ellipsoid(model, piece.name, piece.size, at, piece.color, piece.material)
				else
					-- A cylinder along X: its length is the X size, its diameter the larger of Y and Z.
					part = Kit.cylinder(
						model,
						piece.name,
						piece.size.X,
						math.max(piece.size.Y, piece.size.Z),
						at,
						piece.color,
						piece.material
					)
				end
				Kit.decor(part, false)
			end
			return model
		end
		local spool = standIn(WireArt.Build())
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
		holder("SpoolHolder", standIn(WireArt.Held()), WireArt.Grip(), CF.new(10, 0, 0))
		holder("HammerHolder", HammerArt.Held(), HammerArt.Grip(), CF.new(14, 0, 0))

		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		return {
			root = root,
			shadowRadius = 30,
			fov = 35,
			cameras = {
				cam(
					1.2,
					2.4,
					-7.5,
					1.3,
					1.1,
					0,
					"the spool beside the hammer (STAND-IN pieces of the real sizes, not the uploaded meshes)"
				),
				cam(-1.5, 2.2, -2.6, 0, 0.9, 0, "the assembled spool, close up (STAND-IN, not the uploaded meshes)"),
				cam(12, 3.4, -11, 12, 2.7, 0, "held in hand, next to the hammer in hand (spool is a STAND-IN)"),
				cam(11.2, 3.6, -9, 11.2, 2.9, 0, "held: the spool in hand (STAND-IN, not the uploaded meshes)"),
			},
		}
	end,
}
