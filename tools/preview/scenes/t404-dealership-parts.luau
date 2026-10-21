--!nocheck
-- T404: Dealership from outside, parts only. Views: 1 front, 2 forty-five degrees.
local T404 = require("./_t404")

return T404.scene({
	kind = "Dealership",
	title = "DEALERSHIP",
	accent = { 47, 109, 181 },
	meshes = false,
	distance = 60,
	height = 12,
})
