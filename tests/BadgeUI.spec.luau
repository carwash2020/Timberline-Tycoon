--!nocheck
-- BadgeUI: the panel reads the server's list and does not fire BadgeSync.
return function(t)
	local fs = require("@lune/fs")
	local BadgeData = t.shared("BadgeData")

	t.test("the panel is read-only, 44 px, and bound for keyboard, touch, and a pad", function()
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/BadgeUI.luau")
		t.ok(string.find(source, "BadgeData.MinTapPx", 1, true))
		t.ok(string.find(source, "BadgeData.OpenKeyboard", 1, true))
		t.eq(string.find(source, "BadgeData.OpenGamepad", 1, true), nil, "View is the quick menu's now")
		t.ok(string.find(source, 'HudNav.Add(open.face, { id = "badges"', 1, true), "the quick menu's Badges tile")
		t.ok(string.find(source, "BadgeData.CloseKeyboard", 1, true))
		t.ok(string.find(source, "HUD.Popup", 1, true))
		t.ok(string.find(source, "OnClientEvent", 1, true))
		t.ok(string.find(source, "FireServer", 1, true) == nil, "the client never fires BadgeSync")
		t.ok(string.find(source, 'SetAttribute("Badges"', 1, true) == nil, "the client does not write the earned set")
		t.eq(BadgeData.MinTapPx >= 44, true)
		local client = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Client.client.luau")
		t.ok(string.find(client, '"BadgeUI"', 1, true))
	end)
end
