--!nocheck
-- Player-typed text reaches other players only through TextFilter, and every
-- failure shows the placeholder, never the raw text.
return function(t)
	local Logic = t.shared("TextFilterLogic")

	local function boot(service)
		local loader = t.loader({ services = { TextService = service } })
		return loader:server("TextFilter")
	end

	local function result(overrides)
		local r = {
			GetNonChatStringForBroadcastAsync = function()
				return "Oak ####"
			end,
			GetChatForUserAsync = function(_self, toUserId)
				return "for " .. toUserId
			end,
		}
		for k, v in pairs(overrides or {}) do
			r[k] = v
		end
		return r
	end

	local function service(r, calls)
		return {
			FilterStringAsync = function(_self, text, userId, context)
				table.insert(calls, { text = text, userId = userId, context = context })
				if type(r) == "function" then
					return r(text)
				end
				return r
			end,
		}
	end

	t.test("Clean: control characters and runs of spaces go, over-long and non-strings are refused", function()
		t.eq(Logic.Clean("  hello \t\n world  ", 20), "hello world")
		t.eq(Logic.Clean("", 20), nil)
		t.eq(Logic.Clean("   ", 20), nil)
		t.eq(Logic.Clean(12, 20), nil)
		t.eq(Logic.Clean(nil, 20), nil)
		t.eq(Logic.Clean(string.rep("a", 21), 20), nil, "too long is refused, not cut into another message")
		t.eq(Logic.Clean(string.rep("a", 20), 20), string.rep("a", 20))
		t.eq(Logic.Clean(string.rep("a", 500)), nil, "the hard cap holds with no limit given")
		t.eq(Logic.Clean("\255\254", 10), nil, "bad UTF-8 is refused")
	end)

	t.test("Resolve and Strict: anything but a real string fails closed", function()
		t.eq(Logic.Resolve("Hi"), "Hi")
		for _, bad in ipairs({ "", 5, true, {} }) do
			t.eq(Logic.Resolve(bad), "####")
			t.eq(Logic.Strict(bad), nil)
		end
		t.eq(Logic.Resolve(nil), "####")
	end)

	t.test("Broadcast filters with PublicChat and returns Roblox's text, not the typed text", function()
		local calls = {}
		local F = boot(service(result(), calls))
		t.eq(F.Broadcast("  rude   words ", 42, 30), "Oak ####")
		t.eq(#calls, 1)
		t.eq(calls[1].text, "rude words", "cleaned before it is sent")
		t.eq(calls[1].userId, 42)
		t.eq(calls[1].context, t.roblox.Enum.TextFilterContext.PublicChat)
	end)

	t.test(
		"every failure shows the placeholder: a thrown filter, a nil result, a failing read, a missing service",
		function()
			local cases = {
				thrown = boot(service(function()
					error("HTTP 500")
				end, {})),
				nilResult = boot(service(nil, {})),
				readFails = boot(service(
					result({
						GetNonChatStringForBroadcastAsync = function()
							error("moderation down")
						end,
						GetChatForUserAsync = function()
							error("moderation down")
						end,
					}),
					{}
				)),
				notAString = boot(service(
					result({
						GetNonChatStringForBroadcastAsync = function()
							return 7
						end,
						GetChatForUserAsync = function()
							return {}
						end,
					}),
					{}
				)),
				noService = boot(nil),
				noMethod = boot({}),
			}
			for name, F in pairs(cases) do
				t.eq(F.Broadcast("secret words", 1), "####", name .. " broadcast")
				t.eq(F.ForUser("secret words", 1, 2), "####", name .. " per reader")
				t.eq(F.TryBroadcast("secret words", 1), nil, name .. " try")
				t.eq(F.ForEach("secret words", 1, { { UserId = 2 } })[1], nil)
			end
		end
	)

	t.test("junk input never reaches the service", function()
		local calls = {}
		local F = boot(service(result(), calls))
		t.eq(F.Broadcast("", 1), "####")
		t.eq(F.Broadcast(5, 1), "####")
		t.eq(F.Broadcast("ok", "1"), "####", "the sender must be a user id")
		t.eq(F.ForUser("ok", 1, "2"), "####", "the reader must be a user id")
		t.eq(F.Broadcast(string.rep("x", 300), 1), "####")
		t.eq(#calls, 0)
	end)

	t.test("ForUser and ForEach filter per reader (GetChatForUserAsync), one filter call for all", function()
		local calls = {}
		local F = boot(service(result(), calls))
		t.eq(F.ForUser("hi there", 1, 2), "for 2")
		local ann, bob = { UserId = 10 }, { UserId = 11 }
		local shown = F.ForEach("hi there", 1, { ann, bob })
		t.eq(shown[ann], "for 10")
		t.eq(shown[bob], "for 11")
		t.eq(#calls, 2, "one call for ForUser, one for the whole ForEach")
	end)

	t.test("a reader whose own filter fails gets the placeholder; the others still read theirs", function()
		local F = boot(service(
			result({
				GetChatForUserAsync = function(_self, toUserId)
					if toUserId == 11 then
						error("that reader failed")
					end
					return "ok " .. toUserId
				end,
			}),
			{}
		))
		local ann, bob = { UserId = 10 }, { UserId = 11 }
		local shown = F.ForEach("hello", 1, { ann, bob })
		t.eq(shown[ann], "ok 10")
		t.eq(shown[bob], "####")
	end)

	t.test("no player text is sent to other clients anywhere but through TextFilter", function()
		-- Today the only player-typed text others can see is a save name
		-- (SaveSlotService); it must use TextFilter and nothing else.
		local fs = require("@lune/fs")
		local service = fs.readFile("src/ServerScriptService/SaveSlotService.luau")
		t.ok(string.find(service, "TextFilter.TryBroadcast", 1, true))
		t.ok(not string.find(service, "FilterStringAsync", 1, true), "no second, unchecked filter call")
		local direct = {}
		for _, entry in ipairs(fs.readDir("src/ServerScriptService")) do
			if string.match(entry, "%.luau$") and entry ~= "TextFilter.luau" then
				local source = fs.readFile("src/ServerScriptService/" .. entry)
				if string.find(source, "FilterStringAsync", 1, true) then
					table.insert(direct, entry)
				end
			end
		end
		t.eq(direct, {}, "only TextFilter calls TextService")
	end)
end
