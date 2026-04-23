--!strict
local Canvas = require("../../src/Raster/Canvas")
local t = require("../framework")

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1 / 255 + 1e-6
end

t.suite("Canvas", function()
	t.test("create() makes a zeroed buffer", function()
		local c = Canvas.create(4, 4)
		t.expect(c.width).toBe(4)
		t.expect(c.height).toBe(4)
		local r, g, b, a = Canvas.getPixel(c, 0, 0)
		t.expect(r).toBe(0)
		t.expect(g).toBe(0)
		t.expect(b).toBe(0)
		t.expect(a).toBe(0)
	end)

	t.test("setPixel + getPixel roundtrip", function()
		local c = Canvas.create(2, 2)
		Canvas.setPixel(c, 1, 0, 1, 0.5, 0.25, 1)
		local r, g, b, a = Canvas.getPixel(c, 1, 0)
		t.expect(near(r, 1)).toBeTruthy()
		t.expect(near(g, 0.5)).toBeTruthy()
		t.expect(near(b, 0.25)).toBeTruthy()
		t.expect(a).toBe(1)
	end)

	t.test("out-of-bounds setPixel is a no-op", function()
		local c = Canvas.create(2, 2)
		Canvas.setPixel(c, 5, 5, 1, 0, 0, 1)
		Canvas.setPixel(c, -1, 0, 1, 0, 0, 1)
		-- Should not crash; pixels remain zero.
		local _, _, _, a = Canvas.getPixel(c, 0, 0)
		t.expect(a).toBe(0)
	end)

	t.test("clear fills every pixel", function()
		local c = Canvas.create(3, 3)
		Canvas.clear(c, 1, 0, 0, 1)
		for y = 0, 2 do
			for x = 0, 2 do
				local r, _, _, a = Canvas.getPixel(c, x, y)
				t.expect(near(r, 1)).toBeTruthy()
				t.expect(a).toBe(1)
			end
		end
	end)

	t.test("blendPixel with alpha=1 overwrites", function()
		local c = Canvas.create(1, 1)
		Canvas.clear(c, 0, 0, 0, 1)
		Canvas.blendPixel(c, 0, 0, 1, 1, 1, 1)
		local r = Canvas.getPixel(c, 0, 0)
		t.expect(near(r, 1)).toBeTruthy()
	end)

	t.test("blendPixel with partial alpha blends source-over", function()
		local c = Canvas.create(1, 1)
		Canvas.clear(c, 0, 0, 0, 1)
		Canvas.blendPixel(c, 0, 0, 1, 0, 0, 0.5)
		local r, g, b, a = Canvas.getPixel(c, 0, 0)
		-- src-over with dst alpha 1: outA=1, outR = src*0.5 + dst*0.5 = 0.5
		t.expect(near(r, 0.5)).toBeTruthy()
		t.expect(near(g, 0)).toBeTruthy()
		t.expect(near(b, 0)).toBeTruthy()
		t.expect(near(a, 1)).toBeTruthy()
	end)

	t.test("blendSpan paints opaque pixels", function()
		local c = Canvas.create(4, 1)
		Canvas.blendSpan(c, 1, 3, 0, 1, 0, 0, 1)
		t.expect(Canvas.getPixel(c, 0, 0)).toBe(0)
		local r1 = Canvas.getPixel(c, 1, 0)
		local r2 = Canvas.getPixel(c, 2, 0)
		local r3 = Canvas.getPixel(c, 3, 0)
		t.expect(near(r1, 1)).toBeTruthy()
		t.expect(near(r2, 1)).toBeTruthy()
		t.expect(r3).toBe(0)
	end)

	t.test("blendSpan clips to canvas bounds", function()
		local c = Canvas.create(4, 1)
		Canvas.blendSpan(c, -2, 10, 0, 1, 0, 0, 1)
		for x = 0, 3 do
			local r = Canvas.getPixel(c, x, 0)
			t.expect(near(r, 1)).toBeTruthy()
		end
	end)

	t.test("pack/unpack roundtrip", function()
		local packed = Canvas.pack(1, 0.5, 0.25, 0)
		local r, g, b, a = Canvas.unpack(packed)
		t.expect(near(r, 1)).toBeTruthy()
		t.expect(near(g, 0.5)).toBeTruthy()
		t.expect(near(b, 0.25)).toBeTruthy()
		t.expect(a).toBe(0)
	end)
end)
