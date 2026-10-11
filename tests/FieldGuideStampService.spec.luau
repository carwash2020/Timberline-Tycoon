--!nocheck
-- Rosa's stamps on the server: the first sale of a wood stamps it and pays once.
return function(t)
	local function setup()
		local profile = {
			cash = 0,
			totalEarned = 0,
			bestAxeTier = 1,
			compendium = {},
			guideStamps = {},
			onboarding = {},
			secretsFound = {},
			tutorialDone = true,
			forest = { figures = {} },
		}
		local player = {
			UserId = 5,
			Name = "T",
			attrs = {},
			SetAttribute = function(self, k, v)
				self.attrs[k] = v
			end,
		}
		local loader = t.loader({
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
			},
		})
		local Service = loader:server("FieldGuideService")
		local toasts = {}
		Service.Init(function(_, text)
			table.insert(toasts, text)
		end)
		return Service, player, profile, toasts, loader:shared("WoodData"), loader:shared("FieldGuideStamps")
	end

	t.test("the first sale of a wood stamps it, pays once and toasts", function()
		local Service, player, profile, toasts, WoodData, Stamps = setup()
		local id = WoodData.All()[1].id
		Service.Stamp(player, { [id] = 4 })
		t.eq(profile.guideStamps[id], true)
		t.ok(profile.cash >= Stamps.StampReward(1))
		local paid = profile.cash
		t.eq(#toasts, 1)
		Service.Stamp(player, { [id] = 9 })
		t.eq(profile.cash, paid, "a second sale of the same wood pays nothing")
		t.eq(#toasts, 1)
		t.ok(player.attrs.FieldGuideStamps ~= nil and player.attrs.FieldGuideSecrets ~= nil)
	end)

	t.test("a finished biome page pays its bonus once", function()
		local Service, player, profile, _, WoodData, Stamps = setup()
		local biome = WoodData.All()[1].biome
		local sold = {}
		for _, id in ipairs(Stamps.PageWoods(biome)) do
			sold[id] = 1
		end
		Service.Stamp(player, sold)
		t.eq(profile.guideStamps[Stamps.PagePrefix .. biome], true)
		local n = #Stamps.PageWoods(biome)
		t.eq(profile.cash, n * Stamps.StampReward(1) + Stamps.PageReward(1))
	end)

	t.test("junk and zero sales change nothing", function()
		local Service, player, profile = setup()
		Service.Stamp(player, { nothing = 3 })
		Service.Stamp(player, {})
		t.eq(profile.cash, 0)
		t.eq(next(profile.guideStamps), nil)
	end)
end
