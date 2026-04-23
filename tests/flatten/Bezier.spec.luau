--!strict
local Bezier = require("../../src/Flatten/Bezier")
local t = require("../framework")

local function polylineLength(pts: { number }): number
	local len = 0
	for i = 3, #pts, 2 do
		local dx = pts[i] - pts[i - 2]
		local dy = pts[i + 1] - pts[i - 1]
		len += math.sqrt(dx * dx + dy * dy)
	end
	return len
end

t.suite("Bezier.flattenCubic", function()
	t.test("flat curve yields chord endpoints only", function()
		local out: { number } = { 0, 0 }
		Bezier.flattenCubic(out, 0, 0, 10, 0, 20, 0, 30, 0, 0.1)
		-- colinear curve: should reduce to just the end point
		t.expect(#out >= 4).toBeTruthy()
		local last = #out
		t.expect(out[last - 1]).toBe(30)
		t.expect(out[last]).toBe(0)
	end)

	t.test("curved path produces multiple segments", function()
		local out: { number } = { 0, 0 }
		Bezier.flattenCubic(out, 0, 0, 0, 100, 100, 100, 100, 0, 0.25)
		t.expect(#out > 6).toBeTruthy()
	end)

	t.test("final point matches d", function()
		local out: { number } = { 0, 0 }
		Bezier.flattenCubic(out, 0, 0, 10, 10, 20, -10, 30, 5, 0.1)
		t.expect(out[#out - 1]).toBe(30)
		t.expect(out[#out]).toBe(5)
	end)

	t.test("tighter tolerance -> more vertices", function()
		local coarse: { number } = { 0, 0 }
		Bezier.flattenCubic(coarse, 0, 0, 0, 100, 100, 100, 100, 0, 1)
		local fine: { number } = { 0, 0 }
		Bezier.flattenCubic(fine, 0, 0, 0, 100, 100, 100, 100, 0, 0.05)
		t.expect(#fine > #coarse).toBeTruthy()
	end)

	t.test("subdivision approximates integral arc length", function()
		-- A quarter-circle-ish cubic (not exact, but close). The flattened
		-- length should be within ~10% of the analytical circle quarter.
		local out: { number } = { 100, 0 }
		local k = 0.5522847498307936
		Bezier.flattenCubic(out, 100, 0, 100, 100 * k, 100 * k, 100, 0, 100, 0.1)
		local expected = math.pi * 100 / 2 -- quarter circle of radius 100
		local approx = polylineLength(out)
		t.expect(math.abs(approx - expected) / expected < 0.1).toBeTruthy()
	end)
end)

t.suite("Bezier.flattenQuadratic", function()
	t.test("flat quadratic collapses", function()
		local out: { number } = { 0, 0 }
		Bezier.flattenQuadratic(out, 0, 0, 5, 0, 10, 0, 0.1)
		t.expect(out[#out - 1]).toBe(10)
		t.expect(out[#out]).toBe(0)
	end)

	t.test("curved quadratic subdivides", function()
		local out: { number } = { 0, 0 }
		Bezier.flattenQuadratic(out, 0, 0, 50, 100, 100, 0, 0.25)
		t.expect(#out > 6).toBeTruthy()
	end)
end)
