--!nocheck
-- T404: the Sawmill from outside, with the town meshes. Views: 1 front, 2 forty-five degrees.
local T404 = require("./_t404")

return T404.scene({
	kind = "Sawmill",
	title = "SAWMILL",
	accent = { 120, 80, 60 },
	meshes = true,
	distance = 75,
	height = 16,
})
