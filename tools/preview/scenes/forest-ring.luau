--!nocheck
-- The forest ring as a player at the spawn sees it on the high tier
-- (phase 10, FOR-02): the whole world (_world.luau) and exactly the filler
-- ForestFiller loads round a camera on the spawn pad: real filler trees
-- within QualityBudgets.High.FillerNear, dark stand-in blocks out to
-- FillerFar, and the grass tufts round the spawn and the north edge's
-- lawn (TuftNear). 1-4 from the spawn's eye (north past the sawmill, west, south
-- through the Starter Forest, south-east over the lot), 5 the forest's
-- north edge from its lawn, 6 the town and the ring from above, 7 the
-- near trees giving way to the stand-ins, from high over the town.
-- Heavy like world: shoot one view at a time.

local World = require("./_world")

return {
	build = function(ctx)
		local QualityBudgets = ctx.shared("QualityBudgets")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local built = World.build(ctx)
		local eye = WorldPlan.SpawnEye()
		World.forest(ctx, built.root, eye, QualityBudgets.High)
		World.tufts(ctx, built.root, { eye, ctx.roblox.Vector3.new(80, 7, 270) }, QualityBudgets.High.TuftNear)
		local e = { eye.X, eye.Y, eye.Z }
		built.cameras = {
			{ pos = e, target = { 0, 14, 400 }, label = "the spawn's eye, north", fov = 70 },
			{ pos = e, target = { -400, 12, 120 }, label = "the spawn's eye, west", fov = 70 },
			{ pos = e, target = { -30, 10, -300 }, label = "the spawn's eye, south", fov = 70 },
			{ pos = e, target = { 260, 10, -260 }, label = "the spawn's eye, south-east", fov = 70 },
			{ pos = { 80, 7, 270 }, target = { 120, 12, 420 }, label = "the north edge from the lawn", fov = 70 },
			{ pos = { 300, 380, -420 }, target = { 0, 0, 120 }, label = "the town and the ring from above" },
			{ pos = { 0, 900, -700 }, target = { 0, 0, 200 }, label = "near trees, then stand-ins" },
		}
		return built
	end,
}
