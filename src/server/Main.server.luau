--!strict
-- Server entry point. Boots server-side adapters; holds no game logic itself.
require("./Ranks").start()
local Sessions = require("./Sessions")
Sessions.start(require("./Submits"))
require("./Returns").start(Sessions.isOver)
print("[pickman] server started")
