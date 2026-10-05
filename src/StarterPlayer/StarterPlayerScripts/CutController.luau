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
--     finger). A gamepad has no pointer: ButtonR2 or the trigger, and the
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
-- While an axe is out, the section you'd cut is outlined (cream in reach,
-- amber too far or too hard), checked 30 times a second (15 on low).

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CoreLoop = require(ReplicatedStorage.Shared.CoreLoop)
local FieldGuide = require(ReplicatedStorage.Shared.FieldGuide)
local GameConfig = require(ReplicatedStorage.Shared.GameConfig)
local GrabLogic = require(ReplicatedStorage.Shared.GrabLogic)
local HintLogic = require(ReplicatedStorage.Shared.HintLogic)
local ItemCatalog = require(ReplicatedStorage.Shared.ItemCatalog)
local Net = require(ReplicatedStorage.Shared.Net)
local SectionLogic = require(ReplicatedStorage.Shared.SectionLogic)
local SoundData = require(ReplicatedStorage.Shared.SoundData)
local WoodData = require(ReplicatedStorage.Shared.WoodData)
local SwingLogic = require(ReplicatedStorage.Shared.SwingLogic)
local FaceTarget = require(script.Parent.FaceTarget)
local HUD = require(script.Parent.HUD)
local Quality = require(script.Parent.Quality)
local SwingPose = require(script.Parent.SwingPose)

local CutController = {}

CutController.HoverHz = { high = 30, low = 15 } -- the outline's ray, a second
CutController.RayLength = 250
CutController.WoodGroup = "Wood" -- nearest-section search; the pointer ray does not use it
CutController.NearSlack = 1.5 -- studs past the axe's reach the nearest-section search looks
CutController.HardToastEvery = 3
CutController.BootWait = 120 -- seconds to wait for the server to say which loop runs

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
	return SectionLogic.AimAt(section.CFrame, section.Size, root, pointer, pointerNormal)
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
			local upright = math.abs(d.CFrame.UpVector.Y) >= SectionLogic.Upright
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

-- The nearest section within the axe's reach (a gamepad, a missed tap).
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
	local best: Target? = nil
	local bestScore = math.huge
	for _, p in ipairs(parts) do
		local part, model, kind = CutController.TargetOf(p)
		if part and model and kind and kind ~= "node" then
			local target = describe(part, model, kind, axe, hrp.Position, nil, nil)
			local offset = target.hit - hrp.Position
			local score = CutController.NearScore(offset, look)
			if target.problem == nil and score < bestScore then
				best, bestScore = target, score
			end
		end
	end
	return best
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

local function toastRefuse(fromClick: boolean, refused: Target?, now: number)
	if not fromClick then
		return
	end
	local why = if refused and refused.problem then refused.problem else "no target"
	chopNote("rejected: " .. why)
	if refused and refused.problem == "far" then
		HUD.Toast(SectionLogic.Message("far") :: string)
	elseif refused and refused.problem == "hard" then
		SoundData.Play("ChopTooHard")
		if now - lastHardToast > CutController.HardToastEvery then
			lastHardToast = now
			HUD.Toast(SectionLogic.Message("tooHard") :: string)
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
		if wood and HintLogic.Underpowered(listedDamage(axe, wood.biome), wood.hardness) then
			if now - lastHardToast > CutController.HardToastEvery then
				lastHardToast = now
				HUD.Toast(SectionLogic.Message("tooHard") :: string)
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
	local cooldown = if target.kind == "node"
		then GameConfig.SwingCooldown
		else select(2, CutController.Stats(axe, target.woodId or ""))
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

-- Outlines what you'd cut (see the header).
local function updateOutline()
	local hl = highlight
	if not hl then
		return
	end
	local _tool, axe, hrp = equipped()
	local adornee: Instance? = nil
	local color = READY_COLOR
	local onWood, tooHard, thick = false, false, false
	if axe and hrp then
		local target, refused = pickTarget(hrp, axe)
		if target then
			adornee = target.part
		elseif refused and refused.problem == "hard" then
			adornee, color = refused.part, HARD_COLOR
		end
		onWood, tooHard, thick = CutController.PointingFacts(target or refused, axe)
	end
	HUD.SetPointing(onWood, tooHard, thick)
	if adornee then
		hl.Adornee = adornee
		hl.OutlineColor = color
		hl.Enabled = true
	else
		hl.Enabled = false
		hl.Adornee = nil
	end
end

local function bindTool(tool: Tool)
	if bound[tool] or type(tool:GetAttribute("AxeId")) ~= "string" then
		return
	end
	bound[tool] = true
	tool.Activated:Connect(function()
		holding = true
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

function CutController.Start()
	-- MapBuilder says which loop runs before it builds anything.
	local waited = 0
	while workspace:GetAttribute(CoreLoop.ActiveAttribute) == nil and waited < CutController.BootWait do
		waited += task.wait(0.25)
	end
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
		-- A button already took the click. MouseButton1 and the trigger
		-- also swing here: Tool.Activated does not always arrive (click to
		-- move, a Studio camera), and that used to be a silent miss.
		-- R2 is no button's click: a bound action marks it handled even when
		-- it passes it on. Only a menu with the pad selection keeps it.
		local trigger = input.KeyCode == Enum.KeyCode.ButtonR2
		if gameProcessed and not (trigger and GuiService.SelectedObject == nil) then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or trigger then
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
		end
	end)
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		watchCharacter(player.Character)
	end
end

return CutController
