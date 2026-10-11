--!nocheck
-- Plot bans in the saved permissions, the kick rules and the report button's rules.
return function(t)
	local Perm = t.shared("PermissionLogic")
	local Mod = t.shared("ModerationLogic")

	local function ctx(over)
		local c = { ownerId = 1, ownsPlot = true, targetHere = true, targetOnPlot = true, targetIsStaff = false }
		for k, v in pairs(over or {}) do
			c[k] = v
		end
		return c
	end

	t.test("a ban turns every permission off for that person, over 'anyone'", function()
		local p = { anyone = { build = true, interact = true, grab = true, visit = true } }
		t.ok(Perm.Allows(p, 2, "build"))
		local ok = Perm.Ban(p, 1, 2, "Bob", 100)
		t.ok(ok)
		for _, flag in ipairs(Perm.Flags) do
			t.eq(Perm.Allows(p, 2, flag), false, flag)
		end
		t.ok(Perm.MustLeave(p, 2, 1))
		t.eq(Perm.CanVisit(p, 2, 1), false)
		t.ok(Perm.Allows(p, 3, "build"), "other people keep the 'anyone' row")
		t.eq(t.shared("PlotLogic").CanEdit(p, 2, 1, "paint"), false)
	end)

	t.test("ban rules: bad ids, yourself, twice, the cap, names", function()
		local p = {}
		t.eq({ Perm.Ban(p, 1, 1, "Me", 0) }, { false, "You can't ban yourself." })
		for _, junk in ipairs({ "2", 0, -3, 1.5, 0 / 0, math.huge, {}, true }) do
			t.eq({ Perm.Ban(p, 1, junk, "x", 0) }, { false, "bad" }, tostring(junk))
		end
		t.ok(Perm.Ban(p, 1, 2, "Bob_1", 5))
		t.eq({ Perm.Ban(p, 1, 2, "Bob", 6) }, { false, "They are already banned from your plot." })
		t.eq(Perm.Bans(p)[1], { userId = 2, name = "Bob_1", at = 5 })
		Perm.Ban(p, 1, 3, "has spaces & <b>", 6)
		t.eq(Perm.Bans(p)[2].name, "Player 3", "an unsafe name is not kept")
		t.ok(Perm.Ban(p, 1, 4, nil, 7))
		t.eq(Perm.Bans(p)[3].name, "Player 4")
		for i = 5, Perm.MaxBans + 1 do
			Perm.Ban(p, 1, i, "u" .. i, i)
		end
		t.eq(#Perm.Bans(p), Perm.MaxBans)
		local ok, why = Perm.Ban(p, 1, 9999, "late", 1)
		t.eq(ok, false)
		t.ok(string.find(why, "full", 1, true) ~= nil)
	end)

	t.test("a ban can't be toggled away, does not use up the named-people slots, and Unban lifts it", function()
		local p = {}
		Perm.Ban(p, 1, 2, "Bob", 1)
		t.eq(Perm.Set(p, "2", "visit", true), false)
		for i = 1, Perm.MaxPeople do
			t.ok(Perm.Set(p, tostring(100 + i), "sit", true), "person " .. i)
		end
		t.ok(Perm.Unban(p, 2))
		t.eq(Perm.IsBanned(p, 2), false)
		t.eq(p["2"], nil)
		t.eq(Perm.Unban(p, 2), false)
		t.ok(Perm.Allows(p, 2, "visit"), "back to the default")
	end)

	t.test("bans survive the encode / decode of the attribute and the save round trip", function()
		local p = {}
		Perm.Ban(p, 1, 20, "Zed", 2)
		Perm.Ban(p, 1, 10, "Amy", 1)
		t.eq(Perm.EncodeBans(p), "10:Amy;20:Zed", "oldest first")
		t.eq(Perm.DecodeBans("10:Amy;20:Zed"), { { userId = 10, name = "Amy" }, { userId = 20, name = "Zed" } })
		t.eq(Perm.DecodeBans("junk;;-4:x;5:"), {})
		t.eq(Perm.DecodeBans(nil), {})
		local decoded = Perm.Decode(Perm.Encode(p))
		t.eq(decoded["10"].visit, false, "a visitor's own client sees visit off")
		local Util = t.shared("Util")
		local copy = Util.deepCopy(p)
		t.ok(Perm.IsBanned(copy, 20))
	end)

	t.test("Check: owner only, real ids, on the plot to be kicked, never yourself or staff", function()
		local p = {}
		t.eq({ Mod.Check(p, "kick", 2, ctx()) }, { true, 2, nil })
		t.eq({ Mod.Check(p, "ban", 2, ctx({ targetHere = false, targetOnPlot = false })) }, { true, 2, nil })
		t.eq(
			{ Mod.Check(p, "kick", 2, ctx({ targetOnPlot = false })) },
			{ false, nil, "They aren't on your plot right now." }
		)
		t.eq(
			{ Mod.Check(p, "kick", 2, ctx({ targetHere = false })) },
			{ false, nil, "They aren't on your plot right now." }
		)
		t.eq({ Mod.Check(p, "kick", 2, ctx({ ownsPlot = false })) }, { false, nil, "You need a plot to do that." })
		t.eq({ Mod.Check(p, "ban", 1, ctx()) }, { false, nil, "That's you." })
		t.eq(
			{ Mod.Check(p, "ban", 2, ctx({ targetIsStaff = true })) },
			{ false, nil, "You can't do that to the game's owner." }
		)
		t.eq({ Mod.Check(p, "unban", 2, ctx()) }, { false, nil, "They aren't banned from your plot." })
		Perm.Ban(p, 1, 2, "Bob", 0)
		t.eq({ Mod.Check(p, "unban", 2, ctx({ targetHere = false })) }, { true, 2, nil })
		t.eq({ Mod.Check(p, "explode", 2, ctx()) }, { false, nil, "bad" })
		t.eq({ Mod.Check(p, "kick", "2", ctx()) }, { false, nil, "bad" })
	end)

	t.test("kicks last KickSeconds and are in memory only", function()
		local kicks = {}
		t.eq(Mod.IsKicked(kicks, 1, 2, 0), false)
		Mod.Kick(kicks, 1, 2, 10)
		t.ok(Mod.IsKicked(kicks, 1, 2, 10 + Mod.KickSeconds - 1))
		t.eq(Mod.IsKicked(kicks, 1, 3, 11), false, "someone else is fine")
		t.eq(Mod.IsKicked(kicks, 9, 2, 11), false, "another owner's plot is fine")
		t.eq(Mod.IsKicked(kicks, 1, 2, 10 + Mod.KickSeconds), false)
		t.eq(kicks[1][2], nil, "the entry is dropped once it ends")
		t.eq(Mod.Excluded({}, kicks, 1, 1, 0), false, "never the owner")
		Mod.Kick(kicks, 1, 2, 0)
		t.ok(Mod.Excluded({}, kicks, 1, 2, 5))
		local p = {}
		Perm.Ban(p, 1, 3, "Cat", 0)
		t.ok(Mod.Excluded(p, kicks, 1, 3, 5))
	end)

	t.test("the report button: Roblox's reasons only, shown only where the call exists and someone is here", function()
		t.ok(Mod.ReportShown(true, 1))
		t.eq(Mod.ReportShown(false, 5), false, "hidden where the call is unavailable")
		t.eq(Mod.ReportShown(true, 0), false, "nobody to report")
		t.eq(Mod.ReportShown(true, -1), false)
		t.eq(Mod.ReasonId("Swearing"), "Swearing")
		t.eq(Mod.ReasonId("made up"), nil)
		t.eq(Mod.ReasonId(5), nil)
		t.ok(#Mod.ReportReasons >= 6)
		t.ok(Mod.Tap >= 44)
	end)

	t.test("the report tab and the moderation buttons: 44 px taps, no ButtonR2, intents only", function()
		local fs = require("@lune/fs")
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/SettingsUI.luau")
		t.ok(t.shared("SettingsLogic").HasTab("report"))
		t.ok(string.find(ui, "ModerationLogic.ReportShown", 1, true), "hidden by the shared rule")
		t.ok(string.find(ui, "ReportAbuse", 1, true))
		t.ok(not string.find(ui, "ButtonR2", 1, true), "R2 is never bound")
		t.ok(string.find(ui, 'Net.Remote("PlotModerate"):FireServer("kick"', 1, true))
		t.ok(string.find(ui, 'Net.Remote("PlotModerate"):FireServer("ban"', 1, true))
		t.ok(string.find(ui, 'Net.Remote("PlotModerate"):FireServer("unban"', 1, true))
		t.ok(
			string.find(ui, "tap = math.max(rowSize.Y, PermissionLogic.Tap, UITheme.Size.Tap)", 1, true),
			"every row is 44+"
		)
		t.ok(t.shared("PermissionLogic").Tap >= 44)
		local net = t.shared("Net")
		t.ok(table.find(net.RemoteNames, "PlotModerate") ~= nil)
	end)
end
