-- IMGN
-- _Classes/Canvas/init.luau
-- Plinko Labs
--
-- The one object you actually hold. A Canvas owns a PixelBuffer (the pixels) and a Driver (the
-- Instances), and every verb - SetPixel, Fill, the Draw primitives, Shader, Blit - writes the
-- buffer and tells the Driver which pixels went dirty. Nothing reaches the screen until a flush:
-- `:Render()` by hand, or `AutoRender = true` to flush dirty pixels every Heartbeat. This split
-- is the whole point of the package - batch a thousand edits, pay for one flush.

local RunService = game:GetService("RunService")

local PixelBuffer = require(script.Parent.Parent._Core.PixelBuffer)
local ConfigModule = require(script.Parent.Parent._Core.Config)
local Drivers = require(script.Parent.Parent._Drivers)
local Draw = require(script.Parent.Parent._Patterns.Draw)
local Font = require(script.Parent.Parent._Patterns.Font)

local Config = ConfigModule.Config

type PixelBuffer = PixelBuffer.PixelBuffer
type Driver = Drivers.Driver

--[=[
	@class Canvas
	A writable pixel image rendered from GUI Frames - no `EditableImage`, no verification. Create
	one with [IMGN.new], [IMGN.Surface] or [IMGN.Billboard], draw into it, then [Canvas:Render].
	Coordinates are 0-indexed with `(0, 0)` top-left; out-of-bounds writes are clipped silently.
]=]
local Canvas = {}
Canvas.__index = Canvas

--[=[
	@interface CanvasConfig
	@within Canvas
	.Resolution Vector2 -- pixel dimensions of the canvas (width x height), required
	.Parent Instance? -- a GUI container (SurfaceGui/BillboardGui/GuiObject) to mount into now; omit to mount later with `:Mount`
	.Background Color3? -- if set, the canvas starts filled opaque with this colour instead of transparent
	.Driver ("PixelGrid" | "RowMerge")? -- renderer; defaults to [Config.DefaultDriver]
	.AutoRender boolean? -- flush dirty pixels every Heartbeat; defaults to [Config.AutoRender]
]=]
export type CanvasConfig = {
	Resolution: Vector2,
	Parent: Instance?,
	Background: Color3?,
	Driver: Drivers.DriverType?,
	AutoRender: boolean?,
}

export type Canvas = typeof(setmetatable(
	{} :: {
		Width: number,
		Height: number,
		_buffer: PixelBuffer,
		_driver: Driver,
		_autoRender: boolean,
		_heartbeat: RBXScriptConnection?,
		_mounted: boolean,
	},
	Canvas
))

--[=[
	@within Canvas
	Builds a Canvas at `config.Resolution`. If `config.Parent` is given it mounts immediately;
	otherwise call [Canvas:Mount] later. Warns once (unless [Config.WarnOnLargeCanvas] is off) when
	the pixel count exceeds [Config.MaxPixels] - instance count is the ceiling here, not memory.
]=]
function Canvas.new(config: CanvasConfig): Canvas
	local resolution = config.Resolution
	assert(typeof(resolution) == "Vector2", "IMGN.new: config.Resolution must be a Vector2")

	local width = math.floor(resolution.X)
	local height = math.floor(resolution.Y)
	assert(width > 0 and height > 0, "IMGN.new: Resolution must be positive")

	if Config.WarnOnLargeCanvas and width * height > Config.MaxPixels then
		warn(
			`IMGN: canvas {width}x{height} = {width * height} pixels exceeds MaxPixels ({Config.MaxPixels}). `
				.. `A Frame-based canvas is bound by instance count - expect framerate cost at this size. `
				.. `Silence with IMGN.Configure(\{ WarnOnLargeCanvas = false }).`
		)
	end

	local pixelBuffer = PixelBuffer.new(width, height)
	local driverName = config.Driver or Config.DefaultDriver

	local self: Canvas = setmetatable({
		Width = width,
		Height = height,
		_buffer = pixelBuffer,
		_driver = Drivers.get(driverName, pixelBuffer),
		_autoRender = if config.AutoRender ~= nil then config.AutoRender else Config.AutoRender,
		_heartbeat = nil,
		_mounted = false,
	}, Canvas)

	if config.Background then
		Canvas.Fill(self, config.Background, 1)
	end

	if config.Parent then
		Canvas.Mount(self, config.Parent)
	end

	return self
end

--[=[
	@within Canvas
	Builds the Driver's Instances under `parent` (any GUI container). If `AutoRender` is on, wires
	the Heartbeat flush here. Safe to call once; mounting an already-mounted canvas errors.
]=]
function Canvas.Mount(self: Canvas, parent: Instance)
	assert(not self._mounted, "IMGN Canvas: already mounted")
	self._driver:Mount(parent)
	self._mounted = true

	-- Push whatever's already in the buffer (e.g. a Background fill) to the screen.
	self._driver:Flush()

	if self._autoRender then
		self._heartbeat = RunService.Heartbeat:Connect(function()
			self._driver:Flush()
		end)
	end
end

--[=[
	@within Canvas
	Writes `color` (and optional `alpha`, default `1`) at `(x, y)` and marks it dirty. Clipped
	silently if out of bounds. Cheap - the visible update happens on the next flush.
]=]
function Canvas.SetPixel(self: Canvas, x: number, y: number, color: Color3, alpha: number?)
	x, y = math.floor(x), math.floor(y)
	if PixelBuffer.Set(self._buffer, x, y, color, alpha) then
		self._driver:SetDirty(y * self.Width + x)
	end
end

--[=[
	@within Canvas
	Reads the colour and alpha at `(x, y)`. Out-of-bounds returns transparent black.
]=]
function Canvas.GetPixel(self: Canvas, x: number, y: number): (Color3, number)
	return PixelBuffer.Get(self._buffer, math.floor(x), math.floor(y))
end

--[=[
	@within Canvas
	Sets every pixel to `color`/`alpha` and marks the whole canvas dirty.
]=]
function Canvas.Fill(self: Canvas, color: Color3, alpha: number?)
	local width, height = self.Width, self.Height
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			PixelBuffer.Set(self._buffer, x, y, color, alpha)
		end
	end
	self._driver:SetAllDirty()
end

--[=[
	@within Canvas
	Clears every pixel to transparent black.
]=]
function Canvas.Clear(self: Canvas)
	Canvas.Fill(self, Color3.new(0, 0, 0), 0)
end

--[=[
	@within Canvas
	Runs `shader(x, y, currentColor, currentAlpha)` for every pixel and writes back whatever colour
	(and optional alpha) it returns; returning `nil` leaves the pixel untouched. This is the
	procedural/generated path - gradients, noise, plots, data viz.
]=]
function Canvas.Shader(self: Canvas, shader: (x: number, y: number, color: Color3, alpha: number) -> (Color3?, number?))
	local width, height = self.Width, self.Height
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local current, currentAlpha = PixelBuffer.Get(self._buffer, x, y)
			local color, alpha = shader(x, y, current, currentAlpha)
			if color then
				PixelBuffer.Set(self._buffer, x, y, color, if alpha ~= nil then alpha else currentAlpha)
			end
		end
	end
	self._driver:SetAllDirty()
end

--[=[
	@within Canvas
	Draws a line from `(x0, y0)` to `(x1, y1)` in `color`.
]=]
function Canvas.DrawLine(self: Canvas, x0: number, y0: number, x1: number, y1: number, color: Color3, alpha: number?)
	Draw.line(function(x, y)
		Canvas.SetPixel(self, x, y, color, alpha)
	end, x0, y0, x1, y1)
end

--[=[
	@within Canvas
	Draws a rectangle at top-left `(x, y)` of size `width` x `height`. `filled` fills it; otherwise
	just the border.
]=]
function Canvas.DrawRect(
	self: Canvas,
	x: number,
	y: number,
	width: number,
	height: number,
	color: Color3,
	filled: boolean?,
	alpha: number?
)
	Draw.rect(function(px, py)
		Canvas.SetPixel(self, px, py, color, alpha)
	end, x, y, width, height, filled)
end

--[=[
	@within Canvas
	Draws a circle of `radius` centred on `(cx, cy)`. `filled` draws the disc; otherwise the
	outline.
]=]
function Canvas.DrawCircle(self: Canvas, cx: number, cy: number, radius: number, color: Color3, filled: boolean?, alpha: number?)
	Draw.circle(function(x, y)
		Canvas.SetPixel(self, x, y, color, alpha)
	end, cx, cy, radius, filled)
end

--[=[
	@within Canvas
	Draws `text` in the built-in 3x5 bitmap font with its top-left at `(x, y)`. `scale` (default 1)
	enlarges each font pixel into a block. Letters are uppercase-only; see [Font]. Returns the x
	just past the text, for chaining.
]=]
function Canvas.Text(self: Canvas, text: string, x: number, y: number, color: Color3, scale: number?, alpha: number?): number
	return Font.draw(function(px, py)
		Canvas.SetPixel(self, px, py, color, alpha)
	end, text, math.floor(x), math.floor(y), scale)
end

--[=[
	@within Canvas
	Copies another `Canvas`'s pixels into this one with its top-left at `(dx, dy)`. Source pixels
	are clipped against this canvas' bounds.
]=]
function Canvas.Blit(self: Canvas, source: Canvas, dx: number, dy: number)
	dx, dy = math.floor(dx), math.floor(dy)
	for sy = 0, source.Height - 1 do
		for sx = 0, source.Width - 1 do
			local color, alpha = PixelBuffer.Get(source._buffer, sx, sy)
			Canvas.SetPixel(self, dx + sx, dy + sy, color, alpha)
		end
	end
end

--[=[
	@within Canvas
	Flushes every dirty pixel onto its Instances. Call after a batch of edits; a no-op when
	nothing changed. Unnecessary when `AutoRender` is on.
]=]
function Canvas.Render(self: Canvas)
	self._driver:Flush()
end

--[=[
	@within Canvas
	Disconnects the AutoRender Heartbeat (if any) and destroys every Instance. The Canvas is unusable
	afterwards.
]=]
function Canvas.Destroy(self: Canvas)
	if self._heartbeat then
		self._heartbeat:Disconnect()
		self._heartbeat = nil
	end
	self._driver:Destroy()
	self._mounted = false
end

return Canvas
