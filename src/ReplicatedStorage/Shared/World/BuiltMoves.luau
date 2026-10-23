--!strict
-- BuiltMoves (T409): the few pieces the world overlap lint (tests/GeometryLint, rule 2b) found standing
-- inside other pieces, moved to where they are built. WorldPlan's own lists are untouched on purpose: the tree
-- plan keeps off the boulders, the scenery, the fences and the signs, and is pinned as main's (TreeFill,
-- TreeSpread*, TreeCover, ClientFreeze), so the planning lists stay the fingerprint the trees were planned
-- against, and what MapBuilder builds (and the overlap check measures) is these lists. Pure: positions only.
--   boulder 58 (Boulders)       Secret Cave wall and floor -> 7 studs out from the cave, clear of the trees there
--   meadow boulder 16           ruined cabin               -> 4.7 studs south, clear of its back wall
--   meadow boulder 9            log pile 3                 -> 4 studs south, clear of the pile
--   scenery spot 32 (LogPile)   Secret Cave floor          -> out of the cave, 4.3 studs clear, on the ground
--   fences 1 and 2 (the paddock) 17 studs of rail inside Hearth & Home -> stop 0.5 clear of its west wall; fence
--                                3 gives them its corner posts
--   the Skyroot road sign       inside the Skyroot trunk's roots -> 5.7 studs along, clear of them and the road

local BuiltMoves = {}

export type Boulder = { position: Vector3, size: number, seed: number, snowy: boolean, dark: boolean }

local function movedTo(
	list: { Boulder },
	moves: { [number]: { number } },
	heightAt: (number, number) -> number
): { Boulder }
	local out: { Boulder } = {}
	for i, b in ipairs(list) do
		local to = moves[i]
		if to then
			out[i] = {
				position = Vector3.new(to[1], heightAt(to[1], to[2]) - 0.6, to[2]),
				size = b.size,
				seed = b.seed,
				snowy = b.snowy,
				dark = b.dark,
			}
		else
			out[i] = b
		end
	end
	return out
end

-- `plan` is WorldPlan, `terrain` TerrainGen (a parameter so a spec can hand in its own).
function BuiltMoves.Boulders(plan: any, terrain: any): { Boulder }
	return movedTo(plan.Boulders(), { [58] = { -728.5, -79.5 } }, terrain.HeightAt)
end

function BuiltMoves.MeadowBoulders(plan: any, terrain: any): { Boulder }
	return movedTo(plan.MeadowBoulders(), { [16] = { -196.5, 122.8 }, [9] = { 54.4, 262.4 } }, terrain.HeightAt)
end

-- WorldPlan.Scenery() with log pile 32 moved out of the Secret Cave, standing on the ground like the generator
-- stands every piece (its base at the lowest ground under its footprint).
function BuiltMoves.Scenery(plan: any, terrain: any): { any }
	local out: { any } = {}
	for i, spot in ipairs(plan.Scenery()) do
		if i == 32 and spot.kind == "LogPile" then
			local x, z = -715.2, -119.5
			local lowest = math.huge
			for _, q in ipairs(plan.SceneryFootprint(x, z, spot.radius)) do
				lowest = math.min(lowest, terrain.HeightAt(q.X, q.Y))
			end
			local delta = Vector3.new(x - spot.center.X, (lowest - 0.1) - spot.center.Y, z - spot.center.Z)
			local items = {}
			for k, item in ipairs(spot.items) do
				items[k] = { builder = item.builder, cframe = item.cframe + delta, seed = item.seed, size = item.size }
			end
			out[i] = { kind = spot.kind, center = spot.center + delta, radius = spot.radius, items = items }
		else
			out[i] = spot
		end
	end
	return out
end

export type Fence = { length: number, cframe: CFrame, noEndPosts: boolean? }

-- The town's fences with the paddock's two rails cut back to the corner posts, and its end fence without its own.
function BuiltMoves.Fences(fences: { any }): { Fence }
	local out: { Fence } = {}
	for i, f in ipairs(fences) do
		if i == 1 or i == 2 then
			local p = f.cframe.Position
			out[i] = { length = 2, cframe = CFrame.new(-127, p.Y, p.Z) * (f.cframe - f.cframe.Position) }
		elseif i == 3 then
			out[i] = { length = f.length, cframe = f.cframe, noEndPosts = true }
		else
			out[i] = { length = f.length, cframe = f.cframe }
		end
	end
	return out
end

-- WorldPlan.RoadSigns(text) with the Skyroot's sign (the fourth road's) set down at (683.1, 305.4).
function BuiltMoves.RoadSigns(plan: any, terrain: any, text: (string) -> string): { any }
	local out: { any } = {}
	for i, sign in ipairs(plan.RoadSigns(text)) do
		if i == 4 then
			local at: CFrame = sign.cframe
			local flat = CFrame.fromMatrix(Vector3.new(683.09, 0, 305.43), at.XVector, at.YVector, at.ZVector)
			local post = 4.95 + 0.35 -- (WorldPlan's SIGN_POST: the posts' outer faces either side of the middle)
			local a, b = flat * Vector3.new(-post, 0, 0), flat * Vector3.new(post, 0, 0)
			local y = math.min(terrain.HeightAt(a.X, a.Z), terrain.HeightAt(b.X, b.Z))
			local copy = table.clone(sign)
			copy.cframe = flat + Vector3.new(0, y, 0)
			out[i] = copy
		else
			out[i] = sign
		end
	end
	return out
end

return BuiltMoves
