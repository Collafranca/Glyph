--!strict
local PathData = require("../../src/Parser/PathData")
local t = require("../framework")

local function near(a: number, b: number, tol: number?): boolean
	return math.abs(a - b) < (tol or 1e-9)
end

local function expectCommand(got: PathData.Command, expected: { any })
	if #got ~= #expected then
		error(
			string.format(
				"expected command of length %d, got %d: got=%s",
				#expected,
				#got,
				table.concat(got :: any, ","),
				2
			)
		)
	end
	for i = 1, #expected do
		local a, b = got[i], expected[i]
		if type(a) == "number" and type(b) == "number" then
			if not near(a, b) then
				error(string.format("index %d: expected %g, got %g", i, b, a), 2)
			end
		elseif a ~= b then
			error(string.format("index %d: expected %s, got %s", i, tostring(b), tostring(a)), 2)
		end
	end
end

local function expectCommands(got: { PathData.Command }, expected: { { any } })
	if #got ~= #expected then
		error(string.format("expected %d commands, got %d", #expected, #got), 2)
	end
	for i, exp in ipairs(expected) do
		expectCommand(got[i], exp)
	end
end

t.suite("PathData.parse", function()
	t.test("parses M L Z", function()
		local cmds = PathData.parse("M 10 20 L 30 40 Z")
		expectCommands(cmds, {
			{ "M", 10, 20 },
			{ "L", 30, 40 },
			{ "Z" },
		})
	end)

	t.test("implicit lineto after moveto (absolute)", function()
		-- "M 10 10 20 20" = moveto, then one L
		local cmds = PathData.parse("M 10 10 20 20")
		expectCommands(cmds, {
			{ "M", 10, 10 },
			{ "L", 20, 20 },
		})
	end)

	t.test("implicit relative lineto after relative moveto", function()
		-- "m 10 10 20 20" = moveto (10,10), then l 20 20 -> (30,30)
		local cmds = PathData.parse("m 10 10 20 20")
		expectCommands(cmds, {
			{ "M", 10, 10 },
			{ "L", 30, 30 },
		})
	end)

	t.test("relative commands resolve against current point", function()
		local cmds = PathData.parse("M 10 10 l 5 0 l 0 5")
		expectCommands(cmds, {
			{ "M", 10, 10 },
			{ "L", 15, 10 },
			{ "L", 15, 15 },
		})
	end)

	t.test("H and V produce absolute coords", function()
		local cmds = PathData.parse("M 10 10 h 5 v 5 H 0 V 0")
		expectCommands(cmds, {
			{ "M", 10, 10 },
			{ "H", 15 },
			{ "V", 15 },
			{ "H", 0 },
			{ "V", 0 },
		})
	end)

	t.test("Z restores current point to subpath start", function()
		-- After Z, the next M should be relative to the subpath start, not the
		-- pen's last drawn point. m at the start is treated as M (absolute).
		local cmds = PathData.parse("M 10 10 l 5 5 Z l 0 5")
		-- Z returns pen to (10, 10); subsequent l 0 5 -> (10, 15)
		expectCommands(cmds, {
			{ "M", 10, 10 },
			{ "L", 15, 15 },
			{ "Z" },
			{ "L", 10, 15 },
		})
	end)

	t.test("cubic Bezier C absolute", function()
		local cmds = PathData.parse("M 0 0 C 10 0 10 10 20 10")
		expectCommands(cmds, {
			{ "M", 0, 0 },
			{ "C", 10, 0, 10, 10, 20, 10 },
		})
	end)

	t.test("S reflects previous C control point", function()
		-- First C ends at (20, 10) with x2,y2 = (10, 10). S mirrors (10, 10)
		-- about (20, 10) to produce x1=(30, 10) for the next cubic.
		local cmds = PathData.parse("M 0 0 C 10 0 10 10 20 10 S 40 20 50 30")
		expectCommands(cmds, {
			{ "M", 0, 0 },
			{ "C", 10, 0, 10, 10, 20, 10 },
			{ "C", 30, 10, 40, 20, 50, 30 },
		})
	end)

	t.test("S without preceding C collapses implicit control to current point", function()
		local cmds = PathData.parse("M 0 0 L 10 10 S 20 0 30 10")
		expectCommands(cmds, {
			{ "M", 0, 0 },
			{ "L", 10, 10 },
			{ "C", 10, 10, 20, 0, 30, 10 },
		})
	end)

	t.test("Q quadratic absolute", function()
		local cmds = PathData.parse("M 0 0 Q 10 10 20 0")
		expectCommands(cmds, {
			{ "M", 0, 0 },
			{ "Q", 10, 10, 20, 0 },
		})
	end)

	t.test("T reflects previous Q control point", function()
		local cmds = PathData.parse("M 0 0 Q 10 10 20 0 T 40 0")
		-- Q's control (10, 10) reflected about end (20, 0) -> (30, -10)
		expectCommands(cmds, {
			{ "M", 0, 0 },
			{ "Q", 10, 10, 20, 0 },
			{ "Q", 30, -10, 40, 0 },
		})
	end)

	t.test("arc flags parsed as single characters (no separator required)", function()
		-- "A25,25 0 0150,50" = rx=25 ry=25 rot=0 large=0 sweep=1 x=50 y=50
		local cmds = PathData.parse("M0 0 A25,25 0 0150,50")
		expectCommands(cmds, {
			{ "M", 0, 0 },
			{ "A", 25, 25, 0, 0, 1, 50, 50 },
		})
	end)

	t.test("A with explicit separators", function()
		local cmds = PathData.parse("M 0 0 A 25 25 0 1 0 50 50")
		expectCommands(cmds, {
			{ "M", 0, 0 },
			{ "A", 25, 25, 0, 1, 0, 50, 50 },
		})
	end)

	t.test("negative numbers as separators", function()
		-- "10-20" = two numbers: 10, -20
		local cmds = PathData.parse("M10-20")
		expectCommands(cmds, {
			{ "M", 10, -20 },
		})
	end)

	t.test("decimal-only second number (1.5.5 = 1.5, 0.5)", function()
		local cmds = PathData.parse("M1.5.5")
		expectCommands(cmds, {
			{ "M", 1.5, 0.5 },
		})
	end)

	t.test("scientific notation", function()
		local cmds = PathData.parse("M 1e2 2e-1")
		expectCommands(cmds, {
			{ "M", 100, 0.2 },
		})
	end)

	t.test("rejects data that does not start with moveto", function()
		t.expect(function()
			PathData.parse("L 1 2")
		end).toThrow("must begin with")
	end)

	t.test("rejects unknown command", function()
		t.expect(function()
			PathData.parse("M 0 0 X 1 2")
		end).toThrow("unknown path command")
	end)

	t.test("rejects missing argument", function()
		t.expect(function()
			PathData.parse("M 0")
		end).toThrow("expected y")
	end)

	t.test("rejects arc flag that isn't 0/1", function()
		t.expect(function()
			PathData.parse("M 0 0 A 1 1 0 2 1 5 5")
		end).toThrow("large%-arc%-flag")
	end)

	t.test("consecutive moveto pairs implicit-line", function()
		-- "M 0 0 10 0 20 0" -> M then two Ls
		local cmds = PathData.parse("M 0 0 10 0 20 0")
		expectCommands(cmds, {
			{ "M", 0, 0 },
			{ "L", 10, 0 },
			{ "L", 20, 0 },
		})
	end)

	t.test("empty input returns empty", function()
		local cmds = PathData.parse("")
		t.expect(#cmds).toBe(0)
	end)
end)
