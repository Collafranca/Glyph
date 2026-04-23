--!strict
-- Glyph + Lucide smoke test.
--
-- Renders every icon in examples/LucideIcons.luau into its own tile.
-- Lucide icons are stroked single-color SVGs using `currentColor`, so we
-- inject a `color` attribute into the <svg> tag to pick the stroke color.
--
-- If you see "Glyph: EditableImage API is unavailable" in the output,
-- enable Game Settings -> Security -> Allow Mesh & Image APIs, then Play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Glyph = require(ReplicatedStorage:WaitForChild("Glyph"))
local LucideIcons = require(script:WaitForChild("LucideIcons"))

local STROKE_COLOR = "#5dade2"
local ICON_SIZE = 96

-- Inject color="#..." as the first attribute on the root <svg> so
-- currentColor resolves to the requested color.
local function tintIcon(svg: string, color: string): string
	return (string.gsub(svg, "<svg", '<svg color="' .. color .. '"', 1))
end

local function createUi()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "GlyphLucideDemo"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(24, 26, 32)
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Position = UDim2.fromOffset(0, 20)
	title.Text = "Glyph × Lucide"
	title.TextColor3 = Color3.fromRGB(240, 240, 240)
	title.TextSize = 28
	title.Font = Enum.Font.GothamBold
	title.Parent = gui

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, 0, 0, 24)
	status.Position = UDim2.fromOffset(0, 58)
	status.Text = ""
	status.TextColor3 = Color3.fromRGB(200, 200, 200)
	status.TextSize = 14
	status.Font = Enum.Font.Gotham
	status.Parent = gui

	local scroll = Instance.new("ScrollingFrame")
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.new(1, -40, 1, -110)
	scroll.Position = UDim2.fromOffset(20, 90)
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 6
	scroll.Parent = gui

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(140, 160)
	layout.CellPadding = UDim2.fromOffset(12, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll

	return gui, scroll, status
end

local function createTile(parent: Instance, name: string, order: number): (Frame, ImageLabel)
	local tile = Instance.new("Frame")
	tile.Name = name
	tile.BackgroundColor3 = Color3.fromRGB(35, 38, 48)
	tile.BorderSizePixel = 0
	tile.LayoutOrder = order
	tile.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = tile

	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	image.Position = UDim2.new(0.5, -ICON_SIZE / 2, 0, 14)
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = tile

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 24)
	label.Position = UDim2.new(0, 0, 1, -32)
	label.Text = name
	label.TextColor3 = Color3.fromRGB(200, 200, 210)
	label.TextSize = 12
	label.Font = Enum.Font.GothamMedium
	label.Parent = tile

	return tile, image
end

local gui, scroll, status = createUi()

if not Glyph.isAvailable() then
	status.Text =
		"EditableImage API unavailable — enable 'Allow Mesh & Image APIs' in Game Settings → Security, then Play."
	status.TextColor3 = Color3.fromRGB(255, 100, 100)
	return
end

status.Text = string.format("Rendering %d Lucide icons…", #LucideIcons.names)

local handles: { any } = {}
local successes = 0
local failures = {}

for index, name in ipairs(LucideIcons.names) do
	local svg = LucideIcons.sources[name]
	if not svg then
		table.insert(failures, { name = name, err = "icon source missing" })
		continue
	end
	local tinted = tintIcon(svg, STROKE_COLOR)
	local _, imageLabel = createTile(scroll, name, index)
	local ok, handleOrErr = pcall(function()
		return Glyph.render(tinted, {
			parent = imageLabel,
			size = Vector2.new(ICON_SIZE * 2, ICON_SIZE * 2),
			fit = "contain",
		})
	end)
	if ok then
		table.insert(handles, handleOrErr)
		successes += 1
	else
		table.insert(failures, { name = name, err = tostring(handleOrErr) })
	end
end

if #failures == 0 then
	status.Text = string.format("✓ %d/%d rendered", successes, #LucideIcons.names)
	status.TextColor3 = Color3.fromRGB(130, 230, 130)
else
	status.Text = string.format(
		"⚠ %d/%d rendered, %d failed — see Output",
		successes,
		#LucideIcons.names,
		#failures
	)
	status.TextColor3 = Color3.fromRGB(255, 200, 100)
	for _, fail in ipairs(failures) do
		warn(string.format("[Glyph lucide] %s failed: %s", fail.name, fail.err))
	end
end

Players.LocalPlayer.AncestryChanged:Connect(function()
	for _, handle in ipairs(handles) do
		pcall(function()
			handle:Destroy()
		end)
	end
	if gui and gui.Parent then
		gui:Destroy()
	end
end)
