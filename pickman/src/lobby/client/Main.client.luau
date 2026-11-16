--!strict
-- Lobby client entry point. Boots the lobby screen; holds no logic itself.
require("./LobbyView").start()
require("./LobbyPad").start()
print("[pickman] lobby client started")
