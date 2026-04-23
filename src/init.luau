--!strict
--[=[
	@class Glyph

	Runtime SVG renderer for Roblox.

	```lua
	local Glyph = require(ReplicatedStorage.Glyph)

	local handle = Glyph.render(svgSource, {
	    parent = imageLabel,
	    size = Vector2.new(256, 256),
	    fit = "contain",
	})

	-- Later:
	handle:Destroy()
	```

	Requirements:
	- Experience Settings -> Security -> **Allow Mesh & Image APIs** enabled.
	- Creator ID-verified (Roblox policy for `EditableImage`).

	Glyph fails loudly (raises) if `EditableImage` is unavailable — there is
	no silent fallback. The error message explains what to enable.
]=]

local Backend = require(script.Render.Backend)
local Canvas = require(script.Raster.Canvas)
local Mount = require(script.Render.Mount)
local Raster = require(script.Raster.Raster)
local Svg = require(script.Parser.Svg)

local Glyph = {}

Glyph._VERSION = "0.1.0"

--[=[
	@within Glyph
	@interface RenderOptions
	.parent Instance -- ImageLabel / ImageButton / Decal / Texture / MeshPart / SurfaceGui / BillboardGui.
	.size Vector2?   -- Target pixel size. Defaults to the SVG's intrinsic size rounded down to 256x256 maximum.
	.fit ("contain" | "cover" | "fill" | "none")? -- Viewport fit. Default "contain".
	.backgroundColor { number }? -- RGBA [0,1] fill for pixels outside the SVG content. Default transparent.
]=]
export type RenderOptions = {
	parent: Instance,
	size: Vector2?,
	fit: ("contain" | "cover" | "fill" | "none")?,
	backgroundColor: { number }?,
}

--[=[
	@within Glyph
	@interface Handle
	.editableImage Instance -- The underlying EditableImage (read-only access).
	.Destroy (self: Handle) -> () -- Releases the EditableImage and any Glyph-owned instances.
]=]
export type Handle = {
	editableImage: Backend.EditableImage,
	Destroy: (self: Handle) -> (),
}

local DEFAULT_MAX_DIMENSION = 256

local function clampSize(target: Vector2?, viewport: Svg.Viewport): Vector2
	if target then
		return Vector2.new(
			math.clamp(math.floor(target.X), 1, Backend.MAX_SIZE),
			math.clamp(math.floor(target.Y), 1, Backend.MAX_SIZE)
		)
	end
	local w = math.max(1, math.ceil(viewport.width))
	local h = math.max(1, math.ceil(viewport.height))
	local largest = math.max(w, h)
	if largest > DEFAULT_MAX_DIMENSION then
		local scale = DEFAULT_MAX_DIMENSION / largest
		w = math.max(1, math.floor(w * scale + 0.5))
		h = math.max(1, math.floor(h * scale + 0.5))
	end
	return Vector2.new(math.min(w, Backend.MAX_SIZE), math.min(h, Backend.MAX_SIZE))
end

--[=[
	@within Glyph
	Parses an SVG source string, rasterizes it, and attaches the resulting
	image to the supplied parent. Returns a handle whose `Destroy` method
	releases the underlying `EditableImage` and any Glyph-owned instances.

	Raises if:
	- the SVG source is malformed,
	- the parent is not a supported type,
	- the `EditableImage` API is unavailable (experience opt-in missing or
	  creator not ID-verified),
	- the canvas allocation fails (device memory budget exceeded).
]=]
function Glyph.render(svgSource: string, options: RenderOptions): Handle
	assert(type(svgSource) == "string", "Glyph.render: svgSource must be a string")
	assert(type(options) == "table" and options.parent, "Glyph.render: options.parent is required")
	local document = Svg.parse(svgSource)
	local size = clampSize(options.size, document.viewport)
	local canvas = Canvas.create(size.X, size.Y)
	local bg = options.backgroundColor
	if bg then
		Canvas.clear(canvas, bg[1], bg[2], bg[3], bg[4])
	end
	Raster.render(canvas, document, {
		fit = options.fit or "contain",
		backgroundColor = nil,
	})
	local image = Backend.create(size)
	local okWrite, writeErr = pcall(function()
		Backend.write(image, canvas)
	end)
	if not okWrite then
		Backend.destroy(image)
		error("Glyph: failed to upload canvas to EditableImage: " .. tostring(writeErr), 0)
	end
	local okAttach, attachmentOrErr = pcall(function()
		return Mount.attach(options.parent, image)
	end)
	if not okAttach then
		Backend.destroy(image)
		error(tostring(attachmentOrErr), 0)
	end
	local attachment = attachmentOrErr :: Mount.Attachment
	local handle: Handle = {
		editableImage = image,
		Destroy = function(self: Handle)
			Mount.detach(attachment)
			Backend.destroy(self.editableImage)
		end,
	}
	return handle
end

--[=[
	@within Glyph
	Returns whether the `EditableImage` API is available on the current
	thread. Useful for showing a fallback UI before attempting a render.
]=]
function Glyph.isAvailable(): boolean
	return Backend.isAvailable()
end

return Glyph
