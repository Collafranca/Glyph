--!strict
local Svg = require("../../src/Parser/Svg")
local t = require("../framework")

t.suite("Svg.parse — basics", function()
	t.test("rejects non-svg root", function()
		t.expect(function()
			Svg.parse("<foo/>")
		end).toThrow("root element must be <svg>")
	end)

	t.test("parses viewBox", function()
		local doc = Svg.parse([[<svg viewBox="0 0 100 50"/>]])
		t.expect(doc.viewport.viewMinX).toBe(0)
		t.expect(doc.viewport.viewMinY).toBe(0)
		t.expect(doc.viewport.viewWidth).toBe(100)
		t.expect(doc.viewport.viewHeight).toBe(50)
	end)

	t.test("parses width/height", function()
		local doc = Svg.parse([[<svg width="200" height="100"/>]])
		t.expect(doc.viewport.width).toBe(200)
		t.expect(doc.viewport.height).toBe(100)
	end)

	t.test("width/height fall back to defaults", function()
		local doc = Svg.parse([[<svg/>]])
		t.expect(doc.viewport.width).toBe(300)
		t.expect(doc.viewport.height).toBe(150)
	end)
end)

t.suite("Svg.parse — shapes", function()
	t.test("rect lowers to path commands", function()
		local doc =
			Svg.parse([[<svg><rect x="10" y="20" width="30" height="40" fill="red"/></svg>]])
		t.expect(#doc.shapes).toBe(1)
		local shape = doc.shapes[1]
		t.expect(shape.kind).toBe("path")
		t.expect(shape.commands[1][1]).toBe("M")
		t.expect(shape.commands[1][2]).toBe(10)
		t.expect(shape.commands[1][3]).toBe(20)
		local fill = shape.style.fill :: any
		t.expect(fill[1]).toBe(1)
	end)

	t.test("rect with rx emits arcs", function()
		local doc = Svg.parse([[<svg><rect width="20" height="20" rx="4"/></svg>]])
		local shape = doc.shapes[1]
		local hasArc = false
		for _, cmd in ipairs(shape.commands) do
			if cmd[1] == "A" then
				hasArc = true
				break
			end
		end
		t.expect(hasArc).toBeTruthy()
	end)

	t.test("circle lowers to arcs", function()
		local doc = Svg.parse([[<svg><circle cx="5" cy="5" r="3"/></svg>]])
		t.expect(#doc.shapes).toBe(1)
		local shape = doc.shapes[1]
		local arcCount = 0
		for _, cmd in ipairs(shape.commands) do
			if cmd[1] == "A" then
				arcCount += 1
			end
		end
		t.expect(arcCount).toBe(2)
	end)

	t.test("polyline open, polygon closed", function()
		local doc = Svg.parse([[<svg>
			<polyline points="0,0 10,0 10,10"/>
			<polygon points="0,0 10,0 10,10"/>
		</svg>]])
		t.expect(#doc.shapes).toBe(2)
		local polyline = doc.shapes[1]
		local polygon = doc.shapes[2]
		-- polygon ends with Z, polyline does not.
		t.expect(polyline.commands[#polyline.commands][1]).toBe("L")
		t.expect(polygon.commands[#polygon.commands][1]).toBe("Z")
	end)

	t.test("line", function()
		local doc = Svg.parse([[<svg><line x1="0" y1="0" x2="10" y2="10"/></svg>]])
		t.expect(#doc.shapes).toBe(1)
		local shape = doc.shapes[1]
		t.expect(shape.commands[1][1]).toBe("M")
		t.expect(shape.commands[2][1]).toBe("L")
	end)

	t.test("ellipse", function()
		local doc = Svg.parse([[<svg><ellipse cx="0" cy="0" rx="10" ry="5"/></svg>]])
		t.expect(#doc.shapes).toBe(1)
		t.expect(doc.shapes[1].commands[2][1]).toBe("A")
	end)

	t.test("display: none skips shape", function()
		local doc = Svg.parse([[<svg><rect width="10" height="10" display="none"/></svg>]])
		t.expect(#doc.shapes).toBe(0)
	end)
end)

t.suite("Svg.parse — groups and transforms", function()
	t.test("g inherits style to children", function()
		local doc = Svg.parse([[<svg><g fill="red"><rect width="10" height="10"/></g></svg>]])
		t.expect(#doc.shapes).toBe(1)
		local fill = doc.shapes[1].style.fill :: any
		t.expect(fill[1]).toBe(1)
	end)

	t.test("nested transforms compose", function()
		local doc = Svg.parse(
			[[<svg><g transform="translate(5 0)"><rect x="0" y="0" width="1" height="1" transform="translate(3 0)"/></g></svg>]]
		)
		local m = doc.shapes[1].matrix
		t.expect(m[5]).toBe(8)
		t.expect(m[6]).toBe(0)
	end)
end)

t.suite("Svg.parse — gradients", function()
	t.test("linearGradient collected by id", function()
		local doc = Svg.parse([[<svg>
			<defs>
				<linearGradient id="g" x1="0" y1="0" x2="1" y2="0">
					<stop offset="0" stop-color="red"/>
					<stop offset="1" stop-color="blue"/>
				</linearGradient>
			</defs>
			<rect width="10" height="10" fill="url(#g)"/>
		</svg>]])
		t.expect(doc.gradients.g).toBeTruthy()
		local grad = doc.gradients.g :: any
		t.expect(grad.kind).toBe("linear")
		t.expect(#grad.stops).toBe(2)
		t.expect(grad.stops[1].color[1]).toBe(1) -- red
		t.expect(grad.stops[2].color[3]).toBe(1) -- blue
	end)

	t.test("fill via url() preserves id in shape style", function()
		local doc = Svg.parse([[<svg>
			<defs><linearGradient id="g"/></defs>
			<rect width="10" height="10" fill="url(#g)"/>
		</svg>]])
		local paint = doc.shapes[1].style.fill :: any
		t.expect(paint.kind).toBe("url")
		t.expect(paint.id).toBe("g")
	end)

	t.test("stop-opacity via style attribute", function()
		local doc = Svg.parse([[<svg>
			<linearGradient id="g">
				<stop offset="0" stop-color="red" style="stop-opacity: 0.25"/>
			</linearGradient>
		</svg>]])
		local grad = doc.gradients.g :: any
		t.expect(grad.stops[1].opacity).toBe(0.25)
	end)

	t.test("radialGradient defaults", function()
		local doc = Svg.parse([[<svg>
			<radialGradient id="r">
				<stop offset="0" stop-color="white"/>
				<stop offset="1" stop-color="black"/>
			</radialGradient>
		</svg>]])
		local grad = doc.gradients.r :: any
		t.expect(grad.kind).toBe("radial")
		t.expect(#grad.stops).toBe(2)
	end)
end)

t.suite("Svg.parse — clipPath + use", function()
	t.test("clipPath collects its shapes and ids them", function()
		local doc = Svg.parse([[<svg>
			<defs>
				<clipPath id="clip"><rect width="10" height="10"/></clipPath>
			</defs>
			<circle cx="5" cy="5" r="3" clip-path="url(#clip)"/>
		</svg>]])
		t.expect(doc.clipPaths.clip).toBeTruthy()
		t.expect(#doc.clipPaths.clip.shapes).toBe(1)
		t.expect(doc.shapes[1].style.clipPath).toBe("clip")
	end)

	t.test("use instantiates a defs element with translation", function()
		local doc = Svg.parse([[<svg>
			<defs><rect id="r" width="10" height="10"/></defs>
			<use href="#r" x="50" y="20"/>
		</svg>]])
		t.expect(#doc.shapes).toBe(1)
		local m = doc.shapes[1].matrix
		t.expect(m[5]).toBe(50)
		t.expect(m[6]).toBe(20)
	end)
end)

t.suite("Svg.parse — real icon", function()
	t.test("parses a realistic icon", function()
		local doc = Svg.parse([[<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
	<path d="M12 2v4"/>
	<path d="M12 18v4"/>
	<path d="M4.93 4.93l2.83 2.83"/>
	<path d="M16.24 16.24l2.83 2.83"/>
	<circle cx="12" cy="12" r="5"/>
</svg>]])
		t.expect(doc.viewport.viewWidth).toBe(24)
		t.expect(#doc.shapes).toBe(5)
		-- All shapes should inherit stroke from the root.
		for _, shape in ipairs(doc.shapes) do
			t.expect(shape.style.strokeWidth).toBe(2)
			t.expect(shape.style.strokeLinecap).toBe("round")
		end
		-- Fill should be none, stroke resolved from currentColor -> black (default)
		t.expect(doc.shapes[1].style.fill).toBeNil()
	end)
end)
