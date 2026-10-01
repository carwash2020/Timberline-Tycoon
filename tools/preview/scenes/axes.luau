--!nocheck
-- Every axe (Shared/Art/AxeArt, in ItemCatalog's ladder order), standing
-- side-on so the silhouettes read, labelled, with its dropped version lying
-- in front; then two figures holding axes the way Roblox does (the arm
-- raised, the tool's Handle at RightGrip * Tool.Grip:Inverse()), to check
-- the grip.

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local AxeArt = ctx.art("AxeArt")
		local CharacterArt = ctx.art("CharacterArt")
		local ItemCatalog = ctx.shared("ItemCatalog")
		local root = roblox.Instance.new("Model")

		local axes = ItemCatalog.AxeLadder()
		local GAP = 3
		local width = (#axes - 1) * GAP
		Kit.part(
			root,
			"Ground",
			V3.new(width + 30, 1, 26),
			CF.new(width / 2 + 4, -0.5, 2),
			C3.fromRGB(196, 176, 140),
			Enum.Material.WoodPlanks
		)
		for i, def in ipairs(axes) do
			local x = (i - 1) * GAP
			-- Standing, turned so the blade points -X (seen side-on from -Z).
			local axe = AxeArt.Build(def)
			axe:PivotTo(CF.new(x, 0, 0) * CF.Angles(0, math.pi / 2, 0) * axe:GetPivot())
			axe.Parent = root
			local dropped = AxeArt.Dropped(def)
			Kit.placeAt(dropped, CF.new(x, 0, -4.2) * CF.Angles(0, math.pi / 2 - 0.3, 0))
			dropped.Parent = root
			local sign = Kit.part(
				root,
				"Label",
				V3.new(2.7, 0.8, 0.2),
				CF.new(x, 0.4, -6.8),
				C3.fromRGB(110, 74, 44),
				Enum.Material.Wood
			)
			Kit.signText(sign, def.displayName, C3.fromRGB(250, 240, 220), { Enum.NormalId.Front })
		end

		-- Holding axes: R6's RightGrip is the arm's bottom face, its -Z down
		-- the arm; the "hold" pose raises the arm forward.
		local function holder(name, axeId, at)
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
			local def = ItemCatalog.GetAxe(axeId)
			local axe = AxeArt.Held(def)
			local grip = arm.CFrame * CF.new(0, -1, 0) * CF.Angles(-math.pi / 2, 0, 0)
			axe:PivotTo(grip * AxeArt.Grip(def):Inverse())
			axe.Parent = fig
			Kit.placeAt(fig, at)
			fig.Parent = root
		end
		holder("Holder1", "SteelAxe", CF.new(width + 6, 0, 0))
		holder("Holder2", "InfernoAxe", CF.new(width + 11, 0, 0) * CF.Angles(0, -0.6, 0))

		local function cam(x, y, z, tx, ty, tz, label)
			return { pos = { x, y, z }, target = { tx, ty, tz }, label = label }
		end
		local function at(i)
			return (i - 1) * GAP
		end
		return {
			root = root,
			shadowRadius = 60,
			fov = 35,
			cameras = {
				cam(width / 2, 4, -26, width / 2, 1.6, 0, "the ladder, side-on"),
				cam(at(2), 2.6, -9, at(2), 2.2, 0, "Rusty, Steel, Hardened"),
				cam(at(5), 2.6, -9, at(5), 2.2, 0, "Silver, Cobalt, Gold"),
				cam(at(8), 2.6, -9, at(8), 2.2, 0, "Obsidian, Inferno, Starfall"),
				cam(width / 2, 7, -12, width / 2, 0, -4.5, "dropped on the ground"),
				cam(width / 2 + 6, 3, 14, width / 2, 2, 0, "from behind (blades)"),
				cam(width + 3, 6, -10, width + 8.5, 3.5, 0, "held: the grip"),
				cam(width + 19, 5.5, 9.5, width + 8.5, 4, 0, "held, from the side and behind"),
				cam(at(9), 2.8, -4.2, at(9), 2.8, 0, "Starfall up close"),
				cam(at(7) - 1.5, 3.4, -4.4, at(7), 2.8, 0, "Obsidian up close"),
				cam(at(1) + 1.2, 2.8, -4, at(1), 2.4, 0, "Rusty up close"),
			},
		}
	end,
}
