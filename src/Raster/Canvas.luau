--!strict
--[=[
	@class Canvas
	@private

	RGBA pixel buffer with fast `buffer.writeu32` pixel writes.

	Pixels are packed little-endian as `A << 24 | B << 16 | G << 8 | R` so that
	a `writeu32` lays the bytes out as `R, G, B, A` — matching Roblox's
	`EditableImage:WritePixelsBuffer` format (per the EditableImage docs,
	bytes are interpreted in `Color3`/`Color4` RGBA order).
]=]

local Canvas = {}

export type Canvas = {
	width: number,
	height: number,
	buffer: buffer,
	stride: number,
}

--[=[
	@within Canvas
	Allocates a canvas of the requested size, filled with transparent black.
]=]
function Canvas.create(width: number, height: number): Canvas
	assert(width > 0 and height > 0, "canvas dimensions must be positive")
	local buf = buffer.create(width * height * 4)
	return {
		width = width,
		height = height,
		buffer = buf,
		stride = width * 4,
	}
end

--[=[
	@within Canvas
	Clears the entire canvas to the supplied RGBA values in [0, 1].
]=]
function Canvas.clear(canvas: Canvas, r: number, g: number, b: number, a: number)
	local ri = math.floor(r * 255 + 0.5)
	local gi = math.floor(g * 255 + 0.5)
	local bi = math.floor(b * 255 + 0.5)
	local ai = math.floor(a * 255 + 0.5)
	local packed = bit32.bor(
		bit32.band(ri, 0xFF),
		bit32.lshift(bit32.band(gi, 0xFF), 8),
		bit32.lshift(bit32.band(bi, 0xFF), 16),
		bit32.lshift(bit32.band(ai, 0xFF), 24)
	)
	local total = canvas.width * canvas.height
	for i = 0, total - 1 do
		buffer.writeu32(canvas.buffer, i * 4, packed)
	end
end

local function clampByte(v: number): number
	if v < 0 then
		return 0
	elseif v > 255 then
		return 255
	end
	return math.floor(v + 0.5)
end

--[=[
	@within Canvas
	Packs four [0, 1] floats into a 32-bit RGBA word.
]=]
function Canvas.pack(r: number, g: number, b: number, a: number): number
	return bit32.bor(
		clampByte(r * 255),
		bit32.lshift(clampByte(g * 255), 8),
		bit32.lshift(clampByte(b * 255), 16),
		bit32.lshift(clampByte(a * 255), 24)
	)
end

--[=[
	@within Canvas
	Unpacks an RGBA word into four [0, 1] floats.
]=]
function Canvas.unpack(packed: number): (number, number, number, number)
	return bit32.band(packed, 0xFF) / 255,
		bit32.band(bit32.rshift(packed, 8), 0xFF) / 255,
		bit32.band(bit32.rshift(packed, 16), 0xFF) / 255,
		bit32.band(bit32.rshift(packed, 24), 0xFF) / 255
end

--[=[
	@within Canvas
	Returns the pixel at (x, y) as four [0, 1] floats. Out-of-bounds reads
	return transparent black.
]=]
function Canvas.getPixel(canvas: Canvas, x: number, y: number): (number, number, number, number)
	if x < 0 or x >= canvas.width or y < 0 or y >= canvas.height then
		return 0, 0, 0, 0
	end
	local offset = (y * canvas.width + x) * 4
	return Canvas.unpack(buffer.readu32(canvas.buffer, offset))
end

--[=[
	@within Canvas
	Writes `(r, g, b, a)` at `(x, y)`, overwriting any existing pixel (no
	blending). Silently no-ops if out of bounds.
]=]
function Canvas.setPixel(
	canvas: Canvas,
	x: number,
	y: number,
	r: number,
	g: number,
	b: number,
	a: number
)
	if x < 0 or x >= canvas.width or y < 0 or y >= canvas.height then
		return
	end
	local offset = (y * canvas.width + x) * 4
	buffer.writeu32(canvas.buffer, offset, Canvas.pack(r, g, b, a))
end

--[=[
	@within Canvas
	Alpha-composites `(r, g, b, a)` over the existing pixel at `(x, y)` using
	straight-alpha source-over.
]=]
function Canvas.blendPixel(
	canvas: Canvas,
	x: number,
	y: number,
	r: number,
	g: number,
	b: number,
	a: number
)
	if x < 0 or x >= canvas.width or y < 0 or y >= canvas.height then
		return
	end
	if a <= 0 then
		return
	end
	local offset = (y * canvas.width + x) * 4
	if a >= 1 then
		buffer.writeu32(canvas.buffer, offset, Canvas.pack(r, g, b, a))
		return
	end
	local dr, dg, db, da = Canvas.unpack(buffer.readu32(canvas.buffer, offset))
	local inv = 1 - a
	local outA = a + da * inv
	local outR, outG, outB
	if outA <= 0 then
		outR, outG, outB = 0, 0, 0
	else
		outR = (r * a + dr * da * inv) / outA
		outG = (g * a + dg * da * inv) / outA
		outB = (b * a + db * da * inv) / outA
	end
	buffer.writeu32(canvas.buffer, offset, Canvas.pack(outR, outG, outB, outA))
end

--[=[
	@within Canvas
	Fills a horizontal span `[x0, x1)` at row `y` with a solid color,
	alpha-compositing onto the existing pixels. Clipped to the canvas bounds.
]=]
function Canvas.blendSpan(
	canvas: Canvas,
	x0: number,
	x1: number,
	y: number,
	r: number,
	g: number,
	b: number,
	a: number
)
	if y < 0 or y >= canvas.height or a <= 0 or x1 <= x0 then
		return
	end
	local lo = math.max(0, x0)
	local hi = math.min(canvas.width, x1)
	if lo >= hi then
		return
	end
	if a >= 1 then
		local packed = Canvas.pack(r, g, b, a)
		local offset = (y * canvas.width + lo) * 4
		for _ = lo, hi - 1 do
			buffer.writeu32(canvas.buffer, offset, packed)
			offset += 4
		end
		return
	end
	local offset = (y * canvas.width + lo) * 4
	local inv = 1 - a
	for _ = lo, hi - 1 do
		local dr, dg, db, da = Canvas.unpack(buffer.readu32(canvas.buffer, offset))
		local outA = a + da * inv
		local outR, outG, outB
		if outA <= 0 then
			outR, outG, outB = 0, 0, 0
		else
			outR = (r * a + dr * da * inv) / outA
			outG = (g * a + dg * da * inv) / outA
			outB = (b * a + db * da * inv) / outA
		end
		buffer.writeu32(canvas.buffer, offset, Canvas.pack(outR, outG, outB, outA))
		offset += 4
	end
end

return Canvas
