--!strict
-- Client entry point. Boots client-side adapters; holds no game logic itself.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Camera = require("./Camera")
local Controls = require("./Controls")
local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")
local MazeView = require("./MazeView")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local snapshots = remotes:WaitForChild("Snapshot") :: RemoteEvent
local ready = remotes:WaitForChild("Ready") :: RemoteEvent

local built: string? = nil
snapshots.OnClientEvent:Connect(function(snap: Session.Snapshot)
	if built ~= snap.maze then
		built = snap.maze
		MazeView.build(Maze.layout(snap.maze))
	end
	Camera.push(snap)
end)

Camera.start()
Controls.start(Camera.snap)

-- listening now: tell the server, so its first snapshot reaches a client that can show it
ready:FireServer()
print("[pickman] client started")
