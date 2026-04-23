--!strict
-- Glyph Studio smoke test.
--
-- Put this under StarterPlayer -> StarterPlayerScripts (the demo.project.json
-- does that automatically). Hit Play. A ScreenGui appears with a series of
-- SVG icons rendered at runtime.
--
-- If you see "Glyph: EditableImage API is unavailable" in the output, open
-- Game Settings -> Security and toggle "Allow Mesh & Image APIs" on, then
-- restart play.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Glyph = require(ReplicatedStorage:WaitForChild("Glyph"))

local DEMOS: { { name: string, svg: string } } = {
	{
		name = "Triangle",
		svg = [[
			<svg viewBox="0 0 100 100">
				<polygon points="50,10 90,90 10,90" fill="#ff6b6b" stroke="#333" stroke-width="4"/>
			</svg>
		]],
	},
	{
		name = "Star",
		svg = [[
			<svg viewBox="0 0 100 100">
				<polygon points="50,5 61,38 95,38 68,58 79,92 50,72 21,92 32,58 5,38 39,38"
				         fill="#feca57" stroke="#222" stroke-width="2" stroke-linejoin="round"/>
			</svg>
		]],
	},
	{
		name = "Circle + arc path",
		svg = [[
			<svg viewBox="0 0 100 100">
				<circle cx="50" cy="50" r="40" fill="#48dbfb"/>
				<path d="M 20 50 A 30 30 0 0 1 80 50" fill="none" stroke="white" stroke-width="6"
				      stroke-linecap="round"/>
			</svg>
		]],
	},
	{
		name = "Linear gradient",
		svg = [[
			<svg viewBox="0 0 100 100">
				<defs>
					<linearGradient id="g" x1="0" y1="0" x2="1" y2="1">
						<stop offset="0" stop-color="#ff6b6b"/>
						<stop offset="1" stop-color="#5f27cd"/>
					</linearGradient>
				</defs>
				<rect x="5" y="5" width="90" height="90" rx="12" fill="url(#g)"/>
			</svg>
		]],
	},
	{
		name = "Radial gradient",
		svg = [[
			<svg viewBox="0 0 100 100">
				<defs>
					<radialGradient id="r" cx="0.5" cy="0.5" r="0.5">
						<stop offset="0" stop-color="white"/>
						<stop offset="1" stop-color="#2c2c54"/>
					</radialGradient>
				</defs>
				<circle cx="50" cy="50" r="45" fill="url(#r)"/>
			</svg>
		]],
	},
	{
		name = "Heart path",
		svg = [[
			<svg viewBox="0 0 100 100">
				<path d="M 50 80 C 20 65 10 40 25 25 C 35 15 45 20 50 30 C 55 20 65 15 75 25 C 90 40 80 65 50 80 Z"
				      fill="#ee5253"/>
			</svg>
		]],
	},
	{
		name = "Clip path",
		svg = [[
			<svg viewBox="0 0 100 100">
				<defs>
					<clipPath id="c"><circle cx="50" cy="50" r="40"/></clipPath>
				</defs>
				<rect x="0" y="0" width="50" height="100" fill="#00d2d3" clip-path="url(#c)"/>
				<rect x="50" y="0" width="50" height="100" fill="#ff9ff3" clip-path="url(#c)"/>
			</svg>
		]],
	},
	{
		name = "Even-odd rule",
		svg = [[
			<svg viewBox="0 0 100 100">
				<path fill-rule="evenodd" fill="#10ac84"
				      d="M 10 10 h 80 v 80 h -80 Z M 30 30 h 40 v 40 h -40 Z"/>
			</svg>
		]],
	},
}

local function createUi()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "GlyphDemo"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 60)
	title.Position = UDim2.fromOffset(0, 20)
	title.Text = "Glyph — EditableImage SVG rendering"
	title.TextColor3 = Color3.fromRGB(240, 240, 240)
	title.TextSize = 24
	title.Font = Enum.Font.GothamBold
	title.Parent = gui

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(1, 0, 0, 30)
	status.Position = UDim2.fromOffset(0, 60)
	status.Text = ""
	status.TextColor3 = Color3.fromRGB(200, 200, 200)
	status.TextSize = 14
	status.Font = Enum.Font.Gotham
	status.Parent = gui

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, -40, 1, -120)
	grid.Position = UDim2.fromOffset(20, 100)
	grid.Parent = gui

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(200, 240)
	layout.CellPadding = UDim2.fromOffset(16, 16)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	return gui, grid, status
end

local function createTile(
	parent: Instance,
	name: string,
	order: number
): (Frame, ImageLabel, TextLabel)
	local tile = Instance.new("Frame")
	tile.Name = name
	tile.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
	tile.BorderSizePixel = 0
	tile.LayoutOrder = order
	tile.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = tile

	local image = Instance.new("ImageLabel")
	image.Name = "Image"
	image.BackgroundTransparency = 1
	image.Size = UDim2.new(1, -16, 1, -48)
	image.Position = UDim2.fromOffset(8, 8)
	image.ScaleType = Enum.ScaleType.Fit
	image.Parent = tile

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 32)
	label.Position = UDim2.new(0, 0, 1, -36)
	label.Text = name
	label.TextColor3 = Color3.fromRGB(220, 220, 220)
	label.TextSize = 14
	label.Font = Enum.Font.GothamMedium
	label.Parent = tile

	return tile, image, label
end

local gui, grid, status = createUi()

if not Glyph.isAvailable() then
	status.Text =
		"EditableImage API unavailable — enable 'Allow Mesh & Image APIs' in Game Settings → Security, then restart Play."
	status.TextColor3 = Color3.fromRGB(255, 100, 100)
	return
end

status.Text = "Rendering " .. #DEMOS .. " SVGs…"

local handles: { any } = {}
local successes = 0
local failures = {}

for index, demo in ipairs(DEMOS) do
	local _, imageLabel = createTile(grid, demo.name, index)
	local ok, handleOrErr = pcall(function()
		return Glyph.render(demo.svg, {
			parent = imageLabel,
			size = Vector2.new(192, 192),
			fit = "contain",
		})
	end)
	if ok then
		table.insert(handles, handleOrErr)
		successes += 1
	else
		table.insert(failures, { name = demo.name, err = tostring(handleOrErr) })
	end
end

if #failures == 0 then
	status.Text = string.format("✓ %d/%d rendered", successes, #DEMOS)
	status.TextColor3 = Color3.fromRGB(130, 230, 130)
else
	status.Text =
		string.format("⚠ %d/%d rendered, %d failed — see Output", successes, #DEMOS, #failures)
	status.TextColor3 = Color3.fromRGB(255, 200, 100)
	for _, fail in ipairs(failures) do
		warn(string.format("[Glyph demo] %s failed: %s", fail.name, fail.err))
	end
end

-- Clean up on player leaving.
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
