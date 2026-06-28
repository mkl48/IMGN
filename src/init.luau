-- IMGN - verification-free editable images for Roblox.
--
-- One entry point on both realms: require(ReplicatedStorage.IMGN). Roblox gates EditableImage
-- behind creator age/ID verification; IMGN sidesteps it entirely by drawing the image out of GUI
-- Frames instead, so a fully writable runtime canvas needs no verification at all. new() builds a
-- bare Canvas you mount yourself; Surface()/Billboard() build the container for you on a part or
-- adornee. Everything hangs off the Canvas' verbs - SetPixel/Fill/Draw*/Shader/Blit - and nothing
-- renders until :Render() (or AutoRender) flushes the dirty pixels.
--
-- See _Classes/Canvas/init.luau for the full Canvas surface and _Core/Config.luau for the global
-- defaults Configure() overrides.

--[=[
	@class IMGN
]=]

local Canvas = require(script._Classes.Canvas)
local AppClass = require(script._Classes.App)
local LiquidClass = require(script._Classes.Liquid)
local BloodModule = require(script._Classes.Blood)
local ParticlesClass = require(script._Classes.Particles)
local RaycasterClass = require(script._Classes.Raycaster)
local ImageHelper = require(script._Patterns.Image)
local DitherHelper = require(script._Patterns.Dither)
local TextureHelper = require(script._Patterns.Texture)
local ChartHelper = require(script._Patterns.Chart)
local IdenticonHelper = require(script._Patterns.Identicon)
local EffectsHelper = require(script._Patterns.Effect)
local ConfigModule = require(script._Core.Config)

local IMGN = {}

export type Canvas = Canvas.Canvas
export type CanvasConfig = Canvas.CanvasConfig
export type Region = Canvas.Region
export type App = AppClass.App
export type AppConfig = AppClass.AppConfig
export type Object = AppClass.Object
export type ObjectConfig = AppClass.ObjectConfig
export type Liquid = LiquidClass.Liquid
export type LiquidConfig = LiquidClass.LiquidConfig
export type Particles = ParticlesClass.Particles
export type ParticlesConfig = ParticlesClass.ParticlesConfig
export type Raycaster = RaycasterClass.Raycaster
export type RaycasterConfig = RaycasterClass.RaycasterConfig
export type Config = ConfigModule.Config

--[=[
	@within IMGN
	Merges feature-flag overrides into IMGN's shared [Config] - `DefaultDriver`, `MaxPixels`,
	`WarnOnLargeCanvas`, `AutoRender`. Read at `Canvas` creation, so changes apply to canvases made
	afterwards. Unknown keys error.
]=]
function IMGN.Configure(overrides: { [string]: any })
	ConfigModule.configure(overrides)
end

--[=[
	@within IMGN
	Creates a [Canvas] from `config` (see [CanvasConfig]). Pass `Parent` to mount immediately, or
	omit it and call `canvas:Mount(container)` later.
]=]
function IMGN.new(config: CanvasConfig): Canvas
	return Canvas.new(config)
end

--[=[
	@within IMGN
	Creates an [App] (see [AppConfig]) - the managed layer with Objects, collisions and a step/draw
	loop. Pass an existing `Canvas` (e.g. from [IMGN.Surface]) or `Resolution`/`Parent` to build one.
]=]
function IMGN.App(config: AppConfig): App
	return AppClass.new(config)
end

--[=[
	@within IMGN
	Creates a [Liquid] simulation (see [LiquidConfig]) - splatting, dripping, pooling, drying fluid
	on a canvas. `Preset` picks the fluid ("Blood" default, plus Water/Paint/Lava/Slime/Honey).
	Pass an existing `Canvas` or `Resolution`/`Parent`. `:Splat` to add fluid, `:Start` to run it.
]=]
function IMGN.Liquid(config: LiquidConfig): Liquid
	return LiquidClass.new(config)
end

--[=[
	@within IMGN
	The blood engine (built on [Liquid]): `IMGN.Blood.Emit(origin, velocity)` throws a 3D droplet
	that lands and drips, `IMGN.Blood.KillBrick(part)` makes a brick that spurts blood when stepped
	on, `IMGN.Blood.Splat(part, face, worldPos, amount)` paints a surface directly, and
	`IMGN.Blood.Configure{ … }` tunes it. Drips follow the surface's downhill (walls/slopes/rotation).
]=]
IMGN.Blood = BloodModule

--[=[
	@within IMGN
	Creates a [Particles] emitter (see [ParticlesConfig]) drawing on a canvas - `Preset` is "Fire",
	"Sparks", "Rain", "Snow", "Explosion" or "Confetti". `:Start()` for continuous emission or
	`:Burst(n)` for a one-shot.
]=]
function IMGN.Particles(config: ParticlesConfig): Particles
	return ParticlesClass.new(config)
end

--[=[
	@within IMGN
	Palette helpers for [Canvas:Dither] / [Canvas:Quantize]. `IMGN.Palette.Grayscale(n)` builds an
	n-shade grayscale palette; pass any `{ Color3 }` array for a custom palette.
]=]
IMGN.Palette = {
	Grayscale = DitherHelper.grayscale,
}

--[=[
	@within IMGN
	Creates a [Raycaster] - a textured software-3D engine (Doom-style) on a canvas. Pass a `Map`
	(rows of wall-id chars) and `Textures`; move with `:Move`/`:Turn` or `:Start()` for built-in
	WASD, and `:Render()` each frame. Build wall/sprite textures with [IMGN.Texture].
]=]
function IMGN.Raycaster(config: RaycasterConfig): Raycaster
	return RaycasterClass.new(config)
end

--[=[
	@within IMGN
	Texture generators for the [Raycaster]: `IMGN.Texture.brick/checker/solid(...)` build procedural
	textures, and `IMGN.Texture.fromCanvas(canvas)` turns a loaded image into a wall/sprite texture.
]=]
IMGN.Texture = TextureHelper

--[=[
	@within IMGN
	Chart drawing onto a canvas/region: `IMGN.Chart.line(target, data, opts)`,
	`IMGN.Chart.bar(target, data, opts)`, `IMGN.Chart.pie(target, slices)`.
]=]
IMGN.Chart = ChartHelper

--[=[
	@within IMGN
	Draws a deterministic identicon (symmetric avatar) for `seed` onto a canvas/region - a unique
	per-player/per-item icon with no uploads. See [Identicon].
]=]
function IMGN.Identicon(target: any, seed: any, options: any?)
	IdenticonHelper.draw(target, seed, options)
end

--[=[
	@within IMGN
	Post-processing effects you can apply to a canvas/region (also via `canvas:Effect("CRT")`):
	`IMGN.Effects.crt/glitch/hologram/edges/wave/bloom/scanlines/chromatic/vignette/grain/ascii/
	grayscale/invert/posterize/tint(target, ...)`.
]=]
IMGN.Effects = EffectsHelper

--[=[
	@within IMGN
	Decodes a real image file (PNG/BMP/TGA/JPG) and returns a [Canvas] sized to it (times `Scale`),
	already drawn and rendered. The decoder is bundled with IMGN - just pass `bytes`, the file as a
	`string`/`buffer`. `config` accepts `Parent`, `Driver`, `AutoRender`, plus image
	`Scale`/`Format`/`SkipTransparent`. For finer placement onto an existing canvas, use
	[Canvas:LoadImage] instead.
]=]
function IMGN.ImageCanvas(bytes: string | buffer, config: {
	Parent: Instance?,
	Driver: any?,
	AutoRender: boolean?,
	Scale: number?,
	Format: string?,
	SkipTransparent: boolean?,
}?): Canvas
	config = config or {}
	local decoded = ImageHelper.decode(bytes, config.Format)
	local scale = config.Scale or 1
	local width = math.max(1, math.floor(decoded.width * scale + 0.5))
	local height = math.max(1, math.floor(decoded.height * scale + 0.5))

	local canvas = Canvas.new({
		Resolution = Vector2.new(width, height),
		Parent = config.Parent,
		Driver = config.Driver,
		AutoRender = config.AutoRender,
	})
	ImageHelper.blit(canvas, decoded, { Scale = scale, SkipTransparent = config.SkipTransparent })
	canvas:Render()
	return canvas
end

--[=[
	@within IMGN
	Progressive [IMGN.ImageCanvas]: builds the canvas' Frames and draws the image while yielding on
	a per-frame time budget, so a big image loads without dropping frames. `config.Parent` is
	required (it mounts as it builds). Tuning: `FrameBudget` (seconds/frame, default
	[Config.LoadFrameBudget]), `RowsPerFrame` (fallback), `OnProgress(0..1)` (mount is the first
	half, drawing the second) and `OnComplete`. Must run on a yielding thread - wrap in `task.spawn`.
	The decode step itself isn't split.
]=]
function IMGN.ImageCanvasAsync(bytes: string | buffer, config: {
	Parent: Instance,
	Driver: any?,
	AutoRender: boolean?,
	Scale: number?,
	Format: string?,
	SkipTransparent: boolean?,
	FrameBudget: (number | false)?,
	RowsPerFrame: number?,
	OnProgress: ((number) -> ())?,
	OnComplete: (() -> ())?,
}): Canvas
	assert(config and config.Parent, "IMGN.ImageCanvasAsync: config.Parent is required")
	local decoded = ImageHelper.decode(bytes, config.Format)
	local scale = config.Scale or 1
	local width = math.max(1, math.floor(decoded.width * scale + 0.5))
	local height = math.max(1, math.floor(decoded.height * scale + 0.5))
	local report = config.OnProgress

	local canvas = Canvas.new({
		Resolution = Vector2.new(width, height),
		Driver = config.Driver,
		AutoRender = config.AutoRender,
	})

	-- Mount progressively (first half of progress), then draw progressively (second half) - both
	-- pace off the same time budget so the whole load stays under it.
	canvas:MountAsync(config.Parent, {
		FrameBudget = config.FrameBudget,
		RowsPerFrame = config.RowsPerFrame,
		OnProgress = if report then function(f)
			report(f * 0.5)
		end else nil,
	})

	local budget: number?
	if config.FrameBudget == false then
		budget = nil
	elseif config.FrameBudget ~= nil then
		budget = config.FrameBudget :: number
	else
		budget = ConfigModule.Config.LoadFrameBudget
	end
	local pace = ImageHelper.newPacer({
		Budget = budget,
		RowsPerYield = config.RowsPerFrame or ConfigModule.Config.LoadRowsPerFrame,
		Yield = task.wait,
		OnProgress = if report then function(f)
			report(0.5 + f * 0.5)
		end else nil,
		BeforeYield = function()
			canvas:Render()
		end,
	})
	ImageHelper.blitAsync(canvas, decoded, { Scale = scale, SkipTransparent = config.SkipTransparent }, pace)

	if config.OnComplete then
		config.OnComplete()
	end

	return canvas
end

--[=[
	@within IMGN
	Builds a [Canvas] sized to a decoded pixel table (from a web image service, after
	`HttpService:JSONDecode`) - times `Scale` - already drawn and rendered. `data` is the
	`{ width, height, pixels|rows }` shape [Canvas:LoadPixels] accepts. `config` accepts `Parent`,
	`Driver` (try `"GreedyMesh"` for flat art), `AutoRender`, `Scale` and `SkipTransparent`.
]=]
function IMGN.PixelCanvas(data: any, config: {
	Parent: Instance?,
	Driver: any?,
	AutoRender: boolean?,
	Scale: number?,
	SkipTransparent: boolean?,
}?): Canvas
	config = config or {}
	local scale = config.Scale or 1
	local width = math.max(1, math.floor(data.width * scale + 0.5))
	local height = math.max(1, math.floor(data.height * scale + 0.5))

	local canvas = Canvas.new({
		Resolution = Vector2.new(width, height),
		Parent = config.Parent,
		Driver = config.Driver,
		AutoRender = config.AutoRender,
	})
	canvas:LoadPixels(data, { Scale = scale, SkipTransparent = config.SkipTransparent })
	canvas:Render()
	return canvas
end

--[=[
	@within IMGN
	Creates (or reuses) a `SurfaceGui` on `part`'s `face` and mounts a [Canvas] onto it - the
	in-world path (signs, screens, billboards on a brick). `face` defaults to `Enum.NormalId.Front`.
	Any [CanvasConfig] field except `Parent` is honoured.
]=]
function IMGN.Surface(part: BasePart, face: Enum.NormalId?, config: CanvasConfig): (Canvas, SurfaceGui)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "IMGNSurface"
	surface.Face = face or Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 50
	surface.CanvasSize = Vector2.new(config.Resolution.X, config.Resolution.Y)
	surface.Adornee = part
	surface.Parent = part

	local canvasConfig = table.clone(config)
	canvasConfig.Parent = surface
	return Canvas.new(canvasConfig), surface
end

--[=[
	@within IMGN
	Creates a `BillboardGui` adorned to `adornee` and mounts a [Canvas] onto it - the screen-facing
	path (floating image that always faces the camera). `size` is the billboard's `Size`
	(defaults to a square sized from the canvas' aspect). Any [CanvasConfig] field except `Parent`
	is honoured.
]=]
function IMGN.Billboard(adornee: Instance, size: UDim2?, config: CanvasConfig): (Canvas, BillboardGui)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "IMGNBillboard"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.Size = size or UDim2.fromScale(config.Resolution.X / config.Resolution.Y, 1)
	billboard.Parent = adornee

	local canvasConfig = table.clone(config)
	canvasConfig.Parent = billboard
	return Canvas.new(canvasConfig), billboard
end

return IMGN
