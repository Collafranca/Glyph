--!strict
--[=[
	@class Bezier
	@private

	Adaptive subdivision of cubic and quadratic Bezier curves into polylines
	suitable for scanline rasterization. The subdivision criterion uses the
	deviation from the chord: if the worst control-point deviation is below
	the supplied flatness tolerance (in user units) the curve is treated as a
	straight line; otherwise the curve is split at t = 0.5 and both halves are
	recursively flattened.

	The approach produces near-optimal vertex counts for reasonable tolerances
	(0.1 - 0.25 px) without the expensive second-derivative math of parametric
	sampling.
]=]

local Bezier = {}

-- Cap recursion to stop pathological inputs (e.g. NaN control points) from
-- exhausting the stack. 24 levels admits ~16.7M samples — vastly more than
-- any real curve needs.
local MAX_DEPTH = 24

local function deviationCubic(
	ax: number,
	ay: number,
	bx: number,
	by: number,
	cx: number,
	cy: number,
	dx: number,
	dy: number
): number
	-- Perpendicular distance from each control point to the chord AD.
	local chordX = dx - ax
	local chordY = dy - ay
	local chordLen = math.sqrt(chordX * chordX + chordY * chordY)
	if chordLen < 1e-12 then
		-- Degenerate: chord has zero length. Measure distance from control
		-- points to the single point A.
		local d1x = bx - ax
		local d1y = by - ay
		local d2x = cx - ax
		local d2y = cy - ay
		return math.max(math.sqrt(d1x * d1x + d1y * d1y), math.sqrt(d2x * d2x + d2y * d2y))
	end
	-- Signed perpendicular distance:
	--   d = |(p - a) x (d - a)| / |d - a|
	local d1 = math.abs((bx - ax) * chordY - (by - ay) * chordX) / chordLen
	local d2 = math.abs((cx - ax) * chordY - (cy - ay) * chordX) / chordLen
	return math.max(d1, d2)
end

local function flattenCubicInto(
	output: { number },
	ax: number,
	ay: number,
	bx: number,
	by: number,
	cx: number,
	cy: number,
	dx: number,
	dy: number,
	tolerance: number,
	depth: number
)
	if depth >= MAX_DEPTH or deviationCubic(ax, ay, bx, by, cx, cy, dx, dy) <= tolerance then
		table.insert(output, dx)
		table.insert(output, dy)
		return
	end
	-- de Casteljau split at t = 0.5
	local abx, aby = (ax + bx) * 0.5, (ay + by) * 0.5
	local bcx, bcy = (bx + cx) * 0.5, (by + cy) * 0.5
	local cdx, cdy = (cx + dx) * 0.5, (cy + dy) * 0.5
	local abcx, abcy = (abx + bcx) * 0.5, (aby + bcy) * 0.5
	local bcdx, bcdy = (bcx + cdx) * 0.5, (bcy + cdy) * 0.5
	local mx, my = (abcx + bcdx) * 0.5, (abcy + bcdy) * 0.5
	flattenCubicInto(output, ax, ay, abx, aby, abcx, abcy, mx, my, tolerance, depth + 1)
	flattenCubicInto(output, mx, my, bcdx, bcdy, cdx, cdy, dx, dy, tolerance, depth + 1)
end

--[=[
	@within Bezier
	Flattens a cubic Bezier (a -> d via b, c) into the supplied output array
	of `{x, y, x, y, ...}` coordinates. Does NOT emit the starting point —
	callers are expected to have already appended `ax, ay`.
]=]
function Bezier.flattenCubic(
	output: { number },
	ax: number,
	ay: number,
	bx: number,
	by: number,
	cx: number,
	cy: number,
	dx: number,
	dy: number,
	tolerance: number
)
	flattenCubicInto(output, ax, ay, bx, by, cx, cy, dx, dy, tolerance, 0)
end

local function deviationQuadratic(
	ax: number,
	ay: number,
	bx: number,
	by: number,
	cx: number,
	cy: number
): number
	local chordX = cx - ax
	local chordY = cy - ay
	local chordLen = math.sqrt(chordX * chordX + chordY * chordY)
	if chordLen < 1e-12 then
		local dx = bx - ax
		local dy = by - ay
		return math.sqrt(dx * dx + dy * dy)
	end
	return math.abs((bx - ax) * chordY - (by - ay) * chordX) / chordLen
end

local function flattenQuadraticInto(
	output: { number },
	ax: number,
	ay: number,
	bx: number,
	by: number,
	cx: number,
	cy: number,
	tolerance: number,
	depth: number
)
	if depth >= MAX_DEPTH or deviationQuadratic(ax, ay, bx, by, cx, cy) <= tolerance then
		table.insert(output, cx)
		table.insert(output, cy)
		return
	end
	local abx, aby = (ax + bx) * 0.5, (ay + by) * 0.5
	local bcx, bcy = (bx + cx) * 0.5, (by + cy) * 0.5
	local mx, my = (abx + bcx) * 0.5, (aby + bcy) * 0.5
	flattenQuadraticInto(output, ax, ay, abx, aby, mx, my, tolerance, depth + 1)
	flattenQuadraticInto(output, mx, my, bcx, bcy, cx, cy, tolerance, depth + 1)
end

--[=[
	@within Bezier
	Flattens a quadratic Bezier (a -> c via b) into the supplied output.
]=]
function Bezier.flattenQuadratic(
	output: { number },
	ax: number,
	ay: number,
	bx: number,
	by: number,
	cx: number,
	cy: number,
	tolerance: number
)
	flattenQuadraticInto(output, ax, ay, bx, by, cx, cy, tolerance, 0)
end

return Bezier
