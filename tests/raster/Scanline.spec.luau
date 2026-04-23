--!strict
local Scanline = require("../../src/Raster/Scanline")
local t = require("../framework")

-- Accumulates emitted spans into an array for inspection.
local function collectSpans(
	subpaths: { Scanline.Subpath },
	fillRule: "nonzero" | "evenodd",
	w: number,
	h: number
): { Scanline.Span }
	local spans: { Scanline.Span } = {}
	Scanline.render(subpaths, fillRule, w, h, function(span)
		table.insert(spans, span)
	end)
	return spans
end

-- Returns total covered pixels (coverage * (x1 - x0)) across all rows.
local function totalCoverage(spans: { Scanline.Span }): number
	local total = 0
	for _, s in ipairs(spans) do
		total += (s.x1 - s.x0) * s.coverage
	end
	return total
end

t.suite("Scanline.render — rectangles", function()
	t.test("axis-aligned opaque rect produces full-coverage spans", function()
		local square = {
			{
				points = { 2, 2, 8, 2, 8, 8, 2, 8, 2, 2 },
				closed = true,
			},
		}
		local spans = collectSpans(square, "nonzero", 10, 10)
		-- Expected coverage = 6 columns * 6 rows = 36 pixels of full coverage.
		t.expect(math.abs(totalCoverage(spans) - 36) < 0.5).toBeTruthy()
		-- Every span should be full-coverage.
		for _, s in ipairs(spans) do
			t.expect(s.coverage).toBe(1)
		end
	end)

	t.test("offscreen rect produces no spans", function()
		local square = {
			{
				points = { -10, -10, -5, -10, -5, -5, -10, -5, -10, -10 },
				closed = true,
			},
		}
		local spans = collectSpans(square, "nonzero", 10, 10)
		t.expect(#spans).toBe(0)
	end)

	t.test("rect clipped at canvas edge fills visible portion", function()
		-- Rect extends beyond canvas right edge.
		local square = {
			{
				points = { 5, 2, 20, 2, 20, 8, 5, 8, 5, 2 },
				closed = true,
			},
		}
		local spans = collectSpans(square, "nonzero", 10, 10)
		-- Visible: columns 5..9 = 5 wide, rows 2..7 = 6 tall -> 30.
		t.expect(math.abs(totalCoverage(spans) - 30) < 0.5).toBeTruthy()
	end)
end)

t.suite("Scanline.render — fill rules", function()
	t.test("nonzero fills the whole nested region", function()
		-- Outer CCW, inner CCW (same winding) -> nonzero sees +2 inside inner,
		-- so the inner region remains filled.
		local subpaths = {
			{
				points = { 0, 0, 20, 0, 20, 20, 0, 20, 0, 0 },
				closed = true,
			},
			{
				points = { 5, 5, 15, 5, 15, 15, 5, 15, 5, 5 },
				closed = true,
			},
		}
		local spans = collectSpans(subpaths, "nonzero", 20, 20)
		-- Filled area should be the whole 20x20 = 400 (inner doesn't hole
		-- it out under nonzero with same winding).
		t.expect(math.abs(totalCoverage(spans) - 400) < 1).toBeTruthy()
	end)

	t.test("evenodd holes the inner region", function()
		local subpaths = {
			{
				points = { 0, 0, 20, 0, 20, 20, 0, 20, 0, 0 },
				closed = true,
			},
			{
				points = { 5, 5, 15, 5, 15, 15, 5, 15, 5, 5 },
				closed = true,
			},
		}
		local spans = collectSpans(subpaths, "evenodd", 20, 20)
		-- 400 - 100 = 300 filled under evenodd.
		t.expect(math.abs(totalCoverage(spans) - 300) < 1).toBeTruthy()
	end)
end)

t.suite("Scanline.render — anti-aliasing", function()
	t.test("sub-pixel triangle produces partial coverage", function()
		-- A small triangle whose edges don't align to pixel boundaries must
		-- produce some coverage < 1.
		local tri = {
			{
				points = { 2.3, 2.1, 7.7, 2.1, 5, 7.5, 2.3, 2.1 },
				closed = true,
			},
		}
		local spans = collectSpans(tri, "nonzero", 10, 10)
		local partial = 0
		for _, s in ipairs(spans) do
			if s.coverage > 0.01 and s.coverage < 0.99 then
				partial += 1
			end
		end
		t.expect(partial > 0).toBeTruthy()
	end)
end)

t.suite("Scanline.render — empty input", function()
	t.test("no subpaths -> no spans", function()
		t.expect(#collectSpans({}, "nonzero", 10, 10)).toBe(0)
	end)

	t.test("degenerate single-point subpath -> no spans", function()
		local spans = collectSpans({ { points = { 5, 5 }, closed = true } }, "nonzero", 10, 10)
		t.expect(#spans).toBe(0)
	end)
end)
