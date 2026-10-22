--!nocheck
-- HammerPickerFit (T420): every card's name, blurb and cost text fits the room the
-- card gives it, at a 667 and an 844 wide phone, a 1280 and a 1920 computer and a
-- TV. Lune has no TextService, so widths are estimated like BuildMenuTextFit does
-- (lowercase 0.58 em, uppercase and digits 0.70, space 0.28, plus 10%); the real
-- check is the Studio screenshots.
return function(t)
	local HammerPicker = t.shared("HammerPicker")
	local BuildMenuLogic = t.shared("BuildMenuLogic")
	local BlueprintBook = t.shared("BlueprintBook")
	local PlotData = t.shared("PlotData")

	local function width(text, px)
		local em = 0
		for ch in string.gmatch(text, ".") do
			if ch == " " then
				em += 0.28
			elseif string.find(ch, "[%u%d]") then
				em += 0.70
			else
				em += 0.58
			end
		end
		return em * px * 1.10
	end

	local function wrap(text, px, avail)
		local lines, current, widest = 1, "", 0
		for word in string.gmatch(text, "%S+") do
			widest = math.max(widest, width(word, px))
			local try = if current == "" then word else current .. " " .. word
			if width(try, px) <= avail or current == "" then
				current = try
			else
				lines += 1
				current = word
			end
		end
		return lines, widest
	end

	local SIZES = {
		{ "667x375 phone", 667, true, 1 },
		{ "844x390 phone", 844, true, 1 },
		{ "1280x720 PC", 1280, false, 1 },
		{ "1920x1080 PC", 1920, false, 1.25 },
		{ "1920x1080 TV", 1920, false, 1.5 },
	}

	local function entries()
		local book = {}
		for _, bp in ipairs(PlotData.Blueprints) do
			table.insert(book, bp.id)
		end
		return BlueprintBook.Entries(book, {}, true)
	end

	t.test("the grid: two cards across on a phone, three or four on a computer, cards wide enough to read", function()
		for _, size in ipairs(SIZES) do
			local layout = BuildMenuLogic.Layout(size[2], size[3], size[4])
			local grid = HammerPicker.GridFor(layout.panelW, size[3])
			if size[3] then
				t.eq(grid.cols, 2, size[1])
			else
				t.ok(grid.cols >= 3 and grid.cols <= 4, size[1] .. " columns " .. grid.cols)
			end
			t.ok(grid.tileW >= 170, size[1] .. " card is " .. grid.tileW .. " px wide")
			t.ok(grid.textW > 100, size[1] .. " text room " .. grid.textW)
		end
	end)

	t.test("every name fits in 2 lines, every blurb in 3 and every cost in 2, at every size", function()
		local checked = 0
		local ctx = { tier = 5, cash = 100000, boxed = false }
		for _, size in ipairs(SIZES) do
			local layout = BuildMenuLogic.Layout(size[2], size[3], size[4])
			local grid = HammerPicker.GridFor(layout.panelW, size[3])
			local card = HammerPicker.CardSizes(size[3])
			for _, entry in ipairs(entries()) do
				local c = HammerPicker.Card(entry, ctx)
				local nameLines, nameWord = wrap(c.name, card.nameText, grid.textW)
				local blurbLines = wrap(c.blurb, card.blurbText, grid.textW)
				local costLines, costWord = wrap(c.costText, card.costText, grid.textW)
				t.ok(nameLines <= 2 and nameWord <= grid.textW, string.format("%s: name %q", size[1], c.name))
				t.ok(
					blurbLines <= card.blurbLines,
					string.format("%s: blurb of %s takes %d lines", size[1], c.id, blurbLines)
				)
				t.ok(
					costLines <= card.costLines and costWord <= grid.textW,
					string.format("%s: cost %q takes %d lines", size[1], c.costText, costLines)
				)
				checked += 1
			end
		end
		t.ok(checked >= 5 * 79, "checked " .. checked)
	end)

	t.test("no text is under the 14 px floor and the card heights hold their lines", function()
		for _, card in ipairs({ HammerPicker.PhoneCard, HammerPicker.WideCard }) do
			t.ok(card.nameText >= 14 and card.blurbText >= 14 and card.costText >= 14)
			t.ok(card.nameH >= card.nameText * 2)
			t.ok(card.blurbH >= card.blurbText * card.blurbLines)
			t.ok(card.costH >= card.costText * card.costLines)
			t.eq(card.h, card.artH + card.nameH + card.blurbH + card.costH + card.gap * 4)
		end
	end)
end
