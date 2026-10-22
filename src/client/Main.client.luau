--!strict
-- Client entry point. Boots client-side adapters; holds no game logic itself.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BlastView = require("./BlastView")
local Camera = require("./Camera")
local Controls = require("./Controls")
local DangerHud = require("./DangerHud")
local Flow = require("@game/ReplicatedStorage/Shared/Logic/Flow")
local FlowView = require("./FlowView")
local GhostView = require("./GhostView")
local HudView = require("./HudView")
local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")
local MazeView = require("./MazeView")
local PelletView = require("./PelletView")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local snapshots = remotes:WaitForChild("Snapshot") :: RemoteEvent
local ready = remotes:WaitForChild("Ready") :: RemoteEvent

-- the rules the server plays by, so the overlay times its fade to the same dying pause
local RULES = assert(Session.GAME_CONFIG.play, "Session.GAME_CONFIG has no play rules")

local built: string? = nil
local model: Model? = nil
local pellets: PelletView.Handle? = nil
local lit = false -- the walls are drawn lit
snapshots.OnClientEvent:Connect(function(frame: Session.Frame)
	if built ~= frame.maze then
		built = frame.maze
		if model then
			model:Destroy() -- its pellets with it
		end
		local m = Maze.layout(frame.maze)
		local walls = MazeView.build(m)
		model = walls
		pellets = PelletView.build(m, walls)
		lit = false -- new walls are built unlit
	end
	Camera.push(frame)
	Camera.hopped(frame.hopped)
	local snap: Session.Snapshot = frame -- a frame carries everything a snapshot does
	GhostView.push(snap)
	DangerHud.push(snap, Maze.layout(snap.maze))
	HudView.show(frame.play)
	HudView.shots(frame.shots)
	BlastView.push(frame)
	local overlay = Flow.overlay(frame.play, RULES, FlowView.trip())
	FlowView.show(overlay)
	if model and overlay.flash ~= lit then
		lit = overlay.flash
		MazeView.flash(model, overlay.flash)
	end
	Camera.setCursor(overlay.cursor)
	-- last: a code that fails to decode can't stop the rest of the frame
	if pellets then
		PelletView.show(pellets, frame.pellets)
	end
end)

Camera.start()
GhostView.start()
DangerHud.start(Camera.pose)
Controls.keys({ arrows = Camera.arrows, aim = Camera.aim })
Controls.start(Camera.snap, Camera.lookBy, HudView.snapRect, Camera.holdMouse)
PelletView.start()
HudView.start()
FlowView.start()

-- listening now: tell the server, so its first snapshot reaches a client that can show it
ready:FireServer()
print("[pickman] client started")
