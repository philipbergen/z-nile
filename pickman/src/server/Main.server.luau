--!strict
-- Server entry point. Boots server-side adapters; holds no game logic itself.
require("./Ranks").start()
local Bests = require("./Bests")
local Sessions = require("./Sessions")
Bests.start()
Sessions.starts(Bests.startOf)
Sessions.listen(Bests.reached)
Sessions.start(require("./Submits"))
require("./Returns").start(Sessions.isOver)
print("[pickman] server started")
