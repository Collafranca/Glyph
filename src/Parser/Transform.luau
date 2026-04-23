--!strict
--[=[
	@class Transform
	@private

	Parses SVG `transform` attribute lists into a 2x3 affine matrix and
	supplies helpers for composing, applying, and inspecting them.

	A matrix is stored as `{a, b, c, d, e, f}` with the same meaning as
	`matrix(a b c d e f)` from SVG 1.1:

	```
	[ x' ]   [ a  c  e ] [ x ]
	[ y' ] = [ b  d  f ] [ y ]
	[ 1  ]   [ 0  0  1 ] [ 1 ]
	```

	Supported transform functions: `matrix`, `translate`, `scale`, `rotate`
	(with optional center), `skewX`, `skewY`. Multiple functions in a single
	attribute are composed left-to-right (standard SVG semantics).
]=]

local Transform = {}

export type Matrix = { number }

--[=[
	@within Transform
	Returns the identity matrix.
]=]
function Transform.identity(): Matrix
	return { 1, 0, 0, 1, 0, 0 }
end

--[=[
	@within Transform
	Concatenates two matrices: `Transform.multiply(a, b)` returns `a * b`, i.e.
	the transform that first applies `b` then `a`.
]=]
function Transform.multiply(a: Matrix, b: Matrix): Matrix
	return {
		a[1] * b[1] + a[3] * b[2],
		a[2] * b[1] + a[4] * b[2],
		a[1] * b[3] + a[3] * b[4],
		a[2] * b[3] + a[4] * b[4],
		a[1] * b[5] + a[3] * b[6] + a[5],
		a[2] * b[5] + a[4] * b[6] + a[6],
	}
end

--[=[
	@within Transform
	Applies `m` to the point `(x, y)` returning `(x', y')`.
]=]
function Transform.apply(m: Matrix, x: number, y: number): (number, number)
	return m[1] * x + m[3] * y + m[5], m[2] * x + m[4] * y + m[6]
end

local function translate(tx: number, ty: number): Matrix
	return { 1, 0, 0, 1, tx, ty }
end

local function scale(sx: number, sy: number): Matrix
	return { sx, 0, 0, sy, 0, 0 }
end

local function rotate(angleDegrees: number, cx: number?, cy: number?): Matrix
	local theta = math.rad(angleDegrees)
	local cos = math.cos(theta)
	local sin = math.sin(theta)
	local rot: Matrix = { cos, sin, -sin, cos, 0, 0 }
	if cx or cy then
		local x = cx or 0
		local y = cy or 0
		return Transform.multiply(translate(x, y), Transform.multiply(rot, translate(-x, -y)))
	end
	return rot
end

local function skewX(angleDegrees: number): Matrix
	return { 1, 0, math.tan(math.rad(angleDegrees)), 1, 0, 0 }
end

local function skewY(angleDegrees: number): Matrix
	return { 1, math.tan(math.rad(angleDegrees)), 0, 1, 0, 0 }
end

-- Consumes a whitespace-/comma-separated list of numbers from inside the
-- function's parentheses and returns them as an array.
local function parseArgs(body: string): { number }
	local args: { number } = {}
	for token in string.gmatch(body, "[^%s,]+") do
		local n = tonumber(token)
		if not n then
			error("invalid number '" .. token .. "' in transform", 0)
		end
		table.insert(args, n)
	end
	return args
end

--[=[
	@within Transform
	Parses a `transform` attribute value and returns the composed matrix.
	Returns the identity matrix when the attribute is empty.
]=]
function Transform.parse(input: string): Matrix
	local result = Transform.identity()
	local pos = 1
	local length = #input
	while pos <= length do
		-- Skip whitespace and commas between functions.
		local _, whitespaceEnd = string.find(input, "^[%s,]+", pos)
		if whitespaceEnd then
			pos = whitespaceEnd + 1
		end
		if pos > length then
			break
		end
		local nameStart, nameEnd, name = string.find(input, "^([%a_][%w_]*)", pos)
		if not nameStart then
			error("expected transform function at position " .. pos, 0)
		end
		pos = (nameEnd :: number) + 1
		local _, argsOpenEnd = string.find(input, "^%s*%(", pos)
		if not argsOpenEnd then
			error("expected '(' after '" .. (name :: string) .. "'", 0)
		end
		pos = argsOpenEnd + 1
		local closePos = string.find(input, ")", pos, true)
		if not closePos then
			error("unterminated arguments for '" .. (name :: string) .. "'", 0)
		end
		local body = string.sub(input, pos, closePos - 1)
		pos = closePos + 1
		local args = parseArgs(body)
		local step: Matrix
		if name == "matrix" then
			if #args ~= 6 then
				error("matrix() expects 6 arguments, got " .. #args, 0)
			end
			step = { args[1], args[2], args[3], args[4], args[5], args[6] }
		elseif name == "translate" then
			if #args == 1 then
				step = translate(args[1], 0)
			elseif #args == 2 then
				step = translate(args[1], args[2])
			else
				error("translate() expects 1 or 2 arguments, got " .. #args, 0)
			end
		elseif name == "scale" then
			if #args == 1 then
				step = scale(args[1], args[1])
			elseif #args == 2 then
				step = scale(args[1], args[2])
			else
				error("scale() expects 1 or 2 arguments, got " .. #args, 0)
			end
		elseif name == "rotate" then
			if #args == 1 then
				step = rotate(args[1])
			elseif #args == 3 then
				step = rotate(args[1], args[2], args[3])
			else
				error("rotate() expects 1 or 3 arguments, got " .. #args, 0)
			end
		elseif name == "skewX" then
			if #args ~= 1 then
				error("skewX() expects 1 argument, got " .. #args, 0)
			end
			step = skewX(args[1])
		elseif name == "skewY" then
			if #args ~= 1 then
				error("skewY() expects 1 argument, got " .. #args, 0)
			end
			step = skewY(args[1])
		else
			error("unknown transform function '" .. (name :: string) .. "'", 0)
		end
		result = Transform.multiply(result, step)
	end
	return result
end

return Transform
