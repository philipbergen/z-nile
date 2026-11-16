--!strict
-- Lobby server entry point. Boots the server adapters; holds no logic itself.
local Bests = require("./Bests")
Bests.start()
local Starts = require("./Starts")
Starts.choosing(Bests.choose)
Starts.start()
require("./Boards").start()
print("[pickman] lobby server started")
