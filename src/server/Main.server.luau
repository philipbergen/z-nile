--!strict
-- Server entry point. Boots server-side adapters; holds no game logic itself.
require("./Sessions").start()
print("[pickman] server started")
