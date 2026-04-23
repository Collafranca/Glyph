--!strict
local Xml = require("../../src/Parser/Xml")
local t = require("../framework")

t.suite("Xml.parse", function()
	t.test("parses a single empty element", function()
		local root = Xml.parse("<svg/>")
		t.expect(root.kind).toBe("element")
		t.expect(root.name).toBe("svg")
		t.expect(#root.children).toBe(0)
		t.expect(#root.attributeOrder).toBe(0)
	end)

	t.test("parses a single element with text", function()
		local root = Xml.parse("<g>hello</g>")
		t.expect(root.name).toBe("g")
		t.expect(#root.children).toBe(1)
		local child = root.children[1]
		t.expect(child.kind).toBe("text")
		t.expect((child :: any).value).toBe("hello")
	end)

	t.test("parses attributes with both quote styles", function()
		local root = Xml.parse([[<rect x="10" y='20' width="30"/>]])
		t.expect(root.attributes.x).toBe("10")
		t.expect(root.attributes.y).toBe("20")
		t.expect(root.attributes.width).toBe("30")
		t.expect(root.attributeOrder).toEqual({ "x", "y", "width" })
	end)

	t.test("parses nested elements", function()
		local root = Xml.parse([[<svg><g><rect/></g></svg>]])
		t.expect(root.name).toBe("svg")
		t.expect(#root.children).toBe(1)
		local g = root.children[1] :: any
		t.expect(g.name).toBe("g")
		t.expect(#g.children).toBe(1)
		t.expect(g.children[1].name).toBe("rect")
	end)

	t.test("mixes text and elements in order", function()
		local root = Xml.parse("<p>hello <b>bold</b> world</p>")
		t.expect(#root.children).toBe(3)
		t.expect((root.children[1] :: any).value).toBe("hello ")
		t.expect((root.children[2] :: any).name).toBe("b")
		t.expect((root.children[3] :: any).value).toBe(" world")
	end)

	t.test("decodes predefined entities", function()
		local root = Xml.parse([[<t attr="&amp;&lt;&gt;&quot;&apos;">&amp;&lt;&gt;</t>]])
		t.expect(root.attributes.attr).toBe([[&<>"']])
		t.expect((root.children[1] :: any).value).toBe("&<>")
	end)

	t.test("decodes numeric character references", function()
		local root = Xml.parse([[<t>&#65;&#x41;&#x2665;</t>]])
		local value = (root.children[1] :: any).value
		-- A A heart
		t.expect(string.sub(value, 1, 2)).toBe("AA")
		t.expect(#value > 2).toBeTruthy()
	end)

	t.test("preserves colons in names (namespaces)", function()
		local root = Xml.parse([[<svg xmlns:xlink="x"><use xlink:href="#a"/></svg>]])
		t.expect(root.attributes["xmlns:xlink"]).toBe("x")
		local use = root.children[1] :: any
		t.expect(use.name).toBe("use")
		t.expect(use.attributes["xlink:href"]).toBe("#a")
	end)

	t.test("handles self-closing and separate-closing tags equivalently", function()
		local a = Xml.parse("<r/>")
		local b = Xml.parse("<r></r>")
		t.expect(a.name).toBe(b.name)
		t.expect(#a.children).toBe(#b.children)
	end)

	t.test("skips XML declaration", function()
		local root = Xml.parse([[<?xml version="1.0" encoding="UTF-8"?><svg/>]])
		t.expect(root.name).toBe("svg")
	end)

	t.test("skips comments", function()
		local root = Xml.parse([[<!-- hi --><svg><!-- inside --><g/></svg>]])
		t.expect(root.name).toBe("svg")
		t.expect(#root.children).toBe(1)
		t.expect((root.children[1] :: any).name).toBe("g")
	end)

	t.test("handles CDATA as literal text", function()
		local source = "<s><![CDATA[<not>&parsed;</not>]]></s>"
		local root = Xml.parse(source)
		t.expect(#root.children).toBe(1)
		t.expect((root.children[1] :: any).value).toBe("<not>&parsed;</not>")
	end)

	t.test("skips DOCTYPE", function()
		local root = Xml.parse([[<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "x.dtd"><svg/>]])
		t.expect(root.name).toBe("svg")
	end)

	t.test("handles BOM", function()
		local root = Xml.parse("\239\187\191<svg/>")
		t.expect(root.name).toBe("svg")
	end)

	t.test("handles whitespace-only text", function()
		local root = Xml.parse("<g>\n  \n</g>")
		t.expect(#root.children).toBe(1)
		t.expect((root.children[1] :: any).value).toBe("\n  \n")
	end)

	t.test("parses multiple nested siblings preserving order", function()
		local root = Xml.parse([[<svg><rect/><circle/><path d="M0 0"/></svg>]])
		t.expect(#root.children).toBe(3)
		t.expect((root.children[1] :: any).name).toBe("rect")
		t.expect((root.children[2] :: any).name).toBe("circle")
		t.expect((root.children[3] :: any).name).toBe("path")
		t.expect((root.children[3] :: any).attributes.d).toBe("M0 0")
	end)

	t.test("rejects mismatched closing tag", function()
		t.expect(function()
			Xml.parse("<a></b>")
		end).toThrow("mismatched end tag")
	end)

	t.test("rejects unterminated element", function()
		t.expect(function()
			Xml.parse("<a><b></a>")
		end).toThrow("mismatched end tag")
	end)

	t.test("rejects unterminated start tag", function()
		t.expect(function()
			Xml.parse("<a")
		end).toThrow()
	end)

	t.test("rejects duplicate attribute", function()
		t.expect(function()
			Xml.parse([[<a x="1" x="2"/>]])
		end).toThrow("duplicate attribute")
	end)

	t.test("rejects '<' inside attribute value", function()
		t.expect(function()
			Xml.parse([[<a x="b<c"/>]])
		end).toThrow("not allowed in attribute value")
	end)

	t.test("rejects unknown entity", function()
		t.expect(function()
			Xml.parse([[<a>&bogus;</a>]])
		end).toThrow("unknown entity")
	end)

	t.test("rejects missing root element", function()
		t.expect(function()
			Xml.parse("<!-- just a comment -->")
		end).toThrow("missing root element")
	end)

	t.test("error message includes line and column", function()
		local ok, err = pcall(function()
			Xml.parse("<a>\n<b>\n</c>")
		end)
		t.expect(ok).toBeFalsy()
		t.expect(tostring(err)).toMatch("line 3")
	end)

	t.test("parses an SVG-flavoured document", function()
		local source = [[<?xml version="1.0" encoding="UTF-8"?>
<!-- an icon -->
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
    <path d="M12 2 L22 22 L2 22 Z" fill="#ff0000" stroke-width="2"/>
    <circle cx="12" cy="12" r="5"/>
</svg>]]
		local root = Xml.parse(source)
		t.expect(root.name).toBe("svg")
		t.expect(root.attributes.viewBox).toBe("0 0 24 24")
		-- Whitespace text nodes between elements are preserved; filter for elements.
		local elementChildren = 0
		for _, c in ipairs(root.children) do
			if c.kind == "element" then
				elementChildren += 1
			end
		end
		t.expect(elementChildren).toBe(2)
	end)
end)
