--!strict
-- Regenerates examples/LucideIcons.luau from the SVG files in
-- examples/lucide/. Run with: lune run scripts/bake-lucide.luau

local fs = require("@lune/fs")

local SOURCE_DIR = "examples/lucide"
local OUTPUT = "examples/LucideDemo/LucideIcons.luau"

local entries = fs.readDir(SOURCE_DIR)
local names: { string } = {}
for _, entry in ipairs(entries) do
	if string.sub(entry, -4) == ".svg" then
		table.insert(names, string.sub(entry, 1, -5))
	end
end
table.sort(names)

local lines: { string } = {
	"--!strict",
	"-- 22 Lucide (lucide-icons/lucide) SVG sources, inlined so the demo doesn't",
	"-- need network access at runtime. Regenerate with:",
	"--   lune run scripts/bake-lucide.luau",
	"--",
	"-- Icons are MIT-licensed; see https://github.com/lucide-icons/lucide.",
	"",
	"local LucideIcons = {}",
	"",
	"LucideIcons.names = {",
}
for _, name in ipairs(names) do
	table.insert(lines, string.format('\t"%s",', name))
end
table.insert(lines, "}")
table.insert(lines, "")
table.insert(lines, "LucideIcons.sources = {")
for _, name in ipairs(names) do
	local svg = fs.readFile(SOURCE_DIR .. "/" .. name .. ".svg")
	-- Use a level-1 long bracket; Lucide icons never contain `]==]`.
	table.insert(lines, string.format('\t["%s"] = [==[', name))
	table.insert(lines, svg)
	table.insert(lines, "]==],")
end
table.insert(lines, "}")
table.insert(lines, "")
table.insert(lines, "return LucideIcons")
table.insert(lines, "")

fs.writeFile(OUTPUT, table.concat(lines, "\n"))
print(string.format("Wrote %d icons to %s", #names, OUTPUT))
