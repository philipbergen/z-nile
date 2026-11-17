--!strict
-- Lobby server entry point. Boots the server adapters; holds no logic itself.
local Bests = require("./Bests")
Bests.start()
local Starts = require("./Starts")
Starts.choosing(Bests.choose)
local Paid = require("./Paid")
Paid.start(Starts.start(Paid.allow)) -- f0145: paid play in front of START GAME
require("./Boards").start()
print("[pickman] lobby server started")
