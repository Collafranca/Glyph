--!strict
local Transform = require("../../src/Parser/Transform")
local t = require("../framework")

local function near(a: number, b: number, tol: number?): boolean
	return math.abs(a - b) < (tol or 1e-9)
end

local function expectMatrix(
	m: Transform.Matrix,
	a: number,
	b: number,
	c: number,
	d: number,
	e: number,
	f: number
)
	local ok = near(m[1], a)
		and near(m[2], b)
		and near(m[3], c)
		and near(m[4], d)
		and near(m[5], e)
		and near(m[6], f)
	if not ok then
		error(
			string.format(
				"expected {%g,%g,%g,%g,%g,%g}, got {%g,%g,%g,%g,%g,%g}",
				a,
				b,
				c,
				d,
				e,
				f,
				m[1],
				m[2],
				m[3],
				m[4],
				m[5],
				m[6]
			),
			2
		)
	end
end

t.suite("Transform.parse", function()
	t.test("empty input returns identity", function()
		expectMatrix(Transform.parse(""), 1, 0, 0, 1, 0, 0)
		expectMatrix(Transform.parse("   "), 1, 0, 0, 1, 0, 0)
	end)

	t.test("matrix() takes 6 args", function()
		expectMatrix(Transform.parse("matrix(1 2 3 4 5 6)"), 1, 2, 3, 4, 5, 6)
		expectMatrix(Transform.parse("matrix(1,2,3,4,5,6)"), 1, 2, 3, 4, 5, 6)
	end)

	t.test("translate(x) fills y=0", function()
		expectMatrix(Transform.parse("translate(10)"), 1, 0, 0, 1, 10, 0)
	end)

	t.test("translate(x, y)", function()
		expectMatrix(Transform.parse("translate(10 20)"), 1, 0, 0, 1, 10, 20)
	end)

	t.test("scale(s) is uniform", function()
		expectMatrix(Transform.parse("scale(2)"), 2, 0, 0, 2, 0, 0)
	end)

	t.test("scale(sx, sy)", function()
		expectMatrix(Transform.parse("scale(2, 3)"), 2, 0, 0, 3, 0, 0)
	end)

	t.test("rotate(90) around origin", function()
		local m = Transform.parse("rotate(90)")
		local x, y = Transform.apply(m, 1, 0)
		if not (near(x, 0) and near(y, 1)) then
			error(string.format("expected (0,1), got (%g,%g)", x, y), 0)
		end
	end)

	t.test("rotate(90, cx, cy) around pivot", function()
		-- rotate 90deg around (10, 10): point (11, 10) -> (10, 11)
		local m = Transform.parse("rotate(90 10 10)")
		local x, y = Transform.apply(m, 11, 10)
		if not (near(x, 10) and near(y, 11)) then
			error(string.format("expected (10,11), got (%g,%g)", x, y), 0)
		end
	end)

	t.test("skewX(45) shears", function()
		local m = Transform.parse("skewX(45)")
		local x, y = Transform.apply(m, 0, 1)
		if not (near(x, 1) and near(y, 1)) then
			error(string.format("expected (1,1), got (%g,%g)", x, y), 0)
		end
	end)

	t.test("skewY(45) shears", function()
		local m = Transform.parse("skewY(45)")
		local x, y = Transform.apply(m, 1, 0)
		if not (near(x, 1) and near(y, 1)) then
			error(string.format("expected (1,1), got (%g,%g)", x, y), 0)
		end
	end)

	t.test("composes left-to-right (first listed is outermost)", function()
		-- translate then scale: point (1, 1) -> scale first (to 2, 2), then
		-- translate (to 12, 12). Per SVG, transforms apply right-to-left when
		-- multiplying by the point, so listed order is the outermost-first.
		local m = Transform.parse("translate(10 10) scale(2)")
		local x, y = Transform.apply(m, 1, 1)
		if not (near(x, 12) and near(y, 12)) then
			error(string.format("expected (12,12), got (%g,%g)", x, y), 0)
		end
	end)

	t.test("handles mixed separators", function()
		local m = Transform.parse("translate(1,2)   scale(3 4),rotate(0)")
		expectMatrix(m, 3, 0, 0, 4, 1, 2)
	end)

	t.test("rejects unknown function", function()
		t.expect(function()
			Transform.parse("warpspeed(1)")
		end).toThrow("unknown transform")
	end)

	t.test("rejects wrong arg count", function()
		t.expect(function()
			Transform.parse("matrix(1 2 3)")
		end).toThrow("matrix")
		t.expect(function()
			Transform.parse("translate()")
		end).toThrow("translate")
	end)

	t.test("rejects missing parentheses", function()
		t.expect(function()
			Transform.parse("rotate 45")
		end).toThrow("expected '%('")
	end)
end)
