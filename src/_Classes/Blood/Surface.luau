-- IMGN
-- _Classes/Blood/Surface.luau
-- Plinko Labs
--
-- The 3D<->canvas math the blood engine needs: which face a hit landed on, where on that face's
-- canvas a world point sits, and - the important one for realism - the canvas-space gravity for a
-- face, so drips run downhill on walls, slopes and rotated parts alike.
--
-- gravityVector is pure and verified. The CFrame/face-axis bits (faceVectors, worldToPixel) follow
-- Roblox conventions that need a Studio sanity check - flagged below - since the exact tangent of
-- each NormalId and the SurfaceGui canvas orientation can't be exercised outside a running place.

local Surface = {}

--[=[
	@class Surface
	@within Blood
	Internal 3D<->canvas helpers for the blood engine.
]=]

-- Pick, from a precomputed list of `{ id, normal }`, the face whose world normal best matches
-- `worldNormal`. Pure - the testable core of faceFromNormal.
function Surface.bestFace(faces: { { id: any, normal: Vector3 } }, worldNormal: Vector3): any
	local best, bestDot = faces[1].id, -math.huge
	for _, face in faces do
		local d = face.normal:Dot(worldNormal)
		if d > bestDot then
			bestDot = d
			best = face.id
		end
	end
	return best
end

--[=[
	@within Surface
	The NormalId of `part` whose world-space normal is closest to `worldNormal` (e.g. a raycast hit
	normal). NEEDS STUDIO CHECK: relies on `Vector3.fromNormalId` + the part's CFrame.
]=]
function Surface.faceFromNormal(part: BasePart, worldNormal: Vector3): Enum.NormalId
	local cf = part.CFrame
	local faces = {}
	for _, id in Enum.NormalId:GetEnumItems() do
		table.insert(faces, { id = id, normal = cf:VectorToWorldSpace(Vector3.fromNormalId(id)) })
	end
	return Surface.bestFace(faces, worldNormal)
end

--[=[
	@within Surface
	World-space unit vectors for a face: its `normal`, the canvas `right` (+X) and canvas `down`
	(+Y). `down` is flipped to actually point downward in the world for non-horizontal faces, so a
	wall's canvas Y runs with gravity. NEEDS STUDIO CHECK on the tangent convention.
]=]
function Surface.faceVectors(part: BasePart, normalId: Enum.NormalId): (Vector3, Vector3, Vector3)
	local cf = part.CFrame
	local normal = cf:VectorToWorldSpace(Vector3.fromNormalId(normalId)).Unit

	-- a right tangent perpendicular to the normal (fall back to the part's own right axis when the
	-- face is nearly horizontal and world-up is parallel to the normal)
	local right = normal:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-3 then
		right = cf.RightVector
	end
	right = right.Unit

	local down = right:Cross(normal).Unit
	if down:Dot(Vector3.new(0, -1, 0)) < 0 then
		-- make canvas +Y point downward in the world (and keep the basis consistent)
		down = -down
		right = -right
	end
	return normal, right, down
end

--[=[
	@within Surface
	The canvas-space gravity (Vector2) for a face: world-down projected onto its `right`/`down`
	axes. A vertical wall gives `(0, 1)` (drips straight down); a slope tilts it; a floor gives
	about `(0, 0)` (no in-plane gravity → the fluid just pools). Pure + verified.
]=]
function Surface.gravityVector(right: Vector3, down: Vector3): Vector2
	local worldDown = Vector3.new(0, -1, 0)
	return Vector2.new(worldDown:Dot(right), worldDown:Dot(down))
end

--[=[
	@within Surface
	Converts a world point on `part`'s `normalId` face to a `(x, y)` pixel on a `resW` x `resH`
	canvas. NEEDS STUDIO CHECK: face-axis -> UV mapping depends on Roblox conventions.
]=]
function Surface.worldToPixel(
	part: BasePart,
	normalId: Enum.NormalId,
	worldPos: Vector3,
	resW: number,
	resH: number
): (number, number)
	local _normal, right, down = Surface.faceVectors(part, normalId)
	-- vector from the part centre to the hit, in world space
	local rel = worldPos - part.Position
	-- how far along the face's right/down axes (in studs), then to 0..1 using the face's extent
	local along = rel:Dot(right)
	local downAmt = rel:Dot(down)
	-- face extent along each axis: project the part size onto right/down (abs of each component)
	local size = part.Size
	local widthStuds = math.abs(right.X * size.X) + math.abs(right.Y * size.Y) + math.abs(right.Z * size.Z)
	local heightStuds = math.abs(down.X * size.X) + math.abs(down.Y * size.Y) + math.abs(down.Z * size.Z)
	local u = if widthStuds > 0 then along / widthStuds + 0.5 else 0.5
	local v = if heightStuds > 0 then downAmt / heightStuds + 0.5 else 0.5
	return math.clamp(math.floor(u * resW), 0, resW - 1), math.clamp(math.floor(v * resH), 0, resH - 1)
end

return Surface
