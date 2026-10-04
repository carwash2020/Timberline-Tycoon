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
				EconomyService = {},
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
				SetAttribute = function() end,
			}
			profiles[who] = data
			return who, data
		end
		return {
			fire = function(who, ...)
				signal.fn(who, ...)
			end,
			calls = calls,
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
end
