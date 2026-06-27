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
local ImageHelper = require(script._Patterns.Image)
local ConfigModule = require(script._Core.Config)

local IMGN = {}

export type Canvas = Canvas.Canvas
export type CanvasConfig = Canvas.CanvasConfig
export type App = AppClass.App
export type AppConfig = AppClass.AppConfig
export type Object = AppClass.Object
export type ObjectConfig = AppClass.ObjectConfig
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
	Progressive [IMGN.ImageCanvas]: builds the canvas' Frames and draws the image a few rows per
	frame so a big image loads smoothly instead of freezing. `config.Parent` is required (it mounts
	as it builds), `config.RowsPerFrame` (default 8) tunes the budget, and `config.OnProgress(0..1)`
	reports progress (mount counts as the first half, drawing the second). Must run on a yielding
	thread - wrap the call in `task.spawn`. Note the decode step itself isn't split.
]=]
function IMGN.ImageCanvasAsync(bytes: string | buffer, config: {
	Parent: Instance,
	Driver: any?,
	AutoRender: boolean?,
	Scale: number?,
	Format: string?,
	SkipTransparent: boolean?,
	RowsPerFrame: number?,
	OnProgress: ((number) -> ())?,
}): Canvas
	assert(config and config.Parent, "IMGN.ImageCanvasAsync: config.Parent is required")
	local decoded = ImageHelper.decode(bytes, config.Format)
	local scale = config.Scale or 1
	local width = math.max(1, math.floor(decoded.width * scale + 0.5))
	local height = math.max(1, math.floor(decoded.height * scale + 0.5))
	local rows = config.RowsPerFrame or 8
	local report = config.OnProgress

	local canvas = Canvas.new({
		Resolution = Vector2.new(width, height),
		Driver = config.Driver,
		AutoRender = config.AutoRender,
	})

	-- Mount progressively (first half of progress), then draw progressively (second half).
	canvas:MountAsync(config.Parent, rows, if report then function(f)
		report(f * 0.5)
	end else nil)
	ImageHelper.blitAsync(canvas, decoded, { Scale = scale, SkipTransparent = config.SkipTransparent }, rows, function()
		task.wait()
	end, if report then function(f)
		report(0.5 + f * 0.5)
	end else nil)

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
