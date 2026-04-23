--!strict
--[=[
	@class FlattenPath
	@private

	Converts a stream of absolute path commands (from `PathData.parse`) into a
	list of subpaths, where each subpath is a polyline of `(x, y)` pairs and
	a `closed` flag.

	Every curve command (C, Q, A) is flattened via `Bezier` and `Arc` so the
	output is purely linear segments. Subpaths are split on each M; a Z closes
	the current subpath by setting `closed = true` and marking the pen as
	retur-ned to the subpath's start point (the next M or implicit move picks
	up from there).

	Transform is applied after flattening so the flatness tolerance is expressed
	in post-transform pixels. Callers pass in the world-space matrix and an
	estimated per-user-unit pixel scale to choose the tolerance.
]=]

local Arc = require("./Arc")
local Bezier = require("./Bezier")
local PathData = require("../Parser/PathData")
local Transform = require("../Parser/Transform")

local FlattenPath = {}

export type Subpath = {
	-- Interleaved x/y coordinates, one entry per vertex (pair of values).
	points: { number },
	closed: boolean,
}

local function approxMatrixScale(m: Transform.Matrix): number
	-- Derive a representative per-unit pixel scale from the matrix. Use the
	-- larger of the two basis-vector magnitudes so tolerance errs on the side
	-- of finer subdivision for anisotropic transforms.
	local sx = math.sqrt(m[1] * m[1] + m[2] * m[2])
	local sy = math.sqrt(m[3] * m[3] + m[4] * m[4])
	return math.max(sx, sy)
end

local function applyMatrix(m: Transform.Matrix, points: { number })
	for i = 1, #points, 2 do
		local x = points[i]
		local y = points[i + 1]
		points[i] = m[1] * x + m[3] * y + m[5]
		points[i + 1] = m[2] * x + m[4] * y + m[6]
	end
end

--[=[
	@within FlattenPath
	Flattens `commands` into a list of subpaths in world space.

	`pixelTolerance` is expressed in output pixels (typically 0.25). The
	function divides it by the matrix scale to convert into the user-space
	tolerance used internally before the matrix is applied.
]=]
function FlattenPath.flatten(
	commands: { PathData.Command },
	matrix: Transform.Matrix,
	pixelTolerance: number
): { Subpath }
	local scale = approxMatrixScale(matrix)
	local tolerance = if scale > 0 then pixelTolerance / scale else pixelTolerance
	local subpaths: { Subpath } = {}
	local current: Subpath? = nil
	local cx, cy = 0, 0
	local sx, sy = 0, 0 -- subpath start
	local function openSubpath(x: number, y: number)
		current = { points = { x, y }, closed = false }
		table.insert(subpaths, current :: Subpath)
		cx, cy = x, y
		sx, sy = x, y
	end
	local function ensureSubpath()
		if not current then
			openSubpath(0, 0)
		end
	end
	local function appendLine(x: number, y: number)
		ensureSubpath()
		local c = current :: Subpath
		table.insert(c.points, x)
		table.insert(c.points, y)
		cx, cy = x, y
	end
	for _, cmd in ipairs(commands) do
		local op = cmd[1]
		if op == "M" then
			openSubpath(cmd[2] :: number, cmd[3] :: number)
		elseif op == "L" then
			appendLine(cmd[2] :: number, cmd[3] :: number)
		elseif op == "H" then
			appendLine(cmd[2] :: number, cy)
		elseif op == "V" then
			appendLine(cx, cmd[2] :: number)
		elseif op == "C" then
			ensureSubpath()
			local c = current :: Subpath
			Bezier.flattenCubic(
				c.points,
				cx,
				cy,
				cmd[2] :: number,
				cmd[3] :: number,
				cmd[4] :: number,
				cmd[5] :: number,
				cmd[6] :: number,
				cmd[7] :: number,
				tolerance
			)
			cx, cy = cmd[6] :: number, cmd[7] :: number
		elseif op == "Q" then
			ensureSubpath()
			local c = current :: Subpath
			Bezier.flattenQuadratic(
				c.points,
				cx,
				cy,
				cmd[2] :: number,
				cmd[3] :: number,
				cmd[4] :: number,
				cmd[5] :: number,
				tolerance
			)
			cx, cy = cmd[4] :: number, cmd[5] :: number
		elseif op == "A" then
			ensureSubpath()
			local c = current :: Subpath
			local rx = cmd[2] :: number
			local ry = cmd[3] :: number
			local rotDeg = cmd[4] :: number
			local large = cmd[5] :: number
			local sweep = cmd[6] :: number
			local x2 = cmd[7] :: number
			local y2 = cmd[8] :: number
			local seg = Arc.toCenter(cx, cy, rx, ry, rotDeg, large, sweep, x2, y2)
			if seg then
				local cubics = Arc.toCubics(seg)
				local px, py = cx, cy
				for i = 1, #cubics, 6 do
					Bezier.flattenCubic(
						c.points,
						px,
						py,
						cubics[i],
						cubics[i + 1],
						cubics[i + 2],
						cubics[i + 3],
						cubics[i + 4],
						cubics[i + 5],
						tolerance
					)
					px = cubics[i + 4]
					py = cubics[i + 5]
				end
				cx, cy = x2, y2
			else
				appendLine(x2, y2)
			end
		elseif op == "Z" then
			if current then
				local c = current :: Subpath
				-- Only append a closing edge if the pen isn't already at the
				-- subpath start (avoids redundant zero-length segments).
				local last = #c.points
				if last >= 2 then
					local lastX = c.points[last - 1]
					local lastY = c.points[last]
					if lastX ~= sx or lastY ~= sy then
						table.insert(c.points, sx)
						table.insert(c.points, sy)
					end
				end
				c.closed = true
			end
			cx, cy = sx, sy
			current = nil
		end
	end
	for _, subpath in ipairs(subpaths) do
		applyMatrix(matrix, subpath.points)
	end
	return subpaths
end

return FlattenPath
