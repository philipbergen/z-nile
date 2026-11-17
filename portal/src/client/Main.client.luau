--!strict
-- portal's client entry (c0184 scaffold): boots the client adapters as the features arrive.
require("@game/ReplicatedStorage/Arcade/TestPurchase").start()
require("./CarouselView").start()
require("./PlayButtons").start()
