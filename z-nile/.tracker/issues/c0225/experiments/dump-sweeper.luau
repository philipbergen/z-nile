-- writes fence.SWEEPER (of the checkout this runs in) to the file named by the first argument
local fence = require("../../../../tests/lib/fence")
local fs = require("@lune/fs")
local process = require("@lune/process")
fs.writeFile(process.args[1], fence.SWEEPER)
