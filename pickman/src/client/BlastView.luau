--!strict
-- Client adapter: the blaster's beam (f0100). When a frame says the server took a shot in that very step
-- (frame.shot.tick == frame.tick), a thin neon beam runs from the tile the server shot from (frame.shot.from, not
-- where the camera happens to be) along its heading to View.beamEnd for a moment, so it shows what the server did. A fire the server dropped (a pause, no shot held, a second one in a tick) has no frame.shot and shows
-- nothing. A ghost the shot hit turns into eyes in the same frames.
local Debris = game:GetService("Debris")

local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")
local View = require("@game/ReplicatedStorage/Shared/Logic/View")

local BEAM_SECONDS = 0.15 -- real time
local BEAM_STUDS = 0.4 -- thickness
local COLOR = Color3.fromRGB(0, 255, 255)

local BlastView = {}

local latest: Session.Frame? = nil
local function draw(m: Maze.Maze, p: { x: number, y: number }, heading: Maze.Heading)
	local ex, ey = View.beamEnd(m, p.x, p.y, heading)
	local x0, z0 = View.world(p.x, p.y)
	local x1, z1 = View.world(ex, ey)
	local length = math.max(math.abs(x1 - x0), math.abs(z1 - z0))
	if length <= 0 then
		return
	end
	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Material = Enum.Material.Neon
	beam.Color = COLOR
	beam.Size = if x1 ~= x0
		then Vector3.new(length, BEAM_STUDS, BEAM_STUDS)
		else Vector3.new(BEAM_STUDS, BEAM_STUDS, length)
	beam.Position = Vector3.new((x0 + x1) / 2, View.SCALE.eyeHeight - 0.5, (z0 + z1) / 2)
	beam.Parent = workspace
	Debris:AddItem(beam, BEAM_SECONDS)
end

-- Every frame, newest first: a shot the server took in this frame's step is drawn once.
function BlastView.push(frame: Session.Frame)
	if latest ~= nil and frame.tick <= latest.tick then
		return
	end
	latest = frame
	local shot = frame.shot
	if shot and shot.tick == frame.tick then
		draw(View.frameMaze(frame), shot.from, shot.heading)
	end
end

return BlastView
