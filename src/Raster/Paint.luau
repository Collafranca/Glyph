--!strict
--[=[
	@class Paint
	@private

	Paint sources: solid colors and gradients. A paint is represented as a
	sampler function `(x, y) -> (r, g, b, a)` in canvas-space coordinates. The
	rasterizer calls it once per pixel (or per span for solid paints) to get
	the material to blend.

	Gradients bake the object-bounding-box transform and `gradientUnits`
	mapping into their sampler closures at build time, so pixel sampling is
	just a dot-product plus a stop lookup.
]=]

local Color = require("../Parser/Color")
local Length = require("../Parser/Length")
local Style = require("../Parser/Style")
local Svg = require("../Parser/Svg")
local Transform = require("../Parser/Transform")

local Paint = {}

export type Sampler = (x: number, y: number) -> (number, number, number, number)

export type BoundingBox = { minX: number, minY: number, maxX: number, maxY: number }

-- Applies opacity to the alpha channel.
local function applyOpacity(a: number, opacity: number): number
	return a * opacity
end

--[=[
	@within Paint
	A solid-color sampler. `color` is straight RGBA in [0, 1].
]=]
function Paint.solid(color: Color.Rgba, opacity: number): Sampler
	local r, g, b, a = color[1], color[2], color[3], applyOpacity(color[4], opacity)
	return function(_x: number, _y: number)
		return r, g, b, a
	end
end

-- Evaluate gradient stops at parameter `t` in [0, 1] (caller has already
-- applied spreadMethod). Returns RGBA.
local function evalStops(stops: { Svg.GradientStop }, t: number): (number, number, number, number)
	if #stops == 0 then
		return 0, 0, 0, 0
	end
	if t <= stops[1].offset then
		local s = stops[1]
		return s.color[1], s.color[2], s.color[3], s.color[4] * s.opacity
	end
	if t >= stops[#stops].offset then
		local s = stops[#stops]
		return s.color[1], s.color[2], s.color[3], s.color[4] * s.opacity
	end
	for i = 1, #stops - 1 do
		local s0 = stops[i]
		local s1 = stops[i + 1]
		if t >= s0.offset and t <= s1.offset then
			local span = s1.offset - s0.offset
			local u = if span > 0 then (t - s0.offset) / span else 0
			local a0 = s0.color[4] * s0.opacity
			local a1 = s1.color[4] * s1.opacity
			return s0.color[1] + (s1.color[1] - s0.color[1]) * u,
				s0.color[2] + (s1.color[2] - s0.color[2]) * u,
				s0.color[3] + (s1.color[3] - s0.color[3]) * u,
				a0 + (a1 - a0) * u
		end
	end
	local s = stops[#stops]
	return s.color[1], s.color[2], s.color[3], s.color[4] * s.opacity
end

local function applySpread(t: number, spread: "pad" | "reflect" | "repeat"): number
	if spread == "pad" then
		if t < 0 then
			return 0
		elseif t > 1 then
			return 1
		end
		return t
	elseif spread == "repeat" then
		local f = t - math.floor(t)
		return f
	else -- reflect
		local cycle = math.floor(t / 2) * 2
		local phase = t - cycle -- [0, 2)
		if phase > 1 then
			return 2 - phase
		end
		return phase
	end
end

-- Computes the inverse of a 2x3 affine matrix. We need the inverse to map
-- canvas-space pixel coordinates back into gradient-space before evaluating
-- the gradient parameter.
local function invertAffine(m: Transform.Matrix): Transform.Matrix
	local a, b, c, d, e, f = m[1], m[2], m[3], m[4], m[5], m[6]
	local det = a * d - b * c
	assert(det ~= 0, "cannot invert singular matrix")
	local invDet = 1 / det
	return {
		d * invDet,
		-b * invDet,
		-c * invDet,
		a * invDet,
		(c * f - d * e) * invDet,
		(b * e - a * f) * invDet,
	}
end

local function resolveGradientLength(
	length: Length.Length,
	reference: number,
	default: number
): number
	if length == nil then
		return default
	end
	if type(length) == "number" then
		return length
	end
	return (length :: { value: number }).value / 100 * reference
end

--[=[
	@within Paint
	Builds a linear-gradient sampler. The gradient is defined by the SVG
	`LinearGradient` spec, the shape's bounding box (for `objectBoundingBox`
	units), and the shape's world-space matrix.
]=]
function Paint.linearGradient(
	gradient: Svg.LinearGradient,
	bbox: BoundingBox,
	shapeMatrix: Transform.Matrix,
	opacity: number
): Sampler
	-- Gradient endpoints in the gradient's native coordinate space.
	local x1, y1, x2, y2
	if gradient.units == "objectBoundingBox" then
		local w = bbox.maxX - bbox.minX
		local h = bbox.maxY - bbox.minY
		x1 = bbox.minX + resolveGradientLength(gradient.x1, 1, 0) * w
		y1 = bbox.minY + resolveGradientLength(gradient.y1, 1, 0) * h
		x2 = bbox.minX + resolveGradientLength(gradient.x2, 1, 1) * w
		y2 = bbox.minY + resolveGradientLength(gradient.y2, 1, 0) * h
	else
		x1 = resolveGradientLength(gradient.x1, bbox.maxX - bbox.minX, 0)
		y1 = resolveGradientLength(gradient.y1, bbox.maxY - bbox.minY, 0)
		x2 = resolveGradientLength(gradient.x2, bbox.maxX - bbox.minX, 0)
		y2 = resolveGradientLength(gradient.y2, bbox.maxY - bbox.minY, 0)
	end
	-- Compose shape matrix with gradientTransform so canvas-space pixels can
	-- be mapped back into the gradient's space.
	local toCanvas = Transform.multiply(shapeMatrix, gradient.transform)
	local toGradient = invertAffine(toCanvas)
	local dx = x2 - x1
	local dy = y2 - y1
	local denom = dx * dx + dy * dy
	local stops = gradient.stops
	local spread: "pad" | "reflect" | "repeat" = gradient.spreadMethod
	if denom < 1e-12 or #stops == 0 then
		-- Degenerate gradient: use first stop color.
		local s = if #stops > 0 then stops[1] else nil
		if not s then
			return function(_x, _y)
				return 0, 0, 0, 0
			end
		end
		local color = s.color
		local a = color[4] * s.opacity * opacity
		return function(_x, _y)
			return color[1], color[2], color[3], a
		end
	end
	return function(px: number, py: number)
		local gx = toGradient[1] * px + toGradient[3] * py + toGradient[5]
		local gy = toGradient[2] * px + toGradient[4] * py + toGradient[6]
		local t = ((gx - x1) * dx + (gy - y1) * dy) / denom
		t = applySpread(t, spread)
		local r, g, b, a = evalStops(stops, t)
		return r, g, b, a * opacity
	end
end

--[=[
	@within Paint
	Builds a radial-gradient sampler. Focal point defaults to the center
	when not specified. Uses a simple distance-from-center mapping; the
	focal-offset case (where `fx`, `fy` differ from `cx`, `cy`) traces
	through the focal point per SVG 1.1 §13.2.3 but is approximated here
	as a linear interpolation between focus and center for simplicity.
]=]
function Paint.radialGradient(
	gradient: Svg.RadialGradient,
	bbox: BoundingBox,
	shapeMatrix: Transform.Matrix,
	opacity: number
): Sampler
	local cx, cy, r, fx, fy
	if gradient.units == "objectBoundingBox" then
		local w = bbox.maxX - bbox.minX
		local h = bbox.maxY - bbox.minY
		cx = bbox.minX + resolveGradientLength(gradient.cx, 1, 0.5) * w
		cy = bbox.minY + resolveGradientLength(gradient.cy, 1, 0.5) * h
		r = resolveGradientLength(gradient.r, 1, 0.5) * math.max(w, h)
		fx = if gradient.fx then bbox.minX + resolveGradientLength(gradient.fx, 1, 0.5) * w else cx
		fy = if gradient.fy then bbox.minY + resolveGradientLength(gradient.fy, 1, 0.5) * h else cy
	else
		cx = resolveGradientLength(gradient.cx, bbox.maxX - bbox.minX, 0)
		cy = resolveGradientLength(gradient.cy, bbox.maxY - bbox.minY, 0)
		r = resolveGradientLength(
			gradient.r,
			math.max(bbox.maxX - bbox.minX, bbox.maxY - bbox.minY),
			0
		)
		fx = if gradient.fx
			then resolveGradientLength(gradient.fx, bbox.maxX - bbox.minX, 0)
			else cx
		fy = if gradient.fy
			then resolveGradientLength(gradient.fy, bbox.maxY - bbox.minY, 0)
			else cy
	end
	local toCanvas = Transform.multiply(shapeMatrix, gradient.transform)
	local toGradient = invertAffine(toCanvas)
	local stops = gradient.stops
	local spread: "pad" | "reflect" | "repeat" = gradient.spreadMethod
	if r <= 0 or #stops == 0 then
		local s = if #stops > 0 then stops[1] else nil
		if not s then
			return function(_x, _y)
				return 0, 0, 0, 0
			end
		end
		local color = s.color
		local a = color[4] * s.opacity * opacity
		return function(_x, _y)
			return color[1], color[2], color[3], a
		end
	end
	-- For the degenerate focal == center case we can skip the more complex
	-- SVG-spec math and just return |p - center| / r.
	if fx == cx and fy == cy then
		return function(px: number, py: number)
			local gx = toGradient[1] * px + toGradient[3] * py + toGradient[5]
			local gy = toGradient[2] * px + toGradient[4] * py + toGradient[6]
			local ddx = gx - cx
			local ddy = gy - cy
			local t = math.sqrt(ddx * ddx + ddy * ddy) / r
			t = applySpread(t, spread)
			local rr, gg, bb, aa = evalStops(stops, t)
			return rr, gg, bb, aa * opacity
		end
	end
	-- Focal-offset radial: per SVG 1.1 §13.2.3 we shoot a ray from (fx, fy)
	-- through the sample point, intersect with the circle of radius r
	-- centered at (cx, cy), and t is the ratio of |p - f| to |intersection - f|.
	return function(px: number, py: number)
		local gx = toGradient[1] * px + toGradient[3] * py + toGradient[5]
		local gy = toGradient[2] * px + toGradient[4] * py + toGradient[6]
		local dx = gx - fx
		local dy = gy - fy
		-- Solve |(f - c) + t_ray * (p - f)|^2 = r^2 for the positive root.
		local fcx = fx - cx
		local fcy = fy - cy
		local aCoeff = dx * dx + dy * dy
		local bCoeff = 2 * (fcx * dx + fcy * dy)
		local cCoeff = fcx * fcx + fcy * fcy - r * r
		local disc = bCoeff * bCoeff - 4 * aCoeff * cCoeff
		local t
		if disc < 0 or aCoeff < 1e-12 then
			t = 0
		else
			local tRay = (-bCoeff + math.sqrt(disc)) / (2 * aCoeff)
			if tRay <= 0 then
				t = 0
			else
				t = 1 / tRay
			end
		end
		t = applySpread(t, spread)
		local rr, gg, bb, aa = evalStops(stops, t)
		return rr, gg, bb, aa * opacity
	end
end

--[=[
	@within Paint
	Builds a sampler for a resolved `Paint` field (solid RGBA, gradient
	reference, or currentColor sentinel). Returns `nil` if the paint is
	"none" (caller should skip drawing).
]=]
function Paint.build(
	paint: Style.Paint?,
	gradients: { [string]: Svg.Gradient },
	bbox: BoundingBox,
	shapeMatrix: Transform.Matrix,
	opacity: number
): Sampler?
	if paint == nil then
		return nil
	end
	if type(paint) == "table" then
		local tab = paint :: any
		if tab.kind == "url" then
			local grad = gradients[tab.id]
			if not grad then
				-- Per SVG 1.1: a paint reference that fails to resolve falls
				-- back to black. Use the fallback-less form (most exporters
				-- don't emit a fallback paint).
				return Paint.solid({ 0, 0, 0, 1 }, opacity)
			end
			if grad.kind == "linear" then
				return Paint.linearGradient(grad :: Svg.LinearGradient, bbox, shapeMatrix, opacity)
			else
				return Paint.radialGradient(grad :: Svg.RadialGradient, bbox, shapeMatrix, opacity)
			end
		else
			-- An Rgba tuple.
			return Paint.solid(paint :: Color.Rgba, opacity)
		end
	end
	-- `"currentColor"` or `"none"`: currentColor should have been resolved
	-- during style inheritance; if we see it here, default to black.
	if paint == "none" then
		return nil
	end
	return Paint.solid({ 0, 0, 0, 1 }, opacity)
end

return Paint
