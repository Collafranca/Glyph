--!strict
local Length = require("../../src/Parser/Length")
local t = require("../framework")

local function near(a: number, b: number, tol: number?): boolean
	return math.abs(a - b) < (tol or 1e-6)
end

t.suite("Length.parse", function()
	t.test("unitless", function()
		t.expect(Length.parse("10")).toBe(10)
		t.expect(Length.parse("-3.5")).toBe(-3.5)
	end)

	t.test("px", function()
		t.expect(Length.parse("12px")).toBe(12)
	end)

	t.test("in", function()
		t.expect(near(Length.parse("1in") :: number, 96)).toBeTruthy()
	end)

	t.test("pt", function()
		t.expect(near(Length.parse("72pt") :: number, 96)).toBeTruthy()
	end)

	t.test("mm and cm", function()
		t.expect(near(Length.parse("10mm") :: number, 10 * 96 / 25.4)).toBeTruthy()
		t.expect(near(Length.parse("1cm") :: number, 96 / 2.54)).toBeTruthy()
	end)

	t.test("percent stays a percent", function()
		local parsed = Length.parse("50%")
		t.expect(Length.isPercent(parsed)).toBeTruthy()
		t.expect(Length.resolve(parsed, 200)).toBe(100)
	end)

	t.test("resolve on number is identity", function()
		t.expect(Length.resolve(Length.parse("42"), 100)).toBe(42)
	end)

	t.test("rejects invalid", function()
		t.expect(function()
			Length.parse("abc")
		end).toThrow("invalid length")
		t.expect(function()
			Length.parse("10zz")
		end).toThrow("unknown length unit")
	end)
end)
