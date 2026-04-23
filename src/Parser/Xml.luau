--!strict
--[=[
	@class Xml
	@private

	Minimal, dependency-free XML 1.0 parser tailored for SVG documents.

	Scope and non-goals:
	- Well-formed XML: element nesting is validated; mismatched closing tags
	  raise an error.
	- Entities: the five predefined entities (`&amp; &lt; &gt; &quot; &apos;`)
	  plus decimal (`&#123;`) and hexadecimal (`&#xFF;`) character references.
	  External and user-defined entities are not supported.
	- Namespaces: attribute names are preserved verbatim (e.g. `xlink:href`);
	  Glyph resolves known prefixes at the SVG layer rather than here.
	- CDATA sections are parsed and returned as literal text. Comments and
	  processing instructions are skipped. DOCTYPE is tolerated and skipped.
	- No DTD validation, no schema, no entity resolution beyond predefined.

	The parser returns a lightweight tree of `XmlElement` nodes with
	attribute tables and ordered children (elements interleaved with text).
]=]

local Xml = {}

export type XmlText = {
	kind: "text",
	value: string,
}

export type XmlElement = {
	kind: "element",
	name: string,
	attributes: { [string]: string },
	attributeOrder: { string },
	children: { XmlNode },
}

export type XmlNode = XmlText | XmlElement

local CHAR_AMP = 0x26
local CHAR_LT = 0x3C
local CHAR_GT = 0x3E
local CHAR_SLASH = 0x2F
local CHAR_QUESTION = 0x3F
local CHAR_BANG = 0x21
local CHAR_DASH = 0x2D
local CHAR_LBRACKET = 0x5B
local CHAR_EQ = 0x3D
local CHAR_QUOTE = 0x22
local CHAR_APOS = 0x27
local CHAR_SPACE = 0x20
local CHAR_TAB = 0x09
local CHAR_LF = 0x0A
local CHAR_CR = 0x0D

local function isWhitespace(b: number): boolean
	return b == CHAR_SPACE or b == CHAR_TAB or b == CHAR_LF or b == CHAR_CR
end

-- XML 1.0 NameStartChar and NameChar: https://www.w3.org/TR/xml/#NT-NameStartChar
-- We support ASCII letters/digits, `_`, `-`, `.`, `:` which covers all of SVG in
-- practice. Full Unicode categories are intentionally omitted.
local function isNameStart(b: number): boolean
	return (b >= 0x41 and b <= 0x5A) -- A-Z
		or (b >= 0x61 and b <= 0x7A) -- a-z
		or b == 0x5F -- _
		or b == 0x3A -- :
end

local function isNameChar(b: number): boolean
	return isNameStart(b)
		or (b >= 0x30 and b <= 0x39) -- 0-9
		or b == 0x2D -- -
		or b == 0x2E -- .
end

type Cursor = {
	source: string,
	pos: number, -- 1-based, next byte to read
	length: number,
}

local function peek(cur: Cursor): number
	return string.byte(cur.source, cur.pos) or -1
end

local function peekAt(cur: Cursor, offset: number): number
	return string.byte(cur.source, cur.pos + offset) or -1
end

local function startsWith(cur: Cursor, literal: string): boolean
	return string.sub(cur.source, cur.pos, cur.pos + #literal - 1) == literal
end

local function lineColumn(cur: Cursor, position: number): (number, number)
	local line = 1
	local lineStart = 1
	local i = 1
	while i < position do
		local b = string.byte(cur.source, i)
		if b == CHAR_LF then
			line += 1
			lineStart = i + 1
		end
		i += 1
	end
	return line, position - lineStart + 1
end

local function fail(cur: Cursor, position: number, message: string): any
	local line, column = lineColumn(cur, position)
	error(string.format("XML parse error at line %d, column %d: %s", line, column, message), 0)
	return nil -- unreachable; Luau flow analysis requires this return
end

local function skipWhitespace(cur: Cursor)
	while cur.pos <= cur.length and isWhitespace(peek(cur)) do
		cur.pos += 1
	end
end

local function expectChar(cur: Cursor, char: number, label: string)
	if peek(cur) ~= char then
		fail(cur, cur.pos, "expected " .. label)
	end
	cur.pos += 1
end

local function readName(cur: Cursor): string
	local start = cur.pos
	if cur.pos > cur.length or not isNameStart(peek(cur)) then
		fail(cur, cur.pos, "expected name")
	end
	cur.pos += 1
	while cur.pos <= cur.length and isNameChar(peek(cur)) do
		cur.pos += 1
	end
	return string.sub(cur.source, start, cur.pos - 1)
end

local DECIMAL_REF = "^#(%d+);"
local HEX_REF = "^#[xX](%x+);"
local NAMED_REF = "^(%a+);"

local namedEntities: { [string]: string } = {
	amp = "&",
	lt = "<",
	gt = ">",
	quot = '"',
	apos = "'",
}

-- Decodes an entity starting at `cur.pos` (the ampersand has NOT yet been
-- consumed). Advances the cursor past the terminating `;`.
local function decodeEntity(cur: Cursor): string
	local ampPos = cur.pos
	cur.pos += 1 -- consume &
	local rest = string.sub(cur.source, cur.pos)
	local body = string.match(rest, DECIMAL_REF)
	if body then
		local code = tonumber(body)
		if not code then
			fail(cur, ampPos, "invalid decimal character reference")
		end
		cur.pos += #body + 2 -- '#' + digits + ';'
		return utf8.char(code :: number)
	end
	body = string.match(rest, HEX_REF)
	if body then
		local code = tonumber(body, 16)
		if not code then
			fail(cur, ampPos, "invalid hex character reference")
		end
		cur.pos += #body + 3 -- '#' + 'x' + digits + ';'
		return utf8.char(code :: number)
	end
	body = string.match(rest, NAMED_REF)
	if body then
		local resolved = namedEntities[body]
		if not resolved then
			fail(cur, ampPos, "unknown entity '&" .. body .. ";'")
		end
		cur.pos += #body + 1 -- name + ';'
		return resolved :: string
	end
	fail(cur, ampPos, "malformed entity reference")
	return "" -- unreachable
end

local function readAttributeValue(cur: Cursor): string
	local quote = peek(cur)
	if quote ~= CHAR_QUOTE and quote ~= CHAR_APOS then
		fail(cur, cur.pos, "expected quoted attribute value")
	end
	cur.pos += 1
	local buffer = {}
	while cur.pos <= cur.length do
		local b = peek(cur)
		if b == quote then
			cur.pos += 1
			return table.concat(buffer)
		elseif b == CHAR_LT then
			fail(cur, cur.pos, "'<' not allowed in attribute value")
		elseif b == CHAR_AMP then
			table.insert(buffer, decodeEntity(cur))
		else
			-- Grab a literal run in one slice for speed.
			local start = cur.pos
			while cur.pos <= cur.length do
				local bb = peek(cur)
				if bb == quote or bb == CHAR_LT or bb == CHAR_AMP then
					break
				end
				cur.pos += 1
			end
			table.insert(buffer, string.sub(cur.source, start, cur.pos - 1))
		end
	end
	fail(cur, cur.pos, "unterminated attribute value")
	return ""
end

-- Skip `<!-- ... -->`. Caller has already consumed `<!--`.
local function skipComment(cur: Cursor)
	while cur.pos <= cur.length do
		if peek(cur) == CHAR_DASH and peekAt(cur, 1) == CHAR_DASH then
			if peekAt(cur, 2) == CHAR_GT then
				cur.pos += 3
				return
			end
			fail(cur, cur.pos, "'--' not allowed inside comment")
		end
		cur.pos += 1
	end
	fail(cur, cur.pos, "unterminated comment")
end

-- Skip `<?...?>`. Caller has already consumed `<?`.
local function skipProcessingInstruction(cur: Cursor)
	while cur.pos <= cur.length do
		if peek(cur) == CHAR_QUESTION and peekAt(cur, 1) == CHAR_GT then
			cur.pos += 2
			return
		end
		cur.pos += 1
	end
	fail(cur, cur.pos, "unterminated processing instruction")
end

-- Skip a DOCTYPE declaration. Caller has already consumed `<!DOCTYPE`.
-- Handles nested `[ ... ]` internal subset.
local function skipDoctype(cur: Cursor)
	local depth = 0
	while cur.pos <= cur.length do
		local b = peek(cur)
		if b == CHAR_LBRACKET then
			depth += 1
		elseif b == 0x5D then -- ']'
			depth -= 1
		elseif b == CHAR_GT and depth <= 0 then
			cur.pos += 1
			return
		end
		cur.pos += 1
	end
	fail(cur, cur.pos, "unterminated DOCTYPE")
end

-- Returns raw CDATA content. Caller has already consumed `<![CDATA[`.
local function readCData(cur: Cursor): string
	local start = cur.pos
	while cur.pos <= cur.length do
		if startsWith(cur, "]]>") then
			local value = string.sub(cur.source, start, cur.pos - 1)
			cur.pos += 3
			return value
		end
		cur.pos += 1
	end
	fail(cur, cur.pos, "unterminated CDATA section")
	return ""
end

-- Parse attributes inside a start tag. Cursor is at the first byte after the
-- tag name. Returns an `attributes` map and the attribute order.
local function readAttributes(cur: Cursor): ({ [string]: string }, { string })
	local attrs: { [string]: string } = {}
	local order: { string } = {}
	while true do
		skipWhitespace(cur)
		local b = peek(cur)
		if b == CHAR_GT or b == CHAR_SLASH then
			return attrs, order
		end
		if cur.pos > cur.length then
			fail(cur, cur.pos, "unterminated start tag")
		end
		local name = readName(cur)
		skipWhitespace(cur)
		expectChar(cur, CHAR_EQ, "'=' after attribute name")
		skipWhitespace(cur)
		local value = readAttributeValue(cur)
		if attrs[name] ~= nil then
			fail(cur, cur.pos, "duplicate attribute '" .. name .. "'")
		end
		attrs[name] = value
		table.insert(order, name)
	end
end

-- Read the text run that terminates at the next `<` or end-of-input. Decodes
-- entities. Returns the empty string if there is no text.
local function readText(cur: Cursor): string
	local buffer: { string } = {}
	while cur.pos <= cur.length do
		local b = peek(cur)
		if b == CHAR_LT then
			break
		elseif b == CHAR_AMP then
			table.insert(buffer, decodeEntity(cur))
		else
			local start = cur.pos
			while cur.pos <= cur.length do
				local bb = peek(cur)
				if bb == CHAR_LT or bb == CHAR_AMP then
					break
				end
				cur.pos += 1
			end
			table.insert(buffer, string.sub(cur.source, start, cur.pos - 1))
		end
	end
	return table.concat(buffer)
end

local parseElement: (cur: Cursor) -> XmlElement

-- Called when cursor is at `<`. Dispatches to comment / PI / CDATA / DOCTYPE /
-- element / end-tag marker based on the next bytes. Returns either an element
-- node, a sentinel `"endtag"` string (with the end-tag name), or `nil` if the
-- construct was skipped (comment / PI / DOCTYPE).
local function parseMarkup(cur: Cursor): (XmlElement?, string?)
	assert(peek(cur) == CHAR_LT, "parseMarkup called off '<'")
	local next1 = peekAt(cur, 1)
	if next1 == CHAR_BANG then
		-- <!-- comment -->  or  <![CDATA[ ... ]]>  or  <!DOCTYPE ...>
		if peekAt(cur, 2) == CHAR_DASH and peekAt(cur, 3) == CHAR_DASH then
			cur.pos += 4
			skipComment(cur)
			return nil, nil
		elseif startsWith(cur, "<![CDATA[") then
			-- CDATA is not valid at the root between elements; callers that support
			-- it (text content of an element) consume it inline, so bail.
			fail(cur, cur.pos, "unexpected CDATA outside element content")
			return nil, nil
		elseif startsWith(cur, "<!DOCTYPE") then
			cur.pos += 9
			skipDoctype(cur)
			return nil, nil
		else
			fail(cur, cur.pos, "unknown '<!' construct")
			return nil, nil
		end
	elseif next1 == CHAR_QUESTION then
		cur.pos += 2
		skipProcessingInstruction(cur)
		return nil, nil
	elseif next1 == CHAR_SLASH then
		-- End tag: </Name>
		cur.pos += 2
		local name = readName(cur)
		skipWhitespace(cur)
		expectChar(cur, CHAR_GT, "'>' to close end tag")
		return nil, name
	else
		return parseElement(cur), nil
	end
end

function parseElement(cur: Cursor): XmlElement
	expectChar(cur, CHAR_LT, "'<'")
	local name = readName(cur)
	local attrs, order = readAttributes(cur)
	skipWhitespace(cur)
	local element: XmlElement = {
		kind = "element",
		name = name,
		attributes = attrs,
		attributeOrder = order,
		children = {},
	}
	local b = peek(cur)
	if b == CHAR_SLASH then
		cur.pos += 1
		expectChar(cur, CHAR_GT, "'>' to close self-closing tag")
		return element
	end
	expectChar(cur, CHAR_GT, "'>' to end start tag")

	-- Content: mix of text, elements, comments, PIs, and CDATA.
	while cur.pos <= cur.length do
		local c = peek(cur)
		if c == CHAR_LT then
			-- CDATA is the only `<!`-construct allowed inside element content.
			if startsWith(cur, "<![CDATA[") then
				cur.pos += 9
				local value = readCData(cur)
				if #value > 0 then
					table.insert(element.children, { kind = "text", value = value } :: XmlText)
				end
			else
				local child, endName = parseMarkup(cur)
				if endName then
					if endName ~= name then
						fail(
							cur,
							cur.pos,
							"mismatched end tag: expected '" .. name .. "', got '" .. endName .. "'"
						)
					end
					return element
				end
				if child then
					table.insert(element.children, child)
				end
			end
		else
			local text = readText(cur)
			if #text > 0 then
				table.insert(element.children, { kind = "text", value = text } :: XmlText)
			end
		end
	end
	fail(cur, cur.pos, "unterminated element '" .. name .. "'")
	return element
end

--[=[
	Parses an XML document and returns its root element. Raises an error if the
	input is not well-formed.

	@within Xml
	@param source string
	@return XmlElement
]=]
function Xml.parse(source: string): XmlElement
	local cur: Cursor = {
		source = source,
		pos = 1,
		length = #source,
	}
	-- Skip prolog: BOM, whitespace, XML declaration, DOCTYPE, comments, PIs.
	-- BOM (EF BB BF)
	if
		string.byte(source, 1) == 0xEF
		and string.byte(source, 2) == 0xBB
		and string.byte(source, 3) == 0xBF
	then
		cur.pos = 4
	end
	while cur.pos <= cur.length do
		skipWhitespace(cur)
		if cur.pos > cur.length then
			break
		end
		if peek(cur) ~= CHAR_LT then
			fail(cur, cur.pos, "unexpected content before root element")
		end
		local next1 = peekAt(cur, 1)
		if next1 == CHAR_QUESTION or next1 == CHAR_BANG then
			-- PI / comment / DOCTYPE — discard.
			local child, endName = parseMarkup(cur)
			assert(child == nil and endName == nil, "prolog should not emit nodes")
		else
			local root = parseElement(cur)
			skipWhitespace(cur)
			-- Trailing comments / PIs are allowed per XML 1.0 but extremely rare.
			while cur.pos <= cur.length and peek(cur) == CHAR_LT do
				local child, endName = parseMarkup(cur)
				if child or endName then
					fail(cur, cur.pos, "unexpected content after root element")
				end
				skipWhitespace(cur)
			end
			if cur.pos <= cur.length then
				fail(cur, cur.pos, "unexpected content after root element")
			end
			return root
		end
	end
	fail(cur, cur.pos, "missing root element")
	return nil :: any
end

return Xml
