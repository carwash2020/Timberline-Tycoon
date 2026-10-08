--!nocheck
-- Old Hank, the plot salesman: his offers are data, there is one price, he
-- never sleeps, and what he says carries the real price.
return function(t)
	local PlotSalesmanData = t.shared("PlotSalesmanData")
	local NPCData = t.shared("NPCData")
	local GameConfig = t.shared("GameConfig")
	local ShopHoursLogic = t.shared("ShopHoursLogic")

	local function mentions(text, needle)
		return string.find(text, needle, 1, true) ~= nil
	end

	t.test("offers are a data list: the only one today is Buy a plot, at GameConfig.PlotPrice", function()
		t.eq(#PlotSalesmanData.Offers, 1)
		local seen = {}
		for _, offer in ipairs(PlotSalesmanData.Offers) do
			t.eq(type(offer.id), "string")
			t.ok(not seen[offer.id], "unique id " .. offer.id)
			seen[offer.id] = true
			t.eq(type(offer.label), "string")
			t.eq(type(offer.pitch), "string")
			t.eq(type(offer.price), "function")
			t.eq(type(offer.available), "function")
		end
		local buy = PlotSalesmanData.Find("buyPlot")
		t.ok(buy ~= nil)
		t.eq(buy.label, "Buy a plot")
		t.eq(buy.price(), GameConfig.PlotPrice)
		t.eq(PlotSalesmanData.Find("nope"), nil)
	end)

	t.test("one price, read live from GameConfig, never u3 or a second number", function()
		local buy = PlotSalesmanData.Find("buyPlot")
		local old = GameConfig.PlotPrice
		for _, price in ipairs({ old, 150, 777 }) do
			GameConfig.PlotPrice = price
			local pitch = PlotSalesmanData.Pitch(buy)
			t.ok(mentions(pitch, "$" .. price), pitch)
			t.ok(not mentions(pitch, "u\194\179") and not mentions(pitch, "u3"), "no u3")
			t.eq(select(2, string.gsub(pitch, "%$", "")), 1, "exactly one price in the pitch")
			local line = PlotSalesmanData.Choose({ ownsPlot = false, full = false }).line
			t.ok(mentions(line, "$" .. price), line)
			for _, greeting in ipairs(PlotSalesmanData.Greetings()) do
				t.ok(mentions(greeting, "$" .. price), greeting)
				t.eq(select(2, string.gsub(greeting, "%$", "")), 1, "one price: " .. greeting)
			end
		end
		GameConfig.PlotPrice = old
	end)

	t.test("Choose: a buyer gets the offer, an owner or a full district gets a line and no offer", function()
		local buyer = PlotSalesmanData.Choose({ ownsPlot = false, full = false })
		t.eq(buyer.offer.id, "buyPlot")
		local owner = PlotSalesmanData.Choose({ ownsPlot = true, full = false })
		t.eq(owner.offer, nil)
		t.eq(owner.line, PlotSalesmanData.OwnsLine)
		local full = PlotSalesmanData.Choose({ ownsPlot = false, full = true })
		t.eq(full.offer, nil)
		t.eq(full.line, PlotSalesmanData.FullLine)
		t.eq(#PlotSalesmanData.Available({ ownsPlot = false, full = false }), 1)
		t.eq(#PlotSalesmanData.Available({ ownsPlot = true, full = false }), 0)
	end)

	t.test("he is always on: every hour, no shop hours, never laid down to sleep", function()
		for hour = 0, 24, 0.5 do
			t.ok(PlotSalesmanData.IsAvailable(hour), "available at " .. hour)
			t.ok(ShopHoursLogic.IsOpen(PlotSalesmanData.Id, hour), "no hours for " .. PlotSalesmanData.Id)
			t.ok(ShopHoursLogic.IsOpen("LandOffice", hour), "LandOffice has no hours")
		end
		local hank = NPCData.Get(PlotSalesmanData.Id)
		t.ok(hank ~= nil, "he is in the roster")
		t.eq(hank.shop, nil, "no shop: NPCService.Apply skips him, so he never sleeps")
	end)

	t.test("he is an old farmer standing at the Land Office counter", function()
		local hank = NPCData.Get(PlotSalesmanData.Id)
		t.eq(hank.name, "Old Hank")
		t.eq(hank.spot.kind, "counter")
		t.eq(hank.spot.model, "LandOffice")
		t.eq(hank.route, nil, "he stays put")
		t.eq(hank.look.hat, "straw")
		t.ok(hank.look.overalls ~= nil and hank.look.stripe ~= nil, "overalls over a plaid shirt")
		t.ok(hank.look.beard ~= nil and hank.look.beard ~= "none")
		t.eq(hank.look.hayStalk, true)
		t.ok(hank.idle ~= nil, "he has an idle animation")
		t.ok(#hank.greetings > 0 and #hank.lines > 0)
		local ids = {}
		for _, npc in ipairs(NPCData.All()) do
			t.ok(not ids[npc.id], "unique id " .. npc.id)
			ids[npc.id] = true
			t.ok(npc.name ~= "Old Hank" or npc.id == "OldHank")
		end
	end)

	t.test("every line he can say about plots quotes the real price", function()
		local hank = NPCData.Get(PlotSalesmanData.Id)
		local price = "$" .. GameConfig.PlotPrice
		for _, line in ipairs(hank.greetings) do
			t.ok(mentions(line, price), line)
		end
		local found = false
		for _, line in ipairs(hank.lines) do
			found = found or mentions(line, price)
		end
		t.ok(found, "a chatter line states the price")
	end)

	t.test("the Land Office tutorial step is untouched: the same plot price and reward", function()
		local TutorialData = t.shared("TutorialData")
		local plot
		for _, step in ipairs(TutorialData.StepsV2) do
			if step.id == "plot" then
				plot = step
			end
		end
		t.ok(plot ~= nil, "step id plot still exists")
		t.eq(plot.beacon, "landOffice")
		t.eq(plot.event, "plotClaimed")
		t.ok(mentions(plot.murphShort, "$" .. GameConfig.PlotPrice))
	end)

	t.test("Old Hank's bases question: one offer id, the crate count, and the no-pad wording", function()
		t.eq(PlotSalesmanData.BasesOfferId, "bases")
		local withPad = PlotSalesmanData.BasesLine(true, 0, 3)
		t.ok(string.find(withPad, "Nothing in a crate is ever lost", 1, true) ~= nil)
		t.eq(string.find(withPad, "crated with me", 1, true), nil, "no crates, no count")
		t.ok(string.find(PlotSalesmanData.BasesLine(true, 2, 3), "2 of 3 bases crated with me", 1, true) ~= nil)
		t.ok(string.find(PlotSalesmanData.BasesLine(false, 0, 3), "no pad", 1, true) ~= nil)
	end)
end
