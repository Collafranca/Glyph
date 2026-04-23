--!strict
--[=[
	@class Scanline
	@private

	Polygon scan-conversion with fill-rule support and 4x vertical
	supersampled anti-aliasing.

	The algorithm:

	1. Collect every polygon edge that crosses the target scan row.
	2. For each of 4 sub-rows at y + (k + 0.5) / 4 for k in 0..3, compute the
	   x-crossing of each edge and tally in/out state per pixel column.
	3. Emit runs of (startX, endX, coverage) where coverage is the fractional
	   sum of sub-row hits divided by 4.

	The supersampling lives inside the scan converter rather than the canvas
	so we don't pay 4x memory for AA. It's 4x the arithmetic, but arithmetic
	is cheap compared to buffer writes.

	Fill rules:
	- `"nonzero"`: sums signed crossings (up-to-down edges = +1, down-to-up
	  = -1); fills pixels where the sum is non-zero.
	- `"evenodd"`: XOR-toggles in/out on each crossing.
]=]

local Scanline = {}

local SUBPIXEL_SAMPLES = 4

export type Subpath = {
	points: { number },
	closed: boolean,
}

export type Span = {
	y: number,
	x0: number,
	x1: number, -- exclusive
	coverage: number, -- [0, 1]
}

type Edge = {
	yMin: number,
	yMax: number,
	x0: number,
	y0: number,
	dxDy: number, -- dx/dy for incremental x computation
	sign: number, -- +1 if edge goes downwards (y2 > y1), -1 otherwise
}

local function buildEdges(subpaths: { Subpath }): { Edge }
	local edges: { Edge } = {}
	for _, subpath in ipairs(subpaths) do
		local pts = subpath.points
		local n = #pts
		if n < 4 then
			continue
		end
		-- Walk edges. For closed subpaths the last->first edge is included
		-- during flattening (FlattenPath appends the closing point), so we
		-- don't need to re-emit it here.
		for i = 1, n - 2, 2 do
			local x1 = pts[i]
			local y1 = pts[i + 1]
			local x2 = pts[i + 2]
			local y2 = pts[i + 3]
			if y1 == y2 then
				continue
			end
			local sign: number, yMin, yMax, x0, y0, x1e, y1e
			if y1 < y2 then
				sign = 1
				yMin, yMax = y1, y2
				x0, y0 = x1, y1
				x1e, y1e = x2, y2
			else
				sign = -1
				yMin, yMax = y2, y1
				x0, y0 = x2, y2
				x1e, y1e = x1, y1
			end
			local _ = y1e
			local dxDy = (x1e - x0) / (y1e - y0)
			table.insert(edges, {
				yMin = yMin,
				yMax = yMax,
				x0 = x0,
				y0 = y0,
				dxDy = dxDy,
				sign = sign,
			})
		end
	end
	return edges
end

local function boundsOf(edges: { Edge }, canvasHeight: number): (number, number)
	if #edges == 0 then
		return 0, -1
	end
	local minY = math.huge
	local maxY = -math.huge
	for _, edge in ipairs(edges) do
		if edge.yMin < minY then
			minY = edge.yMin
		end
		if edge.yMax > maxY then
			maxY = edge.yMax
		end
	end
	return math.max(0, math.floor(minY)), math.min(canvasHeight - 1, math.ceil(maxY))
end

-- Sort an array of numbers in ascending order in-place. Used per-sub-row, so
-- small sizes (usually <20) — insertion sort wins over table.sort setup cost.
local function insertionSort(array: { number }, length: number)
	for i = 2, length do
		local v = array[i]
		local j = i - 1
		while j >= 1 and array[j] > v do
			array[j + 1] = array[j]
			j -= 1
		end
		array[j + 1] = v
	end
end

-- Returns an array of x-crossing values at scanline y.
-- For nonzero, the returned array is interleaved: (x, sign, x, sign, ...).
local function collectCrossings(
	edges: { Edge },
	y: number,
	output: { number },
	withSigns: boolean
): number
	local count = 0
	for _, edge in ipairs(edges) do
		if y >= edge.yMin and y < edge.yMax then
			local x = edge.x0 + (y - edge.y0) * edge.dxDy
			if withSigns then
				count += 1
				output[count] = x
				count += 1
				output[count] = edge.sign
			else
				count += 1
				output[count] = x
			end
		end
	end
	return count
end

-- Sort signed crossings by x while keeping (x, sign) pairs together.
local function sortSignedCrossings(pairs: { number }, length: number)
	-- Length is always even. Pair sort: extract keys, sort, rebuild.
	-- For small N the cost is dominated by the ripple anyway.
	for i = 3, length, 2 do
		local x = pairs[i]
		local sign = pairs[i + 1]
		local j = i - 2
		while j >= 1 and pairs[j] > x do
			pairs[j + 2] = pairs[j]
			pairs[j + 3] = pairs[j + 1]
			j -= 2
		end
		pairs[j + 2] = x
		pairs[j + 3] = sign
	end
end

--[=[
	@within Scanline
	Scan-converts the polygon formed by `subpaths` and calls `emit(span)` for
	each resulting span.

	`fillRule` is `"nonzero"` or `"evenodd"`. The callback is invoked in
	ascending row order; within a row, spans are emitted left-to-right and do
	not overlap. Coverage is in [0, 1] after 4x sub-pixel averaging.

	Spans with coverage <= 0 are suppressed.
]=]
function Scanline.render(
	subpaths: { Subpath },
	fillRule: "nonzero" | "evenodd",
	canvasWidth: number,
	canvasHeight: number,
	emit: (Span) -> ()
)
	local edges = buildEdges(subpaths)
	if #edges == 0 then
		return
	end
	local y0, y1 = boundsOf(edges, canvasHeight)
	local xCrossings: { number } = {}
	-- Coverage per pixel column; stores 4-sample hit counts, reset per row.
	local coverage: { number } = {}
	for x = 1, canvasWidth do
		coverage[x] = 0
	end
	local touchedMin = math.huge
	local touchedMax = -math.huge
	for y = y0, y1 do
		touchedMin = math.huge
		touchedMax = -math.huge
		for sub = 0, SUBPIXEL_SAMPLES - 1 do
			local ySample = y + (sub + 0.5) / SUBPIXEL_SAMPLES
			if fillRule == "nonzero" then
				local count = collectCrossings(edges, ySample, xCrossings, true)
				sortSignedCrossings(xCrossings, count)
				local winding = 0
				local inStart: number? = nil
				for i = 1, count, 2 do
					local x = xCrossings[i]
					local sign = xCrossings[i + 1]
					local wasInside = winding ~= 0
					winding += sign
					local nowInside = winding ~= 0
					if nowInside and not wasInside then
						inStart = x
					elseif not nowInside and wasInside and inStart then
						local spanStart = math.max(0, math.floor(inStart))
						local spanEnd = math.min(canvasWidth, math.ceil(x))
						if spanEnd > spanStart then
							-- Apply per-pixel partial coverage at edges.
							for px = spanStart, spanEnd - 1 do
								local pxStart = math.max(px, inStart)
								local pxEnd = math.min(px + 1, x)
								coverage[px + 1] += pxEnd - pxStart
							end
							if spanStart < touchedMin then
								touchedMin = spanStart
							end
							if spanEnd > touchedMax then
								touchedMax = spanEnd
							end
						end
						inStart = nil
					end
				end
			else
				local count = collectCrossings(edges, ySample, xCrossings, false)
				insertionSort(xCrossings, count)
				-- Pair adjacent crossings into fill spans.
				for i = 1, count - 1, 2 do
					local xStart = xCrossings[i]
					local xEnd = xCrossings[i + 1]
					if xEnd > xStart then
						local spanStart = math.max(0, math.floor(xStart))
						local spanEnd = math.min(canvasWidth, math.ceil(xEnd))
						for px = spanStart, spanEnd - 1 do
							local pxStart = math.max(px, xStart)
							local pxEnd = math.min(px + 1, xEnd)
							coverage[px + 1] += pxEnd - pxStart
						end
						if spanStart < touchedMin then
							touchedMin = spanStart
						end
						if spanEnd > touchedMax then
							touchedMax = spanEnd
						end
					end
				end
			end
		end
		if touchedMin <= touchedMax then
			-- Coverage[x] is in [0, SUBPIXEL_SAMPLES]; normalise to [0, 1].
			local runStart: number? = nil
			local runCoverage = 0
			for px = touchedMin, touchedMax - 1 do
				local c = coverage[px + 1] / SUBPIXEL_SAMPLES
				coverage[px + 1] = 0
				if c > 0 then
					local extend = runStart ~= nil and math.abs(c - runCoverage) < 1e-9
					if not extend then
						if runStart then
							emit({
								y = y,
								x0 = runStart,
								x1 = px,
								coverage = runCoverage,
							})
						end
						runStart = px
						runCoverage = c
					end
				else
					if runStart then
						emit({
							y = y,
							x0 = runStart,
							x1 = px,
							coverage = runCoverage,
						})
						runStart = nil
					end
				end
			end
			if runStart then
				emit({
					y = y,
					x0 = runStart,
					x1 = touchedMax,
					coverage = runCoverage,
				})
			end
		end
	end
end

return Scanline
