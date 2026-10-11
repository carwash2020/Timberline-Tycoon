--!nocheck
-- Slot names are filtered on the server before they are stored or sent.
return function(t)
	local function boot(filterImpl)
		local calls = {}
		local profiles = {}
		local sent = nil
		local notes = {}
		local loader = t.loader({
			services = {
				TextService = {
					FilterStringAsync = function(_self, text, userId, context)
						table.insert(calls, { text = text, userId = userId, context = context })
						return filterImpl(text)
					end,
				},
			},
			mocks = {
				ProfileService = {
					GetProfile = function(player)
						return profiles[player]
					end,
					Save = function() end,
				},
				EconomyService = { ReplaceCash = function() end },
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
			},
		})
		local Schema = loader:server("ProfileSchema")
		local Util = loader:shared("Util")
		local SaveSlot = loader:server("SaveSlotService")
		local signal = {}
		function signal:Connect(fn)
			self.fn = fn
		end
		local state = {
			FireClient = function(_self, _player, summary)
				sent = summary
			end,
		}
		SaveSlot.Init({ OnServerEvent = signal }, state, function(_player, message)
			table.insert(notes, message)
		end, {
			commit = function() end,
			rebuild = function() end,
		})
		local function player()
			local data = Util.deepCopy(Schema.Template)
			Schema.Migrate(data)
			local who = {
				UserId = 42,
				Name = "Ann",
				attrs = {},
				SetAttribute = function(self, key, value)
					self.attrs[key] = value
				end,
			}
			profiles[who] = data
			return who, data
		end
		return {
			fire = function(who, ...)
				signal.fn(who, ...)
			end,
			calls = calls,
			SaveSlot = SaveSlot,
			notes = notes,
			sent = function()
				return sent
			end,
			player = player,
		}
	end

	t.test("a slot name is filtered for broadcast before anyone can see it", function()
		local harness = boot(function()
			return {
				GetNonChatStringForBroadcastAsync = function()
					return "Oak"
				end,
			}
		end)
		local who, data = harness.player()
		harness.fire(who, "rename", 1, "  Bad Name ")
		t.eq(#harness.calls, 1)
		t.eq(harness.calls[1].text, "Bad Name")
		t.eq(harness.calls[1].userId, 42)
		t.eq(harness.calls[1].context, t.roblox.Enum.TextFilterContext.PublicChat)
		t.eq(data.slots[1].name, "Oak")
		t.eq(harness.sent()[1].name, "Oak")
	end)

	t.test("a filter failure stores the default name, not what was typed", function()
		local harness = boot(function()
			error("filter down")
		end)
		local who, data = harness.player()
		harness.fire(who, "rename", 2, "Secret")
		t.eq(data.slots[2].name, "Save 2")
		t.eq(harness.sent()[2].name, "Save 2")
		t.eq(harness.notes[1], "That name couldn't be shown, so this slot keeps a plain name.")
	end)
	-- Lane F: Save now. The SAVES panel's button writes the truck's load and the
	-- profile on its own 30 s cooldown, and never while a swap or an unload runs.
	t.test(
		"Save now writes once, stamps its cooldown and the time, and a second press inside 30 s writes nothing",
		function()
			local harness = boot(function() end)
			local who, data = harness.player()
			local wrote, truckSaves = 0, 0
			harness.SaveSlot.BindSaveNow(nil, {
				truck = function()
					truckSaves += 1
				end,
				busy = function()
					return false
				end,
			})
			local profileSave = harness.SaveSlot
			t.eq(profileSave.SaveNow(who, data.activeSlot, 1000), true)
			t.eq(truckSaves, 1, "the truck's load went into the profile first")
			t.eq(who.attrs.LastSavedAt, 1000, "Saved at ... reads this")
			t.eq(data.saveCooldownUntil, 1030)
			t.eq(who.attrs.SaveCooldownUntil, 1030)
			t.eq(profileSave.SaveNow(who, data.activeSlot, 1010), false, "inside the cooldown: nothing is written")
			t.eq(truckSaves, 1)
			t.eq(who.attrs.LastSavedAt, 1000, "and the time does not move")
			t.ok(
				string.find(harness.notes[#harness.notes], "20 seconds", 1, true) ~= nil,
				harness.notes[#harness.notes]
			)
			t.eq(profileSave.SaveNow(who, data.activeSlot, 1030), true, "exactly on time it writes again")
			t.eq(truckSaves, 2)
			_ = wrote
		end
	)

	t.test("Save now refuses mid-unload, before a save is picked, for the wrong slot and with junk", function()
		local harness = boot(function() end)
		local who, data = harness.player()
		local busy = true
		local truckSaves = 0
		harness.SaveSlot.BindSaveNow(nil, {
			truck = function()
				truckSaves += 1
			end,
			busy = function()
				return busy
			end,
		})
		t.eq(harness.SaveSlot.SaveNow(who, data.activeSlot, 50), false, "mid-unload")
		t.eq(truckSaves, 0, "nothing was written")
		t.eq(data.saveCooldownUntil, 0, "and no cooldown was spent")
		t.ok(string.find(harness.notes[#harness.notes], "a save is changing", 1, true) ~= nil)
		busy = false
		t.eq(harness.SaveSlot.SaveNow(who, data.activeSlot + 1, 50), false, "another slot than the one being played")
		t.eq(harness.SaveSlot.SaveNow(who, "1", 50), false)
		t.eq(harness.SaveSlot.SaveNow(who, nil, 50), false)
		t.eq(harness.SaveSlot.SaveNow(who, {}, 50), false)
		harness.SaveSlot.PlayerJoined(who) -- joined, has not picked a save yet
		t.eq(harness.SaveSlot.SaveNow(who, data.activeSlot, 50), false, "the join pick is still up")
		t.eq(truckSaves, 0)
		harness.fire(who, "play", data.activeSlot) -- the pick is made
		t.eq(harness.SaveSlot.SaveNow(who, data.activeSlot, 50), true)
		t.eq(truckSaves, 1)
	end)

	t.test("Save now is refused while a load or a reset is running", function()
		local harness = boot(function() end)
		local who, data = harness.player()
		local during = nil
		harness.SaveSlot.BindSaveNow(nil, { truck = function() end })
		-- A load of another save runs the commit hook; Save now pressed from inside it waits.
		local profile = data
		profile.slotCooldownUntil = 0
		harness.SaveSlot.Init(
			{ OnServerEvent = {
				Connect = function(_, fn)
					harness.fire = fn
				end,
			} },
			{ FireClient = function() end },
			function() end,
			{
				commit = function()
					during = harness.SaveSlot.SaveNow(who, data.activeSlot, 10)
				end,
				rebuild = function() end,
			}
		)
		harness.fire(who, "load", data.activeSlot % 3 + 1, true)
		t.eq(during, false, "mid-swap: refused")
	end)
end
