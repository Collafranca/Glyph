--!strict
--[=[
	@class Glyph

	Runtime SVG renderer for Roblox.

	```lua
	local Glyph = require(ReplicatedStorage.Glyph)
	local handle = Glyph.render(svg, { parent = imageLabel })
	```
]=]

local Glyph = {}

Glyph._VERSION = "0.1.0"

--[=[
	@within Glyph
	@interface RenderOptions
	.parent Instance? -- ImageLabel / Decal / Texture / SurfaceGui to render into.
	.size Vector2?    -- Target pixel size. Defaults to SVG viewBox size.
	.fit ("contain" | "cover" | "fill" | "none")? -- preserveAspectRatio translation.
]=]
export type RenderOptions = {
	parent: Instance?,
	size: Vector2?,
	fit: ("contain" | "cover" | "fill" | "none")?,
}

--[=[
	@within Glyph
	@interface Handle
	.Destroy () -> () -- Releases the EditableImage and any owned instances.
]=]
export type Handle = {
	Destroy: (self: Handle) -> (),
}

--[=[
	@within Glyph
	Parses an SVG source string and renders it. Returns a handle; call
	`handle:Destroy()` to release.

	@error "EditableImage unavailable" -- Raised when the API is not accessible on
		the current thread (e.g., experience has not opted in to Mesh & Image APIs).
]=]
function Glyph.render(_svg: string, _options: RenderOptions?): Handle
	error("Glyph.render is not yet implemented", 2)
end

return Glyph
