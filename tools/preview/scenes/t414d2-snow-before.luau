--!nocheck
-- T414d-2 snow, before (see _t414d2.luau). View 1 eye level, 2 from above.
local T414 = require("./_t414d2")
return {
	build = function(ctx)
		return T414.scene(ctx, "snow", false)
	end,
}
