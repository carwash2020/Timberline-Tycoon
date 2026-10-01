--!nocheck
-- TreeUI (StarterPlayerScripts/TreeUI): the tree HP bar is a UITheme pill,
-- about 110x12 px: a Paper track with a 2 px Ink stroke and a Green fill
-- that turns Amber at 50% HP and Danger at 25%; unlit (LightInfluence 0),
-- drawn on top (it sits inside the trunk), hidden past 60 studs.
return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local loader = t.loader({
		services = {
			CollectionService = {},
			Players = { LocalPlayer = {} },
			GuiService = {},
			TextChatService = {},
			UserInputService = {},
		},
	})
	local TreeUI = loader:load("StarterPlayer/StarterPlayerScripts/TreeUI")
	local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
	local C = UITheme.Colors

	t.test("the fill is Green, then Amber at half HP, then Danger at a quarter", function()
		t.eq(TreeUI.FillColor(0.99), C.Green)
		t.eq(TreeUI.FillColor(0.51), C.Green)
		t.eq(TreeUI.FillColor(0.5), C.Amber)
		t.eq(TreeUI.FillColor(0.26), C.Amber)
		t.eq(TreeUI.FillColor(0.25), C.Danger)
		t.eq(TreeUI.FillColor(0.01), C.Danger)
	end)

	t.test("the bar is a themed pill about 110x12 px", function()
		local gui, fill = TreeUI.MakeBar(Vector3.new(0, 2.5, 0))
		t.eq(gui.ClassName, "BillboardGui")
		t.eq(gui.Enabled, false)
		local track = gui:FindFirstChild("HPBg")
		t.ok(track, "a track")
		t.eq(track.Size.X.Offset, 110)
		t.eq(track.Size.Y.Offset, 12)
		t.eq(track.Size.X.Scale, 0)
		t.eq(track.BackgroundColor3, C.Paper)
		local stroke = track:FindFirstChildOfClass("UIStroke")
		t.ok(stroke, "an Ink stroke")
		t.eq(stroke.Color, C.Ink)
		t.eq(stroke.Thickness, 2)
		local corner = track:FindFirstChildOfClass("UICorner")
		t.ok(corner and corner.CornerRadius.Offset >= 6, "a pill (round ends)")
		-- The billboard leaves room for the stroke, which is drawn outside.
		t.ok(gui.Size.X.Offset >= 110 + 4 and gui.Size.Y.Offset >= 12 + 4, "room for the stroke")
		t.eq(gui.Size.X.Scale, 0) -- a fixed size on screen, not in studs
		t.eq(fill.Parent, track)
		t.eq(fill.BackgroundColor3, C.Green)
		t.ok(fill:FindFirstChildOfClass("UICorner"), "the fill has round ends too")
	end)

	t.test("the bar is unlit, on top and hidden past 60 studs", function()
		local gui = TreeUI.MakeBar(Vector3.new(0, -3, 0))
		t.eq(gui.LightInfluence, 0)
		t.eq(gui.AlwaysOnTop, true)
		t.eq(gui.MaxDistance, 60)
		t.eq(gui.StudsOffsetWorldSpace, Vector3.new(0, -3, 0)) -- world up, whatever the trunk's turn
	end)
end
