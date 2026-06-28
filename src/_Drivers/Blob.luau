-- IMGN
-- _Drivers/Blob.luau
-- Plinko Labs
--
-- Like PixelGrid, but every pixel is an oversized CIRCLE instead of a square. Neighbouring
-- circles overlap, so a low-resolution buffer renders as smooth, organic, metaball-style blobs
-- with rounded edges - no square pixels, no stair-stepped boundary. Perfect for fluids (blood,
-- water): run the sim coarse + cheap, and the circles melt the grid into something that looks
-- high-resolution. Dirty-tracked like PixelGrid, so only changed cells repaint.

local Blob = {}
Blob.__index = Blob

local PixelBuffer = require(script.Parent.Parent._Core.PixelBuffer)
type PixelBuffer = PixelBuffer.PixelBuffer

local OVERSIZE = 1.9 -- each circle is this many cells wide, so neighbours overlap and merge

export type Blob = typeof(setmetatable(
	{} :: {
		_buffer: PixelBuffer,
		_width: number,
		_height: number,
		_frames: { Frame },
		_dirty: { [number]: boolean },
		_dirtyCount: number,
		_container: Frame?,
	},
	Blob
))

--[=[
	@class Blob
	@within Canvas
	One overlapping circle per pixel - smooth, blobby output from a low-res buffer. Selected with
	`Driver = "Blob"`; ideal for the [Liquid] fluid sim.
]=]
function Blob.new(pixelBuffer: PixelBuffer): Blob
	return setmetatable({
		_buffer = pixelBuffer,
		_width = pixelBuffer.Width,
		_height = pixelBuffer.Height,
		_frames = {},
		_dirty = {},
		_dirtyCount = 0,
		_container = nil,
	}, Blob)
end

--[=[
	@within Blob
	Builds the circle grid under a container and parents it into `parent`.
]=]
function Blob.Mount(self: Blob, parent: Instance): Frame
	local width, height = self._width, self._height

	local container = Instance.new("Frame")
	container.Name = "IMGNCanvas"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = true

	local sx, sy = 1 / width, 1 / height

	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local pixel = Instance.new("Frame")
			pixel.AnchorPoint = Vector2.new(0.5, 0.5)
			pixel.BorderSizePixel = 0
			pixel.BackgroundTransparency = 1
			pixel.Size = UDim2.fromScale(sx * OVERSIZE, sy * OVERSIZE)
			pixel.Position = UDim2.fromScale((x + 0.5) * sx, (y + 0.5) * sy)
			pixel.ZIndex = 1
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0) -- full circle
			corner.Parent = pixel
			pixel.Parent = container
			self._frames[y * width + x + 1] = pixel
		end
	end

	container.Parent = parent
	self._container = container
	return container
end

--[=[
	@within Blob
	Marks the pixel at linear `index` (0-based `y*width + x`) for repaint.
]=]
function Blob.SetDirty(self: Blob, index: number)
	if not self._dirty[index] then
		self._dirty[index] = true
		self._dirtyCount += 1
	end
end

--[=[
	@within Blob
	Marks every pixel dirty.
]=]
function Blob.SetAllDirty(self: Blob)
	local total = self._width * self._height
	for index = 0, total - 1 do
		self._dirty[index] = true
	end
	self._dirtyCount = total
end

--[=[
	@within Blob
	Pushes every dirty cell's colour onto its circle, then clears the dirty set.
]=]
function Blob.Flush(self: Blob)
	if self._dirtyCount == 0 then
		return
	end

	local width = self._width
	for index in self._dirty do
		local frame = self._frames[index + 1]
		if frame then
			local x = index % width
			local y = (index - x) / width
			local color, alpha = PixelBuffer.Get(self._buffer, x, y)
			frame.BackgroundColor3 = color
			frame.BackgroundTransparency = 1 - alpha
		end
	end

	self._dirty = {}
	self._dirtyCount = 0
end

--[=[
	@within Blob
	Destroys every circle and the container.
]=]
function Blob.Destroy(self: Blob)
	if self._container then
		self._container:Destroy()
		self._container = nil
	end
	self._frames = {}
	self._dirty = {}
	self._dirtyCount = 0
end

return Blob
