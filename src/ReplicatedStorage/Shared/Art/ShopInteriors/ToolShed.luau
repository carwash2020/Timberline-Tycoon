--!strict
-- ToolShed: the Tool Shed's interior, the PILOT of the new store look (Shared/
-- Art/ShopInterior dispatches here). Built from ShopKit: tier stands on both
-- tables, a header over each table and a sub-sign over each category, warm
-- beams and lanterns, a checkout sign over the counter, the axe rack on the
-- back wall, and real wall racks. The recipe for the other stores is in
-- STATUS.md (Store interiors).

local ShopKit = require(script.Parent.Parent.ShopKit)
local Kit = require(script.Parent.Parent.Kit)
local AxeArt = require(script.Parent.Parent.AxeArt)
local RobuxTableArt = require(script.Parent.Parent.RobuxTableArt)
local BoxLook = require(script.Parent.Parent.Parent.BoxLook)
local HoverTag = require(script.Parent.Parent.Parent.HoverTag)
local ItemCatalog = require(script.Parent.Parent.Parent.ItemCatalog)

type Frame = ShopKit.Frame
local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex
local dBox = ShopKit.dBox
local counterDetail = ShopKit.counterDetail
local backDoor = ShopKit.backDoor
local plankFloor = ShopKit.plankFloor
local floorBorder = ShopKit.floorBorder
local runner = ShopKit.runner
local TABLE = ShopKit.Table.body
local TABLE_TOP = ShopKit.Table.top
local TIMBER = ShopKit.Table.timber
local PAPER = ShopKit.Table.paper

local ToolShed = {}

-- The signs hang from collar ties up in the barn (the roof is a gambrel: at the
-- lane the underside is about 19 high, so a tie at 15.2 is under it). Everything
-- else the interior adds stays under frame.ceilY.
ToolShed.TieY = 15.2
ToolShed.HeaderY = 12.6
ToolShed.TopY = 15.7 -- the highest part the interior adds (the ties' tops)

-- The axe rack on the back wall, as Lumber Tycoon 2 shows its axes: every axe
-- the shop sells (ItemCatalog's ladder, in order), each its real AxeArt model
-- (the part-built or mesh art the held tools use; AxeArt falls back to parts
-- if a mesh fails), standing whole on its own STEP of a stepped wall shelf,
-- each step a little higher than the one before (the ladder climbs), in front
-- of a solid backing block in the axe's tier colour (BoxLook.AxeTiers) with its
-- name plate on it. The price is not printed: aiming at an axe shows it in a
-- tag (Shared/HoverTag).
local RACK_STEP = 0.22 -- each axe's step is this much higher than the last
local RACK_BLOCK = 2.4 -- the tier-colour block behind each axe (and its step) is this wide (an axe's head and handle show up to 2.4 wide)
ToolShed.RackGap = 1.5 -- clear studs between one axe's block and the next (it was 0.3)
local RACK_AXE_SHIFT = 0.4 -- the axes' heads stick out to -x, so the pivot stands this far toward +x to centre one on its block
local RACK_PLATE = 3.0 -- the name plate: wider than the block, still 0.9 clear of the next
local RACK_BASE = 7.5 -- the first step's top
local RACK_PANEL_Y = 9.7
local RACK_PANEL_H = 6.8
local function axeRack(model: Model, frame: Frame)
	local axes: { ItemCatalog.AxeDef } = {}
	for _, axe in ipairs(ItemCatalog.AxeLadder()) do
		if axe.sold ~= false then
			table.insert(axes, axe)
		end
	end
	if #axes == 0 then
		return
	end
	-- Each axe has its own block, ToolShed.RackGap from the next, so a plate, a
	-- block and an axe read as one item and not as one strip.
	local pitch = RACK_BLOCK + ToolShed.RackGap
	local width = (#axes - 1) * pitch + RACK_BLOCK + 1.4
	local wallZ = frame.halfD
	dBox(model, "Pegboard", V3(width, RACK_PANEL_H, 0.3), CF(0, RACK_PANEL_Y, wallZ - 0.2), TABLE)
	for _, y in ipairs({ RACK_PANEL_Y - RACK_PANEL_H / 2, RACK_PANEL_Y + RACK_PANEL_H / 2 }) do
		dBox(model, "AxeRackRail", V3(width + 0.3, 0.35, 0.5), CF(0, y, wallZ - 0.4), TIMBER)
	end
	for i, axe in ipairs(axes) do
		local x = (i - (#axes + 1) / 2) * pitch
		local stepY = RACK_BASE + (i - 1) * RACK_STEP -- the top of this axe's step
		local accent = BoxLook.Accent("Axe", axe.id)
		local art = AxeArt.Build(axe)
		local handle = art.PrimaryPart
		local len = if handle then handle.Size.Y else 3.3
		-- The backing block: a solid panel in the tier colour behind the axe
		-- and its plate, standing a hair off the rack.
		local blockLo = stepY - 1.7
		local blockH = len + 1.9
		local block = dBox(
			model,
			"AxeBlock",
			V3(RACK_BLOCK, blockH, 0.2),
			CF(x, blockLo + blockH / 2, wallZ - 0.45),
			accent,
			MAT.SmoothPlastic
		)
		-- The step the axe stands on: a ledge out of the block, darker.
		dBox(
			model,
			"AxeStep",
			V3(RACK_BLOCK, 0.3, 1.5),
			CF(x, stepY - 0.15, wallZ - 1.3),
			Kit.shade(accent, -0.45),
			MAT.SmoothPlastic
		)
		-- Foot on the step, head up, blade toward -X so the side shows.
		art:PivotTo(CF(x + RACK_AXE_SHIFT, stepY + len / 2, wallZ - 1.3) * CFrame.Angles(0, math.pi / 2, 0))
		art.Name = "RackAxe"
		art:SetAttribute("ItemId", axe.id)
		-- Two parts each (haft + the blade, the piece furthest to -X). A full
		-- AxeArt model is ~20 parts and eight of them do not fit a 250-part shop.
		local pivot = art:GetPivot()
		local primary = art.PrimaryPart
		local blade: BasePart? = nil
		local bladeX = math.huge
		for _, d in ipairs(art:GetDescendants()) do
			if d:IsA("BasePart") and d ~= primary then
				local xObj = pivot:PointToObjectSpace(d.CFrame.Position).X
				if xObj < bladeX then
					bladeX = xObj
					blade = d
				end
			end
		end
		local keep: { [Instance]: boolean } = {}
		if primary then
			keep[primary] = true
		end
		if blade then
			keep[blade] = true
		end
		local drop: { Instance } = {}
		for _, d in ipairs(art:GetDescendants()) do
			if
				(d:IsA("BasePart") and not keep[d])
				or d:IsA("JointInstance")
				or d:IsA("Light")
				or d:IsA("ParticleEmitter")
				or d:IsA("Fire")
				or d:IsA("Smoke")
			then
				table.insert(drop, d)
			end
		end
		for _, d in ipairs(drop) do
			d:Destroy()
		end
		for _, d in ipairs(art:GetDescendants()) do
			if d:IsA("BasePart") then
				Kit.decor(d, false)
			end
		end
		art.Parent = model
		local plate = dBox(
			model,
			"AxePlate",
			V3(RACK_PLATE, 1.3, 0.15),
			CF(x, stepY - 1.0, wallZ - 0.62),
			PAPER,
			MAT.SmoothPlastic
		)
		Kit.signText(plate, axe.displayName, TIMBER, { Enum.NormalId.Front }, Enum.Font.FredokaOne, 0.2)
		-- The axe, its block and its plate tag as one item: the tag sits over the axe.
		local hover: HoverTag.Spec = {
			key = "Rack:" .. axe.id,
			name = axe.displayName,
			kind = "Axe",
			itemId = axe.id,
			shop = "ToolShed",
		}
		HoverTag.Mark(plate, hover)
		HoverTag.Mark(block, hover)
		hover.anchor = true
		HoverTag.Mark(art, hover)
	end
end

-- What the signs say, from the shop's real stock (ids are ItemCatalog ids; a
-- spec checks every slot of the shop is under exactly one sign).
ToolShed.Sections = {
	{
		lane = "AxeTable",
		header = "AXES & BELTS",
		accent = BoxLook.Categories.Axe,
		subs = {
			{
				text = "AXES",
				ids = {
					"SteelAxe",
					"HardenedAxe",
					"SilverAxe",
					"CobaltAxe",
					"GoldAxe",
					"ObsidianAxe",
					"InfernoAxe",
				},
			},
			{ text = "BELT KIT", ids = { "ConveyorFunnel", "ConveyorStraight", "ConveyorTurn", "SkyBin" } },
		},
	},
	{
		lane = "MachineTable",
		header = "MACHINES",
		accent = BoxLook.Categories.Sawmill,
		subs = {
			{
				text = "SAWMILLS",
				ids = { "SawmillRickety", "SawmillSturdy", "Millmaster100", "Millmaster200", "Millmaster200L" },
			},
			{
				text = "PLANERS & SAW",
				ids = { "PlanerHand", "ChopSaw", "PlanerBench", "PlanerSteam", "PlanerIndustrial" },
			},
		},
	},
} :: { ShopKit.Section }

-- A stock crate or barrel in the back corner: the real mesh (Crate, Barrel),
-- with a part-built stand-in that is dropped when the mesh has loaded
-- (ShopKit.MeshProp: fallback first, swap later, never a yielding load).
local function stockProp(model: Model, asset: string, x: number, y: number, z: number, yaw: number)
	local fallback = Instance.new("Model")
	fallback.Name = asset .. "Fallback"
	local at = CF(x, y, z) * CFrame.Angles(0, yaw, 0)
	if asset == "Crate" then
		dBox(fallback, "Crate", V3(2, 2.4, 2), at * CF(0, 1.2, 0), TABLE_TOP)
		dBox(fallback, "CrateBand", V3(2.06, 0.2, 2.06), at * CF(0, 1.2, 0), TIMBER)
	else
		dBox(fallback, "Barrel", V3(1.6, 2.2, 1.6), at * CF(0, 1.1, 0), TABLE)
		dBox(fallback, "BarrelHoop", V3(1.7, 0.16, 1.7), at * CF(0, 1.1, 0), ShopKit.Table.iron)
	end
	fallback.Parent = model
	ShopKit.MeshProp(model, asset, at, fallback)
end

function ToolShed.Build(model: Model, frame: Frame)
	local rng = Kit.rng(2604)
	local ceil = frame.ceilY
	-- The display tables: a tier stand per slot (plinth, tier flag, lock chip).
	ShopKit.SteppedUnit(model, "ToolShed", frame, "DisplayTable", TABLE, TABLE_TOP)
	RobuxTableArt.Build(model, frame.floorTop) -- Lane P (unchanged)
	axeRack(model, frame)
	counterDetail(model, frame)
	backDoor(model, frame, frame.halfW - 0.3, 19, false, 1)

	-- Floor: warm boards with darker planks, a border, and the aisle runner.
	plankFloor(model, frame, hex("#B07F4F"), { hex("#94683F"), hex("#C69660"), hex("#85603C") }, 2.6, rng)
	floorBorder(model, frame, 0.7, hex("#5A3E26"), MAT.Wood)
	runner(model, frame, 2.6, -frame.halfD + 1.4, 8)

	-- Warm timber beams, and the warm lanterns hung from them.
	ShopKit.Beams(model, frame, { -19, -13, -3, 5, 12 })
	ShopKit.Rafter(model, frame, 0)
	-- Over the aisle, at the beams, none in the first 9 studs (the entrance stays open) and
	-- none beside a header's end.
	for _, z in ipairs({ -3, 5 }) do
		ShopKit.WarmLamp(model, -2.6, ceil - 3.4, z, ceil - 0.9)
		ShopKit.WarmLamp(model, 2.6, ceil - 3.4, z, ceil - 0.9)
	end
	ShopKit.WarmLamp(model, 0, ceil - 3.4, -10, ceil - 0.9)
	ShopKit.WarmLamp(model, 0, ceil - 3.4, 12, ceil - 0.9)

	-- Signs: a header over each table and a sub-sign over each category.
	ShopKit.SectionSigns(model, "ToolShed", ToolShed.Sections, {
		headerY = ToolShed.HeaderY,
		headerZ = -8,
		tieY = ToolShed.TieY,
	})
	ShopKit.CheckoutSign(model, frame)

	-- The stock corner by the west wall: real crate and barrel meshes.
	local fy = frame.floorTop
	stockProp(model, "Crate", -14.4, fy, 19.6, 0.1)
	stockProp(model, "Crate", -14.4, fy, 17.4, -0.15)
	stockProp(model, "Barrel", -11.2, fy, 20.4, 0)
	stockProp(model, "Barrel", -16.2, fy, 21, 0.4)
end

return ToolShed
