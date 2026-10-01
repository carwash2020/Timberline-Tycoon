--!nocheck
-- The Cloud Chute, the Sky Bin and the Starfall forge.
return function(t)
	local function setup(options)
		options = options or {}
		local loader = t.loader()
		local Schema = loader:server("ProfileSchema")
		local profile = loader:shared("Util").deepCopy(Schema.Template)
		profile.cash = options.cash or 0
		profile.materials = options.materials or {}
		profile.forgeLogs = options.forgeLogs or {}
		profile.skyBin = options.skyBin or {}
		local player = {
			Name = "Tester",
			attrs = {},
			SetAttribute = function(self, key, value)
				self.attrs[key] = value
			end,
		}
		-- The logs in hand: options.hands lists their wood ids, options.figures
		-- the figure of some of them (by position), like TreeService's records.
		local logs, set = {}, {}
		for i, id in ipairs(options.hands or {}) do
			local uid = string.format("log%02d", i)
			logs[uid] = { def = { id = id }, tags = { figure = (options.figures or {})[i] } }
			set[uid] = true
		end
		local function heldUids()
			local uids = {}
			for uid in pairs(set) do
				table.insert(uids, uid)
			end
			table.sort(uids)
			return uids
		end
		local toasts, granted = {}, {}
		local signal = { Connect = function() end }
		loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
				TreeService = {
					GetLog = function(uid)
						return logs[uid]
					end,
				},
				CarryService = {
					Hands = function()
						return set
					end,
					Publish = function() end,
					TakeWhere = function(_, accept, max)
						local out = {}
						for _, uid in ipairs(heldUids()) do
							if (not max or #out < max) and accept(logs[uid].def) then
								set[uid] = nil
								table.insert(out, logs[uid].def.id)
							end
						end
						return out
					end,
				},
				AxeService = {
					Grant = function(_, axeId)
						table.insert(granted, axeId)
						return { uid = "u", id = axeId }, nil
					end,
				},
				NodeService = { Publish = function() end },
			},
			services = {
				Players = {
					GetPlayers = function()
						return {}
					end,
					PlayerRemoving = signal,
				},
				RunService = { Heartbeat = signal },
				CollectionService = {
					GetTagged = function()
						return {}
					end,
					GetInstanceAddedSignal = function()
						return signal
					end,
				},
			},
		})
		local Aether = loader:server("AetherService")
		Aether.Init(function(_, message)
			table.insert(toasts, message)
		end)
		return {
			A = Aether,
			profile = profile,
			player = player,
			toasts = toasts,
			granted = granted,
			hands = function()
				local ids = {}
				for _, uid in ipairs(heldUids()) do
					table.insert(ids, logs[uid].def.id)
				end
				return ids
			end,
		}
	end

	t.test("figured logs stay in hand: not down the chute, not into the forge", function()
		local s = setup({ hands = { "lumenwood", "lumenwood" }, figures = { "starfall" } })
		s.A.SendDown(s.player)
		t.eq(s.profile.skyBin, { "lumenwood" }, "only the plain log went down")
		t.eq(s.hands(), { "lumenwood" }, "the Starfall Burl log is still in hand")
		t.ok(string.find(s.toasts[1], "gondola") ~= nil, "the toast says how to get it down")
		local forge = setup({ hands = { "lumenwood" }, figures = { "curly" } })
		forge.A.AddToForge(forge.player)
		t.eq(forge.profile.forgeLogs.lumenwood or 0, 0)
		t.eq(forge.hands(), { "lumenwood" })
	end)

	t.test("the chute sends carried logs to the Sky Bin, up to its size", function()
		local s = setup({ hands = { "lumenwood", "lumenwood" } })
		s.A.SendDown(s.player)
		t.eq(s.profile.skyBin, { "lumenwood", "lumenwood" })
		t.eq(s.player.attrs.SkyBin, 2)
		t.eq(s.hands(), {})
		local full = setup({ hands = { "lumenwood", "lumenwood" }, skyBin = table.create(29, "lumenwood") })
		full.A.SendDown(full.player)
		t.eq(#full.profile.skyBin, 30)
		t.eq(#full.hands(), 1, "the one that didn't fit stays in hand")
	end)

	t.test("selling empties the bin", function()
		local s = setup({ skyBin = { "lumenwood", "oak" } })
		t.eq(s.A.TakeSkyBin(s.player), { "lumenwood", "oak" })
		t.eq(s.profile.skyBin, {})
		t.eq(s.A.TakeSkyBin(s.player), {})
	end)

	t.test("the forge takes lumenwood only, and only what it needs", function()
		local s = setup({ hands = { "lumenwood", "oak" }, forgeLogs = { lumenwood = 39 } })
		s.A.AddToForge(s.player)
		t.eq(s.profile.forgeLogs.lumenwood, 40)
		t.eq(s.hands(), { "oak" })
	end)

	t.test("forging: refused with what's missing, then done", function()
		local short = setup({ cash = 60000, forgeLogs = { lumenwood = 40 }, materials = { SkyShard = 11 } })
		short.A.Forge(short.player)
		t.eq(short.granted, {})
		t.eq(short.profile.cash, 60000)
		t.eq(short.toasts[#short.toasts], "The forge needs 1 more Sky Shards.")
		local ready = setup({ cash = 70000, forgeLogs = { lumenwood = 45 }, materials = { SkyShard = 12 } })
		ready.A.Forge(ready.player)
		t.eq(ready.granted, { "StarfallAxe" })
		t.eq(ready.profile.cash, 10000)
		t.eq(ready.profile.forgeLogs.lumenwood, 5)
		t.eq(ready.profile.materials.SkyShard, 0)
	end)
end
