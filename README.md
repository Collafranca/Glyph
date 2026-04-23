# Glyph

Render SVGs at runtime in Roblox. Zero dependencies, pure Luau.

> **Status:** pre-alpha. Under active development.

Glyph parses SVG 1.1 and rasterizes to an `EditableImage`, so any `ImageLabel`,
`Decal`, `Texture`, or `SurfaceGui` can display a live SVG. No external
libraries, no web-service round-trips, no pre-baked textures.

## Quick start

```lua
local Glyph = require(ReplicatedStorage.Glyph)

local handle = Glyph.render(svgString, {
    parent = imageLabel,
    size   = Vector2.new(256, 256),
    fit    = "contain",
})

-- Later:
handle:Destroy()
```

## Requirements

- Roblox experience with **Allow Mesh & Image APIs** enabled (Experience
  Settings &rarr; Security).
- Creator must be ID-verified (Roblox policy for `EditableImage`).

Glyph fails loudly with a clear error if the `EditableImage` API is unavailable
on the calling thread.

## Supported SVG features (v1)

- Elements: `<svg>`, `<g>`, `<defs>`, `<path>`, `<rect>`, `<circle>`,
  `<ellipse>`, `<line>`, `<polyline>`, `<polygon>`, `<use>` (internal refs),
  `<linearGradient>`, `<radialGradient>`, `<stop>`, `<clipPath>`.
- Transforms: `matrix`, `translate`, `scale`, `rotate`, `skewX`, `skewY`.
- Styling: presentation attributes and inline `style="..."`.
- Colors: `#rgb`, `#rrggbb`, `rgb()`, `rgba()`, named CSS colors,
  `currentColor`, `none`.
- Strokes: `stroke-width`, `stroke-linecap`, `stroke-linejoin`,
  `stroke-miterlimit`, `stroke-dasharray`, `stroke-dashoffset`.
- Fill rules: `nonzero`, `evenodd`.

## Not supported (by design, v1)

- `<text>` / `<tspan>` &mdash; convert text to paths in your exporter.
- `<filter>`, `<mask>`, `<pattern>`, `<marker>`, `<image>`.
- SMIL or CSS animation.
- `<foreignObject>`, `<script>`, external CSS.

## Development

Glyph uses [Rokit](https://github.com/rojo-rbx/rokit) to pin every tool.

```sh
rokit install           # install rojo, wally, lune, selene, stylua, ...
wally install           # install Luau dependencies (dev only)
lune run tests          # run headless tests
rojo build -o Glyph.rbxm
```

## License

[MIT](./LICENSE).
