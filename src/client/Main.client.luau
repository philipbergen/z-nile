--!strict
-- Client entry point. Boots client-side adapters; holds no game logic itself.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Camera = require("./Camera")
local Controls = require("./Controls")
local Maze = require("@game/ReplicatedStorage/Shared/Logic/Maze")
local MazeView = require("./MazeView")
local PelletView = require("./PelletView")
local Session = require("@game/ReplicatedStorage/Shared/Logic/Session")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local snapshots = remotes:WaitForChild("Snapshot") :: RemoteEvent
local ready = remotes:WaitForChild("Ready") :: RemoteEvent

local built: string? = nil
local model: Model? = nil
local pellets: PelletView.Handle? = nil
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
	end
	Camera.push(frame)
	-- last: a code that fails to decode can't stop the rest of the frame
	if pellets then
		PelletView.show(pellets, frame.pellets)
	end
end)

Camera.start()
Controls.start(Camera.snap)
PelletView.start()

-- listening now: tell the server, so its first snapshot reaches a client that can show it
ready:FireServer()
print("[pickman] client started")
