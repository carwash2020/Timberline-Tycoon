--!strict
-- TreeSpreadItems: the trees and the obstacles TreeSpread.PlanSkip works on,
-- built the same way for tools/tree_report (which writes TreeSpreadData) and
-- tests/TreeSpreadThin.spec (which checks it). Reads the world plan: never run
-- at boot.

local GrowLogic = require(script.Parent.Parent.GrowLogic)
local WoodData = require(script.Parent.Parent.WoodData)
local TreeSpread = require(script.Parent.TreeSpread)

local TreeSpreadItems = {}

local SUPPLY: { [string]: boolean } = { starter = true, hills = true, snow = true, volcano = true, grove = true }

local function trunkRadius(woodId: string): number
	local wood = WoodData.Get(woodId)
	local shape = if wood and wood.v2 then wood.v2.shape else nil
	local thickness = if shape then shape.trunkThickness else 1.6
	return thickness / 2 + 1.0
end

-- `plan` is WorldPlan. Returns the items (Trees() first, in order, then every
-- other list) and the obstacles (boulders, cluster rocks, scenery).
function TreeSpreadItems.Build(plan: any): ({ TreeSpread.Item }, { TreeSpread.Obstacle })
	local first = plan.FirstTreeCount()
	local items: { TreeSpread.Item } = {}
	for i, spot in ipairs(plan.Trees()) do
		local prefix = if spot.zone then string.match(spot.zone.id, "^[^:]*") else "none"
		local fixed = i <= first or SUPPLY[spot.biome] == true or prefix == "town" or prefix == "plot"
		local anchor = false
		if not fixed then
			local _, sizeName = GrowLogic.Site(spot.position)
			anchor = sizeName == "large"
		end
		table.insert(items, {
			x = spot.position.X,
			z = spot.position.Z,
			index = i,
			movable = not fixed,
			anchor = anchor,
			r = trunkRadius(spot.woodId),
		})
	end
	local function other(list: { any })
		for _, spot in ipairs(list) do
			table.insert(items, {
				x = spot.position.X,
				z = spot.position.Z,
				movable = false,
				r = trunkRadius(spot.woodId or "palmwood"),
			})
		end
	end
	other(plan.StripTrees())
	other(plan.FerryPalms())
	other(plan.Lanternwood())
	other(plan.RegionTrees())
	other(plan.ReachTrees())
	other(plan.AddedTrees())

	local obstacles: { TreeSpread.Obstacle } = {}
	for _, list in ipairs({ plan.Boulders(), plan.MeadowBoulders() }) do
		for _, b in ipairs(list) do
			table.insert(obstacles, { x = b.position.X, z = b.position.Z, r = b.size * 0.86, gap = 2 })
		end
	end
	for _, cluster in ipairs(plan.BoulderClusters()) do
		for _, rock in ipairs(cluster.rocks) do
			table.insert(obstacles, { x = rock.position.X, z = rock.position.Z, r = rock.size * 0.5, gap = 0.0001 })
		end
	end
	for _, spot in ipairs(plan.Scenery()) do
		table.insert(obstacles, { x = spot.center.X, z = spot.center.Z, r = spot.radius, gap = 0.0001 })
	end
	return items, obstacles
end

return TreeSpreadItems
