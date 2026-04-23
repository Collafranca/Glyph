--!strict
local Arc = require("../../src/Flatten/Arc")
local t = require("../framework")

local function near(a: number, b: number, tol: number?): boolean
	return math.abs(a - b) < (tol or 1e-6)
end

t.suite("Arc.toCenter", function()
	t.test("returns nil when start equals end", function()
		t.expect(Arc.toCenter(10, 10, 5, 5, 0, 0, 1, 10, 10)).toBeNil()
	end)

	t.test("returns nil when a radius is zero", function()
		t.expect(Arc.toCenter(0, 0, 0, 5, 0, 0, 1, 10, 0)).toBeNil()
		t.expect(Arc.toCenter(0, 0, 5, 0, 0, 0, 1, 10, 0)).toBeNil()
	end)

	t.test("unit semicircle: rx=ry=1 from (-1,0) to (1,0)", function()
		local seg = Arc.toCenter(-1, 0, 1, 1, 0, 0, 1, 1, 0) :: Arc.Segment
		t.expect(near(seg.cx, 0)).toBeTruthy()
		t.expect(near(seg.cy, 0)).toBeTruthy()
		t.expect(near(seg.rx, 1)).toBeTruthy()
		t.expect(near(seg.ry, 1)).toBeTruthy()
		-- sweep flag = 1 (clockwise in SVG's y-down space) -> +pi sweep
		t.expect(near(math.abs(seg.deltaTheta), math.pi)).toBeTruthy()
	end)

	t.test("scales up radii when too small (F.6.6)", function()
		-- Radii (5, 5) can't reach from (0,0) to (100, 0) — should scale up.
		local seg = Arc.toCenter(0, 0, 5, 5, 0, 0, 1, 100, 0) :: Arc.Segment
		-- After correction, rx should be at least 50 (half the chord).
		t.expect(seg.rx >= 50 - 1e-6).toBeTruthy()
		t.expect(near(seg.rx, seg.ry)).toBeTruthy()
	end)

	t.test("sweepFlag controls direction", function()
		local cw = Arc.toCenter(-1, 0, 1, 1, 0, 0, 1, 1, 0) :: Arc.Segment
		local ccw = Arc.toCenter(-1, 0, 1, 1, 0, 0, 0, 1, 0) :: Arc.Segment
		-- Both halves of the unit circle; their delta signs differ.
		t.expect(cw.deltaTheta * ccw.deltaTheta < 0).toBeTruthy()
	end)

	t.test("largeArc picks major vs minor sweep", function()
		local small = Arc.toCenter(0, 1, 1, 1, 0, 0, 1, 1, 0) :: Arc.Segment
		local large = Arc.toCenter(0, 1, 1, 1, 0, 1, 1, 1, 0) :: Arc.Segment
		t.expect(math.abs(small.deltaTheta) < math.abs(large.deltaTheta)).toBeTruthy()
	end)
end)

t.suite("Arc.toCubics", function()
	t.test("semicircle produces 2 cubics (90-degree slices)", function()
		local seg = Arc.toCenter(-1, 0, 1, 1, 0, 0, 1, 1, 0) :: Arc.Segment
		local cubics = Arc.toCubics(seg)
		-- 6 coords per cubic.
		t.expect(#cubics / 6).toBe(2)
	end)

	t.test("cubic endpoints lie on the ellipse", function()
		local seg = Arc.toCenter(-10, 0, 10, 10, 0, 0, 1, 10, 0) :: Arc.Segment
		local cubics = Arc.toCubics(seg)
		for i = 5, #cubics, 6 do
			local x = cubics[i]
			local y = cubics[i + 1]
			local dist = math.sqrt(x * x + y * y)
			t.expect(near(dist, 10, 1e-3)).toBeTruthy()
		end
	end)

	t.test("full circle produces 4 cubics", function()
		local seg = {
			cx = 0,
			cy = 0,
			rx = 10,
			ry = 10,
			phi = 0,
			theta1 = 0,
			deltaTheta = 2 * math.pi,
		}
		local cubics = Arc.toCubics(seg)
		t.expect(#cubics / 6).toBe(4)
	end)
end)
