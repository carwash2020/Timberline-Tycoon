--!nocheck
return function(t)
	local Util = t.shared("Util")

	t.test("formatCash adds a dollar sign and thousands separators", function()
		t.eq(Util.formatCash(0), "$0")
		t.eq(Util.formatCash(999), "$999")
		t.eq(Util.formatCash(1000), "$1,000")
		t.eq(Util.formatCash(1234567), "$1,234,567")
		t.eq(Util.formatCash(2_000_000), "$2,000,000")
		t.eq(Util.formatCash(-4500), "-$4,500")
		t.eq(Util.formatCash(12.9), "$12", "rounds down")
	end)

	t.test("clamp", function()
		t.eq(Util.clamp(5, 0, 10), 5)
		t.eq(Util.clamp(-1, 0, 10), 0)
		t.eq(Util.clamp(11, 0, 10), 10)
	end)

	t.test("deepCopy copies nested tables", function()
		local original = { a = { b = 1 }, list = { 1, 2 } }
		local copy = Util.deepCopy(original)
		t.eq(copy, original)
		copy.a.b = 2
		t.eq(original.a.b, 1)
	end)

	t.test("guid gives a fresh id each time", function()
		t.ok(Util.guid() ~= Util.guid())
	end)
end
