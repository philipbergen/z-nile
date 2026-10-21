--!strict
-- Runs inside a real Roblox server of the published lobby place (Open Cloud Luau Execution, c0064), not under
-- Lune. Returns "PASS"; anything else, or an error, fails.
local game: any = (getfenv() :: any).game -- Roblox's global; the Lune type definitions don't declare it

local sss = game:GetService("ServerScriptService")
local lobby = sss:FindFirstChild("Lobby")
assert(lobby, "ServerScriptService.Lobby is missing")
assert(lobby:FindFirstChild("Main"), "Lobby.Main is missing")
assert(sss:FindFirstChild("Server") == nil, "the game's ServerScriptService.Server is in the lobby")
local remotes = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
assert(remotes, "ReplicatedStorage.Remotes is missing")
for _, name in { "StartGame", "Status" } do
	assert(remotes:FindFirstChild(name), "Remotes." .. name .. " is missing")
end
assert(game:GetService("Players").CharacterAutoLoads == false, "CharacterAutoLoads must be false")
local id = sss:GetAttribute("GamePlaceId")
assert(type(id) == "number" and id >= 1 and id == math.floor(id), "GamePlaceId is not set to a place id")
return "PASS"
