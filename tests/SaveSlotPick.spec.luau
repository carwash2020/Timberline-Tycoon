--!nocheck
-- Saves are picked by hand: joining loads no save for you. The server holds
-- the player "picking" (SlotPick) until play(index); only then does a save
-- with a plot ask for a pad. Mid-session swaps and the Restart save path
-- keep their old rules.
return function(t)
	local function boot(opts)
		opts = opts or {}
		local profiles, notes, order = {}, {}, {}
		local sent = nil
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(player)
						return profiles[player]
					end,
					Save = function()
						table.insert(order, "save")
					end,
				},
				EconomyService = {
					ReplaceCash = function(player, amount)
						profiles[player].cash = amount
					end,
				},
				RateLimiter = {
					Allow = function()
						return opts.rate ~= false
					end,
				},
			},
		})
		local Schema = loader:server("ProfileSchema")
		local Util = loader:shared("Util")
		local Service = loader:server("SaveSlotService")
		local signal = {}
		function signal:Connect(fn)
			self.fn = fn
		end
		local onBase = {}
		Service.Init({ OnServerEvent = signal }, {
			FireClient = function(_, _player, summary)
				sent = summary
			end,
		}, function(_player, message)
			table.insert(notes, message)
		end, {
			commit = function()
				table.insert(order, "commit")
			end,
			rebuild = function()
				table.insert(order, "rebuild")
			end,
			chosen = function()
				table.insert(order, "chosen")
			end,
			onBase = function(player)
				return onBase[player] == true
			end,
		})
		local function newPlayer(userId)
			local data = Util.deepCopy(Schema.Template)
			Schema.Migrate(data)
			local who = { UserId = userId, Name = "P" .. userId, attrs = {} }
			function who:SetAttribute(key, value)
				self.attrs[key] = value
			end
			profiles[who] = data
			return who, data
		end
		return {
			Service = Service,
			newPlayer = newPlayer,
			fire = function(who, ...)
				signal.fn(who, ...)
			end,
			order = order,
			notes = notes,
			sent = function()
				return sent
			end,
			onBase = onBase,
		}
	end

	t.test("joining loads no save: the player is picking, with the last-played save marked active", function()
		local h = boot()
		local who, data = h.newPlayer(1)
		h.Service.PlayerJoined(who)
		t.eq(who.attrs.SlotPick, true)
		t.eq(h.Service.IsPicking(who), true)
		t.eq(data.activeSlot, 1, "nothing was swapped or loaded")
		t.eq(#h.order, 0)
		t.eq(h.sent()[1].active, true)
		-- JoinSync sends the slots again: still one pick, not a second.
		h.Service.PlayerJoined(who)
		t.eq(who.attrs.SlotPick, true)
	end)

	t.test("playing the last-played save changes nothing and asks its plot for a pad", function()
		local h = boot()
		local who, data = h.newPlayer(1)
		local cash = data.cash
		h.Service.PlayerJoined(who)
		h.fire(who, "play", 1, true)
		t.eq(who.attrs.SlotPick, nil)
		t.eq(h.Service.IsPicking(who), false)
		t.eq(h.order, { "chosen" }, "no commit, no swap, no rebuild: only the pad question")
		t.eq(data.cash, cash)
		t.eq(data.slotCooldownUntil, 0, "and no cooldown was spent")
		-- A second play, or a stale one, does nothing.
		h.fire(who, "play", 1, true)
		t.eq(h.order, { "chosen" })
		h.Service.PlayerJoined(who)
		t.eq(who.attrs.SlotPick, nil, "a resend does not ask again")
	end)

	t.test(
		"playing another save is a normal swap: commit, swap, rebuild (which asks for its pad), cooldown stamped",
		function()
			local h = boot()
			local who, data = h.newPlayer(1)
			h.Service.PlayerJoined(who)
			h.fire(who, "play", 2, true)
			t.eq(data.activeSlot, 2)
			t.eq(h.order, { "commit", "rebuild", "save" }, "the rebuild asks for the pad; no second ask")
			t.eq(who.attrs.SlotPick, nil)
			t.eq(who.attrs.ActiveSlot, 2)
			t.ok(data.slotCooldownUntil > 0)
		end
	)

	t.test("a pick the cooldown refuses leaves the picker up and the save untouched", function()
		local h = boot()
		local who, data = h.newPlayer(1)
		data.slotCooldownUntil = os.time() + 100
		h.Service.PlayerJoined(who)
		h.fire(who, "play", 2, true)
		t.eq(data.activeSlot, 1)
		t.eq(who.attrs.SlotPick, true, "still choosing")
		t.eq(#h.order, 0)
		t.ok(string.find(h.notes[#h.notes], "more seconds", 1, true) ~= nil, h.notes[#h.notes])
		h.fire(who, "play", 1, true)
		t.eq(who.attrs.SlotPick, nil, "the last-played save is always playable")
	end)

	t.test("play is validated: only while picking, only a real save", function()
		local h = boot()
		local who, data = h.newPlayer(1)
		h.fire(who, "play", 2, true)
		t.eq(data.activeSlot, 1, "not picking: ignored")
		h.Service.PlayerJoined(who)
		for _, junk in ipairs({ 0, 4, -1, 1.5, "2", {}, true, 0 / 0, math.huge }) do
			h.fire(who, "play", junk, true)
		end
		t.eq(who.attrs.SlotPick, true)
		t.eq(data.activeSlot, 1)
		t.eq(#h.order, 0)
	end)

	t.test("a player already on a base this session is never asked", function()
		local h = boot()
		local who = h.newPlayer(1)
		h.onBase[who] = true
		h.Service.PlayerJoined(who)
		t.eq(who.attrs.SlotPick, nil)
		t.eq(h.Service.IsPicking(who), false)
	end)

	t.test("Restart save is refused until a save is picked, and still needs its two steps", function()
		local h = boot()
		local who, data = h.newPlayer(1)
		data.cash = 500
		h.Service.PlayerJoined(who)
		h.fire(who, "arm", 0, false)
		h.fire(who, "reset", 0, true)
		t.eq(data.cash, 500, "nothing wiped while picking")
		t.eq(h.notes[#h.notes], "Pick a save to play first.")
		h.fire(who, "play", 1, true)
		h.fire(who, "reset", 0, true)
		t.eq(data.cash, 500, "unarmed: refused")
		t.eq(h.notes[#h.notes], "Press Restart save again to confirm. That save's cash, wood and plot will be wiped.")
		h.fire(who, "arm", 0, false)
		h.fire(who, "reset", 0, true)
		t.ok(data.cash ~= 500 or #h.order > 1, "armed: the wipe went through the normal Perform")
		t.eq(h.order[#h.order], "save")
	end)

	t.test("it is rate limited, and leaving forgets the pick", function()
		local h = boot({ rate = false })
		local who = h.newPlayer(1)
		h.Service.PlayerJoined(who)
		h.fire(who, "play", 1, true)
		t.eq(who.attrs.SlotPick, true, "a limited call did nothing")
		h.Service.PlayerRemoving(who)
		t.eq(h.Service.IsPicking(who), false)
	end)

	t.test("the wiring: the join no longer opens the plot picker, a save pick does", function()
		local fs = require("@lune/fs")
		local server = fs.readFile("src/ServerScriptService/GameServer.server.luau")
		local join = string.find(server, 'safely("PlotService.Prepare"', 1, true)
		t.ok(join ~= nil, "the join only prepares the plot")
		t.eq(string.find(server, 'safely("PlotService.PlayerJoined"', 1, true), nil, "no picker at profile load")
		t.ok(string.find(server, "chosen = function(player: Player)", 1, true), "the pick asks for the pad")
		t.ok(string.find(server, "PlotService.PlayerJoined(player, profile)", 1, true), "through the same picker")
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/PlotPickerUI.luau")
		t.ok(string.find(ui, 'Net.Remote("PlotShown"):FireServer()', 1, true), "the timer starts when it is shown")
	end)
end
