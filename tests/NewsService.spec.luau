--!nocheck
-- NewsService: a brand-new save never gets the "What's new in V1" panel
-- (it has nothing to catch up on); a returning player keeps it.
return function(t)
	local function run(fields, onboarding)
		local profile = { onboarding = onboarding or {} }
		for k, v in pairs(fields) do
			profile[k] = v
		end
		local attrs = {}
		local player = {
			SetAttribute = function(_, name, value)
				attrs[name] = value
			end,
		}
		local loader = t.loader({
			services = { Players = { PlayerRemoving = { Connect = function() end } } },
			mocks = {
				ProfileService = {
					GetProfile = function(p)
						return if p == player then profile else nil
					end,
				},
			},
		})
		local News = loader:server("NewsService")
		News.Start(player, profile)
		return profile, attrs
	end

	t.test("a brand-new player (first tutorial) is marked seen at join", function()
		local profile, attrs = run({ tutorialDone = false, tutorialRefresher = false, tutorialReplay = false })
		t.eq(profile.onboarding["News:V1"], true, "stored in the save")
		t.eq(attrs.NewsV1Seen, true, "the client sees it as seen")
	end)

	t.test("a returning player keeps the panel: finished save, refresher, replay", function()
		local _, a = run({ tutorialDone = true })
		t.eq(a.NewsV1Seen, false, "finished the tutorial before")
		local p2, a2 = run({ tutorialDone = false, tutorialRefresher = true })
		t.eq(a2.NewsV1Seen, false, "loop-change refresher")
		t.eq(p2.onboarding["News:V1"], nil)
		local _, a3 = run({ tutorialDone = false, tutorialReplay = true })
		t.eq(a3.NewsV1Seen, false, "replaying the lessons")
	end)

	t.test("a returning player who already closed it stays seen", function()
		local _, a = run({ tutorialDone = true }, { ["News:V1"] = true })
		t.eq(a.NewsV1Seen, true)
	end)

	t.test("the Settings What's new button is kept", function()
		local fs = require("@lune/fs")
		local ui = fs.readFile("src/StarterPlayer/StarterPlayerScripts/SettingsUI.luau")
		t.ok(string.find(ui, "NewsUI.Open", 1, true), "the button still opens the panel")
	end)
end
