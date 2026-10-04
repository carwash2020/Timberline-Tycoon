--!strict
-- BadgeService: badges already earned (reserved in wave 0). BadgeSync is
-- server -> client, so this module does not connect it and it has no
-- rate limit. Init is a no-op until the badge batch fills it in.

local BadgeService = {}

function BadgeService.Init() end

return BadgeService
