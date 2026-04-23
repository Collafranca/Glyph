--!strict
local Canvas = require("../../src/Raster/Canvas")
local Raster = require("../../src/Raster/Raster")
local Svg = require("../../src/Parser/Svg")
local t = require("../framework")

local function near(a: number, b: number, tol: number?): boolean
	return math.abs(a - b) < (tol or 1 / 255 + 1e-6)
end

-- Count pixels in `canvas` that pass `predicate(r, g, b, a)`.
local function countPixels(
	canvas: Canvas.Canvas,
	predicate: (r: number, g: number, b: number, a: number) -> boolean
): number
	local count = 0
	for y = 0, canvas.height - 1 do
		for x = 0, canvas.width - 1 do
			if predicate(Canvas.getPixel(canvas, x, y)) then
				count += 1
			end
		end
	end
	return count
end

t.suite("Raster.render — solid fill", function()
	t.test("red rectangle fills the pixels it claims", function()
		local doc = Svg.parse([[<svg viewBox="0 0 10 10">
			<rect x="2" y="2" width="6" height="6" fill="red"/>
		</svg>]])
		local canvas = Canvas.create(10, 10)
		Raster.render(canvas, doc, { fit = "fill" })
		-- Corner pixels inside the rect should be red-ish.
		local r, g, b, a = Canvas.getPixel(canvas, 5, 5)
		t.expect(near(r, 1)).toBeTruthy()
		t.expect(near(g, 0)).toBeTruthy()
		t.expect(near(b, 0)).toBeTruthy()
		t.expect(near(a, 1)).toBeTruthy()
		-- Pixel outside should be untouched.
		local _, _, _, outsideA = Canvas.getPixel(canvas, 0, 0)
		t.expect(outsideA).toBe(0)
	end)

	t.test("background color fills canvas before drawing", function()
		local doc = Svg.parse([[<svg viewBox="0 0 10 10"/>]])
		local canvas = Canvas.create(10, 10)
		Raster.render(canvas, doc, { fit = "fill", backgroundColor = { 0, 1, 0, 1 } })
		local r, g, b, a = Canvas.getPixel(canvas, 5, 5)
		t.expect(near(g, 1)).toBeTruthy()
		t.expect(near(r, 0)).toBeTruthy()
		t.expect(near(b, 0)).toBeTruthy()
		t.expect(near(a, 1)).toBeTruthy()
	end)

	t.test("fill: none draws nothing", function()
		local doc = Svg.parse([[<svg viewBox="0 0 10 10">
			<rect x="0" y="0" width="10" height="10" fill="none"/>
		</svg>]])
		local canvas = Canvas.create(10, 10)
		Raster.render(canvas, doc, { fit = "fill" })
		local count = countPixels(canvas, function(_, _, _, a)
			return a > 0.01
		end)
		t.expect(count).toBe(0)
	end)
end)

t.suite("Raster.render — stroke", function()
	t.test("stroke draws an outline", function()
		local doc = Svg.parse([[<svg viewBox="0 0 20 20">
			<rect x="4" y="4" width="12" height="12" fill="none" stroke="black" stroke-width="2"/>
		</svg>]])
		local canvas = Canvas.create(20, 20)
		Raster.render(canvas, doc, { fit = "fill" })
		-- Center of the rect should be unfilled.
		local _, _, _, centerA = Canvas.getPixel(canvas, 10, 10)
		t.expect(centerA).toBe(0)
		-- Points on the rectangle edges should be drawn.
		local painted = countPixels(canvas, function(_, _, _, a)
			return a > 0.5
		end)
		t.expect(painted > 0).toBeTruthy()
	end)
end)

t.suite("Raster.render — viewport fit modes", function()
	t.test("contain preserves aspect ratio and letterboxes", function()
		-- 20x10 viewBox into a 20x20 canvas with contain should leave top/bottom empty.
		local doc = Svg.parse([[<svg viewBox="0 0 20 10">
			<rect x="0" y="0" width="20" height="10" fill="red"/>
		</svg>]])
		local canvas = Canvas.create(20, 20)
		Raster.render(canvas, doc, { fit = "contain" })
		-- Middle row should be filled, top row should be empty.
		local _, _, _, middleA = Canvas.getPixel(canvas, 10, 10)
		local _, _, _, topA = Canvas.getPixel(canvas, 10, 0)
		t.expect(middleA > 0.5).toBeTruthy()
		t.expect(topA).toBe(0)
	end)

	t.test("fill stretches to the canvas", function()
		local doc = Svg.parse([[<svg viewBox="0 0 20 10">
			<rect x="0" y="0" width="20" height="10" fill="red"/>
		</svg>]])
		local canvas = Canvas.create(20, 20)
		Raster.render(canvas, doc, { fit = "fill" })
		-- Whole canvas should be red.
		local painted = countPixels(canvas, function(_, _, _, a)
			return a > 0.5
		end)
		t.expect(painted).toBe(400)
	end)
end)

t.suite("Raster.render — gradients", function()
	t.test("linear gradient varies across the paint axis", function()
		local doc = Svg.parse([[<svg viewBox="0 0 20 20">
			<defs>
				<linearGradient id="g" x1="0" y1="0" x2="1" y2="0">
					<stop offset="0" stop-color="black"/>
					<stop offset="1" stop-color="white"/>
				</linearGradient>
			</defs>
			<rect x="0" y="0" width="20" height="20" fill="url(#g)"/>
		</svg>]])
		local canvas = Canvas.create(20, 20)
		Raster.render(canvas, doc, { fit = "fill" })
		local leftR = Canvas.getPixel(canvas, 1, 10)
		local rightR = Canvas.getPixel(canvas, 18, 10)
		t.expect(leftR < 0.2).toBeTruthy()
		t.expect(rightR > 0.8).toBeTruthy()
	end)

	t.test("radial gradient lights the center", function()
		local doc = Svg.parse([[<svg viewBox="0 0 20 20">
			<defs>
				<radialGradient id="r" cx="0.5" cy="0.5" r="0.5">
					<stop offset="0" stop-color="white"/>
					<stop offset="1" stop-color="black"/>
				</radialGradient>
			</defs>
			<rect x="0" y="0" width="20" height="20" fill="url(#r)"/>
		</svg>]])
		local canvas = Canvas.create(20, 20)
		Raster.render(canvas, doc, { fit = "fill" })
		local centerR = Canvas.getPixel(canvas, 10, 10)
		local cornerR = Canvas.getPixel(canvas, 0, 0)
		t.expect(centerR > 0.8).toBeTruthy()
		t.expect(cornerR < 0.2).toBeTruthy()
	end)
end)

t.suite("Raster.render — circle path (arc)", function()
	t.test("fills circle interior", function()
		-- A circle centred at (10,10) radius 7 should leave the corners unpainted.
		local doc = Svg.parse([[<svg viewBox="0 0 20 20">
			<circle cx="10" cy="10" r="7" fill="red"/>
		</svg>]])
		local canvas = Canvas.create(20, 20)
		Raster.render(canvas, doc, { fit = "fill" })
		-- Centre red.
		local cr = Canvas.getPixel(canvas, 10, 10)
		t.expect(cr > 0.9).toBeTruthy()
		-- Corners untouched.
		local _, _, _, cornerA = Canvas.getPixel(canvas, 0, 0)
		t.expect(cornerA).toBe(0)
	end)
end)

t.suite("Raster.render — clip path", function()
	t.test("circle clipped by rect leaves only overlap", function()
		local doc = Svg.parse([[<svg viewBox="0 0 20 20">
			<defs>
				<clipPath id="clip"><rect x="10" y="0" width="10" height="20"/></clipPath>
			</defs>
			<circle cx="10" cy="10" r="9" fill="red" clip-path="url(#clip)"/>
		</svg>]])
		local canvas = Canvas.create(20, 20)
		Raster.render(canvas, doc, { fit = "fill" })
		-- Inside the half that survives clipping.
		local rightR = Canvas.getPixel(canvas, 14, 10)
		-- Left of clip should be empty.
		local _, _, _, leftA = Canvas.getPixel(canvas, 5, 10)
		t.expect(rightR > 0.8).toBeTruthy()
		t.expect(leftA).toBe(0)
	end)
end)
