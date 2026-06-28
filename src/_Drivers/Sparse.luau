-- IMGN
-- _Drivers/Sparse.luau
-- Plinko Labs
--
-- PixelGrid pre-builds one Frame per pixel - fine for a small canvas, a killer for a big one
-- (a wall-sized canvas is tens of thousands of mostly-transparent Frames). Sparse only ever
-- instantiates a Frame for a pixel that's actually VISIBLE, and returns it to a pool when that
-- pixel clears. So the instance count tracks the painted area, not the canvas area - you can run a
-- full-resolution sim over a huge surface and only pay for the pixels that have something on them
-- (e.g. the actual blood, not the whole wall).

local Sparse = {}
Sparse.__index = Sparse

local PixelBuffer = require(script.Parent.Parent._Core.PixelBuffer)
type PixelBuffer = PixelBuffer.PixelBuffer

export type Sparse = typeof(setmetatable(
	{} :: {
		_buffer: PixelBuffer,
		_width: number,
		_height: number,
		_assigned: { [number]: Frame }, -- pixel index -> its live Frame
		_pool: { Frame }, -- hidden Frames ready to reuse
		_dirty: { [number]: boolean },
		_dirtyCount: number,
		_container: Frame?,
	},
	Sparse
))

--[=[
	@class Sparse
	@within Canvas
	One Frame per *visible* pixel, pooled on demand - the instance count tracks painted area, not
	canvas area. Selected with `Driver = "Sparse"`; the way to run a sim over a big surface cheaply.
]=]
function Sparse.new(pixelBuffer: PixelBuffer): Sparse
	return setmetatable({
		_buffer = pixelBuffer,
		_width = pixelBuffer.Width,
		_height = pixelBuffer.Height,
		_assigned = {},
		_pool = {},
		_dirty = {},
		_dirtyCount = 0,
		_container = nil,
	}, Sparse)
end

--[=[
	@within Sparse
	Builds an empty container; per-pixel Frames are created lazily as pixels become visible.
]=]
function Sparse.Mount(self: Sparse, parent: Instance): Frame
	local container = Instance.new("Frame")
	container.Name = "IMGNCanvas"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Parent = parent
	self._container = container
	return container
end

function Sparse.SetDirty(self: Sparse, index: number)
	if not self._dirty[index] then
		self._dirty[index] = true
		self._dirtyCount += 1
	end
end

function Sparse.SetAllDirty(self: Sparse)
	local total = self._width * self._height
	for index = 0, total - 1 do
		self._dirty[index] = true
	end
	self._dirtyCount = total
end

local function acquire(self: Sparse): Frame
	local frame = table.remove(self._pool)
	if not frame then
		frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.ZIndex = 1
		frame.Parent = self._container
	end
	frame.Visible = true
	return frame
end

--[=[
	@within Sparse
	Pushes dirty pixels onto Frames - acquiring a pooled Frame when a pixel becomes visible and
	releasing it when the pixel clears - then clears the dirty set.
]=]
function Sparse.Flush(self: Sparse)
	if self._dirtyCount == 0 then
		return
	end

	local width = self._width
	local sx, sy = 1 / width, 1 / self._height
	local assigned, pool = self._assigned, self._pool

	for index in self._dirty do
		local x = index % width
		local y = (index - x) / width
		local color, alpha = PixelBuffer.Get(self._buffer, x, y)
		local frame = assigned[index]

		if alpha > 0.004 then
			if not frame then
				frame = acquire(self)
				frame.Size = UDim2.new(sx, 1, sy, 1) -- +1px overlap covers seams
				frame.Position = UDim2.fromScale(x * sx, y * sy)
				assigned[index] = frame
			end
			frame.BackgroundColor3 = color
			frame.BackgroundTransparency = 1 - alpha
		elseif frame then
			frame.Visible = false
			assigned[index] = nil
			table.insert(pool, frame)
		end
	end

	self._dirty = {}
	self._dirtyCount = 0
end

--[=[
	@within Sparse
	Destroys every Frame and the container.
]=]
function Sparse.Destroy(self: Sparse)
	if self._container then
		self._container:Destroy()
		self._container = nil
	end
	self._assigned = {}
	self._pool = {}
	self._dirty = {}
	self._dirtyCount = 0
end

return Sparse
