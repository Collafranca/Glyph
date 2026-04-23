--!strict
local FlattenPath = require("../../src/Flatten/Path")
local PathData = require("../../src/Parser/PathData")
local Transform = require("../../src/Parser/Transform")
local t = require("../framework")

local function near(a: number, b: number, tol: number?): boolean
	return math.abs(a - b) < (tol or 1e-6)
end

t.suite("FlattenPath.flatten", function()
	t.test("M L produces a single open subpath", function()
		local cmds = PathData.parse("M 0 0 L 10 0 L 10 10")
		local subpaths = FlattenPath.flatten(cmds, Transform.identity(), 0.25)
		t.expect(#subpaths).toBe(1)
		t.expect(subpaths[1].closed).toBeFalsy()
		t.expect(subpaths[1].points).toEqual({ 0, 0, 10, 0, 10, 10 })
	end)

	t.test("Z closes the subpath", function()
		local cmds = PathData.parse("M 0 0 L 10 0 L 10 10 Z")
		local subpaths = FlattenPath.flatten(cmds, Transform.identity(), 0.25)
		t.expect(subpaths[1].closed).toBeTruthy()
		-- Closing point should be the M endpoint.
		local pts = subpaths[1].points
		t.expect(pts[#pts - 1]).toBe(0)
		t.expect(pts[#pts]).toBe(0)
	end)

	t.test("new M starts a new subpath", function()
		local cmds = PathData.parse("M 0 0 L 10 0 M 50 50 L 60 50")
		local subpaths = FlattenPath.flatten(cmds, Transform.identity(), 0.25)
		t.expect(#subpaths).toBe(2)
		t.expect(subpaths[1].points[1]).toBe(0)
		t.expect(subpaths[2].points[1]).toBe(50)
	end)

	t.test("cubic flattens into many points", function()
		local cmds = PathData.parse("M 0 0 C 0 100 100 100 100 0")
		local subpaths = FlattenPath.flatten(cmds, Transform.identity(), 0.25)
		t.expect(#subpaths).toBe(1)
		t.expect(#subpaths[1].points > 4).toBeTruthy()
	end)

	t.test("arc flattens into many points", function()
		local cmds = PathData.parse("M 0 0 A 50 50 0 1 1 100 0")
		local subpaths = FlattenPath.flatten(cmds, Transform.identity(), 0.25)
		t.expect(#subpaths).toBe(1)
		t.expect(#subpaths[1].points > 6).toBeTruthy()
		-- Final point should be ~(100, 0) (allowing for flattening rounding).
		local pts = subpaths[1].points
		t.expect(near(pts[#pts - 1], 100, 0.1)).toBeTruthy()
		t.expect(near(pts[#pts], 0, 0.1)).toBeTruthy()
	end)

	t.test("transform is applied to all points", function()
		local cmds = PathData.parse("M 0 0 L 10 0")
		local matrix = Transform.parse("translate(5 5) scale(2)")
		local subpaths = FlattenPath.flatten(cmds, matrix, 0.25)
		local pts = subpaths[1].points
		-- (0, 0) -> (5, 5); (10, 0) -> (25, 5)
		t.expect(pts[1]).toBe(5)
		t.expect(pts[2]).toBe(5)
		t.expect(pts[3]).toBe(25)
		t.expect(pts[4]).toBe(5)
	end)

	t.test("H and V emit axis-aligned segments", function()
		local cmds = PathData.parse("M 0 0 H 10 V 10")
		local subpaths = FlattenPath.flatten(cmds, Transform.identity(), 0.25)
		t.expect(subpaths[1].points).toEqual({ 0, 0, 10, 0, 10, 10 })
	end)

	t.test("empty commands -> empty output", function()
		local subpaths = FlattenPath.flatten({}, Transform.identity(), 0.25)
		t.expect(#subpaths).toBe(0)
	end)
end)
