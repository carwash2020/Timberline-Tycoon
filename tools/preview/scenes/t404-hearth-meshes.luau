--!nocheck
-- T404: HearthAndHome from outside, with the town meshes. Views: 1 front, 2 forty-five degrees.
local T404 = require("./_t404")

return T404.scene({
	kind = "HearthAndHome",
	title = "HEARTH & HOME",
	accent = { 47, 93, 58 },
	meshes = true,
	distance = 70,
	height = 15,
})
