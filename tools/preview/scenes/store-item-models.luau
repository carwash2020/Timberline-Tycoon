--!nocheck
-- The store item models in their shop boxes (Shared/StoreModelSlots, ItemModel,
-- BoxArt): Barrel, Crate, Glow Wire, Sky Bin, the three gear items, the lamp post,
-- the Robux box with its coins, and the Parcel fallback (an item with no model of its
-- own), standing on a shop table at counter height, the way BoxService stocks it.
-- With PREVIEW_STORE_GLBS=0 the same scene shows the part-built look (the fallback).
-- Views: 1 the whole table, 2 phone (667x375), then a close-up per box, front and
-- three-quarter, in the order of ITEMS below.
--   bash tools/preview/shoot.sh store-item-models
local ITEMS = {
	{ "Blueprint", "Barrel", "Barrel" },
	{ "Blueprint", "Crate", "Crate" },
	{ "Logic", "GlowWire", "Glow Wire" },
	{ "Machine", "SkyBin", "Sky Bin" },
	{ "Gear", "InsulatedCoat", "Insulated Coat" },
	{ "Gear", "HeatBoots", "Heat Boots" },
	{ "Gear", "FeatherfallCloak", "Featherfall Cloak" },
	{ "Cosmetic", "LampPost", "Lamp Post" },
	{ "Gear", "MysteryGear", "No Model Yet" }, -- no slot, no part-built look: the Parcel
	{ "Robux", "Cash10k", "Large Cash Pack", true },
	{ "Robux", "Cash1k", "Small Cash Pack", true, "parts" }, -- the part-built open crate, which shows its coins
}

return {
	ITEMS = ITEMS,
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF, C3 = roblox.Vector3, roblox.CFrame, roblox.Color3
		local Enum = roblox.Enum
		local Kit = ctx.art("Kit")
		local BoxArt = ctx.art("BoxArt")
		local BoxSize = ctx.shared("BoxSize")
		local ItemBox = ctx.shared("ItemBox")
		local RobuxShelf = ctx.shared("RobuxShelf")
		local StoreStock = ctx.shared("StoreStock")
		local Common = require("./_common")
		local MeshKit = ctx.art("MeshKit")
		-- Lune cannot keep a mesh piece's authored pivot (Studio does: MeshKit "authored"), so
		-- the uploaded Robux crate's pieces would all stand at the crate's middle. Their places in
		-- the model are the GLB's node centres (assets/glb/backlog/shops/RobuxBox/RobuxBox.glb).
		local CRATE = { Body = { 0, 1.335, -0.03 }, Glow = { 0, 1.15, -1.3 }, Badge = { 0, 1.9, -1.44 } }
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 200, C3.fromRGB(196, 170, 130))

		local TOP = StoreStock.TableTop
		local sizes = {}
		local total = 0
		for i, row in ipairs(ITEMS) do
			local size
			if row[4] then
				size = BoxSize.Class(RobuxShelf.Class).size
			else
				size = ItemBox.Size(row[1], row[2])
			end
			sizes[i] = size
			total += size.X + 1.4
		end
		-- the table: a plain top on four legs, a little longer than the boxes
		local tableW = total + 1.5
		Kit.part(
			root,
			"TableTop",
			V3.new(tableW, 0.4, 7),
			CF.new(0, TOP - 0.2, 0),
			C3.fromHex("#7A5230"),
			Enum.Material.Wood
		)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				Kit.part(
					root,
					"TableLeg",
					V3.new(0.5, TOP - 0.4, 0.5),
					CF.new(sx * (tableW / 2 - 0.5), (TOP - 0.4) / 2, sz * 3),
					C3.fromHex("#5E3F26"),
					Enum.Material.Wood
				)
			end
		end
		-- a wall behind, so a close-up has something to stand against
		Kit.part(
			root,
			"Wall",
			V3.new(tableW + 14, 14, 0.5),
			CF.new(0, 7, 4.4),
			C3.fromHex("#E6D3A8"),
			Enum.Material.SmoothPlastic
		)

		local cursor = -total / 2 + 0.7
		local cameras = {}
		local centres = {}
		for i, row in ipairs(ITEMS) do
			local size = sizes[i]
			local x = cursor + size.X / 2
			cursor += size.X + 1.4
			local model = roblox.Instance.new("Model")
			model.Name = row[2]
			local body = Kit.part(
				model,
				"Box",
				size,
				CF.new(x, TOP + size.Y / 2, 0),
				C3.fromRGB(34, 36, 41),
				Enum.Material.SmoothPlastic
			)
			body.CanCollide = false
			-- "parts": the crate mesh is refused, so the open crate of parts (and its coins) shows.
			local override = MeshKit.Override
			if row[5] == "parts" and override then
				MeshKit.Reset() -- forget the crate meshes the box before loaded
				MeshKit.Override = function(id, name, size)
					if id >= 9000000000000 and id < 9100000000000 then
						return override(id, name, size)
					end
					return nil
				end
			end
			BoxArt.Dress(model, body, {
				name = row[3],
				kind = row[1],
				itemId = row[2],
				gold = row[4] == true,
				robuxKey = if row[4] then row[2] else nil,
			})
			MeshKit.Override = override
			if row[5] == "parts" then
				MeshKit.Reset()
			end
			if row[4] then
				-- RobuxBoxArt scales the uploaded crate (modelled 2.7 x 2.5 x 2.7) to the box, and
				-- the pieces' places scale with it.
				local frame = body.CFrame * CF.new(0, -size.Y / 2, 0)
				for _, d in ipairs(model:GetDescendants()) do
					local at = d:IsA("MeshPart") and d:GetAttribute("StoreModel") == nil and CRATE[d.Name]
					if at then
						d.CFrame = frame * CF.new(at[1] * size.X / 2.7, at[2] * size.Y / 2.5, at[3] * size.Z / 2.7)
					end
				end
			end
			model.Parent = root
			centres[i] = { x = x, y = TOP + size.Y / 2, size = size }
		end

		table.insert(cameras, {
			pos = { 0, TOP + 4.5, -(total * 0.62 + 6) },
			target = { 0, TOP + 1.6, 0 },
			fov = 52,
			label = "the whole table",
		})
		table.insert(cameras, {
			pos = { 0, TOP + 4.5, -(total * 0.62 + 6) },
			target = { 0, TOP + 1.6, 0 },
			fov = 72,
			label = "phone view (667x375)",
		})
		for i, row in ipairs(ITEMS) do
			local c = centres[i]
			local reach = math.max(c.size.X, c.size.Y) * 1.7 + 2
			table.insert(cameras, {
				pos = { c.x, c.y + c.size.Y * 0.28, -reach },
				target = { c.x, c.y - c.size.Y * 0.05, 0 },
				fov = 44,
				label = row[3] .. " front",
			})
			table.insert(cameras, {
				pos = { c.x + reach * 0.7, c.y + c.size.Y * 0.55, -reach * 0.75 },
				target = { c.x, c.y - c.size.Y * 0.05, 0 },
				fov = 44,
				label = row[3] .. " three-quarter",
			})
		end
		return { root = root, cameras = cameras }
	end,
}
