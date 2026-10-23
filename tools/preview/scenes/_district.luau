--!nocheck
-- The plot district's corner for the T420 renders: the East Link (28 wide,
-- z 66 to 94, curbs), the PLOT DISTRICT sign exactly as WorldPlan places it,
-- real terrain, and Old Hank built as NPCService builds him (CharacterArt,
-- his own look) at `hankAt` facing `lookAt`. The Land Office counter box was
-- built by PlotService (a server module), so the "before" view cannot draw
-- it: it shows only where Hank stood. Lit by the viewer's sun, ambient and
-- shadows (three.js), an approximation of Roblox lighting, not Studio.

local Common = require("./_common")

local District = {}

function District.scene(ctx, hankAt, hankLook, views)
	local roblox = ctx.roblox
	local V3, CF, C3, Enum = roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
	local Kit = ctx.art("Kit")
	local BuildingArt = ctx.art("BuildingArt")
	local CharacterArt = ctx.art("CharacterArt")
	local NPCData = ctx.shared("NPCData")
	local TerrainGen = ctx.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
	local root = roblox.Instance.new("Model")

	-- The East Link, flat on the real ground, with its curbs.
	local function strip(name, x0, x1, z0, z1, color, mat, lift)
		local y = TerrainGen.HeightAt((x0 + x1) / 2, (z0 + z1) / 2)
		Kit.part(root, name, V3.new(x1 - x0, 0.2, z1 - z0), CF.new((x0 + x1) / 2, y + lift, (z0 + z1) / 2), color, mat)
	end
	strip("EastLink", 60, 260, 66, 94, C3.fromRGB(85, 88, 90), Enum.Material.Asphalt, 0.1)
	strip("CurbN", 60, 260, 65.7, 66, C3.fromRGB(154, 150, 140), Enum.Material.Concrete, 0.2)
	strip("CurbS", 60, 260, 94, 94.3, C3.fromRGB(154, 150, 140), Enum.Material.Concrete, 0.2)

	for _, sign in ipairs(WorldPlan.Town().signs) do
		if string.match(sign.text, "^[^\n]+") == "PLOT DISTRICT" then
			local model = BuildingArt.Signpost(sign.text, sign.lit, nil, sign.gateId, sign.noWrap)
			Kit.placeAt(model, sign.cframe)
			-- The viewer draws a SurfaceGui through the board, so the back face's
			-- text shows mirrored over the front's. Drop the back face for the
			-- preview only: what a player reads from the front is what is left.
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("SurfaceGui") and d.Face == Enum.NormalId.Back then
					d:Destroy()
				end
			end
			model.Parent = root
			District.sign = sign
		end
	end

	local npc = NPCData.Get("OldHank")
	local hank = CharacterArt.Build(npc.look)
	local y = TerrainGen.HeightAt(hankAt.X, hankAt.Z)
	Kit.placeAt(
		hank,
		CF.new(hankAt.X, y, hankAt.Z) * CF.Angles(0, NPCData.YawOf(hankLook.X - hankAt.X, hankLook.Z - hankAt.Z), 0)
	)
	hank.Parent = root

	local function eye(x, dy, z)
		return { x, TerrainGen.HeightAt(x, z) + dy, z }
	end
	return {
		root = root,
		terrain = Common.terrain(ctx, 60, 20, 260, 190, 2),
		shadowRadius = 160,
		lighting = { fogNear = 600, fogFar = 2500 },
		fov = 60,
		cameras = views(eye, hankAt),
	}
end

return District
