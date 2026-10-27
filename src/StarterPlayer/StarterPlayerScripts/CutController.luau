--!strict
-- CutController: the axe in the v2 core loop (V2_PLAN.md §3d, M1.3), on
-- every device. Under the v1 loop it does nothing at all (ChopController
-- swings there); under v2 ChopController stands aside and this swings.
--
-- A click, a tap and the gamepad trigger all swing the equipped axe; hold
-- to keep swinging, once per the axe's v2 cooldown for that wood
-- (ItemCatalog.AxeStats). The live remote is Chop (v2). ChopTree is the
-- v1 loop's and is not connected on a live server, so this never fires it.
-- Each swing:
--   * Aims at the section under the pointer. The ray stays in the default
--     collision group, so a click on the crown hits the leaves (they can
--     be queried). A leaf is not a section: PickSection turns it into an
--     in-reach upright trunk of that same tree, and that trunk is what
--     Chop is sent. A Wood-group ray passes through the crown and, on a
--     trunk only a couple of studs wide, hits the ground; the swing then
--     did nothing (no toast, no remote, no Output). The nearest-section
--     search still uses group Wood, so it finds trunks and not leaves.
--     A mouse uses GetMouseLocation with ViewportPointToRay, and also
--     MouseButton1, so a click still swings when the tool's Activated
--     never arrives. A touch uses the finger (TouchTapInWorld /
--     InputObject.Position, screen pixels, ScreenPointToRay), including a
--     touch the engine marked processed: Tool.Activated on a phone runs
--     before that position is stored, and dropping a processed touch left
--     the ray nil, so a tap did nothing unless a section was already
--     inside the axe's few studs (no toast). With no finger stored, the
--     mouse location is the fallback (on a touch screen it follows the
--     finger). A gamepad has no pointer: the tool's own Activated (the
--     right trigger; no script binds or reads it), and the
--     nearest section within the axe's reach. Crystal nodes (tag Node)
--     are mined as before (MineNode). One click is one swing: Activated
--     and the key that caused it share a short gap.
--   * Picks the spot (SectionLogic.AimAt): on a standing trunk, between
--     your knee and your chest at the pointer's height, on the side facing
--     you, so you never have to aim at your own feet; on a limb or a log
--     on the ground, where you pointed.
--   * Checks what the server will (it re-checks everything): in reach
--     (the axe's v2 range), the axe can dent it, the cooldown. Too far or
--     too hard says so (a toast and a clink); a swing too soon waits.
--   * Turns you to face the cut (FaceTarget) and starts the two-handed
--     swing (SwingPose). Chop is sent on the impact frame, not the press;
--     the cooldown starts on the press. The ray is picked again then.
-- While an axe is out, a thin band rings the cut line on the trunk or log you'd
-- cut (cream in reach, amber too hard) and nothing else is outlined; the aim is
-- checked 30 times a second (15 on low) and the band follows its log every frame.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BandLogic = require(ReplicatedStorage.Shared.BandLogic)
local ChopFeelLogic = require(ReplicatedStorage.Shared.ChopFeelLogic)
local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local FieldGuide = require(ReplicatedStorage.Shared.FieldGuide)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local GrabLogic = require(ReplicatedStorage.Shared.GrabLogic)
local HintLogic = require(ReplicatedStorage.Shared.HintLogic)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local SectionLogic = require(ReplicatedStorage.Shared.SectionLogic)
local SectionMetrics = require(ReplicatedStorage.Shared.SectionMetrics)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local SwingLogic = require(ReplicatedStorage.Shared.SwingLogic)
local TemperLogic = require(ReplicatedStorage.Shared.TemperLogic)
local FaceTarget = require(script.Parent.FaceTarget)
local HUD = require(script.Parent.HUD)
local Quality = require(script.Parent.Quality)
local SwingPose = require(script.Parent.SwingPose)
local WoodFX = require(script.Parent.WoodFX)

local CutController = {}

CutController.HoverHz = { high = 30, low = 15 } -- the outline's ray, a second
CutController.RayLength = 250
CutController.WoodGroup = "Wood" -- nearest-section search; the pointer ray does not use it
CutController.NearSlack = 1.5 -- studs past the axe's reach the nearest-section search looks
CutController.HardToastEvery = 3

local READY_COLOR = Color3.fromRGB(255, 244, 214)
local HARD_COLOR = Color3.fromRGB(255, 170, 70)
local RETRY_INTERVAL = 0.2

local player = Players.LocalPlayer

---------------------------------------------------------------------------
-- What can be cut (pure enough for the specs)
---------------------------------------------------------------------------

export type Kind = string -- "tree" (a standing tree), "wood" (a loose piece) or "node" (a crystal node)

-- The model a part sits in that the axe cares about: a standing tree
-- (tag Tree), a loose piece (tag Wood) or a crystal node (tag Node), a
-- few levels up at most.
local function ownerModel(part: Instance): (Model?, Kind?)
	local node: Instance? = part.Parent
	for _ = 1, 4 do
		if node == nil then
			return nil, nil
		end
		if node:IsA("Model") then
			if CollectionService:HasTag(node, "Tree") then
				return node, "tree"
			elseif CollectionService:HasTag(node, "Wood") then
				return node, "wood"
			elseif CollectionService:HasTag(node, "Node") then
				return node, "node"
			end
		end
		node = node.Parent
	end
	return nil, nil
end

-- True for a tree that can be cut right now: grown past a sapling, not
-- felled (its stub), dormant or dead.
function CutController.TreeCuttable(tree: Instance): boolean
	return tree:GetAttribute("Felled") ~= true
		and tree:GetAttribute("Dormant") ~= true
		and tree:GetAttribute("Dead") ~= true
		and tree:GetAttribute("Sapling") ~= true
end

-- What a ray hit means to the axe: the section to cut and what it's part
-- of, or a node to mine, or nil. Leaves, bark details, cut faces and
-- notches are never targets (only parts named Section, with a Section id).
function CutController.TargetOf(hit: Instance?): (BasePart?, Model?, Kind?)
	if hit == nil or not hit:IsA("BasePart") then
		return nil, nil, nil
	end
	local model, kind = ownerModel(hit)
	if not model or not kind then
		return nil, nil, nil
	end
	if kind == "node" then
		return hit :: BasePart, model, kind
	end
	if hit.Name ~= "Section" or type(hit:GetAttribute("Section")) ~= "number" then
		return nil, nil, nil
	end
	if kind == "tree" and not CutController.TreeCuttable(model) then
		return nil, nil, nil
	end
	if model:GetAttribute("Dead") == true then
		return nil, nil, nil
	end
	return hit :: BasePart, model, kind
end

-- Where a swing from `root` (the HumanoidRootPart's position) at `section`
-- lands: SectionLogic.AimAt (knee to chest on a trunk, where you pointed
-- on anything flatter).
function CutController.Aim(
	section: BasePart,
	root: Vector3,
	pointer: Vector3?,
	pointerNormal: Vector3?
): (Vector3, Vector3)
	local cf, size = SectionMetrics.BlockFrame(section)
	return SectionLogic.AimAt(cf, size, root, pointer, pointerNormal)
end

-- The axe's damage and cooldown against a wood (v2), its reach.
function CutController.Stats(axe: ItemCatalog.AxeDef, woodId: string): (number, number, number)
	local v2 = axe.v2
	if not v2 then
		return 0, GameConfig.SwingCooldown, 0
	end
	local damage, cooldown = ItemCatalog.AxeStats(axe, woodId)
	return damage or 0, cooldown or v2.cooldown, v2.range
end

---------------------------------------------------------------------------
-- Aiming
---------------------------------------------------------------------------

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
local grouped = false

-- The nearest-section search's group (leaves don't overlap with Wood),
-- set once the server has registered it (MapBuilder, before the trees).
-- The pointer ray is left in the default group on purpose: a Wood-group
-- ray never hits the crown, and the trunk behind it is easy to miss.
local function useOverlapGroup()
	if grouped then
		return
	end
	grouped = pcall(function(): any
		overlap.CollisionGroup = CutController.WoodGroup
		return nil
	end)
end

local lastTap: Vector2? = nil
local recentTouchSwing = 0 -- os.clock of a TouchTapInWorld swing, so Activated doesn't swing it again

export type AimDevice = "touch" | "mouse" | "gamepad"
export type PointSpace = "screen" | "viewport"

-- "touch", "gamepad" (any Gamepad* input) or "mouse" (everything else).
local function pointerKind(inputName: string): AimDevice
	if inputName == "Touch" then
		return "touch"
	elseif string.sub(inputName, 1, 7) == "Gamepad" then
		return "gamepad"
	end
	return "mouse"
end

function CutController.PointerKind(inputName: string): AimDevice
	return pointerKind(inputName)
end

-- Where the swing's ray starts, and which camera method that point uses.
--   * touch + a stored finger: screen pixels (ScreenPointToRay). The finger
--     is stored even when the engine marks the touch processed.
--   * touch with no finger yet: the mouse location (ViewportPointToRay).
--     Never "no ray": that was the mobile miss.
--   * mouse: the mouse location.
--   * gamepad: no pointer (nil). The nearest section in reach is the aim.
function CutController.PointerPoint(kind: string, tap: Vector2?, mouse: Vector2): (Vector2?, PointSpace)
	if kind == "gamepad" then
		return nil, "viewport"
	end
	if kind == "touch" and tap then
		return tap, "screen"
	end
	return mouse, "viewport"
end

-- A tap in the world should swing: not one a button already took, and not
-- one in the thumbstick's corner (that walks; it doesn't chop).
function CutController.TouchAims(processedByUI: boolean, pos: Vector2, screen: Vector2): boolean
	if processedByUI then
		return false
	end
	return not GrabLogic.InThumbstickZone(pos, screen)
end

-- Ray from wherever the player is pointing, or nil for gamepads.
local function pointerRay(camera: Camera): Ray?
	local kind = pointerKind(UserInputService:GetLastInputType().Name)
	local mouse = UserInputService:GetMouseLocation()
	local point, space = CutController.PointerPoint(kind, lastTap, mouse)
	if not point then
		return nil
	end
	if space == "screen" then
		return camera:ScreenPointToRay(point.X, point.Y)
	end
	return camera:ViewportPointToRay(point.X, point.Y)
end

type Target = {
	part: BasePart,
	model: Model,
	kind: Kind,
	hit: Vector3, -- where the swing lands (a node: its centre)
	normal: Vector3,
	woodId: string?,
	problem: string?, -- "far" | "hard" | nil
}

-- The axe's listed damage against this wood's biome (a biome override
-- wins). HintLogic.Underpowered compares it with the v1 hardness field
-- (the amount taken off each hit), not v2.hardness.
local function listedDamage(axe: ItemCatalog.AxeDef, biome: string): number
	local override = if axe.biomeDamage then axe.biomeDamage[biome] else nil
	return override or axe.damage
end

-- What the HUD's hint needs to know about what the axe is pointing at
-- (`seen`: the target, or what the pointer found and why it won't do):
-- whether it's a loose piece (put the axe away to drag it), whether it's
-- wood this axe can't cut, needs too many hits for, or whose v1 hardness
-- (the amount taken off each hit, not v2.hardness) beats the axe's listed
-- damage (HintLogic.TooHard / Underpowered), and whether
-- the face is thick (HintLogic.Thicker: thicker cuts take longer).
function CutController.PointingFacts(seen: Target?, axe: ItemCatalog.AxeDef?): (boolean, boolean, boolean)
	if seen == nil or axe == nil or seen.kind == "node" then
		return false, false, false
	end
	local onWood = seen.kind == "wood"
	local size = seen.part.Size
	local thick = HintLogic.Thicker(size.X, size.Z)
	if seen.problem == "hard" then
		return onWood, true, thick
	end
	local woodId = seen.woodId
	if woodId == nil or woodId == "" then
		return onWood, false, thick
	end
	local hitsHard = HintLogic.TooHard(FieldGuide.CutHits(axe, woodId, size.X, size.Z))
	local wood = WoodData.Get(woodId)
	local weak = wood ~= nil and HintLogic.Underpowered(listedDamage(axe, wood.biome), wood.hardness)
	return onWood, hitsHard or weak, thick
end

-- The equipped axe tool, its definition and the root part, or nils.
local function equipped(): (Tool?, ItemCatalog.AxeDef?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local id = if tool then tool:GetAttribute("AxeId") else nil
	local axe = if type(id) == "string" then ItemCatalog.GetAxe(id) else nil
	if not tool or not axe or not hrp or not hrp:IsA("BasePart") then
		return nil, nil, nil
	end
	return tool, axe, hrp
end

local function describe(
	part: BasePart,
	model: Model,
	kind: Kind,
	axe: ItemCatalog.AxeDef,
	root: Vector3,
	pointer: Vector3?,
	pointerNormal: Vector3?
): Target
	if kind == "node" then
		local at = part.CFrame.Position
		local far = (at - root).Magnitude > GameConfig.ChopRange
		return {
			part = part,
			model = model,
			kind = kind,
			hit = at,
			normal = Vector3.yAxis,
			problem = if far then "far" else nil,
		}
	end
	local woodId = model:GetAttribute("WoodId")
	local wood = if type(woodId) == "string" then woodId else ""
	local hit, normal = CutController.Aim(part, root, pointer, pointerNormal)
	local damage, _, range = CutController.Stats(axe, wood)
	local problem: string? = nil
	if damage <= 0 then
		problem = "hard"
	elseif (hit - root).Magnitude > range then
		problem = "far"
	end
	return {
		part = part,
		model = model,
		kind = kind,
		hit = hit,
		normal = normal,
		woodId = wood,
		problem = problem,
	}
end

-- A click on dress (leaves, a tier, bark) is not itself a section. Of this
-- model's sections, the one to cut: an in-reach upright trunk when the
-- player is standing at the tree (a crown click), otherwise the closest
-- upright trunk, which comes back "far" so the swing says so instead of
-- vanishing. A loose piece has no upright trunk: the closest in-reach
-- section, or the closest one.
function CutController.PickSection(
	model: Model,
	kind: Kind,
	axe: ItemCatalog.AxeDef,
	root: Vector3,
	pointer: Vector3?,
	pointerNormal: Vector3?
): Target?
	local best: Target? = nil
	local bestScore = math.huge
	local fallback: Target? = nil
	local fallbackD = math.huge
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Section" and type(d:GetAttribute("Section")) == "number" then
			local target = describe(d, model, kind, axe, root, pointer, pointerNormal)
			local upright = math.abs(SectionMetrics.BlockFrame(d).UpVector.Y) >= SectionLogic.Upright
			local dist = (target.hit - root).Magnitude
			if target.problem == nil then
				local score = dist + (if upright or kind ~= "tree" then 0 else 50)
				if score < bestScore then
					best, bestScore = target, score
				end
			elseif (upright or kind ~= "tree") and dist < fallbackD then
				fallback, fallbackD = target, dist
			end
		end
	end
	return best or fallback
end

-- The section (or node) under the pointer, if any. A leaf hit resolves to
-- a section of that tree (PickSection); the leaf itself is never sent.
local function pointed(hrp: BasePart, axe: ItemCatalog.AxeDef): Target?
	local camera = workspace.CurrentCamera
	local ray = if camera then pointerRay(camera) else nil
	if not ray then
		return nil
	end
	rayParams.FilterDescendantsInstances = { player.Character :: Instance }
	local result = workspace:Raycast(ray.Origin, ray.Direction * CutController.RayLength, rayParams)
	if not result then
		return nil
	end
	local part, model, kind = CutController.TargetOf(result.Instance)
	if part and model and kind then
		return describe(part, model, kind, axe, hrp.Position, result.Position, result.Normal)
	end
	if not result.Instance:IsA("BasePart") then
		return nil
	end
	local owner, ownerKind = ownerModel(result.Instance)
	if not owner or (ownerKind ~= "tree" and ownerKind ~= "wood") then
		return nil
	end
	if ownerKind == "tree" and not CutController.TreeCuttable(owner) then
		return nil
	end
	if owner:GetAttribute("Dead") == true then
		return nil
	end
	return CutController.PickSection(owner, ownerKind :: Kind, axe, hrp.Position, result.Position, result.Normal)
end

-- How good a section is to cut: its distance, plus up to NearAhead studs when
-- it is behind the camera. `look` is the camera's flat forward, or nil.
CutController.NearAhead = 6

function CutController.NearScore(offset: Vector3, look: Vector3?): number
	local d = offset.Magnitude
	if look == nil then
		return d
	end
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 1e-3 or look.Magnitude < 1e-3 then
		return d
	end
	local facing = flat.Unit:Dot(look.Unit) -- 1 ahead, -1 behind
	return d + (1 - facing) / 2 * CutController.NearAhead
end

-- Of candidates ({ score, inCone }), which wins: touch and gamepad prefer the
-- best score among those inside the aim cone (ChopFeelLogic.AimConeDegrees);
-- with none in the cone, or with `useCone` false (a mouse), the best score
-- overall. Returns the index, or nil for no candidates. It only chooses the
-- target: reach is checked before anything is a candidate.
function CutController.NearChoice(list: { { score: number, inCone: boolean } }, useCone: boolean): number?
	local best, bestScore = nil, math.huge
	local bestCone, bestConeScore = nil, math.huge
	for i, c in ipairs(list) do
		if c.score < bestScore then
			best, bestScore = i, c.score
		end
		if useCone and c.inCone and c.score < bestConeScore then
			bestCone, bestConeScore = i, c.score
		end
	end
	return bestCone or best
end

-- The nearest section within the axe's reach (a gamepad, a missed tap).
-- Touch and gamepad snap to the nearest one inside a 25 degree cone of the
-- camera's look; a mouse is unchanged.
local function nearest(hrp: BasePart, axe: ItemCatalog.AxeDef): Target?
	local range = if axe.v2 then axe.v2.range else GameConfig.ChopRange
	useOverlapGroup()
	overlap.FilterDescendantsInstances = { player.Character :: Instance }
	local parts = workspace:GetPartBoundsInRadius(hrp.Position, range + CutController.NearSlack, overlap)
	-- With no pointer (a gamepad) the way the camera faces breaks ties: of
	-- the sections in reach, the one ahead of the camera beats a nearer one
	-- behind you. Reach is unchanged.
	local camera = workspace.CurrentCamera
	local look: Vector3? = nil
	if camera then
		local ok, forward = pcall(function()
			return camera.CFrame.LookVector
		end)
		if ok and typeof(forward) == "Vector3" then
			look = Vector3.new(forward.X, 0, forward.Z)
		end
	end
	local useCone = pointerKind(UserInputService:GetLastInputType().Name) ~= "mouse"
	local eye: Vector3? = nil
	local look3: Vector3? = nil
	if camera and useCone then
		local ok, cf = pcall(function()
			return camera.CFrame
		end)
		if ok and typeof(cf) == "CFrame" then
			eye, look3 = cf.Position, cf.LookVector
		end
	end
	local targets: { Target } = {}
	local scored: { { score: number, inCone: boolean } } = {}
	for _, p in ipairs(parts) do
		local part, model, kind = CutController.TargetOf(p)
		if part and model and kind and kind ~= "node" then
			local target = describe(part, model, kind, axe, hrp.Position, nil, nil)
			if target.problem == nil then
				local offset = target.hit - hrp.Position
				local inCone = eye ~= nil and ChopFeelLogic.InCone(target.hit - eye, look3)
				table.insert(targets, target)
				table.insert(scored, { score = CutController.NearScore(offset, look), inCone = inCone })
			end
		end
	end
	local pick = CutController.NearChoice(scored, useCone)
	return if pick then targets[pick] else nil
end

local function pickTarget(hrp: BasePart, axe: ItemCatalog.AxeDef): (Target?, Target?)
	local target = pointed(hrp, axe)
	if target and target.problem == nil then
		return target, nil
	end
	local near = nearest(hrp, axe)
	if near then
		return near, nil
	end
	return nil, target -- what the pointer found and why it won't do
end

---------------------------------------------------------------------------
-- Swinging
---------------------------------------------------------------------------

local holding = false
local cooldownUntil = 0
local retryAt = 0
local lastHardToast = 0
local highlight: Highlight? = nil
local bound: { [Tool]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Turns the character to face the cut (not while seated, climbing or down).
local function face(hrp: BasePart, at: Vector3)
	local char = player.Character
	local humanoid = if char then char:FindFirstChildOfClass("Humanoid") else nil
	if
		not humanoid
		or humanoid.Sit
		or humanoid.SeatPart ~= nil
		or humanoid.PlatformStand
		or humanoid.Health <= 0
		or hrp.Anchored
		or humanoid:GetState() == Enum.HumanoidStateType.Climbing
	then
		return
	end
	local turned = FaceTarget.Turn(hrp.CFrame, at)
	if turned then
		hrp.CFrame = turned
	end
end

-- One line per swing attempt, so a Studio test with no chop is conclusive:
-- "fired" means Chop was sent, "rejected: …" means it was not (and why).
-- Identical rejects inside 0.75s are dropped so a held click doesn't flood
-- Output. Hover (the outline) never prints.
local lastReject = ""
local lastRejectAt = 0

local function chopNote(line: string)
	if string.sub(line, 1, 9) == "rejected" then
		local now = os.clock()
		if line == lastReject and now - lastRejectAt < 0.75 then
			return
		end
		lastReject = line
		lastRejectAt = now
	end
	print("[Chop] " .. line)
end

type Armed = { state: SwingLogic.SwingState, fromClick: boolean }

local armed: Armed? = nil
local swingSerial = 0

local function carriedLogs(): number
	local read = (player :: any).GetAttribute
	if type(read) ~= "function" then
		return 0
	end
	local n = player:GetAttribute("CarriedLogs")
	return if type(n) == "number" then n else 0
end

-- Nil when the body can chop. A missing humanoid does not block here.
local function bodyBlock(): string?
	local char = player.Character
	if not char then
		return "dead"
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local health = if humanoid then humanoid.Health else nil
	local seated = humanoid ~= nil and (humanoid.Sit or humanoid.SeatPart ~= nil)
	return SwingLogic.Blocked(health, seated, carriedLogs())
end

local function cancelArmed()
	local current = armed
	if not current or current.state.cancelled then
		return
	end
	local beforeImpact = not current.state.fired
	SwingLogic.Cancel(current.state)
	SwingPose.CancelLocal(current.state.id)
	armed = nil
	if beforeImpact then
		Net.Remote("Swing"):FireServer(nil, true)
	end
end

CutController.WhiffToastEvery = 1.5
CutController.WhiffSwingSeconds = 0.5 -- the empty swing's length
local lastWhiffToast = 0

local function toastRefuse(fromClick: boolean, refused: Target?, now: number)
	if not fromClick then
		return
	end
	local why = if refused and refused.problem then refused.problem else "no target"
	-- The reasons the log names: cooldown, no target, out of range ("far"),
	-- too hard, and grab held (trySwing).
	chopNote("rejected: " .. (if why == "far" then "out of range" else why))
	if why == "no target" and now - lastWhiffToast > CutController.WhiffToastEvery then
		-- A swing with nothing in range is not silent: the swing sound and a
		-- short note, at most every WhiffToastEvery seconds.
		lastWhiffToast = now
		SoundData.Play(SoundData.SwingFor(nil))
		HUD.TimedToast("none", "Nothing in range to chop.")
		-- And the arm swings through the air (local only: nothing is sent).
		swingSerial += 1
		pcall(SwingPose.BeginLocal, swingSerial, CutController.WhiffSwingSeconds)
	end
	if refused and refused.problem == "far" then
		HUD.TimedToast("far", SectionLogic.Message("far") :: string)
	elseif refused and refused.problem == "hard" then
		SoundData.Play("ChopTooHard")
		if now - lastHardToast > CutController.HardToastEvery then
			lastHardToast = now
			HUD.TimedToast("tooHard", SectionLogic.Message("tooHard") :: string)
		end
	end
end

-- The impact frame. Idempotent: the pose hook and the timer both call it,
-- and the second finds the swing already fired.
local function deliver(id: number)
	local current = armed
	if not current or current.state.id ~= id or current.state.cancelled or current.state.fired then
		return
	end
	local now = os.clock()
	if now < current.state.impactAt then
		task.delay(current.state.impactAt - now, function()
			deliver(id)
		end)
		return
	end
	local tool, axe, hrp = equipped()
	if not tool or not axe or not hrp or bodyBlock() ~= nil then
		cancelArmed()
		return
	end
	local target, refused = pickTarget(hrp, axe)
	local decision = SwingLogic.Resolve(current.state, now, target ~= nil)
	if decision ~= "chop" and decision ~= "glance" then
		return
	end
	SwingPose.SetContact(id, if decision == "chop" then "bite" else "glance")
	if decision == "chop" and target then
		if target.kind == "node" then
			Net.Remote("MineNode"):FireServer(target.model:GetAttribute("Uid"))
		else
			Net.Remote("Chop"):FireServer(target.part, target.hit, target.normal)
		end
		if current.fromClick then
			chopNote("fired")
		end
		-- The swing still lands. The toast is the "too hard" hint when
		-- listed damage is under the wood's v1 hardness (the amount taken
		-- off each hit), not v2.hardness.
		local woodId = target.woodId
		local wood = if type(woodId) == "string" then WoodData.Get(woodId) else nil
		-- The bite shows at the impact frame, not when the server answers.
		if wood and target.kind ~= "node" then
			WoodFX.Predict(wood, target.hit, target.normal, target.part)
		end
		if wood and HintLogic.Underpowered(listedDamage(axe, wood.biome), wood.hardness) then
			if now - lastHardToast > CutController.HardToastEvery then
				lastHardToast = now
				HUD.TimedToast("tooHard", SectionLogic.Message("tooHard") :: string)
			end
		end
	else
		toastRefuse(current.fromClick, refused, now)
	end
	SoundData.Play(SoundData.SwingFor(tool:GetAttribute("AxeId")))
end

SwingPose.HookImpact(deliver)

local function trySwing(fromClick: boolean)
	local now = os.clock()
	if now < cooldownUntil then
		if fromClick then
			chopNote("rejected: cooldown")
		end
		return
	end
	if player:GetAttribute("GrabHeld") == true then
		-- A piece is in the hands (DragController): no swing. Not reachable with
		-- an axe out today (the grab ignores the trigger then), logged if it is.
		if fromClick then
			chopNote("rejected: grab held")
		end
		return
	end
	local block = bodyBlock()
	if block then
		if fromClick then
			chopNote("rejected: " .. block)
		end
		retryAt = now + RETRY_INTERVAL
		return
	end
	local tool, axe, hrp = equipped()
	if not tool or not axe or not hrp then
		if fromClick then
			chopNote("rejected: no axe")
		end
		return
	end
	local target, refused = pickTarget(hrp, axe)
	if not target then
		toastRefuse(fromClick, refused, now)
		retryAt = now + RETRY_INTERVAL
		return
	end
	face(hrp, target.hit)
	-- Keen shortens the swing the way the server's tempered copy does.
	local keen = TemperLogic.CooldownMultiplier(tool:GetAttribute("TemperPrefix"), tool:GetAttribute("TemperTier"))
	local cooldown = if target.kind == "node"
		then GameConfig.SwingCooldown
		else select(2, CutController.Stats(axe, target.woodId or "")) * keen
	cooldownUntil = now + cooldown
	swingSerial += 1
	local state = SwingLogic.Begin(swingSerial, now, cooldown)
	armed = { state = state, fromClick = fromClick }
	SwingPose.BeginLocal(state.id, cooldown)
	Net.Remote("Swing"):FireServer(if target.kind == "node" then "node" else (target.woodId or ""))
	task.delay(state.impactAt - now, function()
		deliver(state.id)
	end)
end

-- Activated and the mouse or trigger that caused it both arrive for one
-- click. The first swings; the other, inside this gap, does not.
local lastClickAt = 0

local function clickSwing()
	local now = os.clock()
	if now - lastClickAt < 0.12 then
		return
	end
	lastClickAt = now
	trySwing(true)
end

---------------------------------------------------------------------------
-- The cut guide: one reused, client-only band around the trunk or log at the
-- height this swing would cut. It is the only highlight: nothing else on the
-- tree or log is outlined or tinted.
---------------------------------------------------------------------------

CutController.GuideThickness = 0.12 -- studs
CutController.GuideTransparency = 0.15

-- Where the guide sits for `kind` on a section with `cf` and `size` (its long
-- axis is local Y): a standing trunk ("tree") at the seam under the pointer
-- (the section's base); a felled log ("wood") at the cut line this swing
-- lands on (the hit, kept CutEdge inside the ends). Returns the guide's
-- CFrame and the height up the section from its bottom.
function CutController.GuideAt(kind: string, cf: CFrame, size: Vector3, hit: Vector3): (CFrame, number)
	local h = 0
	if kind == "wood" then
		h = SectionLogic.ClampHeight(cf:PointToObjectSpace(hit).Y, size.Y)
	end
	return cf * CFrame.new(0, h - size.Y / 2, 0), h
end

local guide: Part? = nil
-- What the band last showed, so a steady aim writes nothing.
local bandPart: BasePart? = nil -- the section the band rings
local bandH = 0 -- the cut height up that section, fixed at aim time
local bandHard = false
local bandBark: Color3? = nil -- the bark the band colour was chosen for
local bandCF: CFrame? = nil
local bandSize: Vector3? = nil

CutController.GuideMove = 0.05 -- studs the band must move before its CFrame is rewritten
CutController.GuideGrow = 0.08 -- studs wider than the section (radius + 0.04), so the band clears its surface and stays within radius + 0.1

-- The band for a section `cf`/`size` cut `h` up from its bottom: a thin ring
-- just wider than the section, centred on the cut line. The only highlight.
function CutController.BandFor(cf: CFrame, size: Vector3, h: number): (CFrame, Vector3)
	return cf * CFrame.new(0, h - size.Y / 2, 0),
		Vector3.new(size.X + CutController.GuideGrow, CutController.GuideThickness, size.Z + CutController.GuideGrow)
end

-- Whether the band must be rewritten: nothing shown yet, or it moved or turned.
function CutController.BandMoved(old: CFrame?, new: CFrame): boolean
	if old == nil then
		return true
	end
	return (new.Position - old.Position).Magnitude > CutController.GuideMove
		or (new.UpVector - old.UpVector).Magnitude > 0.01
end

local function makeGuide(): Part
	local p = Instance.new("Part")
	p.Name = "CutGuide"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = CutController.GuideTransparency
	p.Size = Vector3.new(1, CutController.GuideThickness, 1)
	return p
end

-- Hides the band and the one Highlight that rings it.
local function hideGuide()
	bandPart, bandBark, bandCF, bandSize = nil, nil, nil, nil
	local g = guide
	if g and g.Parent ~= nil then
		g.Parent = nil
	end
	local hl = highlight
	if hl and hl.Enabled then
		hl.Enabled = false
		hl.Adornee = nil
	end
end

-- Puts the band on `part` at height `h`, writing only what changed.
local function placeBand(part: BasePart, h: number, hard: boolean, bark: Color3?)
	local g = guide or makeGuide()
	guide = g
	local frame, logical = SectionMetrics.BlockFrame(part)
	local cf, size = CutController.BandFor(frame, logical, h)
	if SectionMetrics.IsCylinder(part) then
		local dia = math.min(part.Size.Y, part.Size.Z)
		size = Vector3.new(dia + CutController.GuideGrow, CutController.GuideThickness, dia + CutController.GuideGrow)
	end
	if CutController.BandMoved(bandCF, cf) then
		g.CFrame = cf
		bandCF = cf
	end
	if bandSize == nil or (size - bandSize).Magnitude > 0.001 then
		g.Size = size
		bandSize = size
	end
	if bandPart ~= part or bandBark ~= bark or g.Parent == nil then
		-- Ink, or cream on a dark bark. Too hard shows on the Highlight outline.
		g.Color = BandLogic.ColorFor(bark)
		bandPart, bandBark = part, bark
	end
	bandHard = hard
	bandH = h
	if g.Parent ~= workspace then
		g.Parent = workspace
	end
	local hl = highlight
	if hl then
		if hl.Adornee ~= g then
			hl.Adornee = g
		end
		local outline = if hard then HARD_COLOR else READY_COLOR
		if hl.OutlineColor ~= outline then
			hl.OutlineColor = outline
		end
		if not hl.Enabled then
			hl.Enabled = true
		end
	end
end

-- Every frame: a log that is dragged or falls takes its band with it, and a
-- section that is gone, or an axe put away, takes the band away.
local function followBand()
	local part = bandPart
	if part == nil then
		return
	end
	local _tool, axe = equipped()
	if axe == nil or part.Parent == nil then
		hideGuide()
		return
	end
	placeBand(part, bandH, bandHard, bandBark)
end

-- Rings the cut for `seen` (the target, or what the pointer found but the axe
-- can't cut), or hides the band.
local function showGuide(seen: Target?, hard: boolean)
	if not seen or seen.kind == "node" then
		hideGuide()
		return
	end
	local _, h = CutController.GuideAt(seen.kind, seen.part.CFrame, seen.part.Size, seen.hit)
	local def = if seen.woodId then WoodData.Get(seen.woodId) else nil
	placeBand(seen.part, h, hard, if def then def.trunkColor else nil)
end

-- Shows only where this swing would cut (see the header).
local function updateOutline()
	local hl = highlight
	if not hl then
		hideGuide()
		return
	end
	local _tool, axe, hrp = equipped()
	local onWood, tooHard, thick = false, false, false
	local shown: Target? = nil
	local hard = false
	if axe and hrp then
		local target, refused = pickTarget(hrp, axe)
		if target then
			shown = target
		elseif refused and refused.problem == "hard" then
			shown, hard = refused, true
		end
		onWood, tooHard, thick = CutController.PointingFacts(target or refused, axe)
	end
	HUD.SetPointing(onWood, tooHard, thick)
	showGuide(shown, hard)
end

-- One throttled [Chop] line when the engine fires Tool.Activated, for the
-- Xbox "axe will not swing" hunt: whether it fired at all, what the last input
-- was, whether a tool is out (the grab ignores the trigger then), what the pad
-- has selected (a selected GUI object takes the trigger), and whether the
-- engine's Activate binding is among the bound actions (the controls module
-- binds it in Enable; a Disable that is never undone drops it). Everything
-- here is read-only.
local lastActivatedNote = 0

local function activateBound(): string
	local ok, all = pcall(function()
		return ContextActionService:GetAllBoundActionInfo()
	end)
	if not ok or type(all) ~= "table" then
		return "unreadable"
	end
	-- Every bound action whose name contains "activate" (any case), and how
	-- many actions are bound in all, so the engine's real name shows in the
	-- log whatever it is called.
	local total, names = 0, {}
	for name in pairs(all) do
		total += 1
		if string.find(string.lower(tostring(name)), "activate", 1, true) then
			table.insert(names, tostring(name))
		end
	end
	table.sort(names)
	return string.format("%d of %d [%s]", #names, total, table.concat(names, ","))
end

local function activatedNote(tool: Tool)
	local now = os.clock()
	if now - lastActivatedNote < 0.75 then
		return
	end
	lastActivatedNote = now
	local char = player.Character
	local out = false
	if char then
		local ok, found = pcall(function()
			return char:FindFirstChildWhichIsA("Tool")
		end)
		out = ok and found ~= nil
	end
	chopNote(
		string.format(
			"Activated: tool=%s lastInput=%s charTool=%s dragToolOut=%s grabHeld=%s selected=%s activateBinding=%s",
			tostring(tool.Name),
			tostring(UserInputService:GetLastInputType().Name),
			tostring(out),
			tostring(player:GetAttribute("DragToolOut")),
			tostring(player:GetAttribute("GrabHeld")),
			tostring(GuiService.SelectedObject),
			activateBound()
		)
	)
end

local function bindTool(tool: Tool)
	if bound[tool] or type(tool:GetAttribute("AxeId")) ~= "string" then
		return
	end
	bound[tool] = true
	tool.Activated:Connect(function()
		holding = true
		activatedNote(tool)
		-- Touch: TouchTapInWorld swings with the finger on this tap. Activated
		-- on a phone runs first, before that position exists, so wait a
		-- frame and only swing if the tap didn't (a device that fires
		-- Activated alone). Mouse and gamepad swing on the defer, as before.
		if CutController.PointerKind(UserInputService:GetLastInputType().Name) == "touch" then
			task.delay(0, function()
				if os.clock() - recentTouchSwing < 0.2 then
					return
				end
				-- A thumbstick touch can activate the tool. That walks; it
				-- doesn't chop. A world tap already swung (or refused) above.
				local tap = lastTap
				local camera = workspace.CurrentCamera
				local screen = if camera then camera.ViewportSize else Vector2.zero
				if tap and not CutController.TouchAims(false, tap, screen) then
					return
				end
				clickSwing()
			end)
		else
			task.defer(clickSwing)
		end
	end)
	tool.Deactivated:Connect(function()
		holding = false
	end)
	tool.Unequipped:Connect(function()
		holding = false
		cancelArmed()
	end)
end

local function watchCharacter(char: Model)
	holding = false
	cancelArmed()
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") then
			bindTool(child)
		end
	end
	char.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			bindTool(child)
		end
	end)
end

local function startLoop()
	-- MapBuilder says which loop runs before it builds anything.
	if not CoreLoop.V2() then
		return -- the v1 loop: ChopController swings
	end
	local hl = Instance.new("Highlight")
	hl.Name = "CutTarget"
	hl.FillTransparency = 1
	hl.OutlineTransparency = 0.25
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Enabled = false
	hl.Parent = workspace.CurrentCamera
	highlight = hl
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		hl.Parent = workspace.CurrentCamera
	end)
	-- The finger, even when the tool activation marks the touch processed
	-- (that was the miss: the position was thrown away and the ray was nil).
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if input.UserInputType == Enum.UserInputType.Touch then
			lastTap = Vector2.new(input.Position.X, input.Position.Y)
			return
		end
		-- A button already took the click. MouseButton1 also swings here:
		-- Tool.Activated does not always arrive (click to move, a Studio
		-- camera), and that used to be a silent miss. The gamepad's right
		-- trigger swings only through Tool.Activated (the engine fires it by
		-- itself); no script binds or reads that button, and Activated
		-- paces through clickSwing's cooldown and the Keen multiplier.
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			clickSwing()
		end
	end)
	-- A tap that landed in the world, not on a button and not on the
	-- thumbstick. This is what a phone swing is: the position is known
	-- here, so it aims before Activated's deferred swing can run blind.
	UserInputService.TouchTapInWorld:Connect(function(position: Vector2, processedByUI: boolean)
		local camera = workspace.CurrentCamera
		local screen = if camera then camera.ViewportSize else Vector2.zero
		if not CutController.TouchAims(processedByUI, position, screen) then
			return
		end
		lastTap = position
		recentTouchSwing = os.clock()
		clickSwing()
	end)
	local sinceAim = 0
	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		local current = armed
		if current and not current.state.cancelled and not current.state.fired then
			if bodyBlock() ~= nil then
				cancelArmed()
			elseif now >= current.state.impactAt then
				deliver(current.state.id)
			end
		end
		if holding and now >= cooldownUntil and now >= retryAt then
			trySwing(false)
		end
		sinceAim += dt
		local hz = CutController.HoverHz[Quality.Tier()] or CutController.HoverHz.high
		if sinceAim >= 1 / hz then
			sinceAim = 0
			updateOutline()
		else
			followBand()
		end
	end)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

-- Returns at once: the loop is read when the server publishes it (CoreLoop.WhenKnown).
function CutController.Start()
	CoreLoop.WhenKnown(startLoop)
end

return CutController
