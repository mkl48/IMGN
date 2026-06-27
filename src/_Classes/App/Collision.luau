-- IMGN
-- _Classes/App/Collision.luau
-- Plinko Labs
--
-- AABB collision resolution for the App's CanCollide Objects. Two layers: walls (an Object that
-- would leave the canvas is pushed back inside and its velocity flipped along that axis, scaled
-- by Bounce) and pairs (two overlapping Objects are separated along their axis of least
-- penetration, and - for two dynamic bodies - swap that axis' velocity, the equal-mass elastic
-- result; against an Anchored body the mover just reflects). It's intentionally AABB-only: cheap,
-- predictable, and enough for the games this layer is for. Each resolution fires OnCollide.

local Collision = {}

type AABB = { minX: number, minY: number, maxX: number, maxY: number }

local function fire(object: any, other: any)
	if object.OnCollide then
		object.OnCollide(object, other)
	end
end

--[=[
	@class Collision
	@within App
	Internal AABB resolver the App's step loop drives; not part of the public surface.
]=]

--[=[
	@within Collision
	Pushes `object` back inside a `width` x `height` canvas if its AABB crossed an edge, flipping
	the matching velocity component by `-Bounce` and firing OnCollide with the edge name.
]=]
function Collision.resolveWalls(object: any, width: number, height: number)
	local b = object:Bounds()
	if not b then
		return
	end

	local vx, vy = object.Velocity.X, object.Velocity.Y
	local px, py = object.Position.X, object.Position.Y
	local bounce = object.Bounce

	if b.minX < 0 then
		px += -b.minX
		vx = math.abs(vx) * bounce
		fire(object, "Left")
	elseif b.maxX > width - 1 then
		px -= b.maxX - (width - 1)
		vx = -math.abs(vx) * bounce
		fire(object, "Right")
	end

	if b.minY < 0 then
		py += -b.minY
		vy = math.abs(vy) * bounce
		fire(object, "Top")
	elseif b.maxY > height - 1 then
		py -= b.maxY - (height - 1)
		vy = -math.abs(vy) * bounce
		fire(object, "Bottom")
	end

	object.Position = Vector2.new(px, py)
	object.Velocity = Vector2.new(vx, vy)
end

local function overlaps(a: AABB, b: AABB): boolean
	return not (a.maxX < b.minX or a.minX > b.maxX or a.maxY < b.minY or a.minY > b.maxY)
end

-- Shift an Object's Position by (dx, dy) unless it's anchored.
local function shift(object: any, dx: number, dy: number)
	if object.Anchored then
		return
	end
	object.Position += Vector2.new(dx, dy)
end

local function resolvePair(a: any, b: any)
	local ab, bb = a:Bounds(), b:Bounds()
	if not ab or not bb or not overlaps(ab, bb) then
		return
	end

	local overlapX = math.min(ab.maxX, bb.maxX) - math.max(ab.minX, bb.minX) + 1
	local overlapY = math.min(ab.maxY, bb.maxY) - math.max(ab.minY, bb.minY) + 1
	local aCenterX, bCenterX = (ab.minX + ab.maxX) / 2, (bb.minX + bb.maxX) / 2
	local aCenterY, bCenterY = (ab.minY + ab.maxY) / 2, (bb.minY + bb.maxY) / 2
	local bounce = (a.Bounce + b.Bounce) / 2

	-- Separate along the axis of least penetration: that's the one they actually hit on.
	if overlapX <= overlapY then
		local aDir = if aCenterX < bCenterX then -1 else 1
		if a.Anchored then
			shift(b, -aDir * overlapX, 0)
		elseif b.Anchored then
			shift(a, aDir * overlapX, 0)
		else
			shift(a, aDir * overlapX / 2, 0)
			shift(b, -aDir * overlapX / 2, 0)
		end

		if a.Anchored ~= b.Anchored then
			-- One wall, one mover: the mover reflects off the X axis.
			local mover = if a.Anchored then b else a
			mover.Velocity = Vector2.new(-mover.Velocity.X * mover.Bounce, mover.Velocity.Y)
		elseif not a.Anchored then
			-- Two dynamic bodies swap their X velocity (equal-mass elastic), scaled by bounce.
			local ax, bx = a.Velocity.X, b.Velocity.X
			a.Velocity = Vector2.new(bx * bounce, a.Velocity.Y)
			b.Velocity = Vector2.new(ax * bounce, b.Velocity.Y)
		end
	else
		local aDir = if aCenterY < bCenterY then -1 else 1
		if a.Anchored then
			shift(b, 0, -aDir * overlapY)
		elseif b.Anchored then
			shift(a, 0, aDir * overlapY)
		else
			shift(a, 0, aDir * overlapY / 2)
			shift(b, 0, -aDir * overlapY / 2)
		end

		if a.Anchored ~= b.Anchored then
			local mover = if a.Anchored then b else a
			mover.Velocity = Vector2.new(mover.Velocity.X, -mover.Velocity.Y * mover.Bounce)
		elseif not a.Anchored then
			local ay, by = a.Velocity.Y, b.Velocity.Y
			a.Velocity = Vector2.new(a.Velocity.X, by * bounce)
			b.Velocity = Vector2.new(b.Velocity.X, ay * bounce)
		end
	end

	fire(a, b)
	fire(b, a)
end

--[=[
	@within Collision
	Resolves every CanCollide pair in `objects` (skips pairs where both are anchored - two walls
	never need separating). O(n^2); fine for the modest object counts this layer targets.
]=]
function Collision.resolvePairs(objects: { any })
	for i = 1, #objects do
		local a = objects[i]
		if not a.CanCollide then
			continue
		end
		for j = i + 1, #objects do
			local b = objects[j]
			if b.CanCollide and not (a.Anchored and b.Anchored) then
				resolvePair(a, b)
			end
		end
	end
end

return Collision
