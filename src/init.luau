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
local ConfigModule = require(script._Core.Config)

local IMGN = {}

export type Canvas = Canvas.Canvas
export type CanvasConfig = Canvas.CanvasConfig
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
