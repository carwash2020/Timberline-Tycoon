--!strict
-- CanopyFade: leaves never hide you (HANDOFF NAT-02). Ten times a second
-- it looks from the camera to your head and to your HumanoidRootPart; a
-- tree canopy in the way (WindSway's canopy parts: Leaves, Frond, the
-- parts of a pine's Tier models, a frostwood's top-level snow-cap Facets)
-- fades to LocalTransparencyModifier 0.7, and eases back 0.3 s after it
-- was last in the way (Shared/CanopyLogic has the numbers and rules).
--   * The rays only see trees (an Include list of the trees in
--     TimberlineMap.Trees near the line of sight), and each tree hit is
--     left out of the next ray, so up to six trees per target are found.
--     A canopy around the camera itself (a ray that starts inside a leaf
--     can't hit it) is found with a bounds query.
--   * Trunks are never faded, and nothing here touches CanCollide or
--     CanQuery (Poppercam, trucks and clicking the leaves rely on them).
--   * TreeFX owns a tree while it falls, lies felled or regrows (and the
--     server hides dormant ones): those are skipped, a fading tree that
--     starts to fall eases back to solid over FadeOutTime (0.4 s, long
--     before TreeFX's own fade starts at FallTime + 0.1) instead of
--     snapping, and a part someone else has set (TreeFX's felled fade to
--     1) is never written. Restoring only puts back to 0 the parts this
--     module faded.
--   * The Trees folder and the trees in it stream in late and out again:
--     everything is looked up fresh each time (no waiting), and a tree that
--     has left the world is dropped on the next frame, its faded parts put
--     back to 0 first (in case the same tree comes back). Nothing is
--     connected per tree, so nothing can leak.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CanopyLogic = require(ReplicatedStorage.Shared.CanopyLogic)

local CanopyFade = {}

type Fade = {
	parts: { BasePart }, -- its canopy parts this module still owns
	alpha: number, -- the fade now
	written: number, -- what was last written to its parts
	lastHit: number, -- os.clock() when it was last in the way
}

local fades: { [Model]: Fade } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
local eyeParams = OverlapParams.new()
eyeParams.FilterType = Enum.RaycastFilterType.Include

local TARGETS = { "Head", "HumanoidRootPart" } -- R6 and R15 both have them

-- TimberlineMap.Trees (TreeService makes it), once it has streamed in.
local function treesFolder(): Instance?
	local map = workspace:FindFirstChild("TimberlineMap")
	return if map then map:FindFirstChild("Trees") else nil
end

-- Felled, dormant, or mid-fall / mid-regrow (attribute FXBusy).
local function blocked(tree: Model): boolean
	return tree:GetAttribute("Felled") == true
		or tree:GetAttribute("Dormant") == true
		or tree:GetAttribute("FXBusy") == true
end

-- The tree (a child of the Trees folder) a hit part belongs to.
local function treeOf(part: Instance, folder: Instance): Model?
	local node: Instance? = part
	while node ~= nil and node.Parent ~= folder do
		node = node.Parent
	end
	return if node ~= nil and node:IsA("Model") then node else nil
end

-- The trees near enough to the lines of sight to be in the way.
local function candidates(folder: Instance, eye: Vector3, targets: { Vector3 }): { Model }
	local out: { Model } = {}
	for _, child in ipairs(folder:GetChildren()) do
		if not child:IsA("Model") then
			continue
		end
		local home = child:GetAttribute("HomePivot")
		if typeof(home) ~= "CFrame" then
			continue
		end
		for _, target in ipairs(targets) do
			if CanopyLogic.NearSightline(home.Position, eye, target) then
				if not blocked(child) then
					table.insert(out, child)
				end
				break
			end
		end
	end
	return out
end

local function mark(tree: Model, now: number)
	local fade = fades[tree]
	if not fade then
		fade = { parts = CanopyLogic.CanopyParts(tree), alpha = 0, written = 0, lastHit = now }
		fades[tree] = fade
	end
	fade.lastHit = now
end

-- Writes `alpha` to every part the fade still owns; a part someone else
-- has set since is left alone for good. `letting`: the tree is TreeFX's
-- now (see CanopyLogic.Owns).
local function write(fade: Fade, alpha: number, letting: boolean?)
	local parts = fade.parts
	for i = #parts, 1, -1 do
		local part = parts[i]
		if CanopyLogic.Owns(part.LocalTransparencyModifier, fade.written, letting) then
			part.LocalTransparencyModifier = alpha
		else
			table.remove(parts, i)
		end
	end
	fade.written = alpha
end

-- Rays from the camera to one target, through the candidate trees.
local function trace(folder: Instance, eye: Vector3, target: Vector3, near: { Model }): { Model }
	return CanopyLogic.Trace(function(exclude: { [Model]: boolean }): (Model?, boolean)
		local include: { Instance } = {}
		for _, tree in ipairs(near) do
			if not exclude[tree] then
				table.insert(include, tree)
			end
		end
		if #include == 0 then
			return nil, false
		end
		rayParams.FilterDescendantsInstances = include
		local hit = workspace:Raycast(eye, target - eye, rayParams)
		if not hit then
			return nil, false
		end
		local tree = treeOf(hit.Instance, folder)
		if not tree then
			return nil, false
		end
		return tree, CanopyLogic.IsCanopyPart(hit.Instance, tree)
	end, CanopyLogic.MaxCasts)
end

-- One look: which canopies are in the way right now.
local function look(now: number)
	local folder = treesFolder()
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	if not folder or not camera or not character then
		return
	end
	local eye = camera.CFrame.Position
	local targets: { Vector3 } = {}
	for _, name in ipairs(TARGETS) do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			local p = part.CFrame.Position
			if (p - eye).Magnitude >= CanopyLogic.MinSightline then
				table.insert(targets, p)
			end
		end
	end
	if #targets == 0 then
		return -- no character yet, or first person
	end
	local near = candidates(folder, eye, targets)
	if #near == 0 then
		return
	end
	for _, target in ipairs(targets) do
		for _, tree in ipairs(trace(folder, eye, target, near)) do
			mark(tree, now)
		end
	end
	-- Leaves around the camera itself.
	local nearList: { Instance } = {}
	for _, tree in ipairs(near) do
		table.insert(nearList, tree)
	end
	eyeParams.FilterDescendantsInstances = nearList
	for _, part in ipairs(workspace:GetPartBoundsInRadius(eye, CanopyLogic.EyeRadius, eyeParams)) do
		local tree = treeOf(part, folder)
		if tree and CanopyLogic.IsCanopyPart(part, tree) then
			mark(tree, now)
		end
	end
end

-- Every frame: fades move toward where they should be.
local function step(now: number, dt: number)
	for tree, fade in pairs(fades) do
		if tree.Parent == nil then
			-- Streamed out or gone: leave nothing see-through behind (in case
			-- it comes back), putting back to 0 only what this faded, and let go.
			write(fade, 0)
			fades[tree] = nil
		else
			-- Felled, dormant, or TreeFX animating it: it can't be in the way
			-- any more, so it eases straight back over FadeOutTime (0.4 s,
			-- done well before TreeFX's own fade starts at FallTime + 0.1);
			-- write() lets go of any part TreeFX has set meanwhile, even to 0.
			local letting = blocked(tree)
			local sinceHit = if letting then math.huge else now - fade.lastHit
			local alpha = CanopyLogic.Step(fade.alpha, sinceHit, dt)
			fade.alpha = alpha
			if alpha ~= fade.written then
				write(fade, alpha, letting)
			end
			if alpha <= 0 then
				fades[tree] = nil
			end
		end
	end
end

-- How many trees it is fading (or bringing back) right now.
function CanopyFade.Tracked(): number
	local n = 0
	for _ in pairs(fades) do
		n += 1
	end
	return n
end

function CanopyFade.Start()
	local since = math.huge
	RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		since += dt
		-- (The slack keeps six 60 fps frames, 0.0999... in floats, a look.)
		if since >= CanopyLogic.Every - 1e-4 then
			since = 0
			look(now)
		end
		if next(fades) ~= nil then
			step(now, dt)
		end
	end)
end

return CanopyFade
