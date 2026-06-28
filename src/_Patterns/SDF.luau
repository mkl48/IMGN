-- IMGN
-- _Patterns/SDF.luau
-- Plinko Labs
--
-- Signed distance functions for the raymarcher. An SDF returns the distance from a point to the
-- nearest surface (negative inside); you compose a whole scene out of these primitives and
-- operators inside a `Scene(p) -> distance` function, and the raymarcher sphere-traces it. This is
-- how a few lines describe smooth, lit, shadowed 3D - no meshes.

--[=[
	@class SDF
	Signed-distance primitives + operators for [Raymarcher] scenes. Reached via `IMGN.SDF`.
]=]
local SDF = {}

local function vabs(v: Vector3): Vector3
	return Vector3.new(math.abs(v.X), math.abs(v.Y), math.abs(v.Z))
end
local function vmax(v: Vector3, s: number): Vector3
	return Vector3.new(math.max(v.X, s), math.max(v.Y, s), math.max(v.Z, s))
end

--[=[
	@within SDF
	Distance to a sphere of `radius` at `center`.
]=]
function SDF.sphere(p: Vector3, center: Vector3, radius: number): number
	return (p - center).Magnitude - radius
end

--[=[
	@within SDF
	Distance to a box at `center` with `half` extents.
]=]
function SDF.box(p: Vector3, center: Vector3, half: Vector3): number
	local q = vabs(p - center) - half
	return vmax(q, 0).Magnitude + math.min(math.max(q.X, math.max(q.Y, q.Z)), 0)
end

--[=[
	@within SDF
	Distance to a horizontal plane at height `y` (the ground).
]=]
function SDF.plane(p: Vector3, y: number): number
	return p.Y - y
end

--[=[
	@within SDF
	Distance to a torus (ring) at `center`, major radius `R`, tube radius `r`, lying in the XZ plane.
]=]
function SDF.torus(p: Vector3, center: Vector3, R: number, r: number): number
	local q = p - center
	local l = math.sqrt(q.X * q.X + q.Z * q.Z) - R
	return math.sqrt(l * l + q.Y * q.Y) - r
end

--[=[
	@within SDF
	Rounds a shape's distance by `radius` (inflates it with rounded edges).
]=]
function SDF.round(d: number, radius: number): number
	return d - radius
end

--[=[
	@within SDF
	Union of two shapes (the nearer surface).
]=]
function SDF.union(a: number, b: number): number
	return math.min(a, b)
end

--[=[
	@within SDF
	Subtracts shape `b` from shape `a`.
]=]
function SDF.subtract(a: number, b: number): number
	return math.max(a, -b)
end

--[=[
	@within SDF
	Intersection of two shapes.
]=]
function SDF.intersect(a: number, b: number): number
	return math.max(a, b)
end

--[=[
	@within SDF
	Smooth (blobby) union of two shapes, blended over `k`.
]=]
function SDF.smoothUnion(a: number, b: number, k: number): number
	local h = math.clamp(0.5 + 0.5 * (b - a) / k, 0, 1)
	return b + (a - b) * h - k * h * (1 - h)
end

return SDF
