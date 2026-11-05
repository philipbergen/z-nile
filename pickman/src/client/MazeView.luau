--!strict
-- Client adapter: builds the maze as anchored, non-colliding parts from View's geometry. Every wall colour is View's
-- (View.wallColor, f0109): the level-clear flash, the edible green, and the gold of a wall that can be picked (f0126).
local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")
local View = require("@game/ReplicatedStorage/Shared/Logic/View")

local DOOR = Color3.fromRGB(255, 184, 255)
local FLOOR = Color3.fromRGB(0, 0, 0)

local MazeView = {}

local function rgb(c: View.Rgb): Color3
	return Color3.fromRGB(c.r, c.g, c.b)
end

local function part(parent: Instance, name: string, color: Color3, size: Vector3, center: Vector3)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Color = color
	p.Size = size
	p.Position = center
	p.Parent = parent
end

-- The colour of a wall part of `model` now (f0109): View.wallColor of its lit and edible state, gold if `marked`.
local function wallColorOf(model: Model, marked: boolean?): Color3
	return rgb(
		View.wallColor(model:GetAttribute("Lit") == true, model:GetAttribute("Edible") == true, marked)
	)
end

-- The wall parts of `m`, the marked ones gold, as children of the maze model (where f0109's checks read them), coloured
-- for the model's lit and edible state. A rebuild replaces only the `Wall` and `MarkedWall` parts: pellets and doors stay.
local function walls(model: Model, m: Maze.Maze, marked: { Maze.Tile }?)
	local s = View.SCALE
	for _, child in model:GetChildren() do
		if child.Name == "Wall" or child.Name == "MarkedWall" then
			child:Destroy()
		end
	end
	for _, r in View.walls(m, nil, marked) do
		local cx, cz = View.world((r.x0 + r.x1) / 2, r.y0)
		local size = Vector3.new((r.x1 - r.x0 + 1) * s.tileStuds, s.wallHeight, s.tileStuds)
		local center = Vector3.new(cx, s.wallHeight / 2, cz)
		if r.marked == true then
			part(model, "MarkedWall", wallColorOf(model, true), size, center)
		else
			part(model, "Wall", wallColorOf(model), size, center)
		end
	end
end

-- The walls again after a pick changed them (f0126): the holes `m` has open, the walls `marked` now.
function MazeView.rewall(model: Model, m: Maze.Maze, marked: { Maze.Tile })
	walls(model, m, marked)
end

function MazeView.build(m: Maze.Maze): Model
	local s = View.SCALE
	local model = Instance.new("Model")
	model.Name = "Maze"

	walls(model, m)
	for _, d in Maze.tiles(m, "door") do
		local cx, cz = View.world(d.x, d.y)
		part(
			model,
			"Door",
			DOOR,
			Vector3.new(s.tileStuds, s.wallHeight, 1),
			Vector3.new(cx, s.wallHeight / 2, cz)
		)
	end

	local b = View.bounds(m)
	local x0, z0 = View.world(b.x0 - 0.5, b.y0 - 0.5)
	local x1, z1 = View.world(b.x1 + 0.5, b.y1 + 0.5)
	part(
		model,
		"Floor",
		FLOOR,
		Vector3.new(x1 - x0, 1, z1 - z0),
		Vector3.new((x0 + x1) / 2, -0.5, (z0 + z1) / 2)
	)

	model.Parent = workspace
	return model
end

-- Repaint every wall from the model's lit and edible state (View.wallColor), the marked ones included.
local function paint(model: Model)
	for _, child in model:GetDescendants() do
		if (child.Name == "Wall" or child.Name == "MarkedWall") and child:IsA("BasePart") then
			child.Color = wallColorOf(model, child.Name == "MarkedWall")
		end
	end
end

-- The walls lit (the level-clear flash) or back in their own colour.
function MazeView.flash(model: Model, lit: boolean)
	if model:GetAttribute("Lit") ~= lit then
		model:SetAttribute("Lit", lit)
		paint(model)
	end
end

-- f0109: the walls green while the ghosts are edible.
function MazeView.edible(model: Model, edible: boolean)
	if model:GetAttribute("Edible") ~= edible then
		model:SetAttribute("Edible", edible)
		paint(model)
	end
end

return MazeView
