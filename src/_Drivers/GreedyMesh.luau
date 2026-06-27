-- IMGN
-- _Drivers/GreedyMesh.luau
-- Plinko Labs
--
-- The fewest-Frames renderer: true 2D greedy meshing. Where RowMerge merges same-colour pixels
-- along each row (1D runs), this merges them into maximal rectangles in BOTH axes - a 50x50 flat
-- sky becomes one Frame, not 50. For flat / pixel-art images that's a 90%+ cut in instance count.
--
-- The trade-off: a mesh is global, so any change rebuilds the whole thing (clear every Frame,
-- re-mesh the buffer). That's ideal for a static image loaded once, and wrong for per-frame
-- animation - use PixelGrid there. Frames are pooled across rebuilds; fully-transparent regions
-- cost nothing.

local GreedyMesh = {}
GreedyMesh.__index = GreedyMesh

local PixelBuffer = require(script.Parent.Parent._Core.PixelBuffer)
type PixelBuffer = PixelBuffer.PixelBuffer

export type GreedyMesh = typeof(setmetatable(
	{} :: {
		_buffer: PixelBuffer,
		_width: number,
		_height: number,
		_frames: { Frame },
		_used: number,
		_visited: { boolean },
		_dirty: boolean,
		_container: Frame?,
	},
	GreedyMesh
))

--[=[
	@class GreedyMesh
	@within Canvas
	2D rectangle merging - the lowest Frame count for flat/static images. Selected with
	`Driver = "GreedyMesh"`.
]=]
function GreedyMesh.new(pixelBuffer: PixelBuffer): GreedyMesh
	return setmetatable({
		_buffer = pixelBuffer,
		_width = pixelBuffer.Width,
		_height = pixelBuffer.Height,
		_frames = {},
		_used = 0,
		_visited = {},
		_dirty = false,
		_container = nil,
	}, GreedyMesh)
end

--[=[
	@within GreedyMesh
	Builds an empty container; rectangles are created lazily on the first flush.
]=]
function GreedyMesh.Mount(self: GreedyMesh, parent: Instance): Frame
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

-- Any pixel change dirties the whole mesh (greedy meshing is global).
function GreedyMesh.SetDirty(self: GreedyMesh)
	self._dirty = true
end

function GreedyMesh.SetAllDirty(self: GreedyMesh)
	self._dirty = true
end

local function acquire(self: GreedyMesh): Frame
	self._used += 1
	local frame = self._frames[self._used]
	if not frame then
		frame = Instance.new("Frame")
		frame.BorderSizePixel = 0
		frame.ZIndex = 1
		frame.Parent = self._container
		self._frames[self._used] = frame
	end
	frame.Visible = true
	return frame
end

--[=[
	@within GreedyMesh
	Re-meshes the whole buffer into maximal same-colour rectangles and lays them out as pooled
	Frames. Surplus Frames from a previous, busier mesh are hidden.
]=]
function GreedyMesh.Flush(self: GreedyMesh)
	if not self._dirty or not self._container then
		return
	end
	self._dirty = false

	local pixelBuffer = self._buffer
	local width, height = self._width, self._height
	local sx, sy = 1 / width, 1 / height
	local visited = self._visited
	table.clear(visited)
	self._used = 0

	local function matches(x: number, y: number, r0, g0, b0, a0): boolean
		local r, g, b, a = PixelBuffer.GetBytes(pixelBuffer, x, y)
		return r == r0 and g == g0 and b == b0 and a == a0
	end

	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local base = y * width + x
			if visited[base] then
				continue
			end
			local r, g, b, a = PixelBuffer.GetBytes(pixelBuffer, x, y)

			-- widest run on this row
			local w = 1
			while x + w < width and not visited[base + w] and matches(x + w, y, r, g, b, a) do
				w += 1
			end

			-- extend downward while the full [x, x+w) span matches and is free
			local h = 1
			local growing = true
			while growing and y + h < height do
				for xx = x, x + w - 1 do
					local j = (y + h) * width + xx
					if visited[j] or not matches(xx, y + h, r, g, b, a) then
						growing = false
						break
					end
				end
				if growing then
					h += 1
				end
			end

			-- claim the rectangle
			for yy = y, y + h - 1 do
				local row = yy * width
				for xx = x, x + w - 1 do
					visited[row + xx] = true
				end
			end

			-- emit it (skip fully-transparent regions)
			if a > 0 then
				local frame = acquire(self)
				frame.Position = UDim2.fromScale(x * sx, y * sy)
				frame.Size = UDim2.new(w * sx, 1, h * sy, 1)
				frame.BackgroundColor3 = Color3.fromRGB(r, g, b)
				frame.BackgroundTransparency = 1 - a / 255
			end
		end
	end

	for i = self._used + 1, #self._frames do
		self._frames[i].Visible = false
	end
end

--[=[
	@within GreedyMesh
	Destroys every Frame and the container.
]=]
function GreedyMesh.Destroy(self: GreedyMesh)
	if self._container then
		self._container:Destroy()
		self._container = nil
	end
	self._frames = {}
	self._visited = {}
	self._used = 0
end

return GreedyMesh
