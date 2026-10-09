--!strict
-- SpecBuild: build a model from rows (the pack's model recipes). Each row
-- is one piece: name, kind, size, at, colour (a Palette name or a #hex),
-- and optional material and decor. `origin` is applied on the left, so a
-- row's `at` is in the model's own space. Returns the parts it created.
--
-- Kit cylinders lie along X. A part under 1 stud is decor unless the row
-- says decor = false, and anything under 1 stud casts no shadow.

local Kit = require(script.Parent.Kit)
local Palette = require(script.Parent.Palette)

local SpecBuild = {}

export type Row = {
	name: string,
	kind: string,
	size: Vector3,
	at: CFrame,
	color: string,
	mat: Enum.Material?,
	decor: boolean?,
}

local function colorOf(spec: string): Color3
	if string.sub(spec, 1, 1) == "#" then
		return Kit.hex(spec)
	end
	return Palette.Get(spec)
end

local function widest(size: Vector3): number
	return math.max(size.X, size.Y, size.Z)
end

local function finish(part: BasePart, row: Row, size: Vector3)
	local small = widest(size) < 1
	local decor = row.decor == true or (row.decor ~= false and small)
	if decor then
		Kit.decor(part, false)
	end
	if decor or small then
		part.CastShadow = false
	end
end

function SpecBuild.Build(parent: Instance, rows: { Row }, origin: CFrame): { BasePart }
	local made: { BasePart } = {}
	for _, row in ipairs(rows) do
		local cf = origin * row.at
		local color = colorOf(row.color)
		local mat = row.mat
		if row.kind == "part" then
			local p = Kit.part(parent, row.name, row.size, cf, color, mat)
			finish(p, row, row.size)
			table.insert(made, p)
		elseif row.kind == "wedge" then
			local p = Kit.wedge(parent, row.name, row.size, cf, color, mat)
			finish(p, row, row.size)
			table.insert(made, p)
		elseif row.kind == "cyl" then
			local diameter = math.max(row.size.Y, row.size.Z)
			local p = Kit.cylinder(parent, row.name, row.size.X, diameter, cf, color, mat)
			finish(p, row, row.size)
			table.insert(made, p)
		elseif row.kind == "ball" then
			local p = Kit.ball(parent, row.name, row.size.X, cf, color, mat)
			finish(p, row, row.size)
			table.insert(made, p)
		elseif row.kind == "ellipsoid" then
			local p = Kit.ellipsoid(parent, row.name, row.size, cf, color, mat)
			finish(p, row, row.size)
			table.insert(made, p)
		elseif row.kind == "cone" then
			local seen: { [Instance]: boolean } = {}
			for _, d in ipairs(parent:GetDescendants()) do
				seen[d] = true
			end
			Kit.cone(parent, cf, row.size.X / 2, row.size.Y, 6, function(_i: number): Color3
				return color
			end, mat)
			for _, d in ipairs(parent:GetDescendants()) do
				if d:IsA("BasePart") and not seen[d] then
					d.Name = row.name
					finish(d, row, row.size)
					table.insert(made, d)
				end
			end
		else
			error("unknown spec kind " .. row.kind, 2)
		end
	end
	return made
end

return SpecBuild
