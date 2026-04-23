--!strict
--[=[
	@class Style
	@private

	SVG presentation attribute + inline-style handling. Flattens attribute +
	`style=""` into a uniform key/value map, then resolves a few common values
	into typed style fields. Full CSS selectors / external stylesheets are out
	of scope.

	Precedence: inline `style=""` wins over presentation attributes, matching
	the SVG 1.1 §6.12 rule that the `style` attribute has higher specificity.
]=]

local Color = require("./Color")
local Length = require("./Length")

local Style = {}

-- Tracked presentation attributes. Any unknown attributes are ignored here
-- (they remain available on the XML element if callers need them).
local PRESENTATION: { string } = {
	"fill",
	"fill-opacity",
	"fill-rule",
	"stroke",
	"stroke-opacity",
	"stroke-width",
	"stroke-linecap",
	"stroke-linejoin",
	"stroke-miterlimit",
	"stroke-dasharray",
	"stroke-dashoffset",
	"opacity",
	"color",
	"display",
	"visibility",
	"clip-path",
	"clip-rule",
}

local PRESENTATION_SET: { [string]: true } = {}
for _, k in ipairs(PRESENTATION) do
	PRESENTATION_SET[k] = true
end

export type Paint = Color.ColorValue | { kind: "url", id: string }

export type Style = {
	fill: Paint?,
	fillOpacity: number,
	fillRule: "nonzero" | "evenodd",
	stroke: Paint?,
	strokeOpacity: number,
	strokeWidth: number,
	strokeLinecap: "butt" | "round" | "square",
	strokeLinejoin: "miter" | "round" | "bevel",
	strokeMiterlimit: number,
	strokeDasharray: { number }?,
	strokeDashoffset: number,
	opacity: number,
	color: Color.Rgba,
	display: boolean,
	visibility: boolean,
	clipPath: string?,
	clipRule: "nonzero" | "evenodd",
}

--[=[
	@within Style
	Default root style: SVG 1.1 initial values, with `color = black`.
]=]
function Style.defaults(): Style
	return {
		fill = { 0, 0, 0, 1 } :: Color.Rgba,
		fillOpacity = 1,
		fillRule = "nonzero",
		stroke = nil,
		strokeOpacity = 1,
		strokeWidth = 1,
		strokeLinecap = "butt",
		strokeLinejoin = "miter",
		strokeMiterlimit = 4,
		strokeDasharray = nil,
		strokeDashoffset = 0,
		opacity = 1,
		color = { 0, 0, 0, 1 } :: Color.Rgba,
		display = true,
		visibility = true,
		clipPath = nil,
		clipRule = "nonzero",
	}
end

local function parseStyleAttribute(value: string): { [string]: string }
	local out: { [string]: string } = {}
	for declaration in string.gmatch(value, "[^;]+") do
		local colon = string.find(declaration, ":", 1, true)
		if colon then
			local key = string.match(string.sub(declaration, 1, colon - 1), "^%s*(.-)%s*$")
			local val = string.match(string.sub(declaration, colon + 1), "^%s*(.-)%s*$")
			if key and val and key ~= "" then
				out[key] = val
			end
		end
	end
	return out
end

--[=[
	@within Style
	Merges presentation attributes and inline style into a flat key/value map.
	Inline `style=""` wins on conflict.
]=]
function Style.flatten(attributes: { [string]: string }): { [string]: string }
	local flat: { [string]: string } = {}
	for k, v in pairs(attributes) do
		if PRESENTATION_SET[k] then
			flat[k] = v
		end
	end
	local styleAttr = attributes.style
	if styleAttr then
		for k, v in pairs(parseStyleAttribute(styleAttr)) do
			flat[k] = v
		end
	end
	return flat
end

local function parsePaint(value: string, currentColor: Color.Rgba): Paint?
	local trimmed = string.match(value, "^%s*(.-)%s*$") :: string
	if trimmed == "none" then
		return nil
	end
	-- url(#id) [fallback]
	local id = string.match(trimmed, "^url%(%s*#([^%s%)]+)%s*%)")
	if id then
		return { kind = "url", id = id }
	end
	local color = Color.parse(trimmed)
	if color == nil then
		return nil
	end
	if color == "currentColor" then
		return currentColor
	end
	return color :: Color.Rgba
end

local function parseNumber(value: string): number
	local n = tonumber(string.match(value, "^%s*(.-)%s*$") :: string)
	if not n then
		error("expected number, got '" .. value .. "'", 0)
	end
	return n
end

local function parseOpacity(value: string): number
	-- Opacity accepts 0..1 or a percent.
	local trimmed = string.match(value, "^%s*(.-)%s*$") :: string
	if string.sub(trimmed, -1) == "%" then
		local n = tonumber(string.sub(trimmed, 1, -2))
		if not n then
			error("invalid opacity '" .. value .. "'", 0)
		end
		return math.clamp(n / 100, 0, 1)
	end
	return math.clamp(parseNumber(value), 0, 1)
end

local function parseLengthToUserUnits(value: string, reference: number): number
	local parsed = Length.parse(value)
	return Length.resolve(parsed, reference)
end

local function parseDashArray(value: string): { number }?
	local trimmed = string.match(value, "^%s*(.-)%s*$") :: string
	if trimmed == "none" or trimmed == "" then
		return nil
	end
	local dashes: { number } = {}
	for token in string.gmatch(trimmed, "[^%s,]+") do
		local n = tonumber(token)
		if not n or n < 0 then
			error("invalid dash-array entry '" .. token .. "'", 0)
		end
		table.insert(dashes, n)
	end
	if #dashes == 0 then
		return nil
	end
	-- If odd count, double per SVG spec.
	if #dashes % 2 == 1 then
		local doubled = {}
		for i = 1, #dashes * 2 do
			doubled[i] = dashes[((i - 1) % #dashes) + 1]
		end
		return doubled
	end
	return dashes
end

--[=[
	@within Style
	Applies presentation-attribute + inline-style key/value pairs to a parent
	style, returning a new style. Unknown properties are ignored. The caller
	supplies `viewportSize` for percentage resolution (stroke-width and
	friends accept percentages of the viewport diagonal).
]=]
function Style.inherit(parent: Style, properties: { [string]: string }, viewportSize: number): Style
	local out: Style = table.clone(parent)
	-- First pass: `color` must be resolved before any `currentColor` paints.
	local colorProp = properties.color
	if colorProp then
		local parsed = Color.parse(colorProp)
		if type(parsed) == "table" then
			out.color = parsed :: Color.Rgba
		end
		-- If parsed is "currentColor", that means `color: currentColor;` which is
		-- a no-op (retains parent).
	end
	for key, value in pairs(properties) do
		if key == "color" then
			continue
		elseif key == "fill" then
			out.fill = parsePaint(value, out.color)
		elseif key == "stroke" then
			out.stroke = parsePaint(value, out.color)
		elseif key == "fill-opacity" then
			out.fillOpacity = parseOpacity(value)
		elseif key == "stroke-opacity" then
			out.strokeOpacity = parseOpacity(value)
		elseif key == "opacity" then
			out.opacity = parseOpacity(value)
		elseif key == "fill-rule" then
			local v = string.lower(value)
			if v == "evenodd" then
				out.fillRule = "evenodd"
			else
				out.fillRule = "nonzero"
			end
		elseif key == "clip-rule" then
			local v = string.lower(value)
			if v == "evenodd" then
				out.clipRule = "evenodd"
			else
				out.clipRule = "nonzero"
			end
		elseif key == "stroke-width" then
			out.strokeWidth = parseLengthToUserUnits(value, viewportSize)
		elseif key == "stroke-linecap" then
			local v = string.lower(value)
			if v == "round" or v == "square" then
				out.strokeLinecap = v :: any
			else
				out.strokeLinecap = "butt"
			end
		elseif key == "stroke-linejoin" then
			local v = string.lower(value)
			if v == "round" or v == "bevel" then
				out.strokeLinejoin = v :: any
			else
				out.strokeLinejoin = "miter"
			end
		elseif key == "stroke-miterlimit" then
			out.strokeMiterlimit = parseNumber(value)
		elseif key == "stroke-dasharray" then
			out.strokeDasharray = parseDashArray(value)
		elseif key == "stroke-dashoffset" then
			out.strokeDashoffset = parseLengthToUserUnits(value, viewportSize)
		elseif key == "display" then
			out.display = string.lower(value) ~= "none"
		elseif key == "visibility" then
			out.visibility = string.lower(value) == "visible"
		elseif key == "clip-path" then
			local id = string.match(value, "^url%(%s*#([^%s%)]+)%s*%)")
			if id then
				out.clipPath = id
			elseif string.lower(value) == "none" then
				out.clipPath = nil
			end
		end
	end
	return out
end

return Style
