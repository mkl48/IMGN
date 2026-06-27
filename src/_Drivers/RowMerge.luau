-- IMGN
-- _Drivers/RowMerge.luau
-- Plinko Labs
--
-- The memory-light renderer: instead of one Frame per pixel, each row is run-length-merged so a
-- horizontal span of identical pixels becomes a single wide Frame. A flat-colour 64-wide row can
-- collapse from 64 Frames to two or three. Fully-transparent runs allocate nothing at all. The
-- trade-off vs PixelGrid: a flush rebuilds whole *rows* (every dirty row re-runs its RLE), so
-- this wins for sprites/static art and loses for noisy, every-pixel-different procedural churn.
--
-- Per-row Frame pooling: each row keeps its run Frames and reuses them across rebuilds, only
-- allocating when a rebuild needs more runs than last time and hiding the surplus otherwise.

local RowMerge = {}
RowMerge.__index = RowMerge

local PixelBuffer = require(script.Parent.Parent._Core.PixelBuffer)
type PixelBuffer = PixelBuffer.PixelBuffer

type Row = {
	frames: { Frame },
	used: number,
}

export type RowMerge = typeof(setmetatable(
	{} :: {
		_buffer: PixelBuffer,
		_width: number,
		_height: number,
		_rows: { Row },
		_dirtyRows: { [number]: boolean },
		_dirtyCount: number,
		_container: Frame?,
	},
	RowMerge
))

--[=[
	@class RowMerge
	@within Canvas
	Run-length-merged rows, one Frame per colour run. Selected with `Driver = "RowMerge"`.
]=]
function RowMerge.new(pixelBuffer: PixelBuffer): RowMerge
	local rows = {}
	for y = 0, pixelBuffer.Height - 1 do
		rows[y] = { frames = {}, used = 0 }
	end

	return setmetatable({
		_buffer = pixelBuffer,
		_width = pixelBuffer.Width,
		_height = pixelBuffer.Height,
		_rows = rows,
		_dirtyRows = {},
		_dirtyCount = 0,
		_container = nil,
	}, RowMerge)
end

--[=[
	@within RowMerge
	Builds an empty container Frame and parents it into `parent`. Run Frames are created lazily on
	the first flush of each row.
]=]
function RowMerge.Mount(self: RowMerge, parent: Instance): Frame
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

--[=[
	@within RowMerge
	Marks the row containing linear index `index` (0-based `y*width + x`) dirty.
]=]
function RowMerge.SetDirty(self: RowMerge, index: number)
	local row = (index - index % self._width) / self._width
	if not self._dirtyRows[row] then
		self._dirtyRows[row] = true
		self._dirtyCount += 1
	end
end

--[=[
	@within RowMerge
	Marks every row dirty - used after a whole-buffer `Fill`/`Shader`.
]=]
function RowMerge.SetAllDirty(self: RowMerge)
	for y = 0, self._height - 1 do
		self._dirtyRows[y] = true
	end
	self._dirtyCount = self._height
end

local function acquire(row: Row, container: Frame): Frame
	row.used += 1
	local frame = row.frames[row.used]
	if not frame then
		frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.ZIndex = 1
		frame.Parent = container
		row.frames[row.used] = frame
	end
	frame.Visible = true
	return frame
end

--[=[
	@within RowMerge
	Rebuilds every dirty row by run-length-merging equal pixels into wide Frames, then clears the
	dirty set. Surplus Frames from a previous, busier rebuild are hidden rather than destroyed.
]=]
function RowMerge.Flush(self: RowMerge)
	if self._dirtyCount == 0 then
		return
	end

	local container = self._container :: Frame
	local pixelBuffer = self._buffer
	local width, height = self._width, self._height
	local sx = 1 / width
	local sy = 1 / height

	for y in self._dirtyRows do
		local row = self._rows[y]
		row.used = 0

		local runStart = 0
		local r0, g0, b0, a0 = PixelBuffer.GetBytes(pixelBuffer, 0, y)

		local function emit(startX: number, endX: number, r: number, g: number, b: number, a: number)
			if a == 0 then
				return -- fully transparent run: draw nothing.
			end
			local frame = acquire(row, container)
			frame.Position = UDim2.fromScale(startX * sx, y * sy)
			frame.Size = UDim2.new((endX - startX + 1) * sx, 1, sy, 1)
			frame.BackgroundColor3 = Color3.fromRGB(r, g, b)
			frame.BackgroundTransparency = 1 - a / 255
		end

		for x = 1, width - 1 do
			local r, g, b, a = PixelBuffer.GetBytes(pixelBuffer, x, y)
			if r ~= r0 or g ~= g0 or b ~= b0 or a ~= a0 then
				emit(runStart, x - 1, r0, g0, b0, a0)
				runStart = x
				r0, g0, b0, a0 = r, g, b, a
			end
		end
		emit(runStart, width - 1, r0, g0, b0, a0)

		-- Hide run Frames left over from a busier previous rebuild of this row.
		for i = row.used + 1, #row.frames do
			row.frames[i].Visible = false
		end
	end

	self._dirtyRows = {}
	self._dirtyCount = 0
end

--[=[
	@within RowMerge
	Tears down every run Frame and the container.
]=]
function RowMerge.Destroy(self: RowMerge)
	if self._container then
		self._container:Destroy()
		self._container = nil
	end
	self._rows = {}
	self._dirtyRows = {}
	self._dirtyCount = 0
end

return RowMerge
