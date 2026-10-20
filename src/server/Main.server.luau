--!strict
-- Server entry point. Boots server-side adapters; holds no game logic itself.
require("./Sessions").start(require("./Submits"))
print("[pickman] server started")
