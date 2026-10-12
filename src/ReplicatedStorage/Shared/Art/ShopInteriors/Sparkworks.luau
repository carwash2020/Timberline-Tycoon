--!strict
-- Sparkworks: the automation shop's interior (Shared/Art/ShopInterior
-- dispatches here), in the family look of the Tool Shed pilot (ShopInteriors/
-- ToolShed; recipe in STATUS.md, Store interiors) with its own spark-teal
-- accent: a stand per box on both shelf units (belts and inputs down the west
-- wall, gates, timers, outputs and lasers down the east one), a header over
-- each unit, a sub-sign per category, warm timber beams and lanterns, a
-- checkout board over the counter, copper conduit and fuse boxes on the walls
-- and a stock corner. Looks only: nothing here moves a lane, a slot or a price.

local ShopKit = require(script.Parent.Parent.ShopKit)
local Kit = require(script.Parent.Parent.Kit)

type Frame = ShopKit.Frame
local V3, CF = Vector3.new, CFrame.new
local MAT = Enum.Material
local hex = Kit.hex
local dBox = ShopKit.dBox
local counterDetail = ShopKit.counterDetail
local plankFloor = ShopKit.plankFloor
local floorBorder = ShopKit.floorBorder
local runner = ShopKit.runner
local TABLE = ShopKit.Table.body
local TABLE_TOP = ShopKit.Table.top
local TIMBER = ShopKit.Table.timber

local Sparkworks = {}

local COPPER = hex("#B87333")
local TEAL = hex("#2E8B8B")
local FUSE = hex("#3A332D")

-- The room is 15 high (the roof's underside, the walls' top). The beams run wall to wall
-- against the roof; the signs hang from collar ties (0.5 thick) pressed to the roof, and the
-- lamps from chains that reach it.
Sparkworks.TieY = 14.75
Sparkworks.HeaderY = 12.0
-- The headers hang just inside the door, nearer it than every sub-sign (the first
-- sub-sign is set back SubSetback studs from the lane's front end, behind this
-- plane), so from the doorway no sub-sign or chain crosses a header's letters.
Sparkworks.HeaderZ = -10.5
Sparkworks.TopY = 15.0 -- the highest part the interior adds (the beams' and ties' tops)

-- What the signs say, from the shop's real stock (ids are the items' ids; a
-- spec checks every slot is under exactly one sign). The west unit holds the
-- four belt fittings first, then the inputs; the east one the gates and
-- timers, the outputs, and the laser pair at the back.
Sparkworks.Sections = {
	{
		lane = "FittingShelf",
		header = "BELTS & INPUTS",
		accent = TEAL,
		subs = {
			{ text = "BELTS", ids = { "BeltSupport", "SwitchBelt", "TiltedBelt" } },
			{ text = "INPUTS", ids = { "WoodDetector", "Button", "Lever", "PressurePlate", "SparkSwitch" } },
		},
	},
	{
		lane = "LogicShelf",
		header = "LOGIC & OUTPUTS",
		accent = COPPER,
		subW = 7.2, -- GATES & TIMERS needs the width to stay readable on a phone
		subs = {
			{
				text = "GATES & TIMERS",
				ids = { "GateAnd", "GateOr", "GateXor", "GateNot", "Delay", "Sustain", "Clock" },
			},
			{ text = "OUTPUTS", ids = { "SparkLamp", "GlowWire", "Hatch", "WoodSweeper" } },
			{ text = "LASERS", ids = { "LaserEmitter", "LaserReceiver" } },
		},
	},
} :: { ShopKit.Section }

-- A wall panel behind a shelf unit with copper conduit running along it and a
-- fuse box now and then: the shop's wiring on show. Looks only.
local function wallWork(model: Model, frame: Frame, west: boolean, lo: number, hi: number)
	local wallX = if west then -frame.halfW + 0.3 else frame.halfW - 0.3 -- the panel's middle, 0.3 off the wall
	local into = if west then 1 else -1
	local cz = (lo + hi) / 2
	-- (the panel is 0.6 thick, flush with the wall: its far face is the wall's face)
	dBox(model, "WallPanel", V3(0.6, 9.4, hi - lo), CF(wallX, frame.floorTop + 4.7 + 0.3, cz), TABLE)
	for _, y in ipairs({ 5.2, 10.4 }) do
		dBox(model, "PanelRail", V3(0.5, 0.35, hi - lo + 0.3), CF(wallX + into * 0.1, y, cz), TIMBER)
	end
	-- the conduit run and two drops, each with a fuse box
	dBox(model, "Conduit", V3(0.4, 0.4, hi - lo - 0.6), CF(wallX + into * 0.35, 9.4, cz), COPPER, MAT.Metal)
	for _, z in ipairs({ lo + 3, hi - 3 }) do
		dBox(model, "ConduitDrop", V3(0.4, 3.4, 0.4), CF(wallX + into * 0.35, 7.5, z), COPPER, MAT.Metal)
		dBox(model, "FuseBox", V3(0.5, 1.5, 1.2), CF(wallX + into * 0.45, 5.8, z), FUSE, MAT.Metal)
		dBox(model, "FuseLight", V3(0.2, 0.3, 0.3), CF(wallX + into * 0.78, 6.2, z), TEAL, MAT.SmoothPlastic)
	end
end

-- A wire spool on its side: two timber discs and a copper-wound core.
local function spool(model: Model, x: number, y: number, z: number)
	local at = CF(x, y + 1.3, z) -- (y is the surface the discs stand on)
	Kit.decor(Kit.cylinder(model, "Spool", 1.6, 2.0, at * CFrame.Angles(0, math.pi / 2, 0), COPPER, MAT.Metal), false)
	for _, s in ipairs({ -1, 1 }) do
		Kit.decor(
			Kit.cylinder(
				model,
				"SpoolDisc",
				0.2,
				2.6,
				at * CF(0, 0, s * 0.9) * CFrame.Angles(0, math.pi / 2, 0),
				TIMBER,
				MAT.Wood
			),
			false
		)
	end
end

-- A stock crate or barrel: the real mesh, with a part-built stand-in dropped
-- once the mesh has loaded (ShopKit.MeshProp).
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

function Sparkworks.Build(model: Model, frame: Frame)
	local rng = Kit.rng(2607)
	local ceil = frame.ceilY
	local fy = frame.floorTop
	-- The shelf units: a tier stand per box (belts and logic pieces have no
	-- tier, so their stands keep the category colour and carry no flag).
	local extents = ShopKit.SteppedUnit(model, "Sparkworks", frame, "Shelf", TABLE, TABLE_TOP)
	for _, name in ipairs({ "FittingShelf", "LogicShelf" }) do
		local ext = extents[name]
		if ext then
			wallWork(model, frame, name == "FittingShelf", ext.lo, ext.hi)
		end
	end
	counterDetail(model, frame)

	-- Floor: warm boards, a copper border and the aisle runner.
	plankFloor(model, frame, hex("#B07F4F"), { hex("#94683F"), hex("#C69660"), hex("#85603C") }, 2.8, rng)
	floorBorder(model, frame, 0.8, COPPER, MAT.Metal)
	runner(model, frame, 3.2, -frame.halfD + 1.6, 11)

	-- Warm timber beams (wall to wall, tops against the roof) and lanterns on chains that
	-- reach the roof.
	for _, z in ipairs({ -15, 1, 12 }) do
		dBox(model, "CeilingBeam", V3(2 * frame.halfW, 0.9, 0.9), CF(0, ceil - 0.45, z), TIMBER)
	end
	dBox(model, "CeilingRafter", V3(0.7, 0.7, 2 * frame.halfD), CF(0, ceil - 0.35, 0), TIMBER)
	-- (out over the shelf units' front edges, not on the aisle's middle: a lamp there stands
	-- between the door and the WIRE IT UP board on the back wall)
	for _, z in ipairs({ -5, 1 }) do
		ShopKit.WarmLamp(model, -5.6, ceil - 3.4, z, ceil)
		ShopKit.WarmLamp(model, 5.6, ceil - 3.4, z, ceil)
	end
	ShopKit.WarmLamp(model, -4.4, ceil - 3.4, -7, ceil)
	ShopKit.WarmLamp(model, 4.4, ceil - 3.4, -7, ceil)
	ShopKit.WarmLamp(model, -8, ceil - 3.4, 12, ceil)
	ShopKit.WarmLamp(model, 8, ceil - 3.4, 12, ceil)

	-- Signs: a header over each unit, a sub-sign per category, the checkout board.
	ShopKit.SectionSigns(model, "Sparkworks", Sparkworks.Sections, {
		headerY = Sparkworks.HeaderY,
		headerZ = Sparkworks.HeaderZ,
		tieY = Sparkworks.TieY,
		subShift = 0.5,
	})
	ShopKit.CheckoutSign(model, frame) -- the brass plaque on the counter front and the keeper's mat
	-- The brass CHECKOUT board over the counter: low enough to sit under the shell's hours board
	-- and high enough to clear Juno behind the counter (the kit's own hanging board is higher and
	-- covers that sign).
	local counter = model:FindFirstChild("Counter")
	if counter and counter:IsA("BasePart") then
		ShopKit.HeaderSign(model, {
			cx = counter.CFrame.Position.X,
			cy = 9.6,
			z = counter.CFrame.Position.Z - counter.Size.Z / 2 - 3.4,
			w = 7.6,
			h = 1.6,
			text = "CHECKOUT",
			accent = hex("#4CC36A"),
			ceilY = ceil, -- (the chains reach the roof)
			board = ShopKit.Colors.Brass,
			ink = ShopKit.Colors.Ink,
			name = "CheckoutSign",
		})
	end

	-- The back corners: wire spools in the east one, real crates and a barrel in the west one.
	local fx = frame.halfW - 4
	spool(model, fx, fy + 0.3, 14) -- on the pallet's top (0.3 over the floor)
	spool(model, fx - 3, fy + 0.3, 15)
	dBox(model, "SpoolPallet", V3(5.6, 0.3, 3.4), CF(fx - 1.5, fy + 0.15, 14.6), TIMBER)
	stockProp(model, "Crate", -fx, fy, 14.4, 0.1)
	stockProp(model, "Crate", -fx + 2.6, fy, 15.4, -0.2)
	stockProp(model, "Barrel", -fx - 2.4, fy, 15.6, 0.4)
end

return Sparkworks
