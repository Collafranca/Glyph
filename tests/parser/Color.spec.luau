--!strict
local Color = require("../../src/Parser/Color")
local t = require("../framework")

local function near(a: number, b: number, tol: number?): boolean
	return math.abs(a - b) < (tol or 1e-6)
end

local function expectRgba(got: Color.ColorValue?, r: number, g: number, b: number, a: number)
	if type(got) ~= "table" then
		error("expected rgba tuple, got " .. tostring(got), 2)
	end
	local arr = got :: Color.Rgba
	if not (near(arr[1], r) and near(arr[2], g) and near(arr[3], b) and near(arr[4], a)) then
		error(
			string.format(
				"expected {%g,%g,%g,%g}, got {%g,%g,%g,%g}",
				r,
				g,
				b,
				a,
				arr[1],
				arr[2],
				arr[3],
				arr[4]
			),
			2
		)
	end
end

t.suite("Color.parse", function()
	t.test("parses #rgb", function()
		expectRgba(Color.parse("#f00"), 1, 0, 0, 1)
		expectRgba(Color.parse("#0f0"), 0, 1, 0, 1)
		expectRgba(Color.parse("#00f"), 0, 0, 1, 1)
	end)

	t.test("parses #rgba", function()
		expectRgba(Color.parse("#f008"), 1, 0, 0, 0x88 / 255)
	end)

	t.test("parses #rrggbb", function()
		expectRgba(Color.parse("#ff0000"), 1, 0, 0, 1)
		expectRgba(Color.parse("#808080"), 0x80 / 255, 0x80 / 255, 0x80 / 255, 1)
	end)

	t.test("parses #rrggbbaa", function()
		expectRgba(Color.parse("#FF000080"), 1, 0, 0, 0x80 / 255)
	end)

	t.test("parses rgb() with commas", function()
		expectRgba(Color.parse("rgb(255, 0, 0)"), 1, 0, 0, 1)
	end)

	t.test("parses rgb() with spaces", function()
		expectRgba(Color.parse("rgb(0 255 0)"), 0, 1, 0, 1)
	end)

	t.test("parses rgb() with percents", function()
		expectRgba(Color.parse("rgb(100%, 0%, 50%)"), 1, 0, 0.5, 1)
	end)

	t.test("parses rgba() with commas", function()
		expectRgba(Color.parse("rgba(255, 0, 0, 0.5)"), 1, 0, 0, 0.5)
	end)

	t.test("parses rgba() with slash alpha", function()
		expectRgba(Color.parse("rgb(255 0 0 / 0.25)"), 1, 0, 0, 0.25)
	end)

	t.test("clamps out-of-range values", function()
		expectRgba(Color.parse("rgb(300, -20, 128)"), 1, 0, 128 / 255, 1)
	end)

	t.test("parses named colors", function()
		expectRgba(Color.parse("red"), 1, 0, 0, 1)
		expectRgba(Color.parse("Black"), 0, 0, 0, 1)
		expectRgba(Color.parse(" rebeccapurple "), 102 / 255, 51 / 255, 153 / 255, 1)
	end)

	t.test("returns nil for 'none'", function()
		t.expect(Color.parse("none")).toBeNil()
		t.expect(Color.parse("NONE")).toBeNil()
	end)

	t.test("'transparent' returns fully transparent black", function()
		expectRgba(Color.parse("transparent"), 0, 0, 0, 0)
	end)

	t.test("'currentColor' returns sentinel", function()
		t.expect(Color.parse("currentColor")).toBe("currentColor")
		t.expect(Color.parse("CURRENTCOLOR")).toBe("currentColor")
	end)

	t.test("rejects invalid hex length", function()
		t.expect(function()
			Color.parse("#12")
		end).toThrow("invalid hex")
		t.expect(function()
			Color.parse("#12345")
		end).toThrow("invalid hex")
	end)

	t.test("rejects non-hex digit", function()
		t.expect(function()
			Color.parse("#xy1234")
		end).toThrow("invalid hex")
	end)

	t.test("rejects wrong arg count in rgb()", function()
		t.expect(function()
			Color.parse("rgb(1, 2)")
		end).toThrow("invalid rgb")
		t.expect(function()
			Color.parse("rgb(1, 2, 3, 4)")
		end).toThrow("invalid rgb")
	end)

	t.test("rejects unknown name", function()
		t.expect(function()
			Color.parse("definitely-not-a-color")
		end).toThrow("unknown color")
	end)

	t.test("rejects empty input", function()
		t.expect(function()
			Color.parse("")
		end).toThrow("empty color")
	end)
end)
