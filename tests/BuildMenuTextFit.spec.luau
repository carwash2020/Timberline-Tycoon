--!nocheck
-- BuildMenuTextFit: every blueprint's name fits its card's name plate in at most
-- 2 lines, with no word wider than the plate, at the four sizes the menu is
-- designed for. Lune has no TextService, so a width is estimated per character
-- (lowercase 0.58 em, uppercase and digits 0.70 em, space 0.28 em, plus a 10%
-- safety margin) and the words are wrapped greedily. The real check is the
-- four-size Studio screenshots (the font is Gotham Bold, not what this estimates).
return function(t)
	local BuildMenuLogic = t.shared("BuildMenuLogic")
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

	-- Greedy word wrap: the lines, and the widest single word.
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

	-- (label, viewport width, phone?, UIScale). A phone runs the menu at scale 1;
	-- a computer at ScaleFor (1.25 at 1920 x 1080), a TV at 1.5.
	local SIZES = {
		{ "667x375 phone", 667, true, 1 },
		{ "844x390 phone", 844, true, 1 },
		{ "1280x720 PC", 1280, false, 1 },
		{ "1920x1080 PC", 1920, false, 1.25 },
		{ "1920x1080 TV", 1920, false, 1.5 },
	}

	t.test(
		"the card widths are what the mock measures (149 at 667, 176 at 844 on a phone, about 170 on PC and TV)",
		function()
			local a = BuildMenuLogic.Layout(667, true, 1)
			local b = BuildMenuLogic.Layout(844, true, 1)
			t.ok(math.abs(a.tileW - 149) < 1, "667: " .. a.tileW)
			t.ok(math.abs(b.tileW - 176) < 1, "844: " .. b.tileW)
			t.eq(a.cols, 3)
			t.eq(b.cols, 3)
			for _, size in ipairs({ SIZES[3], SIZES[4], SIZES[5] }) do
				local l = BuildMenuLogic.Layout(size[2], size[3], size[4])
				t.ok(l.tileW > 165 and l.tileW < 190, size[1] .. ": " .. l.tileW)
				t.ok(l.cols >= 3 and l.cols <= 4)
			end
			-- A phone's panel stays inside the screen at scale 1.
			t.ok(a.panelW + BuildMenuLogic.Margin * 2 <= 667)
		end
	)

	t.test("every displayName fits its plate in at most 2 lines at every size, no word wider than the plate", function()
		local names = 0
		for _, size in ipairs(SIZES) do
			local layout = BuildMenuLogic.Layout(size[2], size[3], size[4])
			local px = layout.sizes.name
			for _, bp in ipairs(PlotData.Blueprints) do
				names += 1
				local lines, widest = wrap(bp.displayName, px, layout.plateTextW)
				t.ok(
					lines <= 2,
					string.format(
						"%s: %q takes %d lines in %d px at %d px",
						size[1],
						bp.displayName,
						lines,
						layout.plateTextW,
						px
					)
				)
				t.ok(
					widest <= layout.plateTextW,
					string.format(
						"%s: a word of %q is %d px, wider than the %d px plate",
						size[1],
						bp.displayName,
						widest,
						layout.plateTextW
					)
				)
			end
		end
		t.ok(names >= 5 * 79, "every blueprint at every size (" .. names .. ")")
	end)

	t.test("the text never goes under the 14 px floor, and a phone name is 16 px", function()
		t.eq(BuildMenuLogic.PhoneSizes.name, 16)
		t.eq(BuildMenuLogic.WideSizes.name, 18)
		t.ok(BuildMenuLogic.PhoneSizes.minText >= 14 and BuildMenuLogic.WideSizes.minText >= 14)
	end)
end
