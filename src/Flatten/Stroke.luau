--!strict
--[=[
	@class Stroke
	@private

	Converts a polyline subpath plus a stroke style into one or more filled
	polygons that, when rasterized, look like the stroked path.

	- Dashing splits the polyline into dash segments before outlining.
	- Each dash (or the whole polyline if there's no dash pattern) is
	  expanded into a closed polygon whose width is `stroke-width`.
	- Joins at interior vertices are miter/round/bevel per `stroke-linejoin`.
	- End caps are butt/round/square per `stroke-linecap`.

	The output polygons are suitable for the same scanline rasterizer used
	for fills — there's no separate "stroke" path at render time.
]=]

local Style = require("../Parser/Style")

local Stroke = {}

local CIRCLE_SEGMENTS_PER_RADIAN = 16 / (2 * math.pi) -- 16 per full turn

export type Polygon = { number }

-- Compute the dash segments as flat `{x, y, x, y, ...}` arrays. Dashes are
-- applied *after* flattening so dash lengths are measured in world units.
local function dashedSegments(
	points: { number },
	dasharray: { number },
	dashoffset: number
): { { number } }
	if #dasharray == 0 or #points < 4 then
		return { points }
	end
	-- Normalise offset into [0, cycle)
	local cycle = 0
	for _, d in ipairs(dasharray) do
		cycle += d
	end
	if cycle <= 0 then
		return { points }
	end
	local offset = dashoffset % cycle
	if offset < 0 then
		offset += cycle
	end
	-- Determine starting dash index/position.
	local dashIndex = 1
	local dashRemaining = dasharray[1] - offset
	while dashRemaining <= 0 do
		offset -= dasharray[dashIndex]
		dashIndex += 1
		if dashIndex > #dasharray then
			dashIndex = 1
		end
		dashRemaining = dasharray[dashIndex] - offset
		offset = 0
	end
	local drawing = (dashIndex % 2) == 1
	local segments: { { number } } = {}
	local current: { number }? = nil
	local function emit(x: number, y: number)
		if drawing then
			local c = current
			if not c then
				local fresh: { number } = { x, y }
				current = fresh
				table.insert(segments, fresh)
			else
				table.insert(c, x)
				table.insert(c, y)
			end
		end
	end
	local function closeCurrent()
		current = nil
	end
	local px = points[1]
	local py = points[2]
	emit(px, py)
	for i = 3, #points, 2 do
		local nx = points[i]
		local ny = points[i + 1]
		local dx = nx - px
		local dy = ny - py
		local segLen = math.sqrt(dx * dx + dy * dy)
		if segLen < 1e-12 then
			px, py = nx, ny
			continue
		end
		local traveled = 0
		while traveled < segLen do
			local remain = segLen - traveled
			if dashRemaining >= remain then
				emit(nx, ny)
				dashRemaining -= remain
				traveled = segLen
			else
				local t = (traveled + dashRemaining) / segLen
				local ix = px + dx * t
				local iy = py + dy * t
				emit(ix, iy)
				traveled += dashRemaining
				-- Advance to next dash slot; flip drawing state.
				dashIndex += 1
				if dashIndex > #dasharray then
					dashIndex = 1
				end
				if drawing then
					closeCurrent()
					drawing = false
				else
					drawing = true
					current = { ix, iy }
					table.insert(segments, current :: { number })
				end
				dashRemaining = dasharray[dashIndex]
			end
		end
		px, py = nx, ny
	end
	return segments
end

local function normalize(dx: number, dy: number): (number, number, number)
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 1e-12 then
		return 0, 0, 0
	end
	return dx / length, dy / length, length
end

-- Emit a closed polygon whose vertices are `{x1, y1, x2, y2, ...}`.
local function buildSegmentPolygon(style: Style.Style, points: { number }, output: { Polygon })
	local halfWidth = style.strokeWidth / 2
	if halfWidth <= 0 or #points < 4 then
		return
	end
	local count = #points / 2
	-- Left/right offset vertices accumulate into two tracks, then we
	-- concatenate right-track forward with left-track reversed for a single
	-- closed polygon.
	local leftX: { number } = {}
	local leftY: { number } = {}
	local rightX: { number } = {}
	local rightY: { number } = {}
	-- Precompute edge direction / normal for each segment.
	local edgeNX: { number } = {}
	local edgeNY: { number } = {}
	for i = 1, count - 1 do
		local x1 = points[(i - 1) * 2 + 1]
		local y1 = points[(i - 1) * 2 + 2]
		local x2 = points[i * 2 + 1]
		local y2 = points[i * 2 + 2]
		local nx, ny = normalize(x2 - x1, y2 - y1)
		edgeNX[i] = nx
		edgeNY[i] = ny
	end
	-- First endpoint cap-entry.
	do
		local nx = edgeNX[1]
		local ny = edgeNY[1]
		local px = points[1]
		local py = points[2]
		-- Perpendicular (rotated 90deg CCW): (-ny, nx)
		local ox = -ny * halfWidth
		local oy = nx * halfWidth
		if style.strokeLinecap == "square" then
			px -= nx * halfWidth
			py -= ny * halfWidth
		end
		if style.strokeLinecap == "round" then
			local cx = points[1]
			local cy = points[2]
			local steps = math.max(4, math.ceil(math.pi * CIRCLE_SEGMENTS_PER_RADIAN))
			-- Sweep from (-ox, -oy) back to (ox, oy) through the behind-side.
			local baseAngle = math.atan2(-oy, -ox)
			for s = 0, steps do
				local t = s / steps
				local a = baseAngle + math.pi * t
				table.insert(rightX, cx + math.cos(a) * halfWidth)
				table.insert(rightY, cy + math.sin(a) * halfWidth)
			end
			table.insert(leftX, cx + ox)
			table.insert(leftY, cy + oy)
		else
			table.insert(rightX, px - ox)
			table.insert(rightY, py - oy)
			table.insert(leftX, px + ox)
			table.insert(leftY, py + oy)
		end
	end
	-- Interior joins.
	for i = 2, count - 1 do
		local prevNx = edgeNX[i - 1]
		local prevNy = edgeNY[i - 1]
		local nextNx = edgeNX[i]
		local nextNy = edgeNY[i]
		local px = points[(i - 1) * 2 + 1]
		local py = points[(i - 1) * 2 + 2]
		-- Perpendiculars.
		local prevOx = -prevNy * halfWidth
		local prevOy = prevNx * halfWidth
		local nextOx = -nextNy * halfWidth
		local nextOy = nextNx * halfWidth
		-- Turn sign: positive => left turn (miter on outside = right side)
		local cross = prevNx * nextNy - prevNy * nextNx
		local dot = prevNx * nextNx + prevNy * nextNy
		local turnAngle = math.atan2(math.abs(cross), dot)
		-- Compute miter intersection on both sides.
		local function miterIntersect(
			offX1: number,
			offY1: number,
			offX2: number,
			offY2: number
		): (number, number)
			-- Solve for intersection of lines:
			--   (px + offX1) + s * prevN
			--   (px + offX2) + t * nextN
			local ax = px + offX1
			local ay = py + offY1
			local bx = px + offX2
			local by = py + offY2
			local denom = prevNx * -nextNy - prevNy * -nextNx
			if math.abs(denom) < 1e-10 then
				return (ax + bx) / 2, (ay + by) / 2
			end
			local s = ((bx - ax) * -nextNy - (by - ay) * -nextNx) / denom
			return ax + s * prevNx, ay + s * prevNy
		end
		local insideX, insideY
		local outsideSide = if cross > 0 then "right" else "left"
		local _ = outsideSide
		-- Miter limit: miter length / stroke width. If exceeded, fall back to
		-- bevel regardless of the join style.
		local miterLimit = style.strokeMiterlimit
		local halfTurn = turnAngle / 2
		local sinHalf = math.sin(halfTurn)
		local miterLength = if sinHalf > 1e-6 then 1 / sinHalf else math.huge
		local useBevelForMiter = miterLength > miterLimit
		if style.strokeLinejoin == "miter" and not useBevelForMiter then
			-- Miter on both sides.
			local rx, ry = miterIntersect(-prevOx, -prevOy, -nextOx, -nextOy)
			local lx, ly = miterIntersect(prevOx, prevOy, nextOx, nextOy)
			table.insert(rightX, rx)
			table.insert(rightY, ry)
			table.insert(leftX, lx)
			table.insert(leftY, ly)
		elseif style.strokeLinejoin == "round" then
			-- Inside: still miter; outside: fan of arc samples.
			if cross > 0 then
				-- left turn: right side is outside -> arc on the right
				insideX, insideY = miterIntersect(prevOx, prevOy, nextOx, nextOy)
				table.insert(leftX, insideX)
				table.insert(leftY, insideY)
				local a1 = math.atan2(-prevOy, -prevOx)
				local a2 = math.atan2(-nextOy, -nextOx)
				local span = a2 - a1
				if span < -math.pi then
					span += 2 * math.pi
				elseif span > math.pi then
					span -= 2 * math.pi
				end
				local steps = math.max(2, math.ceil(math.abs(span) * CIRCLE_SEGMENTS_PER_RADIAN))
				for s = 0, steps do
					local t = s / steps
					local a = a1 + span * t
					table.insert(rightX, px + math.cos(a) * halfWidth)
					table.insert(rightY, py + math.sin(a) * halfWidth)
				end
			else
				insideX, insideY = miterIntersect(-prevOx, -prevOy, -nextOx, -nextOy)
				table.insert(rightX, insideX)
				table.insert(rightY, insideY)
				local a1 = math.atan2(prevOy, prevOx)
				local a2 = math.atan2(nextOy, nextOx)
				local span = a2 - a1
				if span < -math.pi then
					span += 2 * math.pi
				elseif span > math.pi then
					span -= 2 * math.pi
				end
				local steps = math.max(2, math.ceil(math.abs(span) * CIRCLE_SEGMENTS_PER_RADIAN))
				for s = 0, steps do
					local t = s / steps
					local a = a1 + span * t
					table.insert(leftX, px + math.cos(a) * halfWidth)
					table.insert(leftY, py + math.sin(a) * halfWidth)
				end
			end
		else
			-- Bevel (or miter fallback): add both sides as separate entries
			-- inside = miter intersection; outside = two points at the two
			-- edge perpendiculars.
			if cross > 0 then
				-- left turn: outside is right
				insideX, insideY = miterIntersect(prevOx, prevOy, nextOx, nextOy)
				table.insert(leftX, insideX)
				table.insert(leftY, insideY)
				table.insert(rightX, px - prevOx)
				table.insert(rightY, py - prevOy)
				table.insert(rightX, px - nextOx)
				table.insert(rightY, py - nextOy)
			else
				insideX, insideY = miterIntersect(-prevOx, -prevOy, -nextOx, -nextOy)
				table.insert(rightX, insideX)
				table.insert(rightY, insideY)
				table.insert(leftX, px + prevOx)
				table.insert(leftY, py + prevOy)
				table.insert(leftX, px + nextOx)
				table.insert(leftY, py + nextOy)
			end
		end
	end
	-- End cap.
	do
		local nx = edgeNX[count - 1]
		local ny = edgeNY[count - 1]
		local px = points[(count - 1) * 2 + 1]
		local py = points[(count - 1) * 2 + 2]
		local ox = -ny * halfWidth
		local oy = nx * halfWidth
		if style.strokeLinecap == "square" then
			px += nx * halfWidth
			py += ny * halfWidth
		end
		if style.strokeLinecap == "round" then
			local cx = points[(count - 1) * 2 + 1]
			local cy = points[(count - 1) * 2 + 2]
			local steps = math.max(4, math.ceil(math.pi * CIRCLE_SEGMENTS_PER_RADIAN))
			local baseAngle = math.atan2(oy, ox)
			for s = 0, steps do
				local t = s / steps
				local a = baseAngle + math.pi * t
				table.insert(rightX, cx + math.cos(a) * halfWidth)
				table.insert(rightY, cy + math.sin(a) * halfWidth)
			end
			table.insert(leftX, cx - ox)
			table.insert(leftY, cy - oy)
		else
			table.insert(rightX, px + ox)
			table.insert(rightY, py + oy)
			table.insert(leftX, px - ox)
			table.insert(leftY, py - oy)
		end
	end
	-- Concatenate: right-track forward, left-track reversed.
	local polygon: Polygon = {}
	for i = 1, #rightX do
		table.insert(polygon, rightX[i])
		table.insert(polygon, rightY[i])
	end
	for i = #leftX, 1, -1 do
		table.insert(polygon, leftX[i])
		table.insert(polygon, leftY[i])
	end
	table.insert(output, polygon)
end

--[=[
	@within Stroke
	Converts a subpath polyline into one or more filled polygons approximating
	a stroked path. Pass the same polyline through regardless of whether the
	original subpath is closed; a closed subpath is stroked by appending its
	first vertex to the end so the closing edge is treated as just another
	segment with a standard join instead of caps.
]=]
function Stroke.expand(points: { number }, closed: boolean, style: Style.Style): { Polygon }
	if style.strokeWidth <= 0 or not style.stroke then
		return {}
	end
	if #points < 4 then
		return {}
	end
	local working: { number } = table.clone(points)
	if closed then
		-- Append the start point so the closing edge gets a proper join
		-- instead of two caps at what should be a smooth corner.
		local firstX = working[1]
		local firstY = working[2]
		local lastX = working[#working - 1]
		local lastY = working[#working]
		if firstX ~= lastX or firstY ~= lastY then
			table.insert(working, firstX)
			table.insert(working, firstY)
		end
	end
	local segments = if style.strokeDasharray
		then dashedSegments(working, style.strokeDasharray, style.strokeDashoffset)
		else { working }
	local polygons: { Polygon } = {}
	for _, segment in ipairs(segments) do
		buildSegmentPolygon(style, segment, polygons)
	end
	return polygons
end

return Stroke
