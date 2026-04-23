--!strict
--[=[
	@class Svg
	@private

	Top-level SVG parser. Consumes a source string and produces an IR document
	suitable for flattening + rasterization.

	Pipeline:
	1. `Xml.parse` turns the source into a node tree.
	2. This module walks the tree, enforces the supported-element allowlist,
	   and builds a flat list of shape primitives each carrying its resolved
	   style, clip-path id, and world-space matrix.
	3. Gradients and clipPaths referenced by `url(#id)` are collected into
	   separate lookup tables so the renderer resolves them lazily.

	Unsupported elements (e.g. `<text>`, `<filter>`) are silently skipped.
	Malformed SVG raises a descriptive error.
]=]

local Color = require("./Color")
local Length = require("./Length")
local PathData = require("./PathData")
local Style = require("./Style")
local Transform = require("./Transform")
local Xml = require("./Xml")

local Svg = {}

export type Viewport = {
	width: number,
	height: number,
	viewMinX: number,
	viewMinY: number,
	viewWidth: number,
	viewHeight: number,
	preserveAspectRatio: string,
}

export type Path = {
	kind: "path",
	commands: { PathData.Command },
	style: Style.Style,
	matrix: Transform.Matrix,
}

export type Shape = Path

export type GradientStop = {
	offset: number,
	color: Color.Rgba,
	opacity: number,
}

export type LinearGradient = {
	kind: "linear",
	x1: Length.Length,
	y1: Length.Length,
	x2: Length.Length,
	y2: Length.Length,
	units: "userSpaceOnUse" | "objectBoundingBox",
	spreadMethod: "pad" | "reflect" | "repeat",
	transform: Transform.Matrix,
	stops: { GradientStop },
	href: string?,
}

export type RadialGradient = {
	kind: "radial",
	cx: Length.Length,
	cy: Length.Length,
	r: Length.Length,
	fx: Length.Length?,
	fy: Length.Length?,
	units: "userSpaceOnUse" | "objectBoundingBox",
	spreadMethod: "pad" | "reflect" | "repeat",
	transform: Transform.Matrix,
	stops: { GradientStop },
	href: string?,
}

export type Gradient = LinearGradient | RadialGradient

export type ClipPath = {
	units: "userSpaceOnUse" | "objectBoundingBox",
	shapes: { Shape },
}

export type Document = {
	viewport: Viewport,
	shapes: { Shape },
	gradients: { [string]: Gradient },
	clipPaths: { [string]: ClipPath },
}

local VIEWBOX_PATTERN =
	"^%s*([%-%d.eE+]+)%s*,?%s*([%-%d.eE+]+)%s*,?%s*([%-%d.eE+]+)%s*,?%s*([%-%d.eE+]+)%s*$"

local function parseViewBox(raw: string): (number, number, number, number)
	local x, y, w, h = string.match(raw, VIEWBOX_PATTERN)
	local nx, ny, nw, nh = tonumber(x), tonumber(y), tonumber(w), tonumber(h)
	if not (nx and ny and nw and nh) then
		error("invalid viewBox '" .. raw .. "'", 0)
	end
	if nw < 0 or nh < 0 then
		error("viewBox width/height must be non-negative", 0)
	end
	return nx, ny, nw, nh
end

local function parseViewport(root: Xml.XmlElement): Viewport
	local widthAttr = root.attributes.width
	local heightAttr = root.attributes.height
	local width: number = if widthAttr then Length.resolve(Length.parse(widthAttr), 300) else 300
	local height: number = if heightAttr then Length.resolve(Length.parse(heightAttr), 150) else 150
	local viewBox = root.attributes.viewBox
	local vx, vy, vw, vh
	if viewBox then
		vx, vy, vw, vh = parseViewBox(viewBox)
	else
		vx, vy, vw, vh = 0, 0, width, height
	end
	return {
		width = width,
		height = height,
		viewMinX = vx,
		viewMinY = vy,
		viewWidth = vw,
		viewHeight = vh,
		preserveAspectRatio = root.attributes.preserveAspectRatio or "xMidYMid meet",
	}
end

local function resolveHref(attributes: { [string]: string }): string?
	local href = attributes.href or attributes["xlink:href"]
	if not href then
		return nil
	end
	if string.sub(href, 1, 1) == "#" then
		return string.sub(href, 2)
	end
	return href
end

local function parseOffset(raw: string?): number
	if not raw then
		return 0
	end
	local trimmed = string.match(raw, "^%s*(.-)%s*$") :: string
	if string.sub(trimmed, -1) == "%" then
		local n = tonumber(string.sub(trimmed, 1, -2))
		if not n then
			error("invalid offset '" .. raw .. "'", 0)
		end
		return math.clamp(n / 100, 0, 1)
	end
	local n = tonumber(trimmed)
	if not n then
		error("invalid offset '" .. raw .. "'", 0)
	end
	return math.clamp(n, 0, 1)
end

local function parseStops(element: Xml.XmlElement, parentStyle: Style.Style): { GradientStop }
	local stops: { GradientStop } = {}
	for _, child in ipairs(element.children) do
		if child.kind == "element" and child.name == "stop" then
			local stopElement = child :: Xml.XmlElement
			local inlineStyle = Style.flatten(stopElement.attributes)
			local stopColorAttr = inlineStyle["stop-color"] or stopElement.attributes["stop-color"]
			local colorValue: Color.Rgba = { 0, 0, 0, 1 }
			if stopColorAttr then
				local parsed = Color.parse(stopColorAttr)
				if type(parsed) == "table" then
					colorValue = parsed :: Color.Rgba
				elseif parsed == "currentColor" then
					colorValue = parentStyle.color
				end
			end
			local opacity = 1
			local opacityRaw = inlineStyle["stop-opacity"] or stopElement.attributes["stop-opacity"]
			if opacityRaw then
				opacity = math.clamp(tonumber(opacityRaw) or 1, 0, 1)
			end
			table.insert(stops, {
				offset = parseOffset(stopElement.attributes.offset),
				color = colorValue,
				opacity = opacity,
			})
		end
	end
	-- Enforce monotonically non-decreasing offsets per SVG 1.1.
	for i = 2, #stops do
		if stops[i].offset < stops[i - 1].offset then
			stops[i].offset = stops[i - 1].offset
		end
	end
	return stops
end

local function parseGradientUnits(raw: string?): "userSpaceOnUse" | "objectBoundingBox"
	if raw == "userSpaceOnUse" then
		return "userSpaceOnUse"
	end
	return "objectBoundingBox"
end

local function parseSpread(raw: string?): "pad" | "reflect" | "repeat"
	if raw == "reflect" then
		return "reflect"
	elseif raw == "repeat" then
		return "repeat"
	end
	return "pad"
end

local function parseLinearGradient(
	element: Xml.XmlElement,
	parentStyle: Style.Style
): LinearGradient
	local attrs = element.attributes
	return {
		kind = "linear",
		x1 = Length.parse(attrs.x1 or "0%"),
		y1 = Length.parse(attrs.y1 or "0%"),
		x2 = Length.parse(attrs.x2 or "100%"),
		y2 = Length.parse(attrs.y2 or "0%"),
		units = parseGradientUnits(attrs.gradientUnits),
		spreadMethod = parseSpread(attrs.spreadMethod),
		transform = if attrs.gradientTransform
			then Transform.parse(attrs.gradientTransform)
			else Transform.identity(),
		stops = parseStops(element, parentStyle),
		href = resolveHref(attrs),
	}
end

local function parseRadialGradient(
	element: Xml.XmlElement,
	parentStyle: Style.Style
): RadialGradient
	local attrs = element.attributes
	local fx = if attrs.fx then Length.parse(attrs.fx) else nil
	local fy = if attrs.fy then Length.parse(attrs.fy) else nil
	return {
		kind = "radial",
		cx = Length.parse(attrs.cx or "50%"),
		cy = Length.parse(attrs.cy or "50%"),
		r = Length.parse(attrs.r or "50%"),
		fx = fx,
		fy = fy,
		units = parseGradientUnits(attrs.gradientUnits),
		spreadMethod = parseSpread(attrs.spreadMethod),
		transform = if attrs.gradientTransform
			then Transform.parse(attrs.gradientTransform)
			else Transform.identity(),
		stops = parseStops(element, parentStyle),
		href = resolveHref(attrs),
	}
end

-- Primitive shape -> path commands. Rect / circle / ellipse / line / polyline
-- / polygon all lower to path data at parse time so the renderer only deals
-- with a single shape type.
local function toNumber(raw: string?, fallback: number): number
	if not raw then
		return fallback
	end
	return Length.resolve(Length.parse(raw), 0)
end

local function rectToPath(attrs: { [string]: string }): { PathData.Command }
	local x = toNumber(attrs.x, 0)
	local y = toNumber(attrs.y, 0)
	local w = toNumber(attrs.width, 0)
	local h = toNumber(attrs.height, 0)
	if w <= 0 or h <= 0 then
		return {}
	end
	local rxRaw = attrs.rx
	local ryRaw = attrs.ry
	local rx = rxRaw and toNumber(rxRaw, 0) or nil
	local ry = ryRaw and toNumber(ryRaw, 0) or nil
	if rx and not ry then
		ry = rx
	elseif ry and not rx then
		rx = ry
	end
	if not rx then
		return {
			{ "M", x, y },
			{ "H", x + w },
			{ "V", y + h },
			{ "H", x },
			{ "Z" },
		}
	end
	local sx = math.min(rx :: number, w / 2)
	local sy = math.min(ry :: number, h / 2)
	return {
		{ "M", x + sx, y },
		{ "H", x + w - sx },
		{ "A", sx, sy, 0, 0, 1, x + w, y + sy },
		{ "V", y + h - sy },
		{ "A", sx, sy, 0, 0, 1, x + w - sx, y + h },
		{ "H", x + sx },
		{ "A", sx, sy, 0, 0, 1, x, y + h - sy },
		{ "V", y + sy },
		{ "A", sx, sy, 0, 0, 1, x + sx, y },
		{ "Z" },
	}
end

local function circleToPath(attrs: { [string]: string }): { PathData.Command }
	local cx = toNumber(attrs.cx, 0)
	local cy = toNumber(attrs.cy, 0)
	local r = toNumber(attrs.r, 0)
	if r <= 0 then
		return {}
	end
	return {
		{ "M", cx - r, cy },
		{ "A", r, r, 0, 1, 0, cx + r, cy },
		{ "A", r, r, 0, 1, 0, cx - r, cy },
		{ "Z" },
	}
end

local function ellipseToPath(attrs: { [string]: string }): { PathData.Command }
	local cx = toNumber(attrs.cx, 0)
	local cy = toNumber(attrs.cy, 0)
	local rx = toNumber(attrs.rx, 0)
	local ry = toNumber(attrs.ry, 0)
	if rx <= 0 or ry <= 0 then
		return {}
	end
	return {
		{ "M", cx - rx, cy },
		{ "A", rx, ry, 0, 1, 0, cx + rx, cy },
		{ "A", rx, ry, 0, 1, 0, cx - rx, cy },
		{ "Z" },
	}
end

local function lineToPath(attrs: { [string]: string }): { PathData.Command }
	local x1 = toNumber(attrs.x1, 0)
	local y1 = toNumber(attrs.y1, 0)
	local x2 = toNumber(attrs.x2, 0)
	local y2 = toNumber(attrs.y2, 0)
	return {
		{ "M", x1, y1 },
		{ "L", x2, y2 },
	}
end

local function parsePointList(raw: string?): { number }
	if not raw then
		return {}
	end
	local pts: { number } = {}
	for token in string.gmatch(raw, "[^%s,]+") do
		local n = tonumber(token)
		if not n then
			error("invalid point coordinate '" .. token .. "'", 0)
		end
		table.insert(pts, n)
	end
	if #pts % 2 ~= 0 then
		error("polyline/polygon requires even number of coordinates", 0)
	end
	return pts
end

local function polylineToPath(attrs: { [string]: string }, close: boolean): { PathData.Command }
	local pts = parsePointList(attrs.points)
	if #pts == 0 then
		return {}
	end
	local cmds: { PathData.Command } = {}
	local moveCmd: PathData.Command = { "M", pts[1], pts[2] }
	table.insert(cmds, moveCmd)
	for i = 3, #pts, 2 do
		local lineCmd: PathData.Command = { "L", pts[i], pts[i + 1] }
		table.insert(cmds, lineCmd)
	end
	if close then
		local closeCmd: PathData.Command = { "Z" }
		table.insert(cmds, closeCmd)
	end
	return cmds
end

-- Tree walker state.
type WalkContext = {
	shapes: { Shape },
	gradients: { [string]: Gradient },
	clipPaths: { [string]: ClipPath },
	defsShapes: { [string]: { Shape } },
	viewportSize: number,
	insideClip: boolean,
	currentClipShapes: { Shape }?,
}

local walkChildren: (
	element: Xml.XmlElement,
	ctx: WalkContext,
	parentStyle: Style.Style,
	parentMatrix: Transform.Matrix
) -> ()

local function elementMatrix(element: Xml.XmlElement, parent: Transform.Matrix): Transform.Matrix
	local raw = element.attributes.transform
	if not raw then
		return parent
	end
	return Transform.multiply(parent, Transform.parse(raw))
end

local function elementStyle(
	element: Xml.XmlElement,
	parent: Style.Style,
	viewportSize: number
): Style.Style
	return Style.inherit(parent, Style.flatten(element.attributes), viewportSize)
end

local function emitShape(ctx: WalkContext, shape: Shape)
	if ctx.insideClip and ctx.currentClipShapes then
		table.insert(ctx.currentClipShapes :: { Shape }, shape)
	else
		table.insert(ctx.shapes, shape)
	end
end

local function handlePath(
	element: Xml.XmlElement,
	ctx: WalkContext,
	style: Style.Style,
	matrix: Transform.Matrix
)
	local d = element.attributes.d
	if not d then
		return
	end
	local commands = PathData.parse(d)
	if #commands == 0 then
		return
	end
	emitShape(ctx, {
		kind = "path",
		commands = commands,
		style = style,
		matrix = matrix,
	})
end

local function handleLoweredShape(
	element: Xml.XmlElement,
	ctx: WalkContext,
	style: Style.Style,
	matrix: Transform.Matrix,
	lowerer: (attrs: { [string]: string }) -> { PathData.Command }
)
	local commands = lowerer(element.attributes)
	if #commands == 0 then
		return
	end
	emitShape(ctx, {
		kind = "path",
		commands = commands,
		style = style,
		matrix = matrix,
	})
end

local function handleUse(
	element: Xml.XmlElement,
	ctx: WalkContext,
	style: Style.Style,
	matrix: Transform.Matrix
)
	local ref = resolveHref(element.attributes)
	if not ref then
		return
	end
	local x = toNumber(element.attributes.x, 0)
	local y = toNumber(element.attributes.y, 0)
	local useMatrix = Transform.multiply(matrix, { 1, 0, 0, 1, x, y })
	local referenced = ctx.defsShapes[ref]
	if not referenced then
		return
	end
	for _, shape in ipairs(referenced) do
		local cloned: Shape = {
			kind = shape.kind,
			commands = shape.commands,
			style = style,
			matrix = Transform.multiply(useMatrix, shape.matrix),
		}
		emitShape(ctx, cloned)
	end
end

local function handleClipPath(
	element: Xml.XmlElement,
	ctx: WalkContext,
	style: Style.Style,
	matrix: Transform.Matrix
)
	local id = element.attributes.id
	if not id then
		return
	end
	local units = parseGradientUnits(element.attributes.clipPathUnits)
	local collector: { Shape } = {}
	local previous = ctx.currentClipShapes
	ctx.currentClipShapes = collector
	ctx.insideClip = true
	walkChildren(element, ctx, style, matrix)
	ctx.currentClipShapes = previous
	ctx.insideClip = previous ~= nil
	ctx.clipPaths[id] = { units = units, shapes = collector } :: ClipPath
end

-- defs children produce either gradients, clipPaths, or a set of shapes that
-- can later be referenced by <use>.
local function handleDefs(
	element: Xml.XmlElement,
	ctx: WalkContext,
	parentStyle: Style.Style,
	parentMatrix: Transform.Matrix
)
	for _, child in ipairs(element.children) do
		if child.kind ~= "element" then
			continue
		end
		local childElement = child :: Xml.XmlElement
		local name = childElement.name
		local childStyle = elementStyle(childElement, parentStyle, ctx.viewportSize)
		local childMatrix = elementMatrix(childElement, parentMatrix)
		if name == "linearGradient" then
			local id = childElement.attributes.id
			if id then
				ctx.gradients[id] = parseLinearGradient(childElement, childStyle)
			end
		elseif name == "radialGradient" then
			local id = childElement.attributes.id
			if id then
				ctx.gradients[id] = parseRadialGradient(childElement, childStyle)
			end
		elseif name == "clipPath" then
			handleClipPath(childElement, ctx, childStyle, childMatrix)
		else
			local id = childElement.attributes.id
			if not id then
				continue
			end
			-- Buffer shapes produced by this element into a named bucket
			-- instead of the root list so <use href="#id"/> can replay them.
			local previous = ctx.shapes
			local buffer: { Shape } = {}
			ctx.shapes = buffer
			walkChildren(childElement, ctx, childStyle, childMatrix)
			if name == "path" then
				handlePath(childElement, ctx, childStyle, childMatrix)
			elseif name == "rect" then
				handleLoweredShape(childElement, ctx, childStyle, childMatrix, rectToPath)
			elseif name == "circle" then
				handleLoweredShape(childElement, ctx, childStyle, childMatrix, circleToPath)
			elseif name == "ellipse" then
				handleLoweredShape(childElement, ctx, childStyle, childMatrix, ellipseToPath)
			elseif name == "line" then
				handleLoweredShape(childElement, ctx, childStyle, childMatrix, lineToPath)
			elseif name == "polyline" then
				handleLoweredShape(childElement, ctx, childStyle, childMatrix, function(attrs)
					return polylineToPath(attrs, false)
				end)
			elseif name == "polygon" then
				handleLoweredShape(childElement, ctx, childStyle, childMatrix, function(attrs)
					return polylineToPath(attrs, true)
				end)
			end
			ctx.defsShapes[id] = ctx.shapes
			ctx.shapes = previous
		end
	end
end

function walkChildren(
	element: Xml.XmlElement,
	ctx: WalkContext,
	parentStyle: Style.Style,
	parentMatrix: Transform.Matrix
)
	for _, child in ipairs(element.children) do
		if child.kind ~= "element" then
			continue
		end
		local childElement = child :: Xml.XmlElement
		local name = childElement.name
		local childStyle = elementStyle(childElement, parentStyle, ctx.viewportSize)
		if not childStyle.display then
			continue
		end
		local childMatrix = elementMatrix(childElement, parentMatrix)
		if name == "g" or name == "svg" then
			walkChildren(childElement, ctx, childStyle, childMatrix)
		elseif name == "defs" then
			handleDefs(childElement, ctx, childStyle, childMatrix)
		elseif name == "clipPath" then
			handleClipPath(childElement, ctx, childStyle, childMatrix)
		elseif name == "linearGradient" then
			local id = childElement.attributes.id
			if id then
				ctx.gradients[id] = parseLinearGradient(childElement, childStyle)
			end
		elseif name == "radialGradient" then
			local id = childElement.attributes.id
			if id then
				ctx.gradients[id] = parseRadialGradient(childElement, childStyle)
			end
		elseif name == "path" then
			handlePath(childElement, ctx, childStyle, childMatrix)
		elseif name == "rect" then
			handleLoweredShape(childElement, ctx, childStyle, childMatrix, rectToPath)
		elseif name == "circle" then
			handleLoweredShape(childElement, ctx, childStyle, childMatrix, circleToPath)
		elseif name == "ellipse" then
			handleLoweredShape(childElement, ctx, childStyle, childMatrix, ellipseToPath)
		elseif name == "line" then
			handleLoweredShape(childElement, ctx, childStyle, childMatrix, lineToPath)
		elseif name == "polyline" then
			handleLoweredShape(childElement, ctx, childStyle, childMatrix, function(attrs)
				return polylineToPath(attrs, false)
			end)
		elseif name == "polygon" then
			handleLoweredShape(childElement, ctx, childStyle, childMatrix, function(attrs)
				return polylineToPath(attrs, true)
			end)
		elseif name == "use" then
			handleUse(childElement, ctx, childStyle, childMatrix)
		end
		-- Unknown / unsupported elements (text, filter, mask, ...) are skipped.
	end
end

--[=[
	@within Svg
	Parses an SVG source string into an IR document.
]=]
function Svg.parse(source: string): Document
	local root = Xml.parse(source)
	if root.name ~= "svg" then
		error("root element must be <svg>, got <" .. root.name .. ">", 0)
	end
	local viewport = parseViewport(root)
	local viewportSize = math.sqrt(viewport.viewWidth ^ 2 + viewport.viewHeight ^ 2)
	local rootStyle = Style.inherit(Style.defaults(), Style.flatten(root.attributes), viewportSize)
	local ctx: WalkContext = {
		shapes = {},
		gradients = {},
		clipPaths = {},
		defsShapes = {},
		viewportSize = viewportSize,
		insideClip = false,
		currentClipShapes = nil,
	}
	local rootMatrix = if root.attributes.transform
		then Transform.parse(root.attributes.transform)
		else Transform.identity()
	walkChildren(root, ctx, rootStyle, rootMatrix)
	return {
		viewport = viewport,
		shapes = ctx.shapes,
		gradients = ctx.gradients,
		clipPaths = ctx.clipPaths,
	}
end

return Svg
