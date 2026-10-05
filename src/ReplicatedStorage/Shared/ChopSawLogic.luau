--!strict
-- ChopSawLogic: the chop saw's cut length, who may change it, and how a
-- log or plank is diced (wave 2, B10). Pure, so the server, the panel and
-- the specs agree. The saw is not a sawmill and not on the economy ladder.
-- Length is timber units ("u"). The remote only steps X by one unit.

local GameConfig = require(script.Parent.GameConfig)
local ItemCatalog = require(script.Parent.ItemCatalog)
local PermissionLogic = require(script.Parent.PermissionLogic)
local PlotData = require(script.Parent.PlotData)
local SectionLogic = require(script.Parent.SectionLogic)
local WoodData = require(script.Parent.WoodData)

local ChopSawLogic = {}

-- Cut length in timber units. The panel steps by CutStep.
ChopSawLogic.MinCut = 1
ChopSawLogic.MaxCut = 32
ChopSawLogic.CutStep = 1
ChopSawLogic.DefaultCut = 8

-- One accepted length step per player. The remote's own budget is wider.
ChopSawLogic.SetGap = 1

-- Blade. Damage never drops a player to 0. One hit per player per gap.
ChopSawLogic.BladeDamage = 10
ChopSawLogic.BladePush = 12
ChopSawLogic.BladeHitGap = 1

-- How fast a held ± button asks again. The server still accepts one step
-- a second; the repeats are what make the next second's step land.
ChopSawLogic.HoldRepeat = 0.2

-- Housing, studs.
ChopSawLogic.BaseX = 6
ChopSawLogic.BaseY = 4
ChopSawLogic.BaseZ = 4

-- The only damage box, studs. Yellow, with a black strip on the infeed face.
ChopSawLogic.GuardX = 3
ChopSawLogic.GuardY = 4
ChopSawLogic.GuardZ = 3

-- Infeed table. Its length is MaxCut timber units, so a full-length set
-- still has wood under the mark.
ChopSawLogic.TableWidth = 4
ChopSawLogic.TableTop = 1.2
ChopSawLogic.TableThick = 0.4
ChopSawLogic.Leg = 0.4
ChopSawLogic.IntakeHeight = 2.4

-- Client-only neon mark at the cut. The server model never builds it.
ChopSawLogic.PreviewThickness = 0.2

-- Disc in the cut plane. It does not query, so it is not a damage box.
ChopSawLogic.BladeDiameter = 3.2
ChopSawLogic.BladeThick = 0.16

-- Black band on the guard's infeed face.
ChopSawLogic.StripeThick = 0.18
ChopSawLogic.StripeBand = 0.45

-- Pivot slab under the footprint.
ChopSawLogic.RootY = 0.2

-- Side board and the price plate.
ChopSawLogic.PanelBoardX = 0.24
ChopSawLogic.PanelBoardY = 2.6
ChopSawLogic.PanelBoardZ = 3.2
ChopSawLogic.SignW = 2.4
ChopSawLogic.SignH = 0.9
ChopSawLogic.SignLift = 1.7
ChopSawLogic.SurfacePixels = 40

-- Screen panel. Phone face is also the board's button. The card is
-- bottom-centre, AboveHotbarPx above the hotbar band (UITheme.Bottom).
ChopSawLogic.PanelFacePx = 48
ChopSawLogic.PanelFaceTvPx = 96
ChopSawLogic.PanelTextPx = 20
ChopSawLogic.PanelGapPx = 8
ChopSawLogic.AboveHotbarPx = 8
ChopSawLogic.ReadoutPx = 96
ChopSawLogic.HintPx = 36
-- Roblox's touch jump button, in screen pixels: 70 wide, its left edge this
-- far in from the right, its top this far up from the bottom.
ChopSawLogic.JumpFromRightPx = 95
ChopSawLogic.JumpFromBottomPx = 90
ChopSawLogic.JumpSizePx = 70

-- How far the "Set the length" prompt reaches.
ChopSawLogic.PromptRange = 12

-- A piece rests this long in the intake before the blade takes it, and a
-- piece already at the cut length still passes through.
ChopSawLogic.Settle = 0.3
ChopSawLogic.PassSeconds = 0.4

-- Faster than this (studs/s) the piece is still in flight.
ChopSawLogic.RestSpeed = 20

ChopSawLogic.UseFlag = "interact"
ChopSawLogic.RunInput = "Run"
ChopSawLogic.WoodIdRefused = "phantomwood"

-- The axe whose cut rate the blade copies (damage and cooldown from the
-- catalog, not a second price). The saw's own price is ItemCatalog.ChopSawPrice.
ChopSawLogic.PaceAxe = "GoldAxe"

export type Graph = SectionLogic.Graph

-- Keys for the open panel. Nothing here is ButtonX or keyboard E, so a
-- placer can stay up beside them (InputKit.PlacerSafe). The D-pad literals
-- live here, not in the client controller.
ChopSawLogic.PanelBinds = {
	{ action = "Shorter", gamepad = Enum.KeyCode.DPadLeft, keyboard = Enum.KeyCode.Left },
	{ action = "Longer", gamepad = Enum.KeyCode.DPadRight, keyboard = Enum.KeyCode.Right },
	{ action = "Cut", gamepad = Enum.KeyCode.ButtonA, keyboard = Enum.KeyCode.Return },
	{ action = "CloseCut", gamepad = Enum.KeyCode.ButtonB, keyboard = Enum.KeyCode.Escape },
}

function ChopSawLogic.PanelFace(tenFoot: boolean): number
	return if tenFoot then ChopSawLogic.PanelFaceTvPx else ChopSawLogic.PanelFacePx
end

export type Rect = { left: number, top: number, right: number, bottom: number }

-- Shorter, readout, longer, Cut, Close, then a hint line.
function ChopSawLogic.PanelCardSize(tenFoot: boolean): Vector2
	local face = ChopSawLogic.PanelFace(tenFoot)
	local gap = ChopSawLogic.PanelGapPx
	local w = face * 4 + ChopSawLogic.ReadoutPx + gap * 4
	local h = face + gap + ChopSawLogic.HintPx
	return Vector2.new(w, h)
end

-- True when the boxes share any area. Edges that only touch do not overlap.
function ChopSawLogic.Overlaps(a: Rect, b: Rect): boolean
	return a.left < b.right and b.left < a.right and a.top < b.bottom and b.top < a.bottom
end

-- Roblox's touch jump button on a `screen`-sized viewport (HudLayout).
function ChopSawLogic.JumpRect(screen: Vector2): Rect
	local left = screen.X - ChopSawLogic.JumpFromRightPx
	local top = screen.Y - ChopSawLogic.JumpFromBottomPx
	local size = ChopSawLogic.JumpSizePx
	return { left = left, top = top, right = left + size, bottom = top + size }
end

-- The card in screen pixels. `scale` is UITheme.ScaleFor for that viewport
-- and `hotbar` is UITheme.Bottom (offsets; the UIScale turns them into
-- pixels). Bottom-centre, AboveHotbarPx above the hotbar. When that box
-- would cross `jump`, the card lifts until it sits the same gap above the
-- jump. `jump` is nil on a computer.
function ChopSawLogic.PanelRect(screen: Vector2, scale: number, hotbar: number, jump: Rect?, tenFoot: boolean): Rect
	local card = ChopSawLogic.PanelCardSize(tenFoot)
	local width = card.X * scale
	local height = card.Y * scale
	local bottom = screen.Y - (hotbar + ChopSawLogic.AboveHotbarPx) * scale
	local left = (screen.X - width) / 2
	local rect: Rect = { left = left, top = bottom - height, right = left + width, bottom = bottom }
	if jump and ChopSawLogic.Overlaps(rect, jump) then
		local lifted = jump.top - ChopSawLogic.AboveHotbarPx * scale
		rect = { left = left, top = lifted - height, right = left + width, bottom = lifted }
	end
	return rect
end

-- True when `rect` shares no area with any box in `obstacles`.
function ChopSawLogic.Clears(rect: Rect, obstacles: { Rect }): boolean
	for _, box in ipairs(obstacles) do
		if ChopSawLogic.Overlaps(rect, box) then
			return false
		end
	end
	return true
end

function ChopSawLogic.PadStep(key: Enum.KeyCode): (string?, number?)
	if key == Enum.KeyCode.DPadLeft or key == Enum.KeyCode.Left then
		return "x", -1
	elseif key == Enum.KeyCode.DPadRight or key == Enum.KeyCode.Right then
		return "x", 1
	end
	return nil, nil
end

function ChopSawLogic.Cuts(key: Enum.KeyCode): boolean
	return key == Enum.KeyCode.ButtonA or key == Enum.KeyCode.Return
end

function ChopSawLogic.PanelCloses(key: Enum.KeyCode): boolean
	return key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Escape
end

function ChopSawLogic.Clamp(u: number): number
	if type(u) ~= "number" or u ~= u or u == math.huge or u == -math.huge then
		return ChopSawLogic.DefaultCut
	end
	local stepped = math.floor(u / ChopSawLogic.CutStep + 0.5) * ChopSawLogic.CutStep
	return math.clamp(stepped, ChopSawLogic.MinCut, ChopSawLogic.MaxCut)
end

-- One press. Nil when the axis isn't X or the direction isn't a single step,
-- so a "y" press changes nothing.
function ChopSawLogic.Step(current: number, axis: string, dir: number): number?
	if axis ~= "x" or (dir ~= 1 and dir ~= -1) then
		return nil
	end
	return ChopSawLogic.Clamp(current + dir * ChopSawLogic.CutStep)
end

-- Hit points removed. 0 when the player is already at 1, so the blade
-- never kills. A player at 5 is left at 1.
function ChopSawLogic.Hurt(health: number): number
	if type(health) ~= "number" or health ~= health or health <= 1 then
		return 0
	end
	return math.min(ChopSawLogic.BladeDamage, health - 1)
end

-- Horizontal shove away from the guard, about BladePush studs. A point on
-- the guard's centre leaves along +Z (out the back of the blade).
function ChopSawLogic.Push(from: Vector3, guardPos: Vector3): Vector3
	local away = Vector3.new(from.X - guardPos.X, 0, from.Z - guardPos.Z)
	if away.Magnitude < 1e-3 then
		away = Vector3.zAxis
	else
		away = away.Unit
	end
	return from + away * ChopSawLogic.BladePush
end

function ChopSawLogic.Inside(part: BasePart, point: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	return math.abs(localPoint.X) <= half.X + 1e-3
		and math.abs(localPoint.Y) <= half.Y + 1e-3
		and math.abs(localPoint.Z) <= half.Z + 1e-3
end

function ChopSawLogic.TableLength(): number
	return ChopSawLogic.MaxCut * GameConfig.WoodUnit
end

function ChopSawLogic.Footprint(): Vector2
	return Vector2.new(ChopSawLogic.BaseX, ChopSawLogic.BaseZ + ChopSawLogic.TableLength())
end

-- Pivot is the footprint centre. The base sits at the +Z end; the table
-- runs toward -Z, up to MaxCut timber units.
function ChopSawLogic.BaseCenter(): Vector3
	local depth = ChopSawLogic.Footprint().Y
	local z = depth / 2 - ChopSawLogic.BaseZ / 2
	return Vector3.new(0, ChopSawLogic.BaseY / 2, z)
end

function ChopSawLogic.BladeCenter(): Vector3
	local base = ChopSawLogic.BaseCenter()
	return Vector3.new(base.X, base.Y, base.Z - ChopSawLogic.BaseZ / 2)
end

function ChopSawLogic.TableCenter(): Vector3
	local bladeZ = ChopSawLogic.BladeCenter().Z
	local len = ChopSawLogic.TableLength()
	local y = ChopSawLogic.TableTop - ChopSawLogic.TableThick / 2
	return Vector3.new(0, y, bladeZ - len / 2)
end

function ChopSawLogic.PreviewStuds(cutU: number): number
	return ChopSawLogic.Clamp(cutU) * GameConfig.WoodUnit
end

function ChopSawLogic.PreviewSize(): Vector3
	return Vector3.new(ChopSawLogic.TableWidth, ChopSawLogic.PreviewThickness, ChopSawLogic.PreviewThickness)
end

-- False only when the attribute or the BoolValue says so. Missing means running.
function ChopSawLogic.IsRunning(attr: any, boolValue: boolean?): boolean
	if attr == false or boolValue == false then
		return false
	end
	return true
end

-- The owner always may (the same user id, including 0). Anyone else needs
-- the plot's interact flag. Owner id 0 is that user, not a free pass.
function ChopSawLogic.MayUse(userId: number, ownerId: number, permissions: any): boolean
	if type(userId) ~= "number" or type(ownerId) ~= "number" then
		return false
	end
	if userId == ownerId then
		return true
	end
	if type(permissions) ~= "table" then
		return false
	end
	return PermissionLogic.Allows(permissions, userId, ChopSawLogic.UseFlag)
end

function ChopSawLogic.AcceptsKind(kind: string): boolean
	return kind == "log" or kind == "plank"
end

-- Why this wood is refused, or nil when the saw will cut it.
function ChopSawLogic.Refusal(woodId: string): string?
	if woodId ~= ChopSawLogic.WoodIdRefused then
		return nil
	end
	local wood = WoodData.Get(woodId)
	local name = if wood then wood.displayName else "that wood"
	return "The chop saw won't cut " .. name .. "."
end

-- Seconds the blade spends, copying the pace axe's damage per second
-- against this face, once per cut. Zero cuts still take PassSeconds.
function ChopSawLogic.Seconds(woodId: string, sx: number, sz: number, cuts: number): number
	if cuts <= 0 then
		return ChopSawLogic.PassSeconds
	end
	local wood = WoodData.Get(woodId)
	local axe = ItemCatalog.GetAxe(ChopSawLogic.PaceAxe)
	if not wood or not wood.v2 or not axe then
		return ChopSawLogic.PassSeconds
	end
	local damage, cooldown = ItemCatalog.AxeStats(axe, woodId)
	if not damage or not cooldown or damage <= 0 or cooldown <= 0 then
		return ChopSawLogic.PassSeconds
	end
	local required = SectionLogic.Required(wood.v2.hardness, sx, sz)
	return cuts * required / (damage / cooldown)
end

function ChopSawLogic.Trunk(length: number, thickness: number): Graph
	return {
		[1] = {
			id = 1,
			parent = nil,
			children = {},
			cf = CFrame.new(),
			length = length,
			thickness = thickness,
		},
	}
end

local function rootOf(graph: Graph): (number?, SectionLogic.Node?)
	local best: number? = nil
	for id, node in pairs(graph) do
		if node.parent == nil and (best == nil or id < best) then
			best = id
		end
	end
	if best == nil then
		return nil, nil
	end
	return best, graph[best]
end

local function maxId(graph: Graph): number
	local n = 0
	for id in pairs(graph) do
		if id > n then
			n = id
		end
	end
	return n
end

-- Cut `graph` into pieces `cutStuds` long. A remainder too small to keep
-- stays on the previous piece, so the volumes still add up. The graph
-- given isn't changed.
function ChopSawLogic.Dice(graph: Graph, cutStuds: number): { Graph }
	local pieces: { Graph } = {}
	if cutStuds ~= cutStuds or cutStuds <= 0 then
		table.insert(pieces, graph)
		return pieces
	end
	local current = graph
	local guard = 0
	while guard < ChopSawLogic.MaxCut do
		guard += 1
		local id, node = rootOf(current)
		if id == nil or node == nil or node.length <= cutStuds + 1e-3 then
			table.insert(pieces, current)
			break
		end
		local remain = node.length - cutStuds
		if SectionLogic.IsChips(SectionLogic.Volume(node.thickness, remain, node.thickness)) then
			table.insert(pieces, current)
			break
		end
		local low, high = SectionLogic.SplitGraph(current, id, cutStuds, maxId(current) + 1)
		table.insert(pieces, low)
		current = high
	end
	return pieces
end

function ChopSawLogic.Blueprint(id: string): PlotData.Blueprint?
	local machine = ItemCatalog.GetMachine(id)
	if not machine then
		return nil
	end
	return {
		id = machine.id,
		displayName = machine.displayName,
		category = "Machine",
		priceCash = machine.priceCash,
		tier = 1,
		footprint = ChopSawLogic.Footprint(),
		boxes = {},
		note = "Cuts a log or a plank to the length on the panel.",
	}
end

return ChopSawLogic
