--!nocheck
-- The SetQuality remote: the Lower / Higher graphics choice. Rate limited,
-- needs a loaded save, accepts "low" and "high" and nothing else, writes the
-- account's setting and mirrors the attribute the client reads.
return function(t)
	local now = 100
	local fakeOs = setmetatable({
		clock = function()
			return now
		end,
	}, { __index = os })

	local function setup(profileFor)
		now = 100
		local settings = t.shared("SettingsLogic").Sanitize(nil)
		local profile = { settings = settings }
		local player = {
			Name = "Tester",
			attributes = {},
			SetAttribute = function(self, name, value)
				self.attributes[name] = value
			end,
			Kick = function() end,
		}
		local loader = t.loader({
			globals = { os = fakeOs },
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						if profileFor == nil then
							return if p == player then profile else nil
						end
						return profileFor(p, profile)
					end,
				},
			},
		})
		return loader:server("QualityService"), player, profile
	end

	t.test("a good choice is saved on the account and mirrored for the client", function()
		local Service, player, profile = setup()
		t.eq(profile.settings.quality, "unset")
		t.eq(Service.Set(player, "low"), true)
		t.eq(profile.settings.quality, "low")
		t.eq(player.attributes.SettingQuality, "low")
		now += 1
		t.eq(Service.Set(player, "high"), true, "it can be changed later (Settings)")
		t.eq(profile.settings.quality, "high")
		t.eq(player.attributes.SettingQuality, "high")
	end)

	t.test("anything else is refused and the save is untouched", function()
		local Service, player, profile = setup()
		t.eq(Service.Set(player, "low"), true)
		for _, bad in ipairs({ "unset", "medium", "auto", "", "HIGH", " high", 1, 0, true, false, {}, "low\\n" }) do
			now += 1 -- a fresh second each time, so only the value is judged
			t.eq(Service.Set(player, bad), false, "refuses " .. tostring(bad))
			t.eq(profile.settings.quality, "low", "still low after " .. tostring(bad))
			t.eq(player.attributes.SettingQuality, "low")
		end
		now += 1
		t.eq(Service.Set(player, nil), false)
		t.eq(profile.settings.quality, "low")
	end)

	t.test("it is rate limited: two a second, then the rest are dropped (a flood is not saved)", function()
		local Service, player, profile = setup()
		local saved = 0
		for i = 1, 20 do
			local choice = if i % 2 == 0 then "low" else "high"
			if Service.Set(player, choice) then
				saved += 1
			end
		end
		t.eq(saved, 2, "two a second")
		t.eq(profile.settings.quality, "low", "the last one that got through (the second call)")
		now += 1
		t.eq(Service.Set(player, "high"), true, "a new second, a new budget")
		t.eq(profile.settings.quality, "high")
	end)

	t.test("a choice sent before the save has loaded is dropped, never saved onto nothing", function()
		local Service, player = setup(function()
			return nil
		end)
		t.eq(Service.Set(player, "low"), false)
		t.eq(player.attributes.SettingQuality, nil, "the client's attribute is not touched either")
	end)

	t.test("it only ever changes the quality setting", function()
		local Service, player, profile = setup()
		local Util = t.shared("Util")
		profile.cash = 123
		profile.axes = { { id = "RustyAxe" } }
		local before = Util.deepCopy(profile)
		before.settings.quality = "high"
		t.eq(Service.Set(player, "high"), true)
		t.eq(profile, before, "cash, axes and every other setting are as they were")
	end)

	t.test("the server's remote handler hands the choice to the service, and the remote exists", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		t.ok(
			string.find(
				source,
				"remote.SetQuality.OnServerEvent:Connect(function(player: Player, value: unknown)",
				1,
				true
			)
		)
		t.ok(string.find(source, "QualityService.Set(player, value)", 1, true))
		local Net = t.shared("Net")
		t.ok(table.find(Net.RemoteNames, "SetQuality") ~= nil)
		t.ok(table.find(Net.RemoteNames, "SaveSetting") ~= nil, "the old remote stays")
	end)
end
