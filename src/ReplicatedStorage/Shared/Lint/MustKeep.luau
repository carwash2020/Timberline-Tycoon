--!strict
-- MustKeep: things that must never go missing or move without someone meaning it (T409). The list
-- is tests/mustkeep.json: each entry is a path, the world position it was built at and a tolerance
-- (0.5 studs). A removed back door, a moved counter or a vanished Intake fails with the expected and
-- the actual position (or "missing"). Pure: takes the root Instance (the built Workspace) and the
-- decoded list; a machine entry builds the machine with `buildMachine`.
--
--   world entries:   { path = "TimberlineMap/ToolShed/BackRoomDoor", pos = {x, y, z}, tol = 0.5,
--                      canCollide = false? }
--     A path is names joined by "/"; "Name#2" is the second child called Name.
--   machine entries: { machine = "SawmillRickety", part = "Intake", pos = {x, y, z}, tol = 0.5 }
--     The position is in the machine's own frame (its PrimaryPart), so it does not depend on
--     where a plot puts it.

local MustKeep = {}

MustKeep.DefaultTolerance = 0.5

export type WorldEntry = { path: string, pos: { number }, tol: number?, canCollide: boolean? }
export type MachineEntry = { machine: string, part: string, pos: { number }, tol: number? }
export type List = { world: { WorldEntry }, machines: { MachineEntry } }

local function child(parent: Instance, step: string): Instance?
	local name, nth = string.match(step, "^(.-)#(%d+)$")
	if not name then
		return parent:FindFirstChild(step)
	end
	local n = 0
	for _, c in ipairs(parent:GetChildren()) do
		if c.Name == name then
			n += 1
			if n == tonumber(nth) then
				return c
			end
		end
	end
	return nil
end

function MustKeep.Find(root: Instance, path: string): Instance?
	local at: Instance? = root
	for step in string.gmatch(path, "[^/]+") do
		if at == nil then
			return nil
		end
		at = child(at, step)
	end
	return at
end

-- Where an instance is: a part's centre, a model's pivot, an attachment's world spot.
function MustKeep.PositionOf(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.CFrame.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	elseif inst:IsA("Attachment") then
		local parent = inst.Parent
		if parent and parent:IsA("BasePart") then
			return (parent.CFrame * inst.CFrame).Position
		end
	end
	return nil
end

local function fmt(v: Vector3): string
	return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
end

local function fmtList(p: { number }): string
	return string.format("(%.2f, %.2f, %.2f)", p[1], p[2], p[3])
end

local function check(
	label: string,
	inst: Instance?,
	relativeTo: CFrame?,
	pos: { number },
	tol: number,
	canCollide: boolean?
): string?
	local expected = Vector3.new(pos[1], pos[2], pos[3])
	if inst == nil then
		return string.format("[MustKeep] %s: expected %s, actual missing", label, fmtList(pos))
	end
	local at = MustKeep.PositionOf(inst)
	if at == nil then
		return string.format(
			"[MustKeep] %s: expected %s, actual has no position (%s)",
			label,
			fmtList(pos),
			inst.ClassName
		)
	end
	if relativeTo then
		at = relativeTo:PointToObjectSpace(at)
	end
	if (at - expected).Magnitude > tol then
		return string.format(
			"[MustKeep] %s: expected %s, actual %s (moved %.2f)",
			label,
			fmtList(pos),
			fmt(at),
			(at - expected).Magnitude
		)
	end
	if canCollide ~= nil and inst:IsA("BasePart") and inst.CanCollide ~= canCollide then
		return string.format(
			"[MustKeep] %s: expected CanCollide %s, actual %s",
			label,
			tostring(canCollide),
			tostring(inst.CanCollide)
		)
	end
	return nil
end

function MustKeep.Run(root: Instance, list: List, buildMachine: ((string) -> Model?)?): { string }
	local failures: { string } = {}
	for _, e in ipairs(list.world) do
		local line =
			check(e.path, MustKeep.Find(root, e.path), nil, e.pos, e.tol or MustKeep.DefaultTolerance, e.canCollide)
		if line then
			table.insert(failures, line)
		end
	end
	for _, e in ipairs(list.machines) do
		local label = e.machine .. "/" .. e.part
		local model = if buildMachine then buildMachine(e.machine) else nil
		local frame = if model and model.PrimaryPart then model.PrimaryPart.CFrame else nil
		local inst = if model then model:FindFirstChild(e.part, true) else nil
		local line: string?
		if model == nil or frame == nil then
			line = string.format(
				"[MustKeep] %s: expected %s, actual missing (the machine did not build)",
				label,
				fmtList(e.pos)
			)
		else
			line = check(label, inst, frame, e.pos, e.tol or MustKeep.DefaultTolerance, nil)
		end
		if line then
			table.insert(failures, line)
		end
	end
	return failures
end

return MustKeep
