--!strict
-- StandIn (T420): no visible part-built stand-in in meshed art. Pure: takes a root Instance, returns lines.
--
-- Meshed art is art whose look is an uploaded mesh (a MeshPart with a MeshId). It is REGISTERED by name
-- here (StandIn.Registry), or by carrying the attribute MeshedArt = true. Under every registered
-- instance (the root itself counts), every BasePart that is visible (Transparency < 1) must be a
-- MeshPart with a non-empty MeshId. A visible plain Part, WedgePart, cylinder or ball is a
-- stand-in built from parts; a MeshPart with no MeshId is a mesh that was never set. Invisible parts
-- (an invisible Handle, a collider) are not looks and are fine.
--
-- It covers exactly the registered names: today the wire spool (the model WireArt builds and the Tool
-- LogicService hands over). It does not look at anything else (the town's part-built buildings are
-- built on purpose and dressed by TownMeshes), so adding a new meshed asset means adding its name here.
-- tests/StandIn.spec runs it over the spool as built (meshes loaded, and the load failed) and over the
-- Tool, and has a deliberate failing control.

local StandIn = {}

StandIn.Registry = { "WireSpool" } :: { string }
StandIn.Attribute = "MeshedArt"

local function pathOf(instance: Instance): string
	local parts: { string } = {}
	local at: Instance? = instance
	while at ~= nil do
		table.insert(parts, 1, at.Name)
		at = at.Parent
	end
	return table.concat(parts, ".")
end

local function registered(instance: Instance): boolean
	return table.find(StandIn.Registry, instance.Name) ~= nil or instance:GetAttribute(StandIn.Attribute) == true
end

-- One line per visible part under a registered instance that is not a MeshPart with a MeshId.
function StandIn.Find(root: Instance): { string }
	local lines: { string } = {}
	local seen: { [Instance]: boolean } = {}
	local function check(owner: Instance)
		for _, d in ipairs(owner:GetDescendants()) do
			if d:IsA("BasePart") and not seen[d] then
				seen[d] = true
				local part = d :: BasePart
				if part.Transparency < 1 then
					if not part:IsA("MeshPart") then
						table.insert(
							lines,
							string.format(
								"[StandIn] %s: %s %q is visible and part-built (no MeshId); meshed art ships its mesh or nothing",
								pathOf(owner),
								part.ClassName,
								part.Name
							)
						)
					elseif (part :: MeshPart).MeshId == "" then
						table.insert(
							lines,
							string.format("[StandIn] %s: MeshPart %q has no MeshId", pathOf(owner), part.Name)
						)
					end
				end
			end
		end
	end
	if registered(root) then
		check(root)
	end
	for _, d in ipairs(root:GetDescendants()) do
		if registered(d) then
			check(d)
		end
	end
	return lines
end

return StandIn
