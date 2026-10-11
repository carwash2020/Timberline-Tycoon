--!strict
-- ItemModel: the real thing inside a shop box. For every item a shop sells
-- (an axe, a sawmill or planer or belt, the chop saw, the Sky Bin, a plan's
-- furniture or building, a truck or trailer, a piece of gear, the lamp post,
-- a Robux gold box) this builds the item's own model through the art
-- module that already draws it (AxeArt, MachineArt, BlueprintModels,
-- TruckArt) and keeps a LOW-DETAIL display copy for the box's window:
--
--   * Display orientation: an axe lies on its side, handle along X, blade up,
--     its broad side to the front window; a vehicle lies along X, nose west
--     (as the showroom parks them); everything else is as built, front -Z.
--   * Extent: the bounding box of the item as it is displayed (every
--     visible part of the built model, in display orientation). BoxSize turns
--     this into the box: extent plus a fixed margin. Nothing in the box's size
--     is a size class any more.
--   * Display copy: at most ModelBudget[kind] parts, the biggest by surface
--     area (a heavy vehicle or machine drops its smallest bolts, lamps and
--     rivets), with every script, light, particle, weld, sign text and seat
--     stripped, so the copy is only parts. BoxArt places it as non-colliding,
--     non-queryable, massless decor, scaled to fit, welded to the box.
--
-- The built models are cached per item (a template), so a box respawn
-- clones a few parts instead of building a truck again. Pure art code.

local AxeArt = require(script.Parent.AxeArt)
local BlueprintModels = require(script.Parent.Parent.BlueprintModels)
local ItemCatalog = require(script.Parent.Parent.ItemCatalog)
local Kit = require(script.Parent.Kit)
local MachineArt = require(script.Parent.MachineArt)
local MachineSkin = require(script.Parent.MachineSkin)
local PlotData = require(script.Parent.Parent.PlotData)
local TruckArt = require(script.Parent.TruckArt)
local TruckLayout = require(script.Parent.Parent.TruckLayout)

local ItemModel = {}

-- The most parts one display copy may have, by item kind. A box is these
-- plus BoxLogic.ShellParts; StoreStock.BoxCount adds them up against
-- GameConfig.StorePartBudget, and the specs check every item against it.
ItemModel.ModelBudget = {
	Axe = 14,
	Sawmill = 18,
	Machine = 16,
	Blueprint = 8,
	Gear = 8,
	Cosmetic = 8,
	Robux = 4,
	Truck = 32,
	Trailer = 28,
	Generic = 6,
} :: { [string]: number }

-- Parts that are never part of what a customer sees of the item: the
-- invisible helper parts the builders add (Transparency 1 is skipped as
-- well) and the signs that carry live text.
local SKIP = { PriceSign = true, Panel = true, LengthReadout = true }

export type Display = {
	kind: string,
	itemId: string,
	parts: { BasePart }, -- the display copy, in a frame centred on the extent's middle
	extent: Vector3, -- the displayed item's bounding box (display orientation, real size)
	shown: Vector3, -- the bounding box of the parts that are kept (never bigger than extent)
	total: number, -- visible parts of the built model, before the budget
	generic: boolean, -- no model of its own: a generic icon stands in
}

local V3, CF = Vector3.new, CFrame.new
local hex = Kit.hex

---------------------------------------------------------------------------
-- Icons for items with no model of their own
---------------------------------------------------------------------------

local MAT = Enum.Material

local function lantern(m: Model)
	local gold, iron = hex("#F2C14E"), hex("#3B3634")
	Kit.part(m, "Base", V3(0.9, 0.16, 0.9), CF(0, 0.08, 0), iron, MAT.Metal)
	Kit.part(m, "Glass", V3(0.7, 0.95, 0.7), CF(0, 0.64, 0), gold, MAT.Neon)
	for _, s in ipairs({ -1, 1 }) do
		Kit.part(m, "Post", V3(0.1, 1.0, 0.1), CF(s * 0.4, 0.66, 0), iron, MAT.Metal)
	end
	Kit.part(m, "Cap", V3(0.95, 0.2, 0.95), CF(0, 1.22, 0), iron, MAT.Metal)
	Kit.part(m, "Handle", V3(0.6, 0.1, 0.1), CF(0, 1.5, 0), iron, MAT.Metal)
end

local function flashlight(m: Model)
	local body, head = hex("#4A4F57"), hex("#C9CDD2")
	Kit.cylinder(m, "Handle", 1.5, 0.5, CF(-0.3, 0.3, 0), body, MAT.Metal)
	Kit.cylinder(m, "Head", 0.7, 0.95, CF(0.8, 0.3, 0), head, MAT.Metal)
	Kit.cylinder(m, "Lens", 0.1, 0.75, CF(1.2, 0.3, 0), hex("#F4E2A1"), MAT.Neon)
	Kit.part(m, "Switch", V3(0.3, 0.12, 0.2), CF(-0.2, 0.6, 0), hex("#C8402F"), MAT.SmoothPlastic)
end

local function coat(m: Model)
	local blue, white = hex("#5C87B8"), hex("#F2F4F7")
	Kit.part(m, "Torso", V3(1.5, 1.8, 0.8), CF(0, 0.9, 0), blue, MAT.Fabric)
	for _, s in ipairs({ -1, 1 }) do
		Kit.part(m, "Sleeve", V3(0.5, 1.5, 0.6), CF(s * 1.0, 0.95, 0), blue, MAT.Fabric)
	end
	Kit.part(m, "Collar", V3(1.6, 0.3, 0.95), CF(0, 1.75, 0), white, MAT.Fabric)
	Kit.part(m, "Hem", V3(1.55, 0.25, 0.85), CF(0, 0.13, 0), white, MAT.Fabric)
end

local function boots(m: Model)
	local red, sole = hex("#B5472A"), hex("#2B2623")
	for _, s in ipairs({ -1, 1 }) do
		Kit.part(m, "Shaft", V3(0.75, 1.1, 0.75), CF(s * 0.6, 0.85, 0.3), red, MAT.Leather)
		Kit.part(m, "Foot", V3(0.8, 0.5, 1.4), CF(s * 0.6, 0.45, -0.05), red, MAT.Leather)
		Kit.part(m, "Sole", V3(0.85, 0.2, 1.5), CF(s * 0.6, 0.1, -0.05), sole, MAT.SmoothPlastic)
	end
end

local function cloak(m: Model)
	local sky, trim = hex("#BFD8FF"), hex("#F4F1E6")
	Kit.part(m, "Cape", V3(1.8, 2.2, 0.2), CF(0, 1.1, 0), sky, MAT.Fabric)
	Kit.part(m, "Shoulders", V3(2.0, 0.4, 0.5), CF(0, 2.05, 0), trim, MAT.Fabric)
	Kit.part(m, "Clasp", V3(0.3, 0.3, 0.12), CF(0, 1.85, -0.3), hex("#E3B73C"), MAT.Metal)
	for i, x in ipairs({ -0.5, 0.5 }) do
		Kit.part(
			m,
			"Feather",
			V3(0.3, 0.8, 0.06),
			CF(x, 0.55, -0.14) * CFrame.Angles(0, 0, 0.2 * (i * 2 - 3)),
			trim,
			MAT.Fabric
		)
	end
end

local function lampPost(m: Model)
	local iron, glow = hex("#2E2B2A"), hex("#E6C36A")
	Kit.part(m, "Foot", V3(1.0, 0.3, 1.0), CF(0, 0.15, 0), iron, MAT.Metal)
	Kit.post(m, "Pole", V3(0, 0.3, 0), 3.4, 0.25, iron, MAT.Metal)
	Kit.part(m, "Arm", V3(0.9, 0.12, 0.12), CF(0.4, 3.6, 0), iron, MAT.Metal)
	Kit.part(m, "Lamp", V3(0.7, 0.8, 0.7), CF(0.8, 3.2, 0), glow, MAT.Neon)
	Kit.part(m, "Hood", V3(0.9, 0.18, 0.9), CF(0.8, 3.7, 0), iron, MAT.Metal)
end

-- Three gold coins in a stack: a Robux box.
local function coins(m: Model)
	local gold, rim = hex("#E3B73C"), hex("#B98A1F")
	for i = 1, 3 do
		Kit.cylinder(
			m,
			"Coin",
			0.28,
			1.3,
			CF((i - 2) * 0.12, 0.15 + (i - 1) * 0.3, 0) * CFrame.Angles(0, 0, math.pi / 2),
			if i == 2 then rim else gold,
			MAT.Metal
		)
	end
end

-- A wrapped parcel: the stand-in for an item with no model.
local function parcel(m: Model)
	Kit.part(m, "Parcel", V3(1.4, 1.2, 1.4), CF(0, 0.6, 0), hex("#C98B4B"), MAT.SmoothPlastic)
	Kit.part(m, "RibbonA", V3(0.3, 1.26, 1.46), CF(0, 0.6, 0), hex("#C8402F"), MAT.SmoothPlastic)
	Kit.part(m, "RibbonB", V3(1.46, 1.26, 0.3), CF(0, 0.6, 0), hex("#C8402F"), MAT.SmoothPlastic)
	Kit.part(m, "Bow", V3(0.5, 0.4, 0.5), CF(0, 1.4, 0), hex("#C8402F"), MAT.SmoothPlastic)
end

local ICONS: { [string]: (Model) -> () } = {
	Lantern = lantern,
	Flashlight = flashlight,
	InsulatedCoat = coat,
	HeatBoots = boots,
	FeatherfallCloak = cloak,
	LampPost = lampPost,
}

---------------------------------------------------------------------------
-- Building the real thing
---------------------------------------------------------------------------

-- Turned onto its side for the window: handle along +X, blade up, thin
-- side to the front (the axe is built standing on its foot, blade at -Z).
local AXE_TURN = CFrame.fromMatrix(Vector3.zero, V3(0, 0, -1), V3(1, 0, 0), V3(0, -1, 0))
-- Side-on, nose toward -X, like the showroom.
local VEHICLE_TURN = CFrame.Angles(0, math.pi / 2, 0)

-- The chop saw's infeed table runs 50 studs back for the logs; the display
-- keeps the head (base, guard, blade) and the first few studs of table.
local function cropChopSaw(model: Model)
	local bladeZ = 0
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name == "BladeGuard" then
			bladeZ = d.CFrame.Position.Z
		end
	end
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") then
			local z = d.CFrame.Position.Z
			if d.Name == "Infeed" then
				local keep = 9
				local zEnd = z + d.Size.Z / 2
				d.Size = V3(d.Size.X, d.Size.Y, keep)
				d.CFrame = CF(d.CFrame.Position.X, d.CFrame.Position.Y, zEnd - keep / 2)
			elseif d.Name == "Leg" and math.abs(z - bladeZ) > 9 then
				d:Destroy()
			end
		end
	end
end

local function buildRaw(kind: string, itemId: string): (Model?, CFrame, boolean)
	if kind == "Axe" then
		local def = ItemCatalog.GetAxe(itemId)
		if def then
			return AxeArt.Build(def), AXE_TURN, false
		end
	elseif kind == "Sawmill" or kind == "Machine" then
		-- The chop saw's display is cropped part by part, so it is the part build
		-- (the Blender mesh is the whole 56 stud deck).
		local plain = itemId == "ChopSaw"
		if plain then
			MachineSkin.Disabled = true
		end
		local model = MachineArt.BuildAny(itemId)
		MachineSkin.Disabled = false
		if model then
			if plain then
				cropChopSaw(model)
			end
			-- TLD-1 mills and planers run along the feed (8 x 12 and longer): turned so
			-- their length lies across the window, like a truck.
			local long = kind == "Sawmill" or (model:GetAttribute("PlanerId") ~= nil)
			return model, if long then VEHICLE_TURN else CFrame.identity, false
		end
	elseif kind == "Blueprint" then
		for _, bp in ipairs(PlotData.Blueprints) do
			if bp.id == itemId then
				return BlueprintModels.Build(bp, false), CFrame.identity, false
			end
		end
	elseif kind == "Truck" then
		local def = ItemCatalog.GetTruck(itemId)
		if def then
			return TruckArt.Build(def), VEHICLE_TURN, false
		end
	elseif kind == "Trailer" then
		local def = ItemCatalog.GetTrailer(itemId)
		local truck = ItemCatalog.GetTruck("Pickup")
		if def and truck then
			local model = Instance.new("Model")
			model.Name = itemId
			TruckArt.AddTrailer(model, def, TruckLayout.ForTrailer(def, TruckLayout.For(truck)))
			return model, VEHICLE_TURN, false
		end
	elseif kind == "Gear" or kind == "Cosmetic" then
		local icon = ICONS[itemId]
		if icon then
			local model = Instance.new("Model")
			model.Name = itemId
			icon(model)
			return model, CFrame.identity, false
		end
	elseif kind == "Robux" then
		local model = Instance.new("Model")
		model.Name = "Coins"
		coins(model)
		return model, CFrame.identity, false
	end
	local model = Instance.new("Model")
	model.Name = "Parcel"
	parcel(model)
	return model, CFrame.identity, true
end

local function visible(p: BasePart): boolean
	return p.Transparency < 1 and not SKIP[p.Name]
end

-- Surface area of the part's box: how much of the item it is.
local function weight(p: BasePart): number
	local s = p.Size
	return s.X * s.Y + s.Y * s.Z + s.X * s.Z
end

local function corners(cf: CFrame, size: Vector3, lo: Vector3?, hi: Vector3?): (Vector3, Vector3)
	local h = size / 2
	local a, b = lo, hi
	for _, x in ipairs({ -1, 1 }) do
		for _, y in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do
				local p = cf * V3(h.X * x, h.Y * y, h.Z * z)
				a = if a then a:Min(p) else p
				b = if b then b:Max(p) else p
			end
		end
	end
	return a :: Vector3, b :: Vector3
end

-- A plain copy of a part: its shape, size, colour and material, its mesh if
-- it has one, and nothing else (no scripts, welds, lights, text or seats).
local function plain(p: BasePart): BasePart
	local copy: BasePart
	if p:IsA("Seat") or p:IsA("VehicleSeat") then
		local block = Instance.new("Part")
		block.Size = p.Size
		block.Color = p.Color
		block.Material = p.Material
		copy = block
	else
		copy = p:Clone() :: BasePart
		for _, child in ipairs(copy:GetChildren()) do
			if not (child:IsA("DataModelMesh") or child:IsA("SurfaceAppearance")) then
				child:Destroy()
			end
		end
	end
	copy.Name = p.Name
	copy.Anchored = true
	copy.Massless = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.CastShadow = false
	return copy
end

local function make(kind: string, itemId: string): Display
	-- A builder that errors (a mesh that will not load, an art module that
	-- changed) must never take the shop with it: the box shows a parcel instead.
	local ok, model, turn, generic = pcall(buildRaw, kind, itemId)
	if not ok then
		warn(string.format("[ItemModel] %s %s did not build: %s", kind, itemId, tostring(model)))
		local parcelModel = Instance.new("Model")
		parcel(parcelModel)
		model, turn, generic = parcelModel, CFrame.identity, true
	end
	local list: { BasePart } = {}
	local lo: Vector3? = nil
	local hi: Vector3? = nil
	if model then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and visible(d) then
				table.insert(list, d)
				lo, hi = corners(turn * d.CFrame, d.Size, lo, hi)
			end
		end
	end
	local low: Vector3 = lo or V3(-0.5, 0, -0.5)
	local high: Vector3 = hi or V3(0.5, 1, 0.5)
	local centre = (low + high) / 2
	local budget = ItemModel.ModelBudget[kind] or ItemModel.ModelBudget.Generic
	table.sort(list, function(a, b)
		local wa, wb = weight(a), weight(b)
		if wa ~= wb then
			return wa > wb
		end
		return a.Name < b.Name
	end)
	local parts: { BasePart } = {}
	local slo: Vector3? = nil
	local shi: Vector3? = nil
	for i = 1, math.min(#list, budget) do
		local src = list[i]
		local copy = plain(src)
		local cf = turn * src.CFrame
		copy.CFrame = CF(cf.Position - centre) * (cf - cf.Position)
		slo, shi = corners(copy.CFrame, copy.Size, slo, shi)
		table.insert(parts, copy)
	end
	local shown = if slo and shi then shi - slo else Vector3.zero
	local total = #list
	if model then
		model:Destroy()
	end
	return {
		kind = kind,
		itemId = itemId,
		parts = parts,
		extent = high - low,
		shown = shown,
		total = total,
		generic = generic,
	}
end

local cache: { [string]: Display } = {}

-- The display copy of an item (built once, then cached).
function ItemModel.Get(kind: string, itemId: string): Display
	local key = kind .. ":" .. itemId
	local hit = cache[key]
	if hit then
		return hit
	end
	local built = make(kind, itemId)
	cache[key] = built
	return built
end

-- The displayed item's bounding box in studs, the number BoxSize works from.
function ItemModel.Extent(kind: string, itemId: string): Vector3
	return ItemModel.Get(kind, itemId).extent
end

-- Whether an item is a vehicle (its box may be bigger than a shelf box).
function ItemModel.IsVehicle(kind: string): boolean
	return kind == "Truck" or kind == "Trailer"
end

-- Clones the display copy into `parent`, scaled by `scale` about its middle,
-- with its middle at `at` (a CFrame in the same space as `parent`'s parts).
-- Returns the parts. They are anchored decor; BoxArt welds them.
function ItemModel.Place(display: Display, parent: Instance, at: CFrame, scale: number): { BasePart }
	local out: { BasePart } = {}
	for _, src in ipairs(display.parts) do
		local copy = src:Clone() :: BasePart
		local cf = src.CFrame
		copy.Size = src.Size * scale
		copy.CFrame = at * (CF(cf.Position * scale) * (cf - cf.Position))
		for _, child in ipairs(copy:GetChildren()) do
			if child:IsA("SpecialMesh") then
				child.Offset = child.Offset * scale
			end
		end
		copy.Parent = parent
		table.insert(out, copy)
	end
	return out
end

return ItemModel
