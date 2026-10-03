--!nocheck
-- Quality (StarterPlayerScripts/Quality, PLAY-05) against a fake
-- UserSettings().GameSettings and UserInputService: the tier comes from
-- the graphics setting and the device, it's readable before Start, and it
-- follows the setting while playing (its changed signal, and a poll every
-- 2 seconds for a keyboard plugged in or a signal that never fires).
return function(t)
	local QualityBudgets = t.shared("QualityBudgets")

	-- A fake client. `level` is the SavedQualityLevel's name; `touch` and
	-- `keyboard` the device's input.
	local function client(level, touch, keyboard, opts)
		opts = opts or {}
		local c = { prints = {}, loops = {}, listeners = {}, reads = 0 }
		local settings = {}
		function c.set(name)
			c.level = name
			for _, fn in ipairs(c.listeners) do
				fn()
			end
		end
		c.level = level
		setmetatable(settings, {
			__index = function(_, key)
				if key == "SavedQualityLevel" then
					c.reads += 1
					if opts.unreadable then
						error("The current thread cannot access 'UserGameSettings'")
					end
					return { Name = c.level }
				elseif key == "GetPropertyChangedSignal" then
					return function(_, property)
						assert(property == "SavedQualityLevel", property)
						return {
							Connect = function(_, fn)
								table.insert(c.listeners, fn)
							end,
						}
					end
				end
				return nil
			end,
		})
		c.input = { TouchEnabled = touch, KeyboardEnabled = keyboard }
		local loader = t.loader({
			services = { UserInputService = c.input },
			globals = {
				UserSettings = function()
					return { GameSettings = settings }
				end,
				print = function(...)
					table.insert(c.prints, table.concat({ ... }, " "))
				end,
				task = {
					spawn = function(fn)
						table.insert(c.loops, coroutine.create(fn))
					end,
					wait = function(seconds)
						c.waited = seconds
						return coroutine.yield()
					end,
				},
			},
		})
		c.Quality = loader:load("StarterPlayer/StarterPlayerScripts/Quality")
		c.warnings = loader.warnings
		-- The poll loop's next pass (one POLL_EVERY later).
		function c.poll()
			for _, co in ipairs(c.loops) do
				assert(coroutine.resume(co))
			end
		end
		return c
	end

	t.test("graphics quality 1-4 is low, on a phone or a desktop", function()
		for _, device in ipairs({ { true, false }, { false, true } }) do
			for level = 1, 4 do
				local c = client("QualityLevel" .. level, device[1], device[2])
				t.eq(c.Quality.Tier(), "low")
				t.eq(c.Quality.Budget(), QualityBudgets.Low)
			end
		end
	end)

	t.test("graphics quality 5-7 is medium and 8-10 is high, even on a phone", function()
		for level = 5, 7 do
			local c = client("QualityLevel" .. level, true, false)
			t.eq(c.Quality.Tier(), "medium")
			t.eq(c.Quality.Budget(), QualityBudgets.Medium)
		end
		for level = 8, 10 do
			local c = client("QualityLevel" .. level, true, false)
			t.eq(c.Quality.Budget(), QualityBudgets.High)
		end
	end)

	t.test("Automatic is low on a touch-only device, high with a keyboard or no touch screen", function()
		t.eq(client("Automatic", true, false).Quality.Tier(), "low", "a phone or a bare tablet")
		t.eq(client("Automatic", true, true).Quality.Tier(), "high", "a touch laptop, a tablet with a keyboard")
		t.eq(client("Automatic", false, true).Quality.Tier(), "high", "a desktop")
		t.eq(client("Automatic", false, false).Quality.Tier(), "high", "a console")
	end)

	t.test("readable before Start, read once, and it says which tier it picked", function()
		local c = client("QualityLevel3", false, true)
		t.eq(c.Quality.Tier(), "low")
		c.Quality.Budget()
		c.Quality.Budget()
		t.eq(c.reads, 1, "cached after the first read")
		t.eq(c.prints, { "[Quality] low (QualityLevel3)" })
		local phone = client("Automatic", true, false)
		phone.Quality.Budget()
		t.eq(phone.prints, { "[Quality] low (Automatic, touch only)" })
	end)

	t.test("moving the graphics slider while playing switches the tier at once", function()
		local c = client("QualityLevel8", false, true)
		c.Quality.Start()
		t.eq(c.Quality.Tier(), "high")
		t.eq(#c.listeners, 1, "watches SavedQualityLevel")
		c.set("QualityLevel2")
		t.eq(c.Quality.Tier(), "low")
		c.set("QualityLevel3")
		t.eq(c.Quality.Tier(), "low")
		c.set("QualityLevel6")
		t.eq(c.Quality.Tier(), "medium")
		t.eq(
			c.prints,
			{ "[Quality] high (QualityLevel8)", "[Quality] low (QualityLevel2)", "[Quality] medium (QualityLevel6)" },
			"one line per change"
		)
		t.eq(#c.warnings, 0)
	end)

	t.test("the poll catches what the signal doesn't: a keyboard plugged in, a silent setting change", function()
		local c = client("Automatic", true, false)
		c.Quality.Start()
		t.eq(c.Quality.Tier(), "low")
		c.poll()
		t.eq(c.waited, 2, "every 2 seconds")
		c.input.KeyboardEnabled = true
		c.poll()
		t.eq(c.Quality.Tier(), "high", "a keyboard: high")
		c.level = "QualityLevel1" -- changed without the signal firing
		c.poll()
		t.eq(c.Quality.Tier(), "low")
	end)

	t.test("an unreadable setting counts as Automatic", function()
		t.eq(client(nil, true, false, { unreadable = true }).Quality.Tier(), "low", "a phone")
		local desk = client(nil, false, true, { unreadable = true })
		t.eq(desk.Quality.Tier(), "high", "a desktop")
		t.eq(desk.prints, { "[Quality] high (level unreadable)" })
	end)

	t.test("no UserSettings and no UserInputService at all (a test loader): high, no errors", function()
		local Quality = t.loader():load("StarterPlayer/StarterPlayerScripts/Quality")
		t.eq(Quality.Budget(), QualityBudgets.High)
	end)
end
