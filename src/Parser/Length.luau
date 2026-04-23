--!strict
--[=[
	@class Length
	@private

	Parses SVG length values. SVG lengths accept an optional unit suffix; in
	rendering contexts where the user coordinate system is the reference, we
	convert to user units assuming 96 DPI (the CSS reference pixel).

	Supported units: `px`, `pt`, `pc`, `mm`, `cm`, `in`, and unitless (user
	units). Percentages are preserved as a distinct tagged value because their
	meaning depends on the attribute they come from.
]=]

local Length = {}

-- Conversion factors to user units at 96 DPI.
local TO_USER_UNITS: { [string]: number } = {
	[""] = 1,
	px = 1,
	pt = 96 / 72,
	pc = 96 / 6,
	mm = 96 / 25.4,
	cm = 96 / 2.54,
	["in"] = 96,
}

export type Length = number | { kind: "percent", value: number }

local NUMBER_PATTERN = "^%s*([+-]?[0-9.eE+-]+)%s*([%a%%]*)%s*$"

--[=[
	@within Length
	Parses a length string, returning either a user-unit `number` or a
	`{ kind = "percent", value = … }` table. Raises if the input is malformed.
]=]
function Length.parse(input: string): Length
	local number, unit = string.match(input, NUMBER_PATTERN)
	if not number then
		error("invalid length '" .. input .. "'", 0)
	end
	local n = tonumber(number)
	if not n then
		error("invalid length '" .. input .. "'", 0)
	end
	if unit == "%" then
		return { kind = "percent", value = n :: number }
	end
	local factor = TO_USER_UNITS[(unit :: string):lower()]
	if not factor then
		error("unknown length unit '" .. (unit :: string) .. "'", 0)
	end
	return (n :: number) * factor
end

--[=[
	@within Length
	Resolves a length to user units. Percentages are scaled by the supplied
	reference value.
]=]
function Length.resolve(length: Length, reference: number): number
	if type(length) == "number" then
		return length
	end
	return length.value / 100 * reference
end

--[=[
	@within Length
	Returns true if the length is a percentage value.
]=]
function Length.isPercent(length: Length): boolean
	return type(length) == "table"
end

return Length
