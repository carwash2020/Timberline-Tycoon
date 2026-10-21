--!nocheck
-- T404: ToolShed from outside, with the town meshes. Views: 1 front, 2 forty-five degrees.
local T404 = require("./_t404")

return T404.scene({
	kind = "ToolShed",
	title = "TOOL SHED",
	accent = { 150, 62, 44 },
	meshes = true,
	distance = 60,
	height = 14,
})
