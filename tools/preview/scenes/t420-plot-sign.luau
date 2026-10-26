--!nocheck
-- T420: the PLOT DISTRICT sign, before (left) and after (right), seen front-on.
-- Both are the game's own BuildingArt.Signpost with the sign's real text: the
-- left one without the `panel` option (what main builds), the right one with
-- it (PlankHoney planks, Ink on a SignCream panel ON the board face).
-- PREVIEW ONLY: a three.js viewer, not Roblox lighting; Roblox's material
-- textures and font rendering are only in Studio. Views:
--   1 front-on, both signs   2 front-on, the new sign alone   3 phone crop of the new sign
local Common = require("./_common")

return {
	build = function(ctx)
		local roblox = ctx.roblox
		local V3, CF = roblox.Vector3, roblox.CFrame
		local Kit = ctx.art("Kit")
		local BuildingArt = ctx.art("BuildingArt")
		local WorldPlan = ctx.load("ReplicatedStorage/Shared/World/WorldPlan")
		local root = roblox.Instance.new("Model")
		Common.ground(ctx, root, 120, nil, V3.new(0, -0.5, 0))
		local plan
		for _, sign in ipairs(WorldPlan.Town().signs) do
			if string.match(sign.text, "^PLOT DISTRICT") then
				plan = sign
			end
		end
		assert(plan ~= nil and plan.panel == true, "the town's PLOT DISTRICT sign asks for the panel")
		local before = BuildingArt.Signpost(plan.text, plan.lit, nil, plan.gateId, plan.noWrap)
		Kit.placeAt(before, CF.new(-12, 0, 0))
		before.Parent = root
		local after = BuildingArt.Signpost(plan.text, plan.lit, nil, plan.gateId, plan.noWrap, plan.panel)
		Kit.placeAt(after, CF.new(8, 0, 0))
		after.Parent = root
		return {
			root = root,
			shadowRadius = 40,
			fov = 35,
			-- A sign's front is its -Z face: stand at -Z and look along +Z.
			cameras = {
				{
					pos = { -2, 7, -38 },
					target = { -2, 5.5, 0 },
					label = "after (left) and before = main (right): front-on",
				},
				{ pos = { 8, 7, -17 }, target = { 8, 7, 0 }, label = "after: front-on, the text on the board face" },
				{ pos = { 8, 7, -14 }, target = { 8, 7, 0 }, label = "after: phone-size crop (844x390)" },
			},
		}
	end,
}
