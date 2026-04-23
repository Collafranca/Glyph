--!strict
--[=[
	@class Mount
	@private

	Attaches an `EditableImage` to a display instance.

	Supported display instances:
	- `ImageLabel` / `ImageButton` — assigned via `ImageContent`
	- `Decal` / `Texture` — via `TextureContent`
	- `MeshPart` — via `TextureContent`
	- `SurfaceGui` / `BillboardGui` — we create an internal `ImageLabel`
	  that fills the surface and bind `ImageContent` on it

	Unsupported display types raise with a list of accepted types.
]=]

local Backend = require("./Backend")

local Mount = {}

export type Attachment = {
	-- Instances Mount created and now owns. Destroyed on `detach`. Never
	-- includes the caller-supplied display.
	ownedInstances: { Instance },
	-- Target whose content property Mount updated.
	display: Instance,
}

local function createFillingImageLabel(surface: Instance): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = "GlyphSurface"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0, 0)
	label.ScaleType = Enum.ScaleType.Fit
	label.Parent = surface
	return label
end

--[=[
	@within Mount
	Attaches `image` to `display` and returns an `Attachment` describing the
	instances Mount now owns.
]=]
function Mount.attach(display: Instance, image: Backend.EditableImage): Attachment
	local content = Content.fromObject(image)
	if display:IsA("ImageLabel") or display:IsA("ImageButton") then
		local anyDisplay = display :: any
		anyDisplay.ImageContent = content
		return { ownedInstances = {}, display = display }
	elseif display:IsA("Decal") or display:IsA("Texture") or display:IsA("MeshPart") then
		local anyDisplay = display :: any
		anyDisplay.TextureContent = content
		return { ownedInstances = {}, display = display }
	elseif display:IsA("SurfaceGui") or display:IsA("BillboardGui") then
		local label = createFillingImageLabel(display)
		label.ImageContent = content
		return { ownedInstances = { label }, display = label }
	end
	error(
		string.format(
			"Glyph: unsupported display '%s'. Supported: ImageLabel, ImageButton, Decal, "
				.. "Texture, MeshPart, SurfaceGui, BillboardGui.",
			display.ClassName
		),
		0
	)
end

--[=[
	@within Mount
	Clears the display's content property and destroys any Mount-owned
	instances.
]=]
function Mount.detach(attachment: Attachment)
	local display = attachment.display
	pcall(function()
		if display:IsA("ImageLabel") or display:IsA("ImageButton") then
			local anyDisplay = display :: any
			anyDisplay.ImageContent = Content.none
		elseif display:IsA("Decal") or display:IsA("Texture") or display:IsA("MeshPart") then
			local anyDisplay = display :: any
			anyDisplay.TextureContent = Content.none
		end
	end)
	for _, owned in ipairs(attachment.ownedInstances) do
		pcall(function()
			owned:Destroy()
		end)
	end
end

return Mount
