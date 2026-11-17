--!strict
-- Lobby client entry point. Boots the lobby screen; holds no logic itself.
require("./LobbyView").start()
require("./PayView").start() -- f0145: what a game costs, under START GAME
local picker = require("./LobbyPicker").new()
require("./LobbyView").usePicker(picker)
picker.attach()
require("./LobbyPad").start()
print("[pickman] lobby client started")
