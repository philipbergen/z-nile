--!strict
-- Lobby server entry point. Boots the server adapters; holds no logic itself.
require("./Starts").start()
require("./Boards").start()
print("[pickman] lobby server started")
