--!strict
--[=[
	@class Raster
	@private

	Top-level rasterizer. Takes a parsed SVG `Document` plus a target canvas,
	applies the viewport transform (SVG user space -> canvas pixels), and
	renders every shape's fill and stroke into the canvas.

	Pipeline per shape:
	1. Flatten the shape's path commands into subpaths (`FlattenPath`).
	2. If the shape has a fill paint: scan-convert the subpaths directly.
	3. If the shape has a stroke: expand each subpath via `Stroke.expand`
	   into polygon(s), then scan-convert those.
	4. Clip by any `clip-path` mask assembled on the first touch.

	Coverage is multiplied with the paint's alpha when blending.
]=]

local Canvas = require("./Canvas")
local FlattenPath = require("../Flatten/Path")
local Paint = require("./Paint")
local Scanline = require("./Scanline")
local Stroke = require("../Flatten/Stroke")
local Style = require("../Parser/Style")
local Svg = require("../Parser/Svg")
local Transform = require("../Parser/Transform")

local Raster = {}

export type RenderOptions = {
	fit: ("contain" | "cover" | "fill" | "none")?,
	backgroundColor: { number }?,
}

local function computeViewportMatrix(
	viewport: Svg.Viewport,
	canvasWidth: number,
	canvasHeight: number,
	fit: "contain" | "cover" | "fill" | "none"
): Transform.Matrix
	local vw = viewport.viewWidth
	local vh = viewport.viewHeight
	if vw <= 0 or vh <= 0 then
		return Transform.identity()
	end
	if fit == "fill" then
		local sx = canvasWidth / vw
		local sy = canvasHeight / vh
		return {
			sx,
			0,
			0,
			sy,
			-viewport.viewMinX * sx,
			-viewport.viewMinY * sy,
		}
	end
	if fit == "none" then
		return {
			1,
			0,
			0,
			1,
			-viewport.viewMinX,
			-viewport.viewMinY,
		}
	end
	local sx = canvasWidth / vw
	local sy = canvasHeight / vh
	local s = if fit == "cover" then math.max(sx, sy) else math.min(sx, sy)
	local offX = (canvasWidth - vw * s) / 2 - viewport.viewMinX * s
	local offY = (canvasHeight - vh * s) / 2 - viewport.viewMinY * s
	return { s, 0, 0, s, offX, offY }
end

local function boundsOf(subpaths: { FlattenPath.Subpath }): Paint.BoundingBox
	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	for _, subpath in ipairs(subpaths) do
		local pts = subpath.points
		for i = 1, #pts, 2 do
			local x = pts[i]
			local y = pts[i + 1]
			if x < minX then
				minX = x
			end
			if y < minY then
				minY = y
			end
			if x > maxX then
				maxX = x
			end
			if y > maxY then
				maxY = y
			end
		end
	end
	if minX > maxX then
		return { minX = 0, minY = 0, maxX = 0, maxY = 0 }
	end
	return { minX = minX, minY = minY, maxX = maxX, maxY = maxY }
end

local function fillSubpaths(
	canvas: Canvas.Canvas,
	subpaths: { FlattenPath.Subpath },
	sampler: Paint.Sampler,
	fillRule: "nonzero" | "evenodd",
	mask: { number }?
)
	Scanline.render(subpaths, fillRule, canvas.width, canvas.height, function(span)
		local y = span.y
		local coverage = span.coverage
		for x = span.x0, span.x1 - 1 do
			local pixelCoverage = coverage
			if mask then
				pixelCoverage *= mask[y * canvas.width + x + 1] or 0
			end
			if pixelCoverage > 0 then
				local r, g, b, a = sampler(x + 0.5, y + 0.5)
				Canvas.blendPixel(canvas, x, y, r, g, b, a * pixelCoverage)
			end
		end
	end)
end

-- Builds a binary clip mask as a flat array of 0/1 floats.
local function buildClipMask(
	canvas: Canvas.Canvas,
	clipPath: Svg.ClipPath,
	clipShape: Svg.Shape,
	viewportMatrix: Transform.Matrix,
	pixelTolerance: number
): { number }
	local mask: { number } = table.create(canvas.width * canvas.height, 0)
	for _, shape in ipairs(clipPath.shapes) do
		local combinedMatrix = Transform.multiply(viewportMatrix, shape.matrix)
		local subpaths = FlattenPath.flatten(shape.commands, combinedMatrix, pixelTolerance)
		Scanline.render(subpaths, "nonzero", canvas.width, canvas.height, function(span)
			local base = span.y * canvas.width
			for x = span.x0, span.x1 - 1 do
				mask[base + x + 1] = math.max(mask[base + x + 1] or 0, span.coverage)
			end
		end)
	end
	local _ = clipShape
	return mask
end

local function renderShape(
	canvas: Canvas.Canvas,
	shape: Svg.Shape,
	document: Svg.Document,
	viewportMatrix: Transform.Matrix,
	pixelTolerance: number,
	clipCache: { [string]: { number } }
)
	local style = shape.style
	if not style.display or not style.visibility then
		return
	end
	local shapeMatrix = Transform.multiply(viewportMatrix, shape.matrix)
	local subpaths = FlattenPath.flatten(shape.commands, shapeMatrix, pixelTolerance)
	if #subpaths == 0 then
		return
	end
	local bbox = boundsOf(subpaths)
	local opacity = style.opacity
	local mask: { number }? = nil
	if style.clipPath then
		mask = clipCache[style.clipPath]
		if not mask then
			local clip = document.clipPaths[style.clipPath]
			if clip then
				local fresh = buildClipMask(canvas, clip, shape, viewportMatrix, pixelTolerance)
				clipCache[style.clipPath] = fresh
				mask = fresh
			end
		end
	end
	-- Fill.
	local fillSampler =
		Paint.build(style.fill, document.gradients, bbox, shapeMatrix, opacity * style.fillOpacity)
	if fillSampler then
		fillSubpaths(canvas, subpaths, fillSampler, style.fillRule, mask)
	end
	-- Stroke.
	if style.stroke and style.strokeWidth > 0 then
		local strokePolys: { { number } } = {}
		for _, subpath in ipairs(subpaths) do
			local polys = Stroke.expand(subpath.points, subpath.closed, style)
			for _, poly in ipairs(polys) do
				table.insert(strokePolys, poly)
			end
		end
		if #strokePolys > 0 then
			-- Convert each polygon to a closed subpath so Scanline sees it
			-- as a filled region.
			local strokeSubpaths: { FlattenPath.Subpath } = {}
			for _, poly in ipairs(strokePolys) do
				-- Close the polygon by appending the first vertex if needed.
				local n = #poly
				local closed: FlattenPath.Subpath = { points = poly, closed = true }
				if n >= 4 and (poly[1] ~= poly[n - 1] or poly[2] ~= poly[n]) then
					table.insert(poly, poly[1])
					table.insert(poly, poly[2])
				end
				table.insert(strokeSubpaths, closed)
			end
			local strokeBbox = boundsOf(strokeSubpaths)
			local strokeSampler = Paint.build(
				style.stroke,
				document.gradients,
				strokeBbox,
				shapeMatrix,
				opacity * style.strokeOpacity
			)
			if strokeSampler then
				fillSubpaths(canvas, strokeSubpaths, strokeSampler, "nonzero", mask)
			end
		end
	end
end

--[=[
	@within Raster
	Renders a parsed SVG document into `canvas`.
]=]
function Raster.render(canvas: Canvas.Canvas, document: Svg.Document, options: RenderOptions?)
	local opts: RenderOptions = options or {}
	local fit: "contain" | "cover" | "fill" | "none" = opts.fit or "contain"
	local bg = opts.backgroundColor
	if bg then
		Canvas.clear(canvas, bg[1], bg[2], bg[3], bg[4])
	end
	local viewportMatrix =
		computeViewportMatrix(document.viewport, canvas.width, canvas.height, fit)
	local pixelTolerance = 0.25
	local clipCache: { [string]: { number } } = {}
	for _, shape in ipairs(document.shapes) do
		renderShape(canvas, shape, document, viewportMatrix, pixelTolerance, clipCache)
	end
end

-- Re-export types used by consumers of this module.
export type Canvas = Canvas.Canvas

-- Suppress "Style imported but unused" lint — Style.Paint is referenced via
-- the `shape.style.fill` / `shape.style.stroke` flow through Paint.build.
local _ = Style

return Raster
