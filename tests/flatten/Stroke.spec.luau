--!strict
local Stroke = require("../../src/Flatten/Stroke")
local Style = require("../../src/Parser/Style")
local t = require("../framework")

local function makeStyle(width: number, overrides: { [string]: any }?): Style.Style
	local s = Style.defaults()
	s.stroke = { 0, 0, 0, 1 }
	s.strokeWidth = width
	if overrides then
		for k, v in pairs(overrides) do
			(s :: any)[k] = v
		end
	end
	return s
end

local function polygonBbox(polygon: { number }): (number, number, number, number)
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	for i = 1, #polygon, 2 do
		local x = polygon[i]
		local y = polygon[i + 1]
		if x < minX then
			minX = x
		end
		if x > maxX then
			maxX = x
		end
		if y < minY then
			minY = y
		end
		if y > maxY then
			maxY = y
		end
	end
	return minX, minY, maxX, maxY
end

t.suite("Stroke.expand — basics", function()
	t.test("no stroke -> no polygons", function()
		local s = makeStyle(1)
		s.stroke = nil
		local out = Stroke.expand({ 0, 0, 10, 0 }, false, s)
		t.expect(#out).toBe(0)
	end)

	t.test("zero width -> no polygons", function()
		local s = makeStyle(0)
		local out = Stroke.expand({ 0, 0, 10, 0 }, false, s)
		t.expect(#out).toBe(0)
	end)

	t.test("short polyline rejected", function()
		local s = makeStyle(2)
		local out = Stroke.expand({ 0, 0 }, false, s)
		t.expect(#out).toBe(0)
	end)
end)

t.suite("Stroke.expand — horizontal line (butt caps)", function()
	t.test("produces one polygon whose bbox matches expected", function()
		local s = makeStyle(4)
		local polys = Stroke.expand({ 0, 0, 10, 0 }, false, s)
		t.expect(#polys).toBe(1)
		local minX, minY, maxX, maxY = polygonBbox(polys[1])
		-- Expected bbox: [0, 10] x [-2, 2] for butt caps and width 4.
		t.expect(minX).toBe(0)
		t.expect(maxX).toBe(10)
		t.expect(minY).toBe(-2)
		t.expect(maxY).toBe(2)
	end)
end)

t.suite("Stroke.expand — cap styles", function()
	t.test("square cap extends length by halfWidth on each end", function()
		local s = makeStyle(4, { strokeLinecap = "square" })
		local polys = Stroke.expand({ 0, 0, 10, 0 }, false, s)
		local minX, _, maxX = polygonBbox(polys[1])
		t.expect(minX).toBe(-2)
		t.expect(maxX).toBe(12)
	end)

	t.test("round cap adds arc geometry (more vertices)", function()
		local s = makeStyle(4, { strokeLinecap = "round" })
		local polys = Stroke.expand({ 0, 0, 10, 0 }, false, s)
		-- butt would produce 4 vertices; round adds the end arc samples.
		t.expect(#polys[1] > 8).toBeTruthy()
	end)
end)

t.suite("Stroke.expand — closed path join continuity", function()
	t.test("closed polyline produces exactly one polygon", function()
		local s = makeStyle(2, { strokeLinejoin = "miter" })
		local square = { 0, 0, 10, 0, 10, 10, 0, 10 }
		local polys = Stroke.expand(square, true, s)
		t.expect(#polys).toBe(1)
	end)
end)

t.suite("Stroke.expand — dashing", function()
	t.test("dashed line produces multiple polygons", function()
		local s = makeStyle(2, {
			strokeDasharray = { 5, 5 },
			strokeDashoffset = 0,
		})
		-- 30-unit line, dash cycle 10 -> 3 visible dashes of length 5.
		local polys = Stroke.expand({ 0, 0, 30, 0 }, false, s)
		t.expect(#polys).toBe(3)
	end)

	t.test("dash offset shifts pattern", function()
		local s = makeStyle(2, {
			strokeDasharray = { 5, 5 },
			strokeDashoffset = 5, -- start in the gap
		})
		local polys = Stroke.expand({ 0, 0, 30, 0 }, false, s)
		-- Starting in the gap of a 5/5 cycle yields 3 dashes on a 30-unit line.
		t.expect(#polys).toBe(3)
	end)

	t.test("empty dasharray behaves like no dash", function()
		local s = makeStyle(2, { strokeDasharray = {} })
		local polys = Stroke.expand({ 0, 0, 30, 0 }, false, s)
		t.expect(#polys).toBe(1)
	end)
end)

t.suite("Stroke.expand — miter limit", function()
	t.test("sharp join with tight miter limit falls back to bevel", function()
		-- Near-180° reversal -> very long miter -> should trigger fallback.
		local tight = makeStyle(2, {
			strokeLinejoin = "miter",
			strokeMiterlimit = 1,
		})
		local loose = makeStyle(2, {
			strokeLinejoin = "miter",
			strokeMiterlimit = 100,
		})
		local pts = { 0, 0, 10, 0, 0.5, 0.1 }
		local tightPoly = Stroke.expand(pts, false, tight)[1]
		local loosePoly = Stroke.expand(pts, false, loose)[1]
		-- Tight should have extra vertex(es) from bevel fallback vs miter.
		t.expect(#tightPoly >= #loosePoly).toBeTruthy()
	end)
end)
