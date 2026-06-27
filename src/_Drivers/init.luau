-- IMGN
-- _Drivers/init.luau
-- Plinko Labs
--
-- The renderer registry. A Driver is the thing that turns the PixelBuffer into Instances and
-- pushes dirty pixels onto them; every Driver exposes the same surface (new/Mount/SetDirty/
-- SetAllDirty/Flush/Destroy) so Canvas treats them interchangeably and never cares which is in
-- play. Resolve one by name with `Drivers.get("PixelGrid")`.

local PixelGrid = require(script.PixelGrid)
local RowMerge = require(script.RowMerge)
local PixelBuffer = require(script.Parent._Core.PixelBuffer)
type PixelBuffer = PixelBuffer.PixelBuffer

--[=[
	@class Drivers
	@within Canvas
	The renderer lookup. `"PixelGrid"` (default) is one Frame per pixel - best for live drawing;
	`"RowMerge"` is run-length-merged rows - best for flat-colour sprites.
]=]
export type DriverType = "PixelGrid" | "RowMerge"

-- The common shape every Driver implements. Both concrete drivers are structurally compatible
-- with this; Canvas only ever calls through these methods.
export type Driver = {
	Mount: (self: any, parent: Instance) -> Frame,
	SetDirty: (self: any, index: number) -> (),
	SetAllDirty: (self: any) -> (),
	Flush: (self: any) -> (),
	Destroy: (self: any) -> (),
}

local constructors: { [string]: (PixelBuffer) -> Driver } = {
	PixelGrid = PixelGrid.new :: any,
	RowMerge = RowMerge.new :: any,
}

local Drivers = {}

--[=[
	@within Drivers
	Constructs the named Driver around `pixelBuffer`. Errors on an unknown name so a typo fails
	loudly at creation rather than rendering nothing.
]=]
function Drivers.get(name: string, pixelBuffer: PixelBuffer): Driver
	local constructor = constructors[name]
	assert(constructor, `IMGN: unknown Driver "{tostring(name)}" (expected "PixelGrid" or "RowMerge")`)
	return constructor(pixelBuffer)
end

return Drivers
