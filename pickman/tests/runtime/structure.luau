--!strict
-- Runs inside a real Roblox server of the published place (Open Cloud Luau Execution), not under Lune.
-- Returns "PASS"; anything else, or an error, fails.
local game: any = (getfenv() :: any).game -- Roblox's global; the Lune type definitions don't declare it

local server = game:GetService("ServerScriptService"):FindFirstChild("Server")
assert(server, "ServerScriptService.Server is missing")
assert(server:FindFirstChild("Main"), "Server.Main is missing")
local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
assert(remotes, "ReplicatedStorage.Remotes is missing")
for _, name in { "Ready", "Intent", "Snapshot", "ToLobby", "LobbyStatus" } do
	assert(remotes:FindFirstChild(name), "Remotes." .. name .. " is missing")
end
local lobby = game:GetService("ServerScriptService"):GetAttribute("LobbyPlaceId")
assert(type(lobby) == "number", "ServerScriptService.LobbyPlaceId must be a number")
assert(game:GetService("Players").CharacterAutoLoads == false, "CharacterAutoLoads must be false")
return "PASS"
