--!nocheck
-- The whole world as MapBuilder builds it (Shared/World/WorldPlan + the art
-- modules): terrain, every tree, the town, boulders, the Skyroot and isles.
-- Client-side decoration (flowers, critters) isn't part of it. The build is
-- _world.luau (world-eye.luau shares it); these are the overview cameras.

local World = require("./_world")

return {
	build = function(ctx)
		local built = World.build(ctx)
		built.cameras = {
			{ pos = { 60, 45, -10 }, target = { 0, 8, 110 }, label = "from the spawn: the town and sawmill" },
			{ pos = { 260, 220, -260 }, target = { 0, 0, 60 }, label = "town and starter forest from above" },
			{ pos = { 20, 24, -60 }, target = { 0, 6, -120 }, label = "into the Starter Forest" },
			{ pos = { -250, 60, 30 }, target = { -420, 20, 110 }, label = "the Hills" },
			{ pos = { 120, 90, 900 }, target = { 0, 30, 1240 }, label = "the Snowfields" },
			{ pos = { 850, 100, 900 }, target = { 1150, 60, 1250 }, label = "the Volcano" },
			{ pos = { -700, 400, 650 }, target = { -1050, 500, 1050 }, label = "the Skyroot and the isles" },
			{ pos = { -1000, 740, 960 }, target = { -1050, 700, 1050 }, label = "on the isles" },
			{ pos = { 0, 2400, -1800 }, target = { 0, 0, 100 }, label = "the whole map" },
		}
		return built
	end,
}
