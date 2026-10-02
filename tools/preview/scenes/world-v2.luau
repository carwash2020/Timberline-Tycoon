--!nocheck
-- The whole world as MapBuilder builds it under the v2 loop (V2_PLAN.md
-- M1.3): world.luau's build and cameras, with the section trees
-- SectionTrees plants at boot (most mature, some young) in place of
-- TreeService's. Compare world-<n>.png with world-v2-<n>.png.

local World = require("./_world")

return {
	build = function(ctx)
		local built = World.build(ctx, { forest = true, v2 = true })
		built.cameras = {
			{ pos = { 60, 45, -10 }, target = { 0, 8, 110 }, label = "from the spawn: the town and sawmill" },
			{ pos = { 260, 220, -260 }, target = { 0, 0, 60 }, label = "town and starter forest from above" },
			-- The section trees are much bigger (V2_PLAN §3a): world.luau's 24-stud
			-- camera is inside their crowns, so this one walks in at eye level.
			{ pos = { 20, 6, -60 }, target = { 0, 12, -120 }, label = "into the Starter Forest, eye level" },
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
