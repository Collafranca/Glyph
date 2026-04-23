--!strict
--[=[
	@class PathData
	@private

	Parses an SVG `path` `d` attribute into a flat list of absolute commands.

	Output representation: an array of command tables, each shaped as
	`{ op, x0, y0, x1, y1, ... }` where `op` is one of the uppercase absolute
	forms: `"M"`, `"L"`, `"H"`, `"V"`, `"C"`, `"S"`, `"Q"`, `"T"`, `"A"`,
	`"Z"`.

	Parsing quirks handled per the SVG 1.1 grammar (§8.3):

	- Relative commands (lowercase) are resolved to absolute coordinates on
	  the fly, with the relative `m` after a closepath tracking the subpath
	  initial point rather than the pen's last point.
	- An implicit `L`/`l` follows an explicit `M`/`m` when more coordinate
	  pairs are supplied without a new command letter.
	- The elliptical arc flag parameters (`large-arc-flag`, `sweep-flag`) are
	  single-character flags: the string `A25,25 0 0150,50` is legal and
	  parses as `large=0, sweep=1, x=50, y=50`.
	- Number tokens are the SVG productions: optional sign, integer and/or
	  fractional part (where `.` is a separator, so `1.5.5` yields two
	  numbers), optional exponent.
	- `Z`/`z` restores the current point to the initial point of the subpath.
	- Smooth-curve reflection (`S`, `T`) only mirrors the previous control
	  point when the preceding command was of the same family.
]=]

local PathData = {}

-- Commands are heterogenous: first entry is the opcode (uppercase letter),
-- the rest are numeric arguments.
export type Command = { string | number }

local ARG_COUNT: { [string]: number } = {
	M = 2,
	L = 2,
	H = 1,
	V = 1,
	C = 6,
	S = 4,
	Q = 4,
	T = 2,
	A = 7,
	Z = 0,
}

local function isCommandLetter(b: number): boolean
	return (b >= 0x41 and b <= 0x5A) or (b >= 0x61 and b <= 0x7A)
end

type Cursor = {
	source: string,
	pos: number,
	length: number,
}

local function peek(cur: Cursor): number
	return string.byte(cur.source, cur.pos) or -1
end

local function skipSeparators(cur: Cursor)
	-- Separators: whitespace (SP, HT, LF, CR) and a single optional comma.
	local sawComma = false
	while cur.pos <= cur.length do
		local b = peek(cur)
		if b == 0x20 or b == 0x09 or b == 0x0A or b == 0x0D then
			cur.pos += 1
		elseif b == 0x2C and not sawComma then -- ','
			sawComma = true
			cur.pos += 1
		else
			break
		end
	end
end

-- Reads an SVG number. Returns the parsed value, or nil if no number is
-- available at the cursor.
local function readNumber(cur: Cursor): number?
	local start = cur.pos
	local pos = start
	local length = cur.length
	local source = cur.source
	local b = string.byte(source, pos)
	if b == 0x2B or b == 0x2D then -- '+' or '-'
		pos += 1
	end
	local digitsBefore = 0
	while pos <= length do
		local d = string.byte(source, pos) :: number
		if d >= 0x30 and d <= 0x39 then
			digitsBefore += 1
			pos += 1
		else
			break
		end
	end
	local digitsAfter = 0
	if pos <= length and string.byte(source, pos) == 0x2E then -- '.'
		pos += 1
		while pos <= length do
			local d = string.byte(source, pos) :: number
			if d >= 0x30 and d <= 0x39 then
				digitsAfter += 1
				pos += 1
			else
				break
			end
		end
	end
	if digitsBefore == 0 and digitsAfter == 0 then
		return nil
	end
	if pos <= length then
		local e = string.byte(source, pos) :: number
		if e == 0x45 or e == 0x65 then -- 'E' or 'e'
			local expStart = pos
			pos += 1
			if pos <= length then
				local s = string.byte(source, pos) :: number
				if s == 0x2B or s == 0x2D then
					pos += 1
				end
			end
			local expDigits = 0
			while pos <= length do
				local d = string.byte(source, pos) :: number
				if d >= 0x30 and d <= 0x39 then
					expDigits += 1
					pos += 1
				else
					break
				end
			end
			if expDigits == 0 then
				-- Not a valid exponent; back out.
				pos = expStart
			end
		end
	end
	local text = string.sub(source, start, pos - 1)
	local value = tonumber(text)
	if not value then
		return nil
	end
	cur.pos = pos
	return value
end

local function readNumberRequired(cur: Cursor, label: string): number
	skipSeparators(cur)
	local n = readNumber(cur)
	if not n then
		error("expected " .. label .. " at position " .. cur.pos, 0)
	end
	return n
end

local function readFlag(cur: Cursor, label: string): number
	skipSeparators(cur)
	if cur.pos > cur.length then
		error("expected " .. label .. " at position " .. cur.pos, 0)
	end
	local b = peek(cur)
	if b == 0x30 then
		cur.pos += 1
		return 0
	elseif b == 0x31 then
		cur.pos += 1
		return 1
	end
	error("expected " .. label .. " (0 or 1) at position " .. cur.pos, 0)
end

-- `table.insert(output, { "M", 10, 20 })` widens the literal to `{string}` in
-- Luau's flow analysis because the first element is a string literal; subsequent
-- numeric values then don't match. Emitting via a helper with typed parameters
-- keeps inference on the `{string | number}` track we actually want.
local function emit(output: { Command }, opcode: string, ...: number)
	local cmd: Command = { opcode }
	for i = 1, select("#", ...) do
		cmd[i + 1] = select(i, ...)
	end
	table.insert(output, cmd)
end

-- Consumes arguments for a single command and appends one or more absolute
-- commands to `output`, updating current-point and subpath-start state.
local function consume(
	cur: Cursor,
	letter: string,
	state: { cx: number, cy: number, sx: number, sy: number, prev: string? },
	output: { Command }
)
	local upper = string.upper(letter)
	local relative = upper ~= letter
	local function refX(x: number): number
		return if relative then state.cx + x else x
	end
	local function refY(y: number): number
		return if relative then state.cy + y else y
	end
	if upper == "M" then
		-- The first pair after M establishes the subpath start; subsequent
		-- implicit pairs are treated as L / l respectively.
		local firstPair = true
		while true do
			skipSeparators(cur)
			local saved = cur.pos
			local x = readNumber(cur)
			if not x then
				cur.pos = saved
				break
			end
			local y = readNumberRequired(cur, "y")
			local ax = refX(x :: number)
			local ay = refY(y)
			if firstPair then
				emit(output, "M", ax, ay)
				state.cx, state.cy = ax, ay
				state.sx, state.sy = ax, ay
				state.prev = "M"
				firstPair = false
			else
				emit(output, "L", ax, ay)
				state.cx, state.cy = ax, ay
				state.prev = "L"
			end
		end
	elseif upper == "L" then
		while true do
			skipSeparators(cur)
			local saved = cur.pos
			local x = readNumber(cur)
			if not x then
				cur.pos = saved
				break
			end
			local y = readNumberRequired(cur, "y")
			local ax = refX(x :: number)
			local ay = refY(y)
			emit(output, "L", ax, ay)
			state.cx, state.cy = ax, ay
			state.prev = "L"
		end
	elseif upper == "H" then
		while true do
			skipSeparators(cur)
			local saved = cur.pos
			local x = readNumber(cur)
			if not x then
				cur.pos = saved
				break
			end
			local ax = refX(x :: number)
			emit(output, "H", ax)
			state.cx = ax
			state.prev = "H"
		end
	elseif upper == "V" then
		while true do
			skipSeparators(cur)
			local saved = cur.pos
			local y = readNumber(cur)
			if not y then
				cur.pos = saved
				break
			end
			local ay = refY(y :: number)
			emit(output, "V", ay)
			state.cy = ay
			state.prev = "V"
		end
	elseif upper == "C" then
		while true do
			skipSeparators(cur)
			local saved = cur.pos
			local x1 = readNumber(cur)
			if not x1 then
				cur.pos = saved
				break
			end
			local y1 = readNumberRequired(cur, "y1")
			local x2 = readNumberRequired(cur, "x2")
			local y2 = readNumberRequired(cur, "y2")
			local x = readNumberRequired(cur, "x")
			local y = readNumberRequired(cur, "y")
			emit(output, "C", refX(x1 :: number), refY(y1), refX(x2), refY(y2), refX(x), refY(y))
			state.cx, state.cy = refX(x), refY(y)
			state.prev = "C"
		end
	elseif upper == "S" then
		while true do
			skipSeparators(cur)
			local saved = cur.pos
			local x2 = readNumber(cur)
			if not x2 then
				cur.pos = saved
				break
			end
			local y2 = readNumberRequired(cur, "y2")
			local x = readNumberRequired(cur, "x")
			local y = readNumberRequired(cur, "y")
			-- Reflect previous control point if prev was C or S; otherwise
			-- the implicit control point coincides with the current point.
			local x1, y1
			local last = output[#output]
			if (state.prev == "C" or state.prev == "S") and last then
				x1 = 2 * state.cx - (last[#last - 3] :: number)
				y1 = 2 * state.cy - (last[#last - 2] :: number)
			else
				x1, y1 = state.cx, state.cy
			end
			emit(output, "C", x1, y1, refX(x2 :: number), refY(y2), refX(x), refY(y))
			state.cx, state.cy = refX(x), refY(y)
			state.prev = "S"
		end
	elseif upper == "Q" then
		while true do
			skipSeparators(cur)
			local saved = cur.pos
			local x1 = readNumber(cur)
			if not x1 then
				cur.pos = saved
				break
			end
			local y1 = readNumberRequired(cur, "y1")
			local x = readNumberRequired(cur, "x")
			local y = readNumberRequired(cur, "y")
			emit(output, "Q", refX(x1 :: number), refY(y1), refX(x), refY(y))
			state.cx, state.cy = refX(x), refY(y)
			state.prev = "Q"
		end
	elseif upper == "T" then
		while true do
			skipSeparators(cur)
			local saved = cur.pos
			local x = readNumber(cur)
			if not x then
				cur.pos = saved
				break
			end
			local y = readNumberRequired(cur, "y")
			local x1, y1
			local last = output[#output]
			if (state.prev == "Q" or state.prev == "T") and last and last[1] == "Q" then
				x1 = 2 * state.cx - (last[2] :: number)
				y1 = 2 * state.cy - (last[3] :: number)
			else
				x1, y1 = state.cx, state.cy
			end
			emit(output, "Q", x1, y1, refX(x :: number), refY(y))
			state.cx, state.cy = refX(x), refY(y)
			state.prev = "T"
		end
	elseif upper == "A" then
		while true do
			skipSeparators(cur)
			local saved = cur.pos
			local rx = readNumber(cur)
			if not rx then
				cur.pos = saved
				break
			end
			local ry = readNumberRequired(cur, "ry")
			local xAxisRotation = readNumberRequired(cur, "x-axis-rotation")
			local largeArc = readFlag(cur, "large-arc-flag")
			local sweep = readFlag(cur, "sweep-flag")
			local x = readNumberRequired(cur, "x")
			local y = readNumberRequired(cur, "y")
			emit(
				output,
				"A",
				math.abs(rx :: number),
				math.abs(ry),
				xAxisRotation,
				largeArc,
				sweep,
				refX(x),
				refY(y)
			)
			state.cx, state.cy = refX(x), refY(y)
			state.prev = "A"
		end
	elseif upper == "Z" then
		emit(output, "Z")
		state.cx, state.cy = state.sx, state.sy
		state.prev = "Z"
	else
		error("unknown path command '" .. letter .. "'", 0)
	end
end

--[=[
	@within PathData
	Parses an SVG `path` `d` attribute string. Returns an array of absolute
	commands. Raises on malformed input.
]=]
function PathData.parse(input: string): { Command }
	local cur: Cursor = { source = input, pos = 1, length = #input }
	local output: { Command } = {}
	local state = { cx = 0, cy = 0, sx = 0, sy = 0, prev = nil :: string? }
	skipSeparators(cur)
	if cur.pos > cur.length then
		return output
	end
	-- SVG requires path data to start with a moveto.
	if not isCommandLetter(peek(cur)) then
		error("path data must begin with a command letter", 0)
	end
	local first = string.sub(input, cur.pos, cur.pos)
	if string.upper(first) ~= "M" then
		error("path data must begin with 'M' or 'm'", 0)
	end
	while cur.pos <= cur.length do
		skipSeparators(cur)
		if cur.pos > cur.length then
			break
		end
		local b = peek(cur)
		if not isCommandLetter(b) then
			error("expected command letter at position " .. cur.pos, 0)
		end
		local letter = string.sub(input, cur.pos, cur.pos)
		if not ARG_COUNT[string.upper(letter)] then
			error("unknown path command '" .. letter .. "'", 0)
		end
		cur.pos += 1
		consume(cur, letter, state, output)
	end
	return output
end

return PathData
