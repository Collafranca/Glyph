--!strict
--[=[
	@class Backend
	@private

	Thin wrapper over `AssetService:CreateEditableImage` with capability
	detection.

	Detection strategy: we look up `AssetService` and check whether the method
	exists. If the method call itself fails (experience hasn't enabled "Allow
	Mesh & Image APIs", creator isn't ID-verified, or device memory budget
	refused the allocation), we surface a `Glyph.Error` with a clear message
	rather than silently degrading.

	The module keeps no hidden state; every call is pure given its inputs.
]=]

local Backend = {}

export type EditableImage = Instance & {
	WritePixelsBuffer: (EditableImage, Vector2, Vector2, buffer) -> (),
	Size: Vector2,
}

Backend.MAX_SIZE = 1024

--[=[
	@within Backend
	Returns whether the EditableImage API is available on the current thread.
	Does NOT allocate — safe to call on every render.

	Detection is conservative: absence of `AssetService` or the creator-side
	`CreateEditableImage` method returns `false`. If both are present but the
	allocation itself would fail (policy / opt-in / memory), `create()` will
	raise — `isAvailable` only tells you the API surface exists.
]=]
function Backend.isAvailable(): boolean
	local assetService = game:FindService("AssetService")
	if not assetService then
		return false
	end
	return typeof((assetService :: any).CreateEditableImage) == "function"
end

--[=[
	@within Backend
	Allocates an `EditableImage` of the requested size. Raises with a
	user-facing error if the API is unavailable, the size is out of range, or
	the allocation fails (policy / memory budget).
]=]
function Backend.create(size: Vector2): EditableImage
	if not Backend.isAvailable() then
		error(
			"Glyph: EditableImage API is unavailable. Enable 'Allow Mesh & Image APIs' in "
				.. "Game Settings -> Security, and make sure the experience creator is ID-verified. "
				.. "See https://create.roblox.com/docs/reference/engine/classes/EditableImage",
			0
		)
	end
	if size.X <= 0 or size.Y <= 0 then
		error(string.format("Glyph: canvas size must be positive, got (%d, %d)", size.X, size.Y), 0)
	end
	if size.X > Backend.MAX_SIZE or size.Y > Backend.MAX_SIZE then
		error(
			string.format(
				"Glyph: canvas size %dx%d exceeds EditableImage maximum of %dx%d",
				size.X,
				size.Y,
				Backend.MAX_SIZE,
				Backend.MAX_SIZE
			),
			0
		)
	end
	local assetService = (game :: any):GetService("AssetService")
	local ok, result = pcall(function()
		return assetService:CreateEditableImage({ Size = size })
	end)
	if not ok then
		error(
			"Glyph: AssetService:CreateEditableImage raised: "
				.. tostring(result)
				.. ". This usually means the experience does not have mesh & image APIs "
				.. "enabled, or the device memory budget was exceeded.",
			0
		)
	end
	if result == nil then
		error(
			"Glyph: AssetService:CreateEditableImage returned nil. This is typically a device "
				.. "memory-budget refusal — try a smaller canvas size.",
			0
		)
	end
	return result :: EditableImage
end

--[=[
	@within Backend
	Writes the canvas buffer into the EditableImage.
]=]
function Backend.write(
	image: EditableImage,
	canvas: { width: number, height: number, buffer: buffer }
)
	local size = Vector2.new(canvas.width, canvas.height)
	image:WritePixelsBuffer(Vector2.zero, size, canvas.buffer)
end

--[=[
	@within Backend
	Destroys the `EditableImage`. Safe to call multiple times.
]=]
function Backend.destroy(image: EditableImage)
	pcall(function()
		image:Destroy()
	end)
end

return Backend
