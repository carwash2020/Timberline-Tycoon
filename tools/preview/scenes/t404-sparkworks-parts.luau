--!nocheck
-- T404: Sparkworks from outside, parts only. Views: 1 front, 2 forty-five degrees.
local T404 = require("./_t404")

return T404.scene({
	kind = "Sparkworks",
	title = "SPARKWORKS",
	accent = { 46, 139, 139 },
	meshes = false,
	distance = 60,
	height = 14,
})
