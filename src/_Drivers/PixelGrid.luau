-- IMGN
-- _Drivers/PixelGrid.luau
-- Plinko Labs
--
-- The default renderer: one pooled Frame per pixel. A flush only touches the Frames whose
-- pixels actually changed (dirty set), so a brush stroke updates a handful of Instances, not the
-- whole grid - which is exactly what live drawing wants. Memory-heavy at high resolution (one
-- Frame per pixel), so flat-colour sprites are better served by RowMerge.
--
-- Seam fix: each pixel Frame is sized one scale-cell PLUS one pixel on each axis
-- (`UDim2.new(1/w, 1, 1/h, 1)`). The +1px overlaps the next pixel so no background shows through
-- the sub-pixel cracks you'd otherwise get from fractional scale sizes.

local PixelGrid = {}
PixelGrid.__index = PixelGrid

local PixelBuffer = require(script.Parent.Parent._Core.PixelBuffer)
type PixelBuffer = PixelBuffer.PixelBuffer

export type PixelGrid = typeof(setmetatable(
	{} :: {
		_buffer: PixelBuffer,
		_width: number,
		_height: number,
		_frames: { Frame },
		_dirty: { [number]: boolean },
		_dirtyCount: number,
		_container: Frame?,
	},
	PixelGrid
))

--[=[
	@class PixelGrid
	@within Canvas
	One Frame per pixel, dirty-tracked. Selected with `Driver = "PixelGrid"` (the default).
]=]
function PixelGrid.new(pixelBuffer: PixelBuffer): PixelGrid
	return setmetatable({
		_buffer = pixelBuffer,
		_width = pixelBuffer.Width,
		_height = pixelBuffer.Height,
		_frames = {},
		_dirty = {},
		_dirtyCount = 0,
		_container = nil,
	}, PixelGrid)
end

--[=[
	@within PixelGrid
	Builds the Frame grid under a new container Frame and parents it into `parent`. The whole grid
	is assembled off-tree and parented once, so the renderer reflows a single time.
]=]
function PixelGrid.Mount(self: PixelGrid, parent: Instance): Frame
	local width, height = self._width, self._height

	local container = Instance.new("Frame")
	container.Name = "IMGNCanvas"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = true

	local sx = 1 / width
	local sy = 1 / height

	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local pixel = Instance.new("Frame")
			pixel.BorderSizePixel = 0
			pixel.BackgroundTransparency = 1
			-- +1px on each axis covers the sub-pixel seam between neighbouring scaled Frames.
			pixel.Size = UDim2.new(sx, 1, sy, 1)
			pixel.Position = UDim2.fromScale(x * sx, y * sy)
			pixel.ZIndex = 1
			pixel.Parent = container
			-- 1-indexed linear store mirroring the buffer's 0-indexed (y*w + x).
			self._frames[y * width + x + 1] = pixel
		end
	end

	container.Parent = parent
	self._container = container
	return container
end

-- Build one row of pixel Frames into the container.
local function buildRow(self: PixelGrid, container: Frame, sx: number, sy: number, y: number)
	local width = self._width
	for x = 0, width - 1 do
		local pixel = Instance.new("Frame")
		pixel.BorderSizePixel = 0
		pixel.BackgroundTransparency = 1
		pixel.Size = UDim2.new(sx, 1, sy, 1)
		pixel.Position = UDim2.fromScale(x * sx, y * sy)
		pixel.ZIndex = 1
		pixel.Parent = container
		self._frames[y * width + x + 1] = pixel
	end
end

--[=[
	@within PixelGrid
	Like [PixelGrid.Mount], but creates the grid `rowsPerYield` rows at a time, calling `yield`
	between batches so building thousands of Frames spreads across frames instead of hitching one.
	`onProgress(fraction)` is reported per batch. Must run on a yielding thread.
]=]
function PixelGrid.MountAsync(
	self: PixelGrid,
	parent: Instance,
	rowsPerYield: number,
	yield: () -> (),
	onProgress: ((number) -> ())?
): Frame
	local height = self._height
	local sx, sy = 1 / self._width, 1 / height

	local container = Instance.new("Frame")
	container.Name = "IMGNCanvas"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Parent = parent
	self._container = container

	local step = math.max(1, rowsPerYield)
	local y = 0
	while y < height do
		local toY = math.min(y + step - 1, height - 1)
		for row = y, toY do
			buildRow(self, container, sx, sy, row)
		end
		if onProgress then
			onProgress((toY + 1) / height)
		end
		y = toY + 1
		if y < height then
			yield()
		end
	end

	return container
end

--[=[
	@within PixelGrid
	Marks the pixel at linear index `index` (0-based `y*width + x`) as needing a flush.
]=]
function PixelGrid.SetDirty(self: PixelGrid, index: number)
	if not self._dirty[index] then
		self._dirty[index] = true
		self._dirtyCount += 1
	end
end

--[=[
	@within PixelGrid
	Marks every pixel dirty - used after a `Fill`/`Shader` that rewrote the whole buffer.
]=]
function PixelGrid.SetAllDirty(self: PixelGrid)
	local total = self._width * self._height
	for index = 0, total - 1 do
		self._dirty[index] = true
	end
	self._dirtyCount = total
end

--[=[
	@within PixelGrid
	Pushes every dirty pixel's colour from the buffer onto its Frame, then clears the dirty set.
	No-op when nothing is dirty.
]=]
function PixelGrid.Flush(self: PixelGrid)
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
	@within PixelGrid
	Tears down every Frame and the container.
]=]
function PixelGrid.Destroy(self: PixelGrid)
	if self._container then
		self._container:Destroy()
		self._container = nil
	end
	self._frames = {}
	self._dirty = {}
	self._dirtyCount = 0
end

return PixelGrid
