--!strict
local Style = require("../../src/Parser/Style")
local t = require("../framework")

t.suite("Style.flatten", function()
	t.test("presentation attributes", function()
		local flat = Style.flatten({ fill = "red", stroke = "blue", id = "skip" })
		t.expect(flat.fill).toBe("red")
		t.expect(flat.stroke).toBe("blue")
		t.expect(flat.id).toBeNil()
	end)

	t.test("inline style wins over presentation attribute", function()
		local flat = Style.flatten({ fill = "red", style = "fill: blue; stroke: green" })
		t.expect(flat.fill).toBe("blue")
		t.expect(flat.stroke).toBe("green")
	end)

	t.test("handles whitespace in declarations", function()
		local flat = Style.flatten({ style = "  fill : red  ;  stroke : blue  " })
		t.expect(flat.fill).toBe("red")
		t.expect(flat.stroke).toBe("blue")
	end)

	t.test("ignores malformed declarations", function()
		local flat = Style.flatten({ style = "fill:red;nope;stroke:blue" })
		t.expect(flat.fill).toBe("red")
		t.expect(flat.stroke).toBe("blue")
	end)
end)

t.suite("Style.inherit", function()
	t.test("inherits parent when no overrides", function()
		local parent = Style.defaults()
		parent.strokeWidth = 5
		local child = Style.inherit(parent, {}, 100)
		t.expect(child.strokeWidth).toBe(5)
	end)

	t.test("fill: url(#id)", function()
		local s = Style.inherit(Style.defaults(), { fill = "url(#grad)" }, 100)
		t.expect(type(s.fill)).toBe("table")
		local paint = s.fill :: any
		t.expect(paint.kind).toBe("url")
		t.expect(paint.id).toBe("grad")
	end)

	t.test("fill: none clears paint", function()
		local s = Style.inherit(Style.defaults(), { fill = "none" }, 100)
		t.expect(s.fill).toBeNil()
	end)

	t.test("currentColor resolves against color property", function()
		local s = Style.inherit(Style.defaults(), { color = "red", fill = "currentColor" }, 100)
		local fill = s.fill :: any
		t.expect(fill[1]).toBe(1)
		t.expect(fill[2]).toBe(0)
		t.expect(fill[3]).toBe(0)
	end)

	t.test("fill-opacity", function()
		local s = Style.inherit(Style.defaults(), { ["fill-opacity"] = "0.5" }, 100)
		t.expect(s.fillOpacity).toBe(0.5)
	end)

	t.test("fill-rule", function()
		local s = Style.inherit(Style.defaults(), { ["fill-rule"] = "evenodd" }, 100)
		t.expect(s.fillRule).toBe("evenodd")
	end)

	t.test("stroke-width with unit", function()
		local s = Style.inherit(Style.defaults(), { ["stroke-width"] = "2px" }, 100)
		t.expect(s.strokeWidth).toBe(2)
	end)

	t.test("stroke-dasharray doubles odd-length arrays", function()
		local s = Style.inherit(Style.defaults(), { ["stroke-dasharray"] = "5 2 1" }, 100)
		t.expect(s.strokeDasharray).toEqual({ 5, 2, 1, 5, 2, 1 })
	end)

	t.test("stroke-dasharray none", function()
		local parent = Style.defaults()
		parent.strokeDasharray = { 5, 2 }
		local s = Style.inherit(parent, { ["stroke-dasharray"] = "none" }, 100)
		t.expect(s.strokeDasharray).toBeNil()
	end)

	t.test("display: none", function()
		local s = Style.inherit(Style.defaults(), { display = "none" }, 100)
		t.expect(s.display).toBeFalsy()
	end)

	t.test("clip-path url", function()
		local s = Style.inherit(Style.defaults(), { ["clip-path"] = "url(#myclip)" }, 100)
		t.expect(s.clipPath).toBe("myclip")
	end)
end)
