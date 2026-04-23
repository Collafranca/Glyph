---
sidebar_position: 1
---

# Getting Started

Glyph renders SVGs at runtime in Roblox. It parses SVG 1.1 source into a
shape IR, rasterizes it in pure Luau, and writes the result into an
`EditableImage` which you can display via an `ImageLabel`, `Decal`,
`Texture`, or `SurfaceGui`.

## Requirements

- Roblox experience with **Allow Mesh & Image APIs** enabled
  (Game Settings &rarr; Security).
- Creator must be ID-verified (Roblox policy for `EditableImage`).

Glyph fails loudly with a clear error if `EditableImage` is unavailable.
There is no silent fallback.

## Installation

### Via Wally

Add to `wally.toml`:

```toml
[dependencies]
Glyph = "collafranca/glyph@^0.1"
```

### Standalone

Grab `Glyph.rbxm` from the [latest release](https://github.com/Collafranca/Glyph/releases/latest)
and drop it into your game's `ReplicatedStorage`.

## Basic usage

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Glyph = require(ReplicatedStorage.Glyph)

local svg = [[
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
         stroke-linecap="round" stroke-linejoin="round">
        <path d="M12 2 L22 22 L2 22 Z"/>
    </svg>
]]

local handle = Glyph.render(svg, {
    parent = someImageLabel,
    size = Vector2.new(128, 128),
    fit = "contain",
})

-- Later, when you want to free the EditableImage:
handle:Destroy()
```

## Supported features

### Elements
`<svg>`, `<g>`, `<defs>`, `<path>`, `<rect>`, `<circle>`, `<ellipse>`,
`<line>`, `<polyline>`, `<polygon>`, `<use>` (internal refs),
`<linearGradient>`, `<radialGradient>`, `<stop>`, `<clipPath>`.

### Styling
- Presentation attributes and inline `style="..."` (inline wins).
- Colors: `#rgb`, `#rrggbb`, `rgb()`, `rgba()`, named CSS colors,
  `currentColor`, `none`, `transparent`.
- Strokes: width, linecap (butt/round/square), linejoin (miter/round/bevel),
  miter-limit, dasharray, dashoffset.
- Fill rules: `nonzero`, `evenodd`.
- Gradients: linear and radial, both `userSpaceOnUse` and
  `objectBoundingBox` units, spread method pad/reflect/repeat.

### Transforms
`matrix`, `translate`, `scale`, `rotate` (with optional pivot),
`skewX`, `skewY`.

## Not supported

These are out of scope for v1 and will raise no error — Glyph silently
skips them during parsing:

- `<text>` / `<tspan>` — convert to paths in your exporter ("Outline text"
  in Illustrator / Figma / Inkscape).
- `<filter>`, `<mask>`, `<pattern>`, `<marker>`, `<image>`.
- SMIL or CSS animation.
- `<foreignObject>`, `<script>`.
- External CSS.

## Troubleshooting

### "EditableImage API is unavailable"

Enable **Game Settings &rarr; Security &rarr; Allow Mesh & Image APIs**
and make sure the experience creator account is ID-verified. Both are
required by Roblox policy for `EditableImage`.

### Canvas size too large

`EditableImage` has a 1024x1024 hard cap. Glyph defaults to 256x256 when
you don't specify a size; pass `size = Vector2.new(w, h)` to override
up to the cap.

### Memory-budget failures

`EditableImage` allocation can fail silently on low-memory devices.
Glyph detects this and raises a clear error — catch it and retry with a
smaller canvas, or show a fallback.
