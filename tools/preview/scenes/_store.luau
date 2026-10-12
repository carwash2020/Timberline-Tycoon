--!nocheck
-- Shared by the per-store interior scenes (store-toolshed, store-hearth,
-- store-sparkworks, store-dealership): one shop at the origin with its roof
-- taken off (a roofed interior renders black here), stocked the way BoxService stocks it
-- (every shelf slot gets its real packaged box, the Robux shelf its gold
-- boxes), the keeper behind the counter, and a 6-stud person carrying a
-- medium box down the aisle so the aisle can be judged.
--
-- A store scene's views are always these four, in this order (the PNGs
-- under previews/store-interiors/ are named after them):
--   1 entrance   2 tier-stand   3 phone (shoot it at 667x375)   4 night
--
-- Use: return Store.scene({ kind, title, accent, keeper, cameras = function() ... end })
-- where cameras returns { entrance = cam, tierStand = cam, phone = cam, night = cam }
-- and a cam is { pos, target, label?, fov? } (night is shot with the night preset);
-- opts.populate(ctx, root, shop) may add the rest of the store (the Dealership's lot);
-- cameras may also return extra = { cam, ... }, views 5 and up, for checking details.
local Store = {}

function Store.scene(opts)
	return {
		build = function(ctx)
			local roblox = ctx.roblox
			local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
			local Kit = ctx.art("Kit")
			local BuildingArt = ctx.art("BuildingArt")
			local BoxArt = ctx.art("BoxArt")
			local StoreStock = ctx.shared("StoreStock")
			local BoxSize = ctx.shared("BoxSize")
			local RobuxShelf = ctx.shared("RobuxShelf")
			local NPCData = ctx.shared("NPCData")
			local CharacterArt = ctx.art("CharacterArt")
			local Common = require("./_common")
			local root = roblox.Instance.new("Model")
			Common.ground(ctx, root, 400, C3.fromRGB(116, 164, 84), V3.new(0, -0.5, 20))

			local function box(at, size, name, kind, color, gold, itemId, tier)
				local model = roblox.Instance.new("Model")
				model.Name = "ShopItem"
				local body = Kit.part(model, "Box", size, CF.new(at), color, roblox.Enum.Material.SmoothPlastic)
				body.CanCollide = false
				BoxArt.Dress(model, body, {
					name = name,
					tier = tier,
					itemId = itemId,
					kind = kind,
					color = color,
					gold = gold,
					side = BoxArt.AisleSide(at.X),
					wood = opts.kind == "HearthAndHome",
				})
				model.Parent = root
			end

			-- The town meshes are off in the game today (GameConfig.TownMeshes = false), so the
			-- shell is part-built here too; with opts.townMeshes = true the barn GLB loads, which
			-- brings its own baked white lamp blocks (not part of the interiors).
			ctx.art("TownMeshes").Enabled = opts.townMeshes == true
			-- opts.slotModels: give the four ModelSlots (Flashlight, Lantern, Wood Sign, Shed Blueprint) the preview
			-- mesh ids of tools/preview/store-items-meshes.json (Connor's GLBs under assets/glb/store-items; the game
			-- has no Roblox ids for them yet, so in the game the slots stay 0). Run with
			--   PREVIEW_MESHES=tools/preview/store-items-meshes.json bash tools/preview/shoot.sh store-hearth
			if opts.slotModels then
				for i, slot in ipairs(ctx.art("ModelSlots").Slots) do
					slot.meshId = 91000000 + i
				end
			end
			local shop = BuildingArt.Shop(opts.kind, opts.title, C3.fromRGB(table.unpack(opts.accent)))
			-- The roof is taken off: the preview has no ambient sky light under a roof, so a
			-- roofed interior renders black. (The game's Lighting lifts it; judge the interior
			-- lights by the brightness caps in ShopKit.Light, not by how dark the roof is.)
			local ROOF = {
				Roof = true,
				Shingle = true,
				RidgeCap = true,
				Gable = true,
				Rafter = true,
				TieBeam = true,
				CeilingBoards = true,
			}
			for _, d in ipairs(shop:GetDescendants()) do
				if d:IsA("BasePart") and ROOF[d.Name] then
					d:Destroy()
				end
			end
			Kit.placeAt(shop, CF.new(0, 0, 0))
			shop.Parent = root
			-- (A store with more than its shell, like the Dealership's vehicle lot, adds it here.)
			if opts.populate then
				opts.populate(ctx, root, shop)
			end

			local counter = shop:FindFirstChild("Counter")
			if counter then
				for _, att in ipairs(counter:GetChildren()) do
					if att:IsA("Attachment") and (att.Name == "ShelfSlot" or att.Name == "RobuxSlot") then
						local at = counter.CFrame:PointToWorldSpace(att.Position)
						local slotId = att:GetAttribute("SlotId")
						if att.Name == "RobuxSlot" then
							local entry = RobuxShelf.Get(slotId)
							local size = BoxSize.Class(RobuxShelf.Class).size
							box(
								at,
								size,
								entry and entry.displayName or "Robux",
								"Robux",
								C3.fromHex(RobuxShelf.Gold),
								true,
								nil
							)
						else
							local slot = StoreStock.Get(slotId)
							if slot then
								local size = StoreStock.BoxSizeOf(slot)
								local count = if slot.limited then 3 else 1
								for i = 1, count do
									local along = (i - (count + 1) / 2) * BoxSize.Pitch(size.Z)
									box(
										V3.new(at.X, at.Y, at.Z + along),
										size,
										slot.displayName,
										slot.itemKind,
										C3.fromHex(slot.color),
										false,
										slot.itemId,
										StoreStock.TierLabel(slot.itemKind, slot.itemId)
									)
								end
							end
						end
					end
				end
			end

			-- The keeper where NPCService stands them.
			local npc = NPCData.Get(opts.keeper)
			if npc then
				local keeper = CharacterArt.Build(npc.look)
				Kit.placeAt(
					keeper,
					NPCData.SpotFor(npc, function(_, partName)
						local part = shop:FindFirstChild(partName)
						if part then
							return part.CFrame, part.Size
						end
						return nil, nil
					end)
				)
				keeper.Parent = root
			end

			-- A customer in the aisle carrying a medium box (a carried box and the aisle at a glance).
			if opts.walker then
				local x, z = opts.walker[1], opts.walker[2]
				local size = BoxSize.Class("M").size
				Kit.part(root, "Person", V3.new(2, 5, 1), CF.new(x, 3.25, z), C3.fromRGB(60, 90, 160))
				Kit.part(root, "Head", V3.new(1.4, 1.4, 1.4), CF.new(x, 6.1, z), C3.fromRGB(235, 200, 160))
				Kit.part(root, "CarriedBox", size, CF.new(x, 4.4, z + 1 + size.Z / 2), C3.fromRGB(34, 36, 41))
			end

			local cams = opts.cameras()
			local function cam(c, label, night)
				return { pos = c.pos, target = c.target, fov = c.fov, label = c.label or label, night = night }
			end
			local cameras = {
				cam(cams.entrance, opts.title .. " entrance"),
				cam(cams.tierStand, opts.title .. " tier stand"),
				cam(cams.phone, opts.title .. " phone view (667x375)"),
				cam(cams.night, opts.title .. " at night", true),
			}
			-- Extra views (5 and up) for checking details: cams.extra = { { pos, target, label, fov }, ... }
			for _, extra in ipairs(cams.extra or {}) do
				table.insert(cameras, cam(extra, opts.title .. " detail"))
			end
			return { root = root, shadowRadius = 90, cameras = cameras }
		end,
	}
end

return Store
