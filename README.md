<div align="center">

# IMGN

**Verification-free editable images for Roblox.**

A writable pixel canvas rendered from GUI frames — no `EditableImage`, no age/ID verification.

*Plinko Labs · Material Develop*

</div>

---

## Why

Roblox's `EditableImage` / `EditableMesh` APIs are gated behind **creator age/ID verification**, because they let an experience generate arbitrary, unmoderated pixels at runtime. If you don't want to verify, you can't ship them.

IMGN sidesteps the whole thing: it draws the image out of ordinary GUI `Frame`s instead of an `EditableImage`, so a fully writable runtime canvas needs **no verification at all**. You get per-pixel drawing, procedural generation, sprites, lines, rects and circles on anything that holds a GUI — a `SurfaceGui` on a part, or a `BillboardGui` on an adornee.

The trade-off is honest: a Frame-based canvas is bound by **instance count**, not memory. It's perfect for pixel art, HUDs, procedural textures, drawing minigames and data viz at modest resolutions. It is *not* a path to photo-resolution images — keep canvases at or below ~128×128 (IMGN warns past that).

## Install

```toml
# wally.toml
[dependencies]
IMGN = "kr3ative/imgn@0.1.0"
```

```sh
wally install
```

## Quick start

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local IMGN = require(ReplicatedStorage.Packages.IMGN)

-- Paint a part's front face with a procedural gradient.
local canvas = IMGN.Surface(workspace.Screen, Enum.NormalId.Front, {
    Resolution = Vector2.new(64, 64),
})

canvas:Shader(function(x, y)
    return Color3.fromHSV((x + y) / 128, 1, 1)
end)

canvas:Render()
```

## Core idea: edit, then flush

A `Canvas` owns the **pixels** (a Luau `buffer` of RGBA bytes) and a **driver** (the `Frame` instances). Every edit writes the buffer and marks the touched pixels *dirty* — nothing reaches the screen until a flush:

```lua
canvas:SetPixel(10, 5, Color3.new(1, 0, 0))
canvas:DrawCircle(32, 32, 8, Color3.new(0, 0, 1), true)
canvas:Render()  -- one flush pushes every dirty pixel at once
```

Batch a thousand edits, pay for one flush. Or set `AutoRender = true` and IMGN flushes dirty pixels every `Heartbeat` for you.

## API

### Entry points

| Call | Returns | Use |
| --- | --- | --- |
| `IMGN.new(config)` | `Canvas` | Bare canvas; pass `Parent` to mount, or mount later. |
| `IMGN.Surface(part, face?, config)` | `Canvas, SurfaceGui` | Builds a `SurfaceGui` on a part's face. |
| `IMGN.Billboard(adornee, size?, config)` | `Canvas, BillboardGui` | Builds a camera-facing `BillboardGui`. |
| `IMGN.Configure(overrides)` | — | Global defaults (see below). |

### `CanvasConfig`

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `Resolution` | `Vector2` | *required* | Canvas size in pixels (width × height). |
| `Parent` | `Instance?` | `nil` | GUI container to mount into now; omit to `:Mount` later. |
| `Background` | `Color3?` | `nil` | Start filled opaque with this colour instead of transparent. |
| `Driver` | `"PixelGrid" \| "RowMerge"` | `"PixelGrid"` | Renderer (see below). |
| `AutoRender` | `boolean?` | `false` | Flush dirty pixels every `Heartbeat`. |

### Canvas methods

Coordinates are **0-indexed**, `(0, 0)` top-left. Out-of-bounds writes are clipped silently.

| Method | Does |
| --- | --- |
| `:SetPixel(x, y, color, alpha?)` | Write one pixel. |
| `:GetPixel(x, y)` → `Color3, alpha` | Read one pixel. |
| `:Fill(color, alpha?)` / `:Clear()` | Whole-canvas fill / clear to transparent. |
| `:Shader(fn)` | `fn(x, y, color, alpha)` → `color?, alpha?` per pixel — the procedural path. |
| `:DrawLine(x0, y0, x1, y1, color, alpha?)` | Bresenham line. |
| `:DrawRect(x, y, w, h, color, filled?, alpha?)` | Rectangle (border or filled). |
| `:DrawCircle(cx, cy, r, color, filled?, alpha?)` | Circle (outline or disc). |
| `:Blit(source, dx, dy)` | Copy another canvas in at `(dx, dy)`. |
| `:Render()` | Flush dirty pixels to instances. |
| `:Mount(parent)` | Build instances under `parent` (if you skipped `Parent`). |
| `:Destroy()` | Disconnect AutoRender, destroy instances. |

## Drivers

A driver turns the pixel buffer into instances. Pick per canvas via `Driver`:

- **`PixelGrid`** *(default)* — one `Frame` per pixel, dirty-tracked. A brush stroke updates only the Frames under it. Best for **live drawing** and frequently-changing content.
- **`RowMerge`** — run-length-merges each row into wide Frames; fully-transparent runs cost nothing. Far fewer instances. Best for **flat-colour sprites and static art**. A flush rebuilds whole dirty rows, so it's less suited to noisy every-pixel churn.

## Global config

```lua
IMGN.Configure({
    DefaultDriver = "PixelGrid",   -- driver when a canvas omits `Driver`
    MaxPixels = 16384,             -- warn past this many pixels (128x128)
    WarnOnLargeCanvas = true,      -- set false to silence the warning
    AutoRender = false,            -- default AutoRender for new canvases
})
```

## Limits

- **Instance count is the ceiling.** Keep canvases modest (≤ ~128×128). Not for photo-resolution images.
- **No reading asset pixels.** IMGN can't decode an existing decal/texture — that still needs `EditableImage`. Loading a real `.png` would mean decoding it in pure Luau and feeding the bytes to `:Blit` (a possible future addition, not in 0.1.0).

## Building from source

The toolchain is pinned in [`rokit.toml`](rokit.toml) (rojo + lune). Fetch it with `rokit install`, then:

```sh
./scripts/build.sh            # everything -> build/IMGN.rbxm, build/IMGN.rbxl, dist/install.luau
./scripts/build.sh model      # just the package model     (rojo build default.project.json)
./scripts/build.sh place      # just the dev place + Showcase (rojo build place.project.json)
./scripts/build.sh installer  # just the command-bar installer (lune run scripts/build-installer)
```

Or drive the tools directly:

```sh
rojo build default.project.json -o build/IMGN.rbxm   # importable model
rojo build place.project.json   -o build/IMGN.rbxl   # open + Play to see the Showcase
rojo serve  place.project.json                       # live-sync via the Rojo Studio plugin
```

### No-Rojo install (Studio command bar)

`scripts/build-installer.luau` bakes the whole source tree into `dist/install.luau` — paste it into the Studio command bar and IMGN appears under `ReplicatedStorage`. For a one-line paste, `dist/bootstrap.luau` HTTP-fetches that installer instead (enable *Game Settings → Security → Allow HTTP Requests*).

## Examples

See [`examples/`](examples):

- **Showcase** — self-contained animated plasma surface; what the dev place runs.

- **GradientSurface** — procedural gradient on a part via `:Shader`.
- **PaintCanvas** — click-drag finger paint on a `ScreenGui` with `AutoRender`.
- **Sprite** — pixel-art heart via `RowMerge`.

## License

MIT © 2026 kr3ative
