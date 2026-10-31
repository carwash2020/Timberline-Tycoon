--!strict
-- FirstView (T415): the assets the first screen needs, as the client preloads them behind the loading card:
-- the player's axe, Murph, and the spawn town's buildings and props. Never the whole manifest (that is the
-- server's MeshKit.Preload). Capped at PerfPolicy.PreloadCap, in this order, so a cut drops the least urgent.

local PerfPolicy = require(script.Parent.PerfPolicy)
local MeshManifest = require(script.Parent.Art.MeshManifest)

local FirstView = {}

-- MeshManifest group names, most urgent first.
FirstView.Groups = { "axes", "murph", "town" } :: { string }

function FirstView.List(): { string }
	local out: { string } = {}
	local seen: { [number]: boolean } = {}
	for _, name in ipairs(FirstView.Groups) do
		for _, group in ipairs(MeshManifest.Groups(true)) do
			if group.name == name then
				for _, entry in ipairs(group.entries) do
					if not seen[entry.id] and #out < PerfPolicy.PreloadCap then
						seen[entry.id] = true
						table.insert(out, "rbxassetid://" .. tostring(entry.id))
					end
				end
			end
		end
	end
	return out
end

return FirstView
