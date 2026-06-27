-- IMGN
-- _Classes/App/Section.luau
-- Plinko Labs
--
-- One line of the canvas handed to an App:Comb callback: a row (when combing the Y axis) or a
-- column (when combing X). You address it 1-dimensionally - `Set(i, color)` writes the i-th
-- pixel along the line, `Fill` paints the whole line - and the Section maps that onto the right
-- (x, y) without you tracking which axis you're on. Index is the line's fixed coordinate
-- (the row's y, or the column's x); Length is how many pixels long it is.

--[=[
	@class Section
	@within App
	A row or column view passed to an [App:Comb] callback. `Orientation` is `"Row"` or `"Column"`;
	`Index` is the fixed coordinate; `Length` is the pixel count along the line.
]=]
local Section = {}
Section.__index = Section

export type Section = typeof(setmetatable(
	{} :: {
		Orientation: "Row" | "Column",
		Index: number,
		Length: number,
		_canvas: any,
	},
	Section
))

function Section.new(canvas: any, orientation: "Row" | "Column", index: number): Section
	return setmetatable({
		Orientation = orientation,
		Index = index,
		Length = if orientation == "Row" then canvas.Width else canvas.Height,
		_canvas = canvas,
	}, Section)
end

-- Map a 1-D position `i` along the line to its (x, y) on the canvas.
local function coord(self: Section, i: number): (number, number)
	if self.Orientation == "Row" then
		return i, self.Index
	end
	return self.Index, i
end

--[=[
	@within Section
	Writes the `i`-th pixel along the line (0-based). Clipped if out of range.
]=]
function Section.Set(self: Section, i: number, color: Color3, alpha: number?)
	local x, y = coord(self, i)
	self._canvas:SetPixel(x, y, color, alpha)
end

--[=[
	@within Section
	Reads the `i`-th pixel along the line.
]=]
function Section.Get(self: Section, i: number): (Color3, number)
	local x, y = coord(self, i)
	return self._canvas:GetPixel(x, y)
end

--[=[
	@within Section
	Paints the whole line one colour.
]=]
function Section.Fill(self: Section, color: Color3, alpha: number?)
	for i = 0, self.Length - 1 do
		Section.Set(self, i, color, alpha)
	end
end

return Section
