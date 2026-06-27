-- IMGN
-- _Core/PixelBuffer.luau
-- Plinko Labs
--
-- The single source of truth for a canvas' pixels: a flat Luau `buffer` of RGBA8 bytes, one
-- pixel = four bytes at offset (y*width + x)*4. Nothing here touches Instances - Drivers read
-- back out of this on flush. Keeping the colour data in a `buffer` (not a table of Color3s)
-- keeps a 128x128 canvas at 64KB with zero per-pixel allocation, so per-frame Shader sweeps and
-- brush strokes don't churn the GC.

--[=[
	@class PixelBuffer
	A fixed-size RGBA8 pixel store. Coordinates are 0-indexed; `(0, 0)` is the top-left pixel.
	Out-of-bounds writes are clipped silently (return `false`) so procedural loops and clipped
	drawing primitives don't have to bounds-check every plot.
]=]
local PixelBuffer = {}
PixelBuffer.__index = PixelBuffer

export type PixelBuffer = typeof(setmetatable(
	{} :: {
		Width: number,
		Height: number,
		_data: buffer,
	},
	PixelBuffer
))

local function toByte(component: number): number
	-- Color3 components are 0..1 floats; round to the nearest 0..255 byte.
	return math.clamp(math.floor(component * 255 + 0.5), 0, 255)
end

--[=[
	@within PixelBuffer
	Allocates a `width` x `height` buffer, every pixel transparent black (all bytes `0`).
]=]
function PixelBuffer.new(width: number, height: number): PixelBuffer
	assert(width > 0 and height > 0, "IMGN PixelBuffer: width and height must be positive")
	assert(width % 1 == 0 and height % 1 == 0, "IMGN PixelBuffer: width and height must be integers")

	return setmetatable({
		Width = width,
		Height = height,
		_data = buffer.create(width * height * 4),
	}, PixelBuffer)
end

--[=[
	@within PixelBuffer
	Whether `(x, y)` lands inside the buffer.
]=]
function PixelBuffer.InBounds(self: PixelBuffer, x: number, y: number): boolean
	return x >= 0 and y >= 0 and x < self.Width and y < self.Height
end

--[=[
	@within PixelBuffer
	Writes `color` (and optional `alpha`, default `1`) at `(x, y)`. Returns `true` if the pixel
	was inside the buffer and written, `false` if it was clipped.
]=]
function PixelBuffer.Set(self: PixelBuffer, x: number, y: number, color: Color3, alpha: number?): boolean
	if not PixelBuffer.InBounds(self, x, y) then
		return false
	end

	local offset = (y * self.Width + x) * 4
	buffer.writeu8(self._data, offset, toByte(color.R))
	buffer.writeu8(self._data, offset + 1, toByte(color.G))
	buffer.writeu8(self._data, offset + 2, toByte(color.B))
	buffer.writeu8(self._data, offset + 3, toByte(if alpha ~= nil then alpha else 1))
	return true
end

--[=[
	@within PixelBuffer
	Reads the colour and alpha at `(x, y)`. Out-of-bounds reads return transparent black.
]=]
function PixelBuffer.Get(self: PixelBuffer, x: number, y: number): (Color3, number)
	if not PixelBuffer.InBounds(self, x, y) then
		return Color3.new(0, 0, 0), 0
	end

	local offset = (y * self.Width + x) * 4
	local r = buffer.readu8(self._data, offset)
	local g = buffer.readu8(self._data, offset + 1)
	local b = buffer.readu8(self._data, offset + 2)
	local a = buffer.readu8(self._data, offset + 3)
	return Color3.fromRGB(r, g, b), a / 255
end

--[=[
	@within PixelBuffer
	Reads the four raw bytes at `(x, y)` without rebuilding a `Color3` - used by Drivers when
	comparing adjacent pixels (RowMerge) so a flush avoids allocating a Color3 per pixel.
]=]
function PixelBuffer.GetBytes(self: PixelBuffer, x: number, y: number): (number, number, number, number)
	local offset = (y * self.Width + x) * 4
	return
		buffer.readu8(self._data, offset),
		buffer.readu8(self._data, offset + 1),
		buffer.readu8(self._data, offset + 2),
		buffer.readu8(self._data, offset + 3)
end

return PixelBuffer
