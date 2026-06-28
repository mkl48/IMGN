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
| `:Text(text, x, y, color, scale?, alpha?)` | Draw text in the built-in 3×5 bitmap font (uppercase, digits, punctuation). |
| `:Blit(source, dx, dy)` | Copy another canvas in at `(dx, dy)`. |
| `:Render()` | Flush dirty pixels to instances. |
| `:Mount(parent)` | Build instances under `parent` (if you skipped `Parent`). |
| `:Destroy()` | Disconnect AutoRender, destroy instances. |

## Drivers

A driver turns the pixel buffer into instances. Pick per canvas via `Driver`. The last three are the classic "render images without melting the engine" tricks — fewer instances, at the cost of rebuilding on change (great for static images, not animation):

| Driver | Instances | Best for |
| --- | --- | --- |
| **`PixelGrid`** *(default)* | one `Frame` per pixel | **live drawing** / animation — dirty-tracked, a brush stroke touches only its pixels |
| **`RowMerge`** | one Frame per horizontal colour run | flat **sprites**; this is "box compression" along rows |
| **`GreedyMesh`** | one Frame per merged 2D **rectangle** | **static / flat images** — merges runs in *both* axes (a 50×50 flat block → 1 Frame, not 50). 90%+ fewer instances on pixel art |
| **`RichText`** | **one `TextLabel`** for the whole image | **lowest** instance count — the image is block glyphs (█) with per-pixel `<font>` colour, RLE-compressed. Approximate alignment (monospace + `TextScaled`), low-res only (~64×64; RichText has a ~16k-char ceiling). Not pixel-perfect |
| **`Blob`** | one *overlapping circle* per pixel | **smooth/organic** output from a low-res buffer — circles merge into metaball-like blobs with no square edges. Ideal for fluids (the blood engine's `"Fluid"` renderer uses it) |
| **`Sparse`** | one Frame per *visible* pixel (pooled) | instance count tracks **painted area, not canvas area** — run a full-resolution sim/canvas over a huge surface and only pay for the pixels with something on them. The blood engine's `"Pixel"` renderer uses it for big parts |

So for loading a photo/sprite once, `GreedyMesh` is usually the sweet spot; for a tiny icon where instance count must be near-zero, try `RichText`. For anything that animates, stay on `PixelGrid`.

## The App layer

`Canvas` is the raw image. **`App`** is the managed engine on top of it: it owns a canvas, a list of **`Object`s** (each a *union of shapes* with collision presets), and a per-frame loop that steps physics, resolves collisions, and redraws only what moved. The whole bouncing-ball script becomes "spawn an Object, `app:Start()`".

```lua
local app = IMGN.App({
    Canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(96, 96) }),
    Background = Color3.fromRGB(12, 12, 20),  -- what Objects erase back to each frame
})

-- An immovable wall (preset "Wall" = anchored + collidable).
app:Object({ Position = Vector2.new(48, 48), Preset = "Wall" })
   :Rect(Vector2.new(-3, -22), Vector2.new(6, 44), Color3.fromRGB(90, 90, 120))

-- A bouncing ball: shapes are offsets from the Object's Position, so it moves as one unit.
app:Object({
    Position = Vector2.new(20, 20),
    Velocity = Vector2.new(40, 25),   -- pixels per second
    Bounce = 1,
}):Circle(Vector2.zero, 5, Color3.fromRGB(0, 170, 255))

app:Start()   -- runs the step→collide→draw loop every frame
```

### Object

An Object is a transform (`Position`, `Velocity`) carrying shapes that draw and collide as one AABB.

- **Shapes** (chainable, offsets are relative to `Position`): `:Circle(offset, radius, color, filled?)`, `:Rect(offset, size, color, filled?)`, `:Pixel(offset, color)`.
- **Presets** seed the flags: `"Dynamic"` (default, free body), `"Wall"`/`"Static"` (anchored solid), `"Ghost"` (moves, no collision). Override per-field with `CanCollide`, `Anchored`, `Bounce`, `Visible`.
- **Collision** is automatic for `CanCollide` bodies — they bounce off the canvas edges *and* each other (anchored bodies are immovable). Or drive it yourself with `obj:Overlaps(other)` and `obj:TouchingEdge()` (these work even on Ghosts — handy for triggers/pickups).
- **Hooks**: `OnUpdate(self, dt)` each frame before physics; `OnCollide(self, other)` where `other` is another Object or an edge name (`"Left"`/`"Right"`/`"Top"`/`"Bottom"`).

### Comb

`app:Comb(axis, direction, fn)` sweeps the canvas a line at a time — a **row** for `"Y"`, a **column** for `"X"`, both for `"XY"` — calling `fn(section)` per line. Great for wipes, scanlines and per-line effects:

```lua
app:Comb("Y", "Forward", function(section)
    section:Fill(Color3.fromHSV(section.Index / 64, 1, 1))  -- vertical rainbow
end)
app.Canvas:Render()
```

A `section` is a 1-D view: `section.Index` (the row's y / column's x), `section.Length`, and `:Set(i, color)` / `:Get(i)` / `:Fill(color)`.

> **App backgrounds are solid.** Objects erase to `Background` each frame, so a static *image* backdrop behind moving objects isn't supported in 0.1.0 (a moving body would erase holes in it). Use a solid `Background`, or draw non-moving scenery as anchored Objects.

## Liquid simulation (blood, water, …)

`IMGN.Liquid` is a cellular fluid sim on a canvas — splats that **flow, drip in rivulets, pool, and dry**. The headline use is realistic **dripping blood** on a surface; the same engine does Water/Paint/Lava/Slime/Honey by preset.

```lua
local blood = IMGN.Liquid({
    Canvas = IMGN.Surface(wall, Enum.NormalId.Front, { Resolution = Vector2.new(96, 120) }),
    Preset = "Blood",   -- Water / Paint / Lava / Slime / Honey
})
blood:Start()

-- splatter on impact (e.g. from a raycast hit mapped to a pixel)
blood:Splat(px, py, 4, { Spread = 8, Velocity = Vector2.new(2, 1) })
```

How it looks right: each step fluid transfers downward but leaves a thin **`Cling`** film behind (the streak), spreads sideways only when **backed up** (high surface tension → narrow drips, not a watery sheet), slowly **evaporates**, and **dries** from its fresh colour to a dark stain. Gravity is a canvas-space vector — `(0, 1)` for a wall (drips down), `(0, 0)` for a floor (just pools). Every field (`Cling`, `Spread`, `Evaporation`, `DryRate`, `Capacity`, `Gravity`, `Color`) is tunable live. Only changed cells repaint, so once it dries it costs almost nothing.

See `examples/BloodDrip.server.luau`.

### Blood engine (`IMGN.Blood`)

A full droplet-and-drip system: throw 3D blood that lands on surfaces and drips down them, correctly following each surface's **downhill** — walls, slopes, and rotated/moving parts.

**Three renderers** (set with `IMGN.Blood.Configure { Renderer = … }`):
- **`"Pixel"`** *(default)* — the `Liquid` cellular **simulation** painted **directly on the hit part's face** (a `SurfaceGui` adorned to the part, so it lies flush and aligned — never floating or rotated), rendered with the **`Sparse` driver** (only *painted* pixels cost anything). One canvas per part-face; when blood reaches an edge it **wraps onto the adjacent face** (a new face canvas) and continues, cascading around corners.
- **`"Fluid"`** — the sim on a small **`Blob`-circle** patch (smooth/organic, localized).
- **`"Vector"`** — smooth animated **`Path2D` strokes** (scripted, the cheapest); drips stop at the surface's real edge and shed, floors puddle.

```lua
-- a kill brick that sprays blood when stepped on
IMGN.Blood.KillBrick(brick, { Droplets = 18, Up = 26, Spread = 18 })

-- or throw a droplet yourself; it falls, lands, and drips
IMGN.Blood.Emit(origin, Vector3.new(10, 20, 0))

-- or paint a surface directly
IMGN.Blood.Splat(part, Enum.NormalId.Front, worldPos, 4)
```

**How it works — blood proxies.** `Emit` spawns a real droplet `Part` that flies under gravity; a per-frame raycast catches where it lands; instead of painting onto the part it hit (which scales the canvas to the *whole* part — a splat on a huge wall comes out low-res and stretched), it spawns a small **fixed-size proxy part** at the impact, oriented to the surface, and paints on *that*. Two wins:

- **Consistent resolution** everywhere — `ProxySize` studs at `PixelsPerStud`, regardless of what it landed on. A splat is the same crisp blood on a pebble or a skyscraper.
- **No face-convention guessing** — the proxy is oriented so its canvas **+Y points downhill** (`Surface.dripBasis` projects world-down onto the surface), so the sim's gravity is just `(0,1)` and drips run correctly down walls *and* slopes. Floors/ceilings get `(0,0)` → blood pools.

Proxies are welded to the hit part (blood follows it if it moves), reused when splats land within `ReuseRadius`, and the droplet shrinks + is destroyed. Tune via `IMGN.Blood.Configure { ProxySize = …, PixelsPerStud = …, Preset = "Blood", … }`.

**Cross-surface flow.** Blood reaching an edge **follows the geometry** like the real thing: it **wraps around a convex corner** onto the part's next face (top → front), or **flows onto a surface just below/past the edge** (a wall meeting the floor), and **only detaches into a falling droplet when there's genuinely nothing to travel down** (a true overhang). So it runs down a ramp, wraps over the end, continues down a wall, and finally drips into open space — cascading surface to surface. Tune the look-ahead with `WrapReach`. Floors/ceilings pool instead of shedding.

**Filters.** `IMGN.Blood.Ignore(instance)` (and `Unignore`) keep droplets from landing on things — your own character, a UI/button, etc. Anything with `CanQuery = false` is skipped automatically.

```lua
IMGN.Blood.Ignore(player.Character)   -- blood won't paint you
```

**Performance + looks:** proxies are a middle ground between one tiny canvas per splat (visible square tiles) and one huge canvas per part (laggy on big walls). Defaults use **bigger, fewer proxies** (`ProxySize = 8`, `ReuseRadius = 5`) so blood streaks within *one* continuous canvas instead of tiling, plus an **`EdgeFade`** so a proxy's square border blends out instead of ending in a hard line. Each sim's hot loop is allocation-free, **skips its flow passes once the blood stops moving**, and **sleeps** once dried (a stain costs ~nothing). Crank `ProxySize`/`PixelsPerStud` up for crisper, more seamless blood, or down for less work; keep droplet counts modest (each can spawn a proxy).

**If drips run upward** in your place, flip them with one global knob (no source edits):

```lua
IMGN.Blood.Configure({ FlipDrip = true })
```

> **Verified vs. needs-Studio:** the 2D sim and the proxy orientation math (`dripBasis` — gravity + a right-handed basis for every surface) are unit-tested. The 3D pieces — droplet physics, the raycast, and the `CFrame.fromMatrix` proxy placement / `SurfaceGui` Back-face orientation — can only be confirmed in a running place. The drip *direction* no longer depends on face conventions (it's baked into the proxy), but if the whole image reads upside-down, `FlipDrip` corrects it.

See `examples/KillBrick.server.luau`.

## Particles

`IMGN.Particles` is a 2D particle emitter on a canvas — fire, sparks, rain, snow, explosions, confetti. Particles move under gravity, fade with age, and only the moving pixels repaint.

```lua
local fire = IMGN.Particles({
    Canvas = IMGN.Surface(part, Enum.NormalId.Front, { Resolution = Vector2.new(72, 72) }),
    Preset = "Fire",          -- Sparks / Rain / Snow / Explosion / Confetti
    Position = Vector2.new(36, 66),
})
fire:Start()        -- continuous emission
fire:Burst(30)      -- or a one-shot burst (explosions, confetti)
```

Every field (`Rate`, `Gravity`, `SpeedMin/Max`, `Spread`, `Direction`, `Life…`, `ColorStart/End`) is overridable; share one canvas between several emitters. See `examples/Particles.server.luau`.

## Interactive input

`canvas:OnInput(fn)` maps clicks/touches/drags to canvas pixels, so a canvas becomes something you can *draw on* — on a `ScreenGui` HUD or a `SurfaceGui` (an **in-world touchscreen**).

```lua
canvas:OnInput(function(x, y, phase)   -- phase = "Began" | "Changed" | "Ended"
    if phase ~= "Ended" then
        canvas:DrawCircle(x, y, 3, Color3.new(0, 0, 0), true)
    end
end)
-- or one-off: local px, py = canvas:PixelAt(input.Position)
```

See `examples/PaintApp.client.luau` (a working paint program).

## Dithering & palettes

`canvas:Dither(palette)` (Floyd–Steinberg) and `canvas:Quantize(palette)` reduce a canvas to a set of colours — the retro / GameBoy look, *and* fewer colours mean longer runs, so the `RowMerge`/`GreedyMesh`/`RichText` drivers get much cheaper.

```lua
canvas:Dither(IMGN.Palette.Grayscale(4))         -- 4-shade dithered
canvas:Dither({ Color3.fromRGB(15,56,15), Color3.fromRGB(155,188,15) })  -- any palette
canvas:Render()
```

## Loading real images

IMGN can draw actual image files — PNG/BMP/TGA/JPG — onto a canvas. The decoder ([osgl-rbx/image](https://github.com/osgl-rbx/image)) is **bundled inside IMGN**, so there's nothing extra to install — just hand it the file bytes. No `EditableImage`, no verification.

```lua
local bytes = HttpService:GetAsync(pngUrl)        -- the file as a string (or a buffer)

-- build a canvas sized to the decoded image:
local canvas = IMGN.ImageCanvas(bytes, { Parent = surfaceGui, Format = "PNG" })

-- or draw onto an existing canvas at an offset/scale:
canvas:LoadImage(bytes, { X = 4, Y = 4, Scale = 0.5, SkipTransparent = true })
canvas:Render()
```

**Getting the bytes is on you** — Roblox can't read an uploaded decal's pixels without `EditableImage`, so the file has to come from somewhere else: `HttpService:GetAsync(url)` (needs *Allow HTTP Requests*), or baked into a ModuleScript (see "No link" below). `LoadImage` options: `X`, `Y`, nearest-neighbour `Scale` (use `< 1` to shrink big images), `Fit` (`"Contain"`/`"Cover"`/`"Stretch"` — size to the canvas instead of `Scale`), explicit `Format`, and `SkipTransparent` (composite instead of replace).

### No link (bake the bytes in)

No URL, no HTTP at runtime — embed the file into a ModuleScript at build time:

```sh
lune run scripts/embed-image cat.png   # -> cat.luau (returns the bytes)
```

```lua
local bytes = require(ReplicatedStorage.Cat)
local canvas = IMGN.ImageCanvas(bytes, { Parent = surfaceGui, Format = "PNG" })
```

### Loading without freezing

A big image is a lot of work in one frame (decode + thousands of Frames). `IMGN.ImageCanvasAsync` builds and draws it while yielding on a **per-frame time budget**, so the game keeps running smoothly — it spends ~4 ms per frame and picks up where it left off, instead of hitching once:

```lua
task.spawn(function()
    local canvas = IMGN.ImageCanvasAsync(bytes, {
        Parent = surfaceGui,
        FrameBudget = 0.004,   -- seconds of work per frame (lower = smoother, slower to finish)
        OnProgress = function(f) print(("%d%%"):format(f * 100)) end,
        OnComplete = function() print("done") end,
    })
end)
```

Tuning knobs (per call, or globally via `IMGN.Configure { LoadFrameBudget = …, LoadRowsPerFrame = … }`):

| Option | Default | Effect |
| --- | --- | --- |
| `FrameBudget` | `0.004` (4 ms) | time spent per frame before yielding. `false` → use `RowsPerFrame` instead |
| `RowsPerFrame` | `8` | fixed rows per yield when there's no budget |
| `OnProgress(f)` | — | `0..1`, fired at each yield (mount is the first half, drawing the second) |
| `OnComplete()` | — | fired once finished |

> **The one thing budgeting can't hide:** the *decode* is a single osgl call and can't be split, so a very large source image still hitches once while it decodes. To keep that seamless too, shrink the source (or use the [web service](#web-image-service), which decodes server-side so the client never does). Placement options (`Fit`, `Align`, `Scale`) and a low-instance [driver](#drivers) like `GreedyMesh` round it out.

## Web image service

If you'd rather not decode images on the client (or want a server to resize them first), IMGN can draw pixel JSON straight from a web service. The repo ships a tiny FastAPI app under [`server/`](server) that fetches an image URL, resizes it, and returns the pixels — host it free on Render / Hugging Face / Vercel (see [`server/README.md`](server/README.md)).

```lua
local json = HttpService:GetAsync(API .. "?url=" .. HttpService:UrlEncode(imageUrl) .. "&max_width=64&format=rle")
local data = HttpService:JSONDecode(json)

local canvas = IMGN.PixelCanvas(data, { Parent = surfaceGui, Driver = "GreedyMesh" })
-- or onto an existing canvas: canvas:LoadPixels(data, { Fit = "Contain" })
```

The service returns either run-length rows (`format=rle`, compact) or a raw grid (`format=raw`); `LoadPixels`/`PixelCanvas` accept both. Pairing it with the `GreedyMesh` driver keeps the instance count low for a static image.

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
- **Real images need their bytes supplied.** IMGN can decode actual PNG/BMP/TGA/JPG files (see [Loading real images](#loading-real-images)), but it can't read the pixels of an *already-uploaded* Roblox decal/texture — that still needs `EditableImage`. You provide the file bytes yourself (HttpService or baked into a module).

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
- **AppBounce** — the App engine: 5 balls bouncing off the walls and each other around a center wall.
- **CombWipe** — `App:Comb` painting a scrolling rainbow one row at a time.
- **Breakout** — a full mini-game: paddle, ball, and bricks that delete themselves via `OnCollide`.
- **DoomFire** — the classic PSX fire effect.
- **FallingSand** — a powder-game sand simulation pouring through a funnel.
- **GameOfLife** — Conway's Life on a wrapping grid.
- **MatrixRain** — falling green code using the bitmap font.
- **Starfield** — a warp-speed flight through projected 3D stars.
- **Mandelbrot** — a self-zooming fractal via `:Shader`.
- **Snake** — the classic, with a bitmap-font scoreboard (WASD / arrows).
- **Raycaster** — a Wolfenstein-style first-person 3D view (W/S walk, A/D turn).
- **LoadImage** — decode a real PNG onto a part (decoder bundled).
- **WebImage** — load an image by URL through the bundled web service (`server/`).
- **BloodDrip** — realistic dripping blood via the `Liquid` sim (`IMGN.Liquid`).
- **KillBrick** — step on it, die, and spray blood that drips downhill (`IMGN.Blood`).
- **BloodArena** — a test play area + a click-to-bleed button that follows your character.
- **Particles** — a fire with bursting sparks (`IMGN.Particles`).
- **PaintApp** — a working paint program using `canvas:OnInput` (works on a SurfaceGui too).

- **GradientSurface** — procedural gradient on a part via `:Shader`.
- **PaintCanvas** — click-drag finger paint on a `ScreenGui` with `AutoRender`.
- **Sprite** — pixel-art heart via `RowMerge`.

## Credits

Image decoding is powered by **[osgl-rbx/image](https://github.com/osgl-rbx/image)** (© 2023–2025 OSGL Contributors), bundled under `src/_Packages/Image/`. It remains under its own [OSGL License](src/_Packages/Image/LICENSE) — only IMGN's own code is MIT.

## License

MIT © 2026 kr3ative — except the bundled `src/_Packages/Image/` (OSGL License, see above).
