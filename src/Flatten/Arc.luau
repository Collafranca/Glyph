--!strict
--[=[
	@class Arc
	@private

	Converts SVG elliptical arc commands into a sequence of cubic Beziers,
	which the Bezier module can then flatten to polylines.

	Follows the implementation notes in SVG 1.1 Appendix F.6 ("Elliptical arc
	implementation notes"):

	- F.6.5: conversion from endpoint parameterization (the SVG form — two
	  endpoints plus radii, rotation, and flags) to center parameterization
	  (center point, start/end angles, sweep).
	- F.6.6: radius correction. If `rx` or `ry` is zero the arc degenerates
	  to a line; if the radii are too small to reach the endpoint, they are
	  scaled up by the spec's prescribed factor.

	Each 90-degree slice of the arc is approximated by a cubic with the
	analytic "magic number" control handles from the standard ellipse-to-Bezier
	derivation (k = (4/3) * tan(theta/4)). The arc is split at 90-degree
	boundaries to keep the per-segment angular sweep small; cubic Beziers can
	model up to about 90 degrees of an elliptical arc with maximum error
	around 2.7e-4 of the radius, which is visually indistinguishable at
	typical icon sizes.
]=]

local Arc = {}

local function vectorAngle(ux: number, uy: number, vx: number, vy: number): number
	local dot = ux * vx + uy * vy
	local lenU = math.sqrt(ux * ux + uy * uy)
	local lenV = math.sqrt(vx * vx + vy * vy)
	local ratio = dot / (lenU * lenV)
	ratio = math.clamp(ratio, -1, 1)
	local sign = ux * vy - uy * vx
	local angle = math.acos(ratio)
	if sign < 0 then
		return -angle
	end
	return angle
end

--[=[
	@within Arc
	@interface Segment
	.cx number     -- center x
	.cy number     -- center y
	.rx number     -- corrected rx
	.ry number     -- corrected ry
	.phi number    -- x-axis rotation (radians)
	.theta1 number -- start angle (radians)
	.deltaTheta number -- sweep (radians; sign matches sweepFlag)
]=]
export type Segment = {
	cx: number,
	cy: number,
	rx: number,
	ry: number,
	phi: number,
	theta1: number,
	deltaTheta: number,
}

--[=[
	@within Arc
	Converts an SVG endpoint-parameterized arc into a center-parameterized
	segment. Returns `nil` if the arc degenerates to a straight line (same
	start and end point).

	Applies the F.6.6 radius correction before returning.
]=]
function Arc.toCenter(
	x1: number,
	y1: number,
	rx: number,
	ry: number,
	xAxisRotationDeg: number,
	largeArcFlag: number,
	sweepFlag: number,
	x2: number,
	y2: number
): Segment?
	if x1 == x2 and y1 == y2 then
		return nil
	end
	local absRx = math.abs(rx)
	local absRy = math.abs(ry)
	if absRx == 0 or absRy == 0 then
		-- Out-of-range radii per F.6.6: treat as straight line.
		return nil
	end
	local phi = math.rad(xAxisRotationDeg)
	local cosPhi = math.cos(phi)
	local sinPhi = math.sin(phi)
	-- Step 1: transform (x1, y1), (x2, y2) to the ellipse's local frame.
	local dx = (x1 - x2) / 2
	local dy = (y1 - y2) / 2
	local x1p = cosPhi * dx + sinPhi * dy
	local y1p = -sinPhi * dx + cosPhi * dy
	-- Step 2: F.6.6.3 — ensure radii are large enough.
	local lambda = (x1p * x1p) / (absRx * absRx) + (y1p * y1p) / (absRy * absRy)
	if lambda > 1 then
		local scale = math.sqrt(lambda)
		absRx *= scale
		absRy *= scale
	end
	-- Step 3: compute center in the local frame.
	local rx2 = absRx * absRx
	local ry2 = absRy * absRy
	local x1p2 = x1p * x1p
	local y1p2 = y1p * y1p
	local denom = rx2 * y1p2 + ry2 * x1p2
	local numer = rx2 * ry2 - denom
	if numer < 0 then
		numer = 0
	end
	local coef = math.sqrt(numer / denom)
	if largeArcFlag == sweepFlag then
		coef = -coef
	end
	local cxp = coef * (absRx * y1p) / absRy
	local cyp = coef * -(absRy * x1p) / absRx
	-- Step 4: transform the center back to the original frame.
	local cx = cosPhi * cxp - sinPhi * cyp + (x1 + x2) / 2
	local cy = sinPhi * cxp + cosPhi * cyp + (y1 + y2) / 2
	-- Step 5: compute start angle and sweep angle.
	local ux = (x1p - cxp) / absRx
	local uy = (y1p - cyp) / absRy
	local vx = (-x1p - cxp) / absRx
	local vy = (-y1p - cyp) / absRy
	local theta1 = vectorAngle(1, 0, ux, uy)
	local deltaTheta = vectorAngle(ux, uy, vx, vy)
	if sweepFlag == 0 and deltaTheta > 0 then
		deltaTheta -= 2 * math.pi
	elseif sweepFlag == 1 and deltaTheta < 0 then
		deltaTheta += 2 * math.pi
	end
	return {
		cx = cx,
		cy = cy,
		rx = absRx,
		ry = absRy,
		phi = phi,
		theta1 = theta1,
		deltaTheta = deltaTheta,
	}
end

-- Evaluates the parameterized ellipse at angle `theta`.
local function ellipsePoint(seg: Segment, theta: number): (number, number)
	local cosPhi = math.cos(seg.phi)
	local sinPhi = math.sin(seg.phi)
	local cosT = math.cos(theta)
	local sinT = math.sin(theta)
	local ex = seg.rx * cosT
	local ey = seg.ry * sinT
	return seg.cx + cosPhi * ex - sinPhi * ey, seg.cy + sinPhi * ex + cosPhi * ey
end

-- Evaluates the derivative (tangent) at angle theta.
local function ellipseTangent(seg: Segment, theta: number): (number, number)
	local cosPhi = math.cos(seg.phi)
	local sinPhi = math.sin(seg.phi)
	local cosT = math.cos(theta)
	local sinT = math.sin(theta)
	local dx = -seg.rx * sinT
	local dy = seg.ry * cosT
	return cosPhi * dx - sinPhi * dy, sinPhi * dx + cosPhi * dy
end

-- Approximates a single slice (theta1 -> theta1 + delta) of the ellipse with
-- one cubic Bezier, using the analytic control-handle length.
local function sliceToCubic(
	seg: Segment,
	theta1: number,
	delta: number
): (number, number, number, number, number, number)
	local theta2 = theta1 + delta
	local alpha = math.sin(delta) * (math.sqrt(4 + 3 * math.tan(delta / 2) ^ 2) - 1) / 3
	local x1, y1 = ellipsePoint(seg, theta1)
	local x2, y2 = ellipsePoint(seg, theta2)
	local t1x, t1y = ellipseTangent(seg, theta1)
	local t2x, t2y = ellipseTangent(seg, theta2)
	local cx1 = x1 + alpha * t1x
	local cy1 = y1 + alpha * t1y
	local cx2 = x2 - alpha * t2x
	local cy2 = y2 - alpha * t2y
	return cx1, cy1, cx2, cy2, x2, y2
end

--[=[
	@within Arc
	Converts a center-parameterized arc segment into a sequence of cubic
	Beziers, appending `(c1x, c1y, c2x, c2y, px, py)` control points to
	`output` for each cubic (the start point is implied by the previous
	cubic's end point, or by `seg` for the first one).

	Each cubic spans at most 90 degrees of arc sweep.
]=]
function Arc.toCubics(seg: Segment): { number }
	local output: { number } = {}
	local remaining = seg.deltaTheta
	local direction = if remaining >= 0 then 1 else -1
	local theta = seg.theta1
	while math.abs(remaining) > 1e-10 do
		local step = math.min(math.abs(remaining), math.pi / 2) * direction
		local cx1, cy1, cx2, cy2, px, py = sliceToCubic(seg, theta, step)
		table.insert(output, cx1)
		table.insert(output, cy1)
		table.insert(output, cx2)
		table.insert(output, cy2)
		table.insert(output, px)
		table.insert(output, py)
		theta += step
		remaining -= step
	end
	return output
end

return Arc
