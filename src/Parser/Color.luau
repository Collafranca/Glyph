--!strict
--[=[
	@class Color
	@private

	Parses SVG 1.1 color strings into straight-RGBA tuples (components in
	`[0, 1]`).

	Supported syntaxes:
	- `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`
	- `rgb(R, G, B)` and `rgb(R G B)` with integer or percent components
	- `rgba(R, G, B, A)` and `rgba(R G B / A)` (SVG 2 space-separated form)
	- CSS/SVG 1.1 named colors (147 of them)
	- `none`        -> returns `nil` (caller treats as "no paint")
	- `transparent` -> returns `{0, 0, 0, 0}`
	- `currentColor` -> returns the sentinel string `"currentColor"` for the
	                    caller to resolve against the current `color` state

	Colors are validated strictly; malformed inputs raise an error rather than
	silently falling back to black so that authors catch mistakes early.
]=]

local Color = {}

export type Rgba = { number }

-- "none" means "don't paint"; currentColor requires caller context.
export type ColorValue = Rgba | "currentColor" | "none"

local NAMED: { [string]: { number } } = {
	aliceblue = { 240, 248, 255 },
	antiquewhite = { 250, 235, 215 },
	aqua = { 0, 255, 255 },
	aquamarine = { 127, 255, 212 },
	azure = { 240, 255, 255 },
	beige = { 245, 245, 220 },
	bisque = { 255, 228, 196 },
	black = { 0, 0, 0 },
	blanchedalmond = { 255, 235, 205 },
	blue = { 0, 0, 255 },
	blueviolet = { 138, 43, 226 },
	brown = { 165, 42, 42 },
	burlywood = { 222, 184, 135 },
	cadetblue = { 95, 158, 160 },
	chartreuse = { 127, 255, 0 },
	chocolate = { 210, 105, 30 },
	coral = { 255, 127, 80 },
	cornflowerblue = { 100, 149, 237 },
	cornsilk = { 255, 248, 220 },
	crimson = { 220, 20, 60 },
	cyan = { 0, 255, 255 },
	darkblue = { 0, 0, 139 },
	darkcyan = { 0, 139, 139 },
	darkgoldenrod = { 184, 134, 11 },
	darkgray = { 169, 169, 169 },
	darkgreen = { 0, 100, 0 },
	darkgrey = { 169, 169, 169 },
	darkkhaki = { 189, 183, 107 },
	darkmagenta = { 139, 0, 139 },
	darkolivegreen = { 85, 107, 47 },
	darkorange = { 255, 140, 0 },
	darkorchid = { 153, 50, 204 },
	darkred = { 139, 0, 0 },
	darksalmon = { 233, 150, 122 },
	darkseagreen = { 143, 188, 143 },
	darkslateblue = { 72, 61, 139 },
	darkslategray = { 47, 79, 79 },
	darkslategrey = { 47, 79, 79 },
	darkturquoise = { 0, 206, 209 },
	darkviolet = { 148, 0, 211 },
	deeppink = { 255, 20, 147 },
	deepskyblue = { 0, 191, 255 },
	dimgray = { 105, 105, 105 },
	dimgrey = { 105, 105, 105 },
	dodgerblue = { 30, 144, 255 },
	firebrick = { 178, 34, 34 },
	floralwhite = { 255, 250, 240 },
	forestgreen = { 34, 139, 34 },
	fuchsia = { 255, 0, 255 },
	gainsboro = { 220, 220, 220 },
	ghostwhite = { 248, 248, 255 },
	gold = { 255, 215, 0 },
	goldenrod = { 218, 165, 32 },
	gray = { 128, 128, 128 },
	green = { 0, 128, 0 },
	greenyellow = { 173, 255, 47 },
	grey = { 128, 128, 128 },
	honeydew = { 240, 255, 240 },
	hotpink = { 255, 105, 180 },
	indianred = { 205, 92, 92 },
	indigo = { 75, 0, 130 },
	ivory = { 255, 255, 240 },
	khaki = { 240, 230, 140 },
	lavender = { 230, 230, 250 },
	lavenderblush = { 255, 240, 245 },
	lawngreen = { 124, 252, 0 },
	lemonchiffon = { 255, 250, 205 },
	lightblue = { 173, 216, 230 },
	lightcoral = { 240, 128, 128 },
	lightcyan = { 224, 255, 255 },
	lightgoldenrodyellow = { 250, 250, 210 },
	lightgray = { 211, 211, 211 },
	lightgreen = { 144, 238, 144 },
	lightgrey = { 211, 211, 211 },
	lightpink = { 255, 182, 193 },
	lightsalmon = { 255, 160, 122 },
	lightseagreen = { 32, 178, 170 },
	lightskyblue = { 135, 206, 250 },
	lightslategray = { 119, 136, 153 },
	lightslategrey = { 119, 136, 153 },
	lightsteelblue = { 176, 196, 222 },
	lightyellow = { 255, 255, 224 },
	lime = { 0, 255, 0 },
	limegreen = { 50, 205, 50 },
	linen = { 250, 240, 230 },
	magenta = { 255, 0, 255 },
	maroon = { 128, 0, 0 },
	mediumaquamarine = { 102, 205, 170 },
	mediumblue = { 0, 0, 205 },
	mediumorchid = { 186, 85, 211 },
	mediumpurple = { 147, 112, 219 },
	mediumseagreen = { 60, 179, 113 },
	mediumslateblue = { 123, 104, 238 },
	mediumspringgreen = { 0, 250, 154 },
	mediumturquoise = { 72, 209, 204 },
	mediumvioletred = { 199, 21, 133 },
	midnightblue = { 25, 25, 112 },
	mintcream = { 245, 255, 250 },
	mistyrose = { 255, 228, 225 },
	moccasin = { 255, 228, 181 },
	navajowhite = { 255, 222, 173 },
	navy = { 0, 0, 128 },
	oldlace = { 253, 245, 230 },
	olive = { 128, 128, 0 },
	olivedrab = { 107, 142, 35 },
	orange = { 255, 165, 0 },
	orangered = { 255, 69, 0 },
	orchid = { 218, 112, 214 },
	palegoldenrod = { 238, 232, 170 },
	palegreen = { 152, 251, 152 },
	paleturquoise = { 175, 238, 238 },
	palevioletred = { 219, 112, 147 },
	papayawhip = { 255, 239, 213 },
	peachpuff = { 255, 218, 185 },
	peru = { 205, 133, 63 },
	pink = { 255, 192, 203 },
	plum = { 221, 160, 221 },
	powderblue = { 176, 224, 230 },
	purple = { 128, 0, 128 },
	rebeccapurple = { 102, 51, 153 },
	red = { 255, 0, 0 },
	rosybrown = { 188, 143, 143 },
	royalblue = { 65, 105, 225 },
	saddlebrown = { 139, 69, 19 },
	salmon = { 250, 128, 114 },
	sandybrown = { 244, 164, 96 },
	seagreen = { 46, 139, 87 },
	seashell = { 255, 245, 238 },
	sienna = { 160, 82, 45 },
	silver = { 192, 192, 192 },
	skyblue = { 135, 206, 235 },
	slateblue = { 106, 90, 205 },
	slategray = { 112, 128, 144 },
	slategrey = { 112, 128, 144 },
	snow = { 255, 250, 250 },
	springgreen = { 0, 255, 127 },
	steelblue = { 70, 130, 180 },
	tan = { 210, 180, 140 },
	teal = { 0, 128, 128 },
	thistle = { 216, 191, 216 },
	tomato = { 255, 99, 71 },
	turquoise = { 64, 224, 208 },
	violet = { 238, 130, 238 },
	wheat = { 245, 222, 179 },
	white = { 255, 255, 255 },
	whitesmoke = { 245, 245, 245 },
	yellow = { 255, 255, 0 },
	yellowgreen = { 154, 205, 50 },
}

local function clamp01(n: number): number
	if n < 0 then
		return 0
	elseif n > 1 then
		return 1
	else
		return n
	end
end

local function hexNibble(char: string): number?
	local b = string.byte(char)
	if b >= 0x30 and b <= 0x39 then
		return b - 0x30
	elseif b >= 0x41 and b <= 0x46 then
		return b - 0x41 + 10
	elseif b >= 0x61 and b <= 0x66 then
		return b - 0x61 + 10
	end
	return nil
end

local function parseHex(spec: string): Rgba?
	local n = #spec
	if n ~= 3 and n ~= 4 and n ~= 6 and n ~= 8 then
		return nil
	end
	local bytes = {}
	for i = 1, n do
		local v = hexNibble(string.sub(spec, i, i))
		if not v then
			return nil
		end
		bytes[i] = v
	end
	if n == 3 or n == 4 then
		local r = (bytes[1] * 16 + bytes[1]) / 255
		local g = (bytes[2] * 16 + bytes[2]) / 255
		local b = (bytes[3] * 16 + bytes[3]) / 255
		local a = if n == 4 then (bytes[4] * 16 + bytes[4]) / 255 else 1
		return { r, g, b, a }
	else
		local r = (bytes[1] * 16 + bytes[2]) / 255
		local g = (bytes[3] * 16 + bytes[4]) / 255
		local b = (bytes[5] * 16 + bytes[6]) / 255
		local a = if n == 8 then (bytes[7] * 16 + bytes[8]) / 255 else 1
		return { r, g, b, a }
	end
end

-- Parses a component of the form "N", "N.N", "N%" into a 0..1 fraction.
-- `channel` is true for R/G/B (which allow [0, 255] or [0%, 100%]); false for
-- alpha (which allows [0, 1] or [0%, 100%]).
local function parseChannel(raw: string, channel: boolean): number?
	local trimmed = string.match(raw, "^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return nil
	end
	local percent = string.sub(trimmed, -1) == "%"
	local numberText = if percent then string.sub(trimmed, 1, -2) else trimmed
	local n = tonumber(numberText)
	if not n then
		return nil
	end
	if percent then
		return clamp01(n / 100)
	end
	if channel then
		return clamp01(n / 255)
	end
	return clamp01(n)
end

local function parseFunctional(spec: string, hasAlpha: boolean): Rgba?
	-- Accept both comma- and whitespace-separated forms, with an optional
	-- '/ alpha' tail for SVG 2 syntax.
	local body = spec
	local alphaSlice: string?
	local slash = string.find(body, "/", 1, true)
	if slash then
		alphaSlice = string.sub(body, slash + 1)
		body = string.sub(body, 1, slash - 1)
	end
	local parts: { string } = {}
	if string.find(body, ",", 1, true) then
		for segment in string.gmatch(body, "[^,]+") do
			table.insert(parts, segment)
		end
	else
		for segment in string.gmatch(body, "%S+") do
			table.insert(parts, segment)
		end
	end
	if hasAlpha and not alphaSlice then
		if #parts ~= 4 then
			return nil
		end
		alphaSlice = parts[4]
		parts[4] = nil
	end
	if #parts ~= 3 then
		return nil
	end
	local r = parseChannel(parts[1], true)
	local g = parseChannel(parts[2], true)
	local b = parseChannel(parts[3], true)
	if not r or not g or not b then
		return nil
	end
	local a = 1
	if alphaSlice then
		local parsed = parseChannel(alphaSlice, false)
		if not parsed then
			return nil
		end
		a = parsed
	end
	return { r, g, b, a }
end

--[=[
	@within Color
	Parses a color string. Returns the parsed `ColorValue`, or `nil` if the
	input describes `none`. Raises on unrecognized inputs.
]=]
function Color.parse(input: string): ColorValue?
	local trimmed = string.match(input, "^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		error("empty color", 0)
	end
	local lower = string.lower(trimmed :: string)
	if lower == "none" then
		return nil
	end
	if lower == "transparent" then
		return { 0, 0, 0, 0 } :: Rgba
	end
	if lower == "currentcolor" then
		return "currentColor"
	end
	if string.sub(trimmed :: string, 1, 1) == "#" then
		local parsed = parseHex(string.sub(trimmed :: string, 2))
		if not parsed then
			error("invalid hex color '" .. (trimmed :: string) .. "'", 0)
		end
		return parsed
	end
	-- rgb( ... ) or rgba( ... )
	local body = string.match(lower, "^rgba?%s*%(%s*(.-)%s*%)$")
	if body then
		local hasAlpha = string.sub(lower, 1, 4) == "rgba"
		-- Use the case-insensitive body extracted from `lower`; numeric
		-- components don't need original casing.
		local parsed = parseFunctional(body, hasAlpha)
		if not parsed then
			error("invalid rgb() color '" .. (trimmed :: string) .. "'", 0)
		end
		return parsed
	end
	-- Named
	local named = NAMED[lower]
	if named then
		return { named[1] / 255, named[2] / 255, named[3] / 255, 1 } :: Rgba
	end
	error("unknown color '" .. (trimmed :: string) .. "'", 0)
end

return Color
