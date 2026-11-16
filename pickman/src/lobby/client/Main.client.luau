--!strict
-- Lobby client entry point. Boots the lobby screen; holds no logic itself.
require("./LobbyView").start()
local picker = require("./LobbyPicker").new()
require("./LobbyView").usePicker(picker)
picker.attach()
require("./LobbyPad").start()
print("[pickman] lobby client started")
